"""Weapon-only effective Unit/Material graph; no native/game calls."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_binding_provenance import (
    UNIT, MATERIAL, U1, M1, M2, PREFERRED,
    fixture, loose_patch, resource, unit, material, command, scope_fingerprint,
)


class WeaponEffectiveSources(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='epic-weapon-effective-')
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def run_worker(self, game, mode='weapon_effective', label='cache'):
        request = self.root / 'request.tsv'
        request.write_text(U1 + '\t' + PREFERRED + '\n', encoding='utf-8')
        output = self.root / label
        args = command(game, output, request) + ['-Mode', mode]
        result = subprocess.run(args, capture_output=True, text=True, timeout=35)
        return result, output

    def dataset(self, game, **kwargs):
        result, output = self.run_worker(game, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        marker = (output / 'complete.txt').read_text().splitlines()
        version = Path(marker[0])
        self.assertEqual(marker[1], '2')
        rows = {tuple(row[:2]): row for row in
                (line.split('\t') for line in (version / 'resources.tsv').read_text().splitlines())}
        sources = {tuple(row[:2]): row for row in
                   (line.split('\t') for line in (version / 'sources.tsv').read_text().splitlines())}
        self.assertEqual(set(rows), set(sources))
        for source in sources.values():
            self.assertEqual(source[4], scope_fingerprint(game))
        return version, rows, sources

    def refused(self, game, expected):
        result, output = self.run_worker(game)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(expected, (output / 'error.txt').read_text())
        self.assertFalse((output / 'complete.txt').exists())
        self.assertFalse(list(output.rglob('*.main')))

    def test_preserves_modified_unit_material_whole_triplets_and_mode_partition(self):
        game = self.root / 'game'
        fixture(game)
        patched_unit = resource(U1, UNIT, unit(((7, M1), (17, M2), (7, M1))), b'modified geometry', b'modified stream')
        patched_mat = resource(M1, MATERIAL, material('abababababababab') + b'opaque-material-tail', b'custom gpu', b'custom stream')
        patch = '9ba626afa44a3aa3.patch_34'
        loose_patch(game, patch, [patched_unit, patched_mat])
        result, stock = self.run_worker(game, mode='stock', label='stock-cache')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Loose patch overrides requested binding source', (stock / 'error.txt').read_text())
        version, rows, sources = self.dataset(game)
        for item in (patched_unit, patched_mat):
            row = rows[(item['kind'], item['name'])]
            self.assertEqual(row[2], patch[:16])
            for part, index in [('main', 3), ('gpu', 4), ('stream', 5)]:
                self.assertEqual((version / row[index]).read_bytes(), item[part])
            self.assertEqual(sources[(item['kind'], item['name'])][2:4], ['loose', patch])
        self.assertEqual(sources[(MATERIAL, M2)][2:4], ['packed', PREFERRED])

    def test_effective_unit_selects_linked_loose_only_material(self):
        game = self.root / 'game'
        fixture(game)
        new_mat = '9393939393939393'
        loose_patch(game, '9ba626afa44a3aa3.patch_34', [
            resource(U1, UNIT, unit(((7, new_mat),)), b'custom geometry'),
            resource(new_mat, MATERIAL, material('abababababababab')),
        ])
        _, rows, sources = self.dataset(game)
        self.assertEqual(set(rows), {(UNIT, U1), (MATERIAL, new_mat)})
        self.assertTrue(all(s[2] == 'loose' for s in sources.values()))

    def test_identical_loose_copies_are_unambiguous_and_first_toc_is_preserved(self):
        game = self.root / 'game'
        fixture(game)
        item = resource(M1, MATERIAL, material('abababababababab'), b'opaque gpu')
        for name in ('eeeeeeeeeeeeeeee.patch_2', 'dddddddddddddddd.patch_10'):
            loose_patch(game, name, [item])
        version, rows, sources = self.dataset(game)
        self.assertEqual(sources[(MATERIAL, M1)][3], 'dddddddddddddddd.patch_10')
        self.assertEqual((version / rows[(MATERIAL, M1)][4]).read_bytes(), b'opaque gpu')

    def test_distinct_unit_material_or_flag_overrides_refuse_without_priority_guess(self):
        for label, kind in [('unit', UNIT), ('material', MATERIAL), ('flags', MATERIAL)]:
            with self.subTest(label=label):
                game = self.root / label
                fixture(game)
                first = resource(U1, UNIT, unit(), b'first') if kind == UNIT else resource(M1, MATERIAL, material('abababababababab'))
                second = dict(first)
                if label == 'flags':
                    second['flags'] = (32, 64)
                else:
                    second['gpu'] = b'different'
                loose_patch(game, 'dddddddddddddddd.patch_2', [first])
                loose_patch(game, 'dddddddddddddddd.patch_99', [second])
                result, output = self.run_worker(game, label=label + '-cache')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Ambiguous effective weapon binding overrides', (output / 'error.txt').read_text())
                self.assertFalse((output / 'complete.txt').exists())

    def test_conflicting_global_section_associations_refuse(self):
        game = self.root / 'game'
        fixture(game)
        loose_patch(game, '9ba626afa44a3aa3.patch_34', [resource(U1, UNIT, unit(((7, M1), (7, M2))))])
        self.refused(game, 'Ambiguous binding provenance unit SectionID')

    def test_effective_material_only_replacement_and_no_patch_mode_partition(self):
        game = self.root / 'game'
        fixture(game)
        _, stock_output = self.run_worker(game, mode='stock', label='stock-cache')
        stock_marker = (stock_output / 'complete.txt').read_text().splitlines()
        self.assertEqual(stock_marker[1], '1')
        self.assertFalse((Path(stock_marker[0]) / 'sources.tsv').exists())
        version, rows, sources = self.dataset(game)
        self.assertNotEqual(version.name, Path(stock_marker[0]).name)
        self.assertTrue(all(s[2] == 'packed' for s in sources.values()))
        loose_patch(game, '9ba626afa44a3aa3.patch_34', [resource(M1, MATERIAL, material('abababababababab'))])
        _, _, sources = self.dataset(game)
        self.assertEqual(sources[(UNIT, U1)][2], 'packed')
        self.assertEqual(sources[(MATERIAL, M1)][2], 'loose')


if __name__ == '__main__':
    unittest.main()
