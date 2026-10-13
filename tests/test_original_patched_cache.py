"""Runtime snapshot worker must keep loose custom LUTs, not bundled stock pixels."""
from pathlib import Path
import hashlib
import os
import struct
import subprocess
import tempfile
import unittest

import numpy as np
from test_game_catalog import fixture
from test_binding_provenance import loose_patch, resource, TEXTURE
from lut_files import encode_dds, load

ROOT = Path(__file__).resolve().parents[1]
ID = '3333333333333333'
PATCH = 'aaaaaaaaaaaaaaaa.patch_0'


def texture(values, *, half=False, mips=1):
    values = np.asarray(values, dtype=np.float32)
    dds = bytearray(encode_dds(np.zeros_like(values))[:148])
    struct.pack_into('<I', dds, 28, mips)
    struct.pack_into('<I', dds, 128, 10 if half else 2)
    raw = bytearray(values.astype('<f2' if half else '<f4').tobytes())
    height, width = values.shape[:2]
    for mip in range(1, mips):
        raw.extend(np.zeros((max(1, height >> mip), max(1, width >> mip), 4),
                            dtype='<f2' if half else '<f4').tobytes())
    return bytes(192) + bytes(dds), bytes(raw)


def override(game, values, *, name=PATCH, hash=ID, half=False, mips=1, layout='gpu', **options):
    main, raw = texture(values, half=half, mips=mips)
    if layout == 'stream':
        gpu, stream = b'', raw
    elif layout == 'split':
        stream, gpu = raw[:len(raw)//2], raw[len(raw)//2:]
    else:
        gpu, stream = raw, b''
    loose_patch(game, name, [resource(hash, TEXTURE, main, gpu, stream, **options)])
    return main, raw


def run(game, output, wanted=None):
    command = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
               '-File', str(ROOT/'tools/original_snapshots.ps1'), '-GameData', str(game),
               '-Output', str(output)]
    command += ['-IndexOnly'] if wanted is None else ['-Wanted', str(wanted)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    error = (output/'error.txt').read_text() if (output/'error.txt').exists() else ''
    return result, error


def version(output, marker='complete.txt'):
    return output/(output/marker).read_text().splitlines()[0]


class PatchedOriginalSnapshots(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='epic-custom-lut-worker-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game, self.output = self.root/'game', self.root/'cache'
        _, self.stock = fixture(self.game, 8)
        self.custom = np.arange(8*23*4, dtype=np.float32).reshape(8, 23, 4)/7-17
        self.custom[0, 13] = [8.5, 100000000, -12.5, -0.0]
        self.wanted = self.root/'wanted.txt'
        self.wanted.write_text(ID+'\n')

    def capture(self):
        result, error = run(self.game, self.output, self.wanted)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr+error)
        return version(self.output)

    def refused(self, phrase):
        result, error = run(self.game, self.output, self.wanted)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(phrase, error)
        self.assertFalse((self.output/'complete.txt').exists())

    def test_loose_override_replaces_stock_with_exact_hdr_and_patch_metadata(self):
        main, _ = override(self.game, self.custom)
        before = {p.name: hashlib.sha256(p.read_bytes()).digest() for p in self.game.iterdir()}
        output = self.capture()
        self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), self.custom.tobytes())
        self.assertEqual((output/f'game-{ID}-original.patch-source').read_bytes(),
                         b'aaaaaaaaaaaaaaaa\n'+main)
        self.assertEqual((output/f'game-{ID}-original.patch-source').stat().st_size, 357)
        self.assertEqual(before, {p.name: hashlib.sha256(p.read_bytes()).digest() for p in self.game.iterdir()})

    def test_old_stock_index_and_changed_same_size_pixels_refresh_cache(self):
        first, error = run(self.game, self.output)
        self.assertEqual(first.returncode, 0, error)
        stock_stamp = version(self.output, 'index-complete.txt').name
        override(self.game, self.custom)
        indexed, error = run(self.game, self.output)
        self.assertEqual(indexed.returncode, 0, error)
        custom_stamp = version(self.output, 'index-complete.txt').name
        self.assertNotEqual(stock_stamp, custom_stamp)
        self.assertEqual((self.output/custom_stamp/'catalog.txt').read_text().splitlines(), [ID])
        self.capture()
        source = self.game/(PATCH+'.gpu_resources')
        stat = source.stat()
        changed = self.custom.copy(); changed[7, 22, 3] = 987.5
        override(self.game, changed)
        # Filename, length, and timestamp alone cannot prove custom source bytes.
        os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        output = self.capture()
        self.assertNotEqual(output.name, custom_stamp)
        self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), changed.tobytes())

    def test_unrelated_large_gpu_tail_is_not_hashed_as_lut_pixels(self):
        override(self.game, self.custom)
        initial = self.capture().name
        with (self.game/(PATCH+'.gpu_resources')).open('ab') as stream:
            stream.write(bytes(1024*1024))
        self.assertEqual(self.capture().name, initial)

    def test_half_material_and_pattern_mip_chain_convert_exactly(self):
        for values in (np.arange(8*23*4, dtype=np.float32).reshape(8, 23, 4)/8-10,
                       np.array([[[-0.0, 0.25, 0.5, 1], [0.75, 0.5, 0.25, 1], [0, 0, 0, 0.375]]], dtype=np.float32)):
            with self.subTest(shape=values.shape):
                override(self.game, values, half=True, mips=2)
                output = self.capture()
                expected = values.astype('<f2').astype('<f4')
                self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), expected.tobytes())

    def test_stream_and_split_pixel_sources(self):
        for layout in ('stream', 'split'):
            with self.subTest(layout=layout):
                override(self.game, self.custom, layout=layout)
                output = self.capture()
                self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), self.custom.tobytes())

    def test_conflicting_duplicate_does_not_guess_patch_number_precedence(self):
        override(self.game, self.custom)
        override(self.game, self.custom+1, name='aaaaaaaaaaaaaaaa.patch_999')
        self.refused('Ambiguous loose LUT replacements')

    def test_identical_duplicate_same_archive_is_not_a_false_conflict(self):
        override(self.game, self.custom)
        override(self.game, self.custom, name='aaaaaaaaaaaaaaaa.patch_1')
        output = self.capture()
        self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), self.custom.tobytes())

    def test_unrequested_conflict_does_not_block_catalog_or_unique_capture(self):
        conflict = '4444444444444444'
        override(self.game, self.custom)
        override(self.game, self.custom, hash=conflict, name='aaaaaaaaaaaaaaaa.patch_1')
        override(self.game, self.custom+1, hash=conflict, name='aaaaaaaaaaaaaaaa.patch_2')
        result, error = run(self.game, self.output)
        self.assertEqual(result.returncode, 0, error)
        self.assertEqual((version(self.output, 'index-complete.txt')/'catalog.txt').read_text().splitlines(),
                         [ID, conflict])
        output = self.capture()
        self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), self.custom.tobytes())
        self.wanted.write_text(conflict+'\n')
        self.refused('Ambiguous loose LUT replacements')

    def test_short_or_missing_sidecar_never_falls_back_to_stock(self):
        override(self.game, self.custom)
        source = self.game/(PATCH+'.gpu_resources')
        source.write_bytes(source.read_bytes()[:-1])
        self.refused('Loose LUT source bounds')
        source.unlink()
        self.refused('Loose LUT sidecar missing')

    def test_changed_malformed_source_clears_previous_success_marker(self):
        override(self.game, self.custom)
        self.capture()
        (self.game/(PATCH+'.gpu_resources')).write_bytes(b'broken')
        self.refused('Loose LUT source bounds')

    def test_bad_metadata_replacing_known_lut_is_refused(self):
        loose_patch(self.game, PATCH, [resource(ID, TEXTURE, b'not-a-DDS')])
        self.refused('DDS metadata unavailable')
        result, error = run(self.game, self.output)
        self.assertEqual(result.returncode, 0, error)
        self.assertEqual((version(self.output, 'index-complete.txt')/'catalog.txt').read_text().splitlines(), [ID])
        self.assertFalse(list(version(self.output, 'index-complete.txt').glob('*.dds')))

    def test_nonfinite_and_out_of_bounds_override_refused(self):
        invalid = self.custom.copy(); invalid[5, 6, 3] = np.nan
        override(self.game, invalid)
        self.refused('Nonfinite LUT')
        override(self.game, self.custom, gpu_at=(1 << 64)-1)
        self.refused('Loose LUT source bounds')

    def test_removed_override_restores_stock_source_and_stamp(self):
        override(self.game, self.custom)
        custom_stamp = self.capture().name
        for path in self.game.glob(PATCH+'*'):
            path.unlink()
        output = self.capture()
        self.assertNotEqual(custom_stamp, output.name)
        self.assertEqual(load(output/f'game-{ID}-original.dds').tobytes(), self.stock.tobytes())

    def test_source_change_since_stamp_refuses_before_any_output(self):
        override(self.game, self.custom)
        self.output.mkdir()
        script = self.root/'changed-source.ps1'
        script.write_text("""param($Reader,$Game,$Output,$Wanted)
$ErrorActionPreference='Stop'
Add-Type -Path $Reader
$status=Join-Path $Output 'progress.txt'
$stamp=[EpicOriginalReader]::SourceStamp($Game,0,$status)
$gpu=Join-Path $Game 'aaaaaaaaaaaaaaaa.patch_0.gpu_resources'
$bytes=[IO.File]::ReadAllBytes($gpu);$bytes[13]=$bytes[13] -bxor 1;[IO.File]::WriteAllBytes($gpu,$bytes)
try {[EpicOriginalReader]::RunChecked($Game,$Output,0,$status,$Wanted,$stamp);exit 2}
catch {if($_.Exception.Message -notlike '*sources changed*'){throw};exit 0}
""")
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy',
                                 'Bypass', '-File', str(script), str(ROOT/'tools/original_snapshots.cs'),
                                 str(self.game), str(self.output), str(self.wanted)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertFalse(list(self.output.glob('*.dds')))
        self.assertFalse(list(self.output.glob('*.patch-source')))

    def test_aggregate_retained_pixel_budget_refuses_small_aliased_input(self):
        values = np.zeros((64, 23, 4), dtype=np.float32)
        main, raw = texture(values, mips=2)
        count = 2500
        toc = bytearray(104+count*80)
        struct.pack_into('<III', toc, 0, 0xf0000011, 1, count)
        for i in range(count):
            row = 104+i*80
            struct.pack_into('<QQQQQ', toc, row, i+1, int(TEXTURE, 16), len(toc), 0, 0)
            struct.pack_into('<III', toc, row+56, len(main), 0, len(raw))
        (self.game/PATCH).write_bytes(toc+main)
        (self.game/(PATCH+'.gpu_resources')).write_bytes(raw)
        self.refused('Loose LUT retained byte budget exceeded')


if __name__ == '__main__':
    unittest.main()
