"""Exercise the runtime provenance PowerShell/C# worker on synthetic archives."""
from pathlib import Path
import hashlib
import re
import struct
import subprocess
import tempfile
import time
import unittest
from test_authored_preview import dsar

ROOT = Path(__file__).resolve().parents[1]
UNIT, MATERIAL, TEXTURE = 'e0a48d0be9a7453f', 'eac0b497876adedf', 'cd4238c6a0c69e32'
U1, U2, M1, M2 = '1111111111111111', '1212121212121212', '2222222222222222', '2323232323232323'
PREFERRED, FALLBACK, UNRELATED = 'bbbbbbbbbbbbbbbb', 'aaaaaaaaaaaaaaaa', 'cccccccccccccccc'
SHARED, SECOND_SHARED = '18235e0c9ec0e636', 'ee6b1ba7e22d71ed'
PART_LIMIT = 8 * 1024 * 1024


def unit(materials=((7, M1), (17, M2))):
    result = bytearray(116 + 4 + len(materials) * 12)
    struct.pack_into('<I', result, 112, 116)
    struct.pack_into('<I', result, 116, len(materials))
    for i, (section, material) in enumerate(materials):
        struct.pack_into('<I', result, 120 + i * 4, section)
        struct.pack_into('<Q', result, 120 + len(materials) * 4 + i * 8, int(material, 16))
    return bytes(result)


def material(texture):
    result = bytearray(148)
    struct.pack_into('<I', result, 64, 1)
    struct.pack_into('<IQ', result, 136, 0x7e662968, int(texture, 16))
    return bytes(result)


def resource(name, kind, main, gpu=b'', stream=b'', **options):
    return dict(name=name, kind=kind, main=main, gpu=gpu, stream=stream, **options)


def defaults():
    return [resource(U1, UNIT, unit(), b'unit-gpu\0\xff', b'unit-stream\xfe'),
            resource(M1, MATERIAL, material('3333333333333333'), b'material-gpu\xff', b'material-stream\0'),
            resource(M2, MATERIAL, material('3434343434343434'))]


def fixture(folder, archives=None, headers=None):
    folder.mkdir(parents=True)
    if archives is None:
        archives = {PREFERRED: defaults(),
                    UNRELATED: [resource('5555555555555555', TEXTURE, b'unloaded-texture'),
                                resource('5656565656565656', MATERIAL, b'unloaded-material'),
                                resource('5757575757575757', UNIT, b'unloaded-unit'),
                                resource('5858585858585858', '0000000000000011', b'other-kind')]}
    archive_parts, expected = {}, {}
    for archive, resources in archives.items():
        main = bytearray(104 + len(resources) * 80)
        struct.pack_into('<III', main, 0, 0xf0000011, 1, len(resources))
        gpu, stream = bytearray(b'prefix-gpu'), bytearray(b'prefix-stream')
        for i, item in enumerate(resources):
            p, offset = 104 + i * 80, len(main)
            main.extend(item['main'])
            struct.pack_into('<QQQQQ', main, p, int(item['name'], 16), int(item['kind'], 16),
                             item.get('main_at', offset), len(stream), len(gpu))
            main[p+40:p+56] = item.get('unknowns', bytes(range(16)))
            struct.pack_into('<III', main, p+56, item.get('main_size', len(item['main'])),
                             item.get('stream_size', len(item['stream'])), item.get('gpu_size', len(item['gpu'])))
            struct.pack_into('<III', main, p+68, *item.get('flags', (16, 64)), i + 1)
            gpu.extend(item['gpu']); stream.extend(item['stream'])
            expected[(archive, item['name'], item['kind'])] = dict(
                main=item['main'], gpu=item['gpu'], stream=item['stream'], toc=bytes(main[p:p+80]))
        if headers and archive in headers:
            struct.pack_into('<III', main, 0, *headers[archive])
        archive_parts[archive] = bytes(main)
        if len(gpu) > 10:
            archive_parts[archive+'.gpu_resources'] = bytes(gpu)
        if len(stream) > 13:
            archive_parts[archive+'.stream'] = bytes(stream)
    combined, records = bytearray(), []
    for name, data in sorted(archive_parts.items()):
        records.append((name, len(combined), len(data))); combined.extend(data)
    bundle_name = 'bundles.00.nxa'
    index = bytearray(24 + len(records)*24 + 4)
    struct.pack_into('<6I', index, 0, 0x41415344, 0, 0, 1, len(records), 0)
    offsets = {}
    for name in [*(record[0] for record in records), bundle_name]:
        offsets[name] = len(index); index.extend(name.encode()+b'\0')
    for i, (name, logical, size) in enumerate(records):
        at = len(index); index.extend(struct.pack('<IIII', 0, 0, logical, 0))
        struct.pack_into('<QIIQ', index, 24+i*24, size, offsets[name], 1, at)
    struct.pack_into('<I', index, 24+len(records)*24, offsets[bundle_name])
    (folder/'bundles.nxa').write_bytes(dsar(bytes(index), 17))
    # Deliberately split headers, TOCs, and all three resource parts over DSAR chunks.
    (folder/bundle_name).write_bytes(dsar(bytes(combined), 97))
    return expected


def command(game, output, request, owner=0):
    return ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', str(ROOT/'tools/binding_provenance.ps1'), '-GameData', str(game),
            '-Output', str(output), '-Request', str(request), '-OwnerPID', str(owner)]


def hashes(folder):
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir() if p.is_file()}


def loose_patch(folder, name, resources):
    main = bytearray(104 + len(resources)*80)
    struct.pack_into('<III', main, 0, 0xf0000011, 1, len(resources))
    gpu, stream = bytearray(b'prefix-gpu'), bytearray(b'prefix-stream')
    for i, item in enumerate(resources):
        p, offset = 104+i*80, len(main)
        main.extend(item['main'])
        struct.pack_into('<QQQQQ', main, p, int(item['name'], 16), int(item['kind'], 16),
                         item.get('main_at', offset), item.get('stream_at', len(stream)), item.get('gpu_at', len(gpu)))
        main[p+40:p+56] = item.get('unknowns', bytes(range(16)))
        struct.pack_into('<III', main, p+56, item.get('main_size', len(item['main'])),
                         item.get('stream_size', len(item['stream'])), item.get('gpu_size', len(item['gpu'])))
        struct.pack_into('<III', main, p+68, *item.get('flags', (16, 64)), i+100)
        gpu.extend(item['gpu']); stream.extend(item['stream'])
    (folder/name).write_bytes(main)
    if len(gpu) > 10:
        (folder/(name+'.gpu_resources')).write_bytes(gpu)
    if len(stream) > 13:
        (folder/(name+'.stream')).write_bytes(stream)


def scope_fingerprint(folder):
    text = ''
    for path in sorted(folder.glob('*.patch_*')):
        if not re.fullmatch(r'[0-9a-fA-F]{16}\.patch_[0-9]+', path.name):
            continue
        text += path.name+'\t'
        for part in (path, Path(str(path)+'.gpu_resources'), Path(str(path)+'.stream')):
            text += (str(part.stat().st_size)+'\t'+hashlib.sha256(part.read_bytes()).hexdigest()+'\t') if part.exists() else '-\t-\t'
        text += '\n'
    return hashlib.sha256(text.encode()).hexdigest()


class BindingProvenanceWorker(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='epic-binding-provenance-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def run_worker(self, game, output=None, text=None, owner=0, request=None):
        output = output or self.root/'cache'
        explicit_request = request is not None
        request = request or self.root/'request.tsv'
        if text is not None or not explicit_request:
            request.write_text(text if text is not None else U1+'\t'+PREFERRED+'\n', encoding='utf-8')
        result = subprocess.run(command(game, output, request, owner), capture_output=True, text=True, timeout=35)
        return result, output, request

    def assert_refused(self, game, message, **kwargs):
        result, output, _ = self.run_worker(game, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn(message, (output/'error.txt').read_text())
        self.assertFalse((output/'complete.txt').exists())
        self.assertFalse(list(output.rglob('*.main')))
        self.assertFalse(list(output.rglob('*.pending')))

    def test_exact_parts_toc_sha_marker_full_catalog_and_atomic_refresh(self):
        game = self.root/'game'; expected = fixture(game); before = hashes(game)
        for _ in range(2):
            result, output, request = self.run_worker(game)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            marker = (output/'complete.txt').read_text().splitlines()
            stamp = hashlib.sha256((game/'bundles.nxa').read_bytes()).hexdigest().upper()
            request_stamp = hashlib.sha256(request.read_bytes()).hexdigest().upper()
            version = Path(marker[0])
            self.assertEqual(marker[1:], ['1', stamp]); self.assertEqual(version, output/stamp/request_stamp)
            rows = [line.split('\t') for line in (version/'resources.tsv').read_text().splitlines()]
            self.assertEqual(len(rows), 3)
            self.assertEqual([(row[0], row[1]) for row in rows], sorted((kind, name) for name, kind in ((U1, UNIT), (M1, MATERIAL), (M2, MATERIAL))))
            for kind, name, archive, main, gpu, stream, toc, main_sha, gpu_sha, stream_sha in rows:
                native = expected[(archive, name, kind)]
                for part, filename, digest in [('main', main, main_sha), ('gpu', gpu, gpu_sha), ('stream', stream, stream_sha)]:
                    if not native[part]:
                        self.assertEqual((filename, digest), ('-', '-')); continue
                    self.assertEqual(filename, f'{name}.{kind}.{part}')
                    self.assertEqual((version/filename).read_bytes(), native[part])
                    self.assertEqual(digest, hashlib.sha256(native[part]).hexdigest())
                self.assertEqual((version/toc).read_bytes(), native['toc'])
                self.assertEqual(len((version/toc).read_bytes()), 80)
            collisions = (version/'collisions.tsv').read_text().splitlines()
            expected_collisions = sorted(f'{kind}\t{name}' for _, name, kind in expected if kind in (UNIT, MATERIAL, TEXTURE))
            self.assertEqual(collisions, expected_collisions)
            self.assertIn(TEXTURE+'\t5555555555555555', collisions)
            self.assertIn(MATERIAL+'\t5656565656565656', collisions)
            self.assertIn(UNIT+'\t5757575757575757', collisions)
            collision_bytes = (version/'collisions.tsv').read_bytes()
            self.assertEqual(len(collision_bytes), len(collisions)*34)
            self.assertNotIn(b'\r', collision_bytes)
            self.assertEqual((version/'collisions.meta').read_bytes(),
                             str(len(collisions)).encode()+b'\n'+hashlib.sha256(collision_bytes).hexdigest().encode()+b'\n')
            self.assertFalse(list(output.rglob('*.pending')))
            self.assertEqual(hashes(game), before)

    def test_loose_identical_override_retains_exact_packed_toc(self):
        game = self.root/'game'; expected = fixture(game)
        copies = defaults()
        for item in copies:
            item['unknowns'] = struct.pack('<QQ', 0x0123456789abcdef, 0xfedcba9876543210)
        loose_patch(game, 'dddddddddddddddd.patch_9', copies)
        before = hashes(game)
        result, output, _ = self.run_worker(game)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        version = Path((output/'complete.txt').read_text().splitlines()[0])
        for line in (version/'resources.tsv').read_text().splitlines():
            kind, name, archive, _, _, _, toc = line.split('\t')[:7]
            self.assertEqual(archive, PREFERRED)
            self.assertEqual((version/toc).read_bytes(), expected[(PREFERRED, name, kind)]['toc'])
        self.assertEqual((version/'scope.meta').read_text().splitlines(),
                         ['top-level-game-data-patches-v1', '1', scope_fingerprint(game)])
        self.assertEqual(hashes(game), before)

    def test_loose_unrelated_lua_and_non_lut_ids_are_in_complete_scope(self):
        game = self.root/'game'; fixture(game)
        lua_name = 'dddddddddddddddd.patch_10'
        loose_patch(game, lua_name, [resource('9999999999999999', 'a14e8dfa2cd117e2', b'return true')])
        added = [('6666666666666666', TEXTURE), ('6767676767676767', MATERIAL), ('6868686868686868', UNIT)]
        loose_patch(game, 'eeeeeeeeeeeeeeee.patch_2', [resource(name, kind, b'unrelated non-LUT') for name, kind in added])
        # Subfolders and names outside the explicit top-level patch scope do not enter the catalog.
        nested = game/'nested'; nested.mkdir()
        loose_patch(nested, 'ffffffffffffffff.patch_1', [resource('6969696969696969', TEXTURE, b'external')])
        (game/'invalid.patch_1').write_bytes(b'out of scope')
        result, output, _ = self.run_worker(game)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        version = Path((output/'complete.txt').read_text().splitlines()[0])
        catalog = (version/'collisions.tsv').read_text().splitlines()
        for name, kind in added:
            self.assertIn(kind+'\t'+name, catalog)
        self.assertNotIn(TEXTURE+'\t6969696969696969', catalog)
        meta = (version/'scope.meta').read_text().splitlines()
        self.assertEqual(meta, ['top-level-game-data-patches-v1', '2', scope_fingerprint(game)])
        # Whole-triplet hashing detects a Lua-only payload change even when its TOC and length stay fixed.
        lua = bytearray((game/lua_name).read_bytes()); lua[-1] ^= 1; (game/lua_name).write_bytes(lua)
        result, _, _ = self.run_worker(game, output)
        self.assertEqual(result.returncode, 0, result.stderr)
        changed = (version/'scope.meta').read_text().splitlines()
        self.assertNotEqual(changed[2], meta[2]); self.assertEqual(changed[2], scope_fingerprint(game))

    def test_loose_requested_material_unit_payload_and_flag_conflicts_refuse(self):
        for label, index, part in [('material', 1, 'main'), ('unit', 0, 'gpu'), ('flags', 1, 'flags')]:
            game = self.root/label; fixture(game); item = defaults()[index]
            item[part] = (32, 64) if part == 'flags' else item[part]+b'!'
            loose_patch(game, 'dddddddddddddddd.patch_0', [item])
            self.assert_refused(game, 'Loose patch overrides requested binding source', output=self.root/(label+'-cache'))

    def test_loose_malformed_missing_and_part_bounds_refuse_entire_cache(self):
        for label, mutation, error in [
                ('magic', lambda p: p.write_bytes(b'X'*72), 'TOC header invalid'),
                ('count', lambda p: p.write_bytes(struct.pack('<III', 0xf0000011, 1, 100001)+b'\0'*60), 'TOC count bounds'),
                ('toc-short', lambda p: p.write_bytes(p.read_bytes()[:120]), 'part bounds'),
                ('main-offset', None, 'part bounds'), ('gpu-offset', None, 'part bounds'),
                ('gpu-missing', None, 'part missing'), ('stream-missing', None, 'part missing'),
                ('main-missing', None, 'main missing for companion')]:
            game = self.root/label; fixture(game); item = defaults()[1]
            if label == 'main-offset': item['main_at'] = 0xffffffffffffffff
            if label == 'gpu-offset': item['gpu_at'] = 0xffffffffffffffff
            name = 'dddddddddddddddd.patch_1'; loose_patch(game, name, [item]); path = game/name
            if mutation: mutation(path)
            elif label == 'gpu-missing': (game/(name+'.gpu_resources')).unlink()
            elif label == 'stream-missing': (game/(name+'.stream')).unlink()
            elif label == 'main-missing': path.unlink()
            self.assert_refused(game, error, output=self.root/(label+'-cache'))

    def test_preferred_owner_identical_duplicates_and_fallback(self):
        for label, archives in [('duplicates', {FALLBACK: [resource('ffffffffffffffff', '0000000000000011', b'decoy')]+defaults(), PREFERRED: defaults()}),
                                ('fallback', {PREFERRED: [], FALLBACK: defaults()})]:
            game = self.root/label; fixture(game, archives)
            result, output, _ = self.run_worker(game, self.root/(label+'-cache'))
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = (Path((output/'complete.txt').read_text().splitlines()[0])/'resources.tsv').read_text().splitlines()
            retained = PREFERRED if label == 'duplicates' else FALLBACK
            self.assertTrue(all(row.split('\t')[2] == retained for row in rows))

    def test_duplicate_payload_parts_and_toc_semantics_refuse(self):
        for part in ('main', 'gpu', 'stream', 'flags'):
            other = defaults()
            item = other[0] if part != 'main' else other[1]
            if part == 'flags':
                item[part] = (32, 64)
            else:
                item[part] = item[part] + b'!'
            game = self.root/part; fixture(game, {PREFERRED: defaults(), FALLBACK: other})
            self.assert_refused(game, 'Conflicting duplicate', output=self.root/(part+'-cache'))

    def test_archive_specific_qwords_preserve_exact_preferred_shared_or_fallback_toc(self):
        def copies(seed, include_unit=True):
            items = defaults() if include_unit else defaults()[1:]
            for i, item in enumerate(items):
                item['unknowns'] = struct.pack('<QQ', seed+i, 0xffff000000000000+seed+i)
            return items
        for label, archives, chosen in [
                ('preferred', {FALLBACK: copies(400), SECOND_SHARED: copies(300),
                               SHARED: copies(200), PREFERRED: copies(100)}, PREFERRED),
                ('shared', {FALLBACK: copies(400, False), SECOND_SHARED: copies(300, False),
                            PREFERRED: copies(100)[:1], SHARED: copies(200, False)}, SHARED),
                ('second-shared', {FALLBACK: copies(400, False),
                                   PREFERRED: copies(100)[:1], SECOND_SHARED: copies(300, False)}, SECOND_SHARED),
                ('ordinal', {UNRELATED: copies(500, False), PREFERRED: copies(100)[:1],
                             FALLBACK: copies(400, False)}, FALLBACK)]:
            game = self.root/label; expected = fixture(game, archives)
            result, output, _ = self.run_worker(game, self.root/(label+'-cache'))
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            version = Path((output/'complete.txt').read_text().splitlines()[0])
            rows = [line.split('\t') for line in (version/'resources.tsv').read_text().splitlines()]
            for row in rows:
                kind, name, archive, _, _, _, toc = row[:7]
                expected_archive = PREFERRED if kind == UNIT else chosen
                self.assertEqual(archive, expected_archive)
                self.assertEqual((version/toc).read_bytes(), expected[(expected_archive, name, kind)]['toc'])
                self.assertEqual((version/toc).read_bytes()[40:56], expected[(expected_archive, name, kind)]['toc'][40:56])
            # A second run must choose the same archive and original TOC bytes.
            initial = {p.name: p.read_bytes() for p in version.iterdir()}
            result, _, _ = self.run_worker(game, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({p.name: p.read_bytes() for p in version.iterdir()}, initial)

    def test_request_and_unit_table_bounds_before_publication(self):
        game = self.root/'requests'; fixture(game)
        for label, text, message in [('empty', '', 'request byte'), ('space', U1+' '+PREFERRED, 'dense'),
                                     ('extra', U1+'\t'+PREFERRED+'\n\n', 'dense'),
                                     ('duplicate', (U1+'\t'+PREFERRED+'\n')*2, 'Duplicate'),
                                     ('over64', ''.join(f'{i:016x}\t{PREFERRED}\n' for i in range(65)), 'unit bounds')]:
            self.assert_refused(game, message, output=self.root/(label+'-cache'), text=text)
        for label, edit, message in [('offset', lambda b: struct.pack_into('<I', b, 112, 0xffffffff), 'offset bounds'),
                                     ('count', lambda b: struct.pack_into('<I', b, 116, 65), 'count bounds'),
                                     ('zero', lambda b: struct.pack_into('<I', b, 116, 0), 'count bounds')]:
            items = defaults(); bad = bytearray(items[0]['main']); edit(bad); items[0]['main'] = bytes(bad)
            current = self.root/label; fixture(current, {PREFERRED: items})
            self.assert_refused(current, message, output=self.root/(label+'-cache'))
        items = defaults(); items[0]['main'] = unit(((7, M1), (7, M2)))
        ambiguous = self.root/'ambiguous'; fixture(ambiguous, {PREFERRED: items})
        self.assert_refused(ambiguous, 'Ambiguous', output=self.root/'ambiguous-cache')

    def test_missing_parts_file_budget_and_full_catalog_corruption_refuse(self):
        for label, mutate, error in [('missing-material', lambda x: x.pop(), 'material resources missing'),
                                     ('main-size', lambda x: x[0].update(main_size=PART_LIMIT+1), 'file byte budget'),
                                     ('gpu-size', lambda x: x[1].update(gpu_size=PART_LIMIT+1), 'file byte budget'),
                                     ('stream-size', lambda x: x[1].update(stream_size=PART_LIMIT+1), 'file byte budget'),
                                     ('bad-main-offset', lambda x: x[0].update(main_at=0xffffffffffffffff), 'Archive bounds')]:
            items = defaults(); mutate(items); game = self.root/label; fixture(game, {PREFERRED: items})
            self.assert_refused(game, error, output=self.root/(label+'-cache'))
        game = self.root/'missing-unit'; fixture(game)
        self.assert_refused(game, 'unit resources missing', output=self.root/'missing-unit-cache', text=U2+'\t'+PREFERRED)
        game = self.root/'short-stream'; items = defaults(); items[1]['stream_size'] = 2000
        fixture(game, {PREFERRED: items})
        self.assert_refused(game, 'Archive bounds', output=self.root/'short-stream-cache')
        for label, header, error in [('unrelated-magic', (0x12345678, 1, 1), 'TOC header invalid'),
                                     ('unrelated-count', (0xf0000011, 1, 100001), 'TOC count bounds'),
                                     ('unrelated-types', (0xf0000011, 4097, 1), 'TOC count bounds')]:
            game = self.root/label
            fixture(game, {PREFERRED: defaults(), UNRELATED: [resource('9999999999999999', TEXTURE, b'other')]},
                    headers={UNRELATED: header})
            self.assert_refused(game, error, output=self.root/(label+'-cache'))

    def test_oversized_logical_index_rejected_before_reader_allocation(self):
        game = self.root/'huge-index'; fixture(game)
        data = bytearray((game/'bundles.nxa').read_bytes())
        count = struct.unpack_from('<I', data, 8)[0]
        struct.pack_into('<Q', data, 32+(count-1)*32, 512*1024*1024)
        (game/'bundles.nxa').write_bytes(data)
        self.assert_refused(game, 'index metadata budget', output=self.root/'huge-index-cache')

    def test_exact_part_limit_64_units_and_64_materials(self):
        items = defaults(); items[0]['gpu'] = b'\xff' * PART_LIMIT
        game = self.root/'part-limit'; fixture(game, {PREFERRED: items})
        result, output, _ = self.run_worker(game, output=self.root/'part-limit-cache')
        self.assertEqual(result.returncode, 0, result.stderr)
        version = Path((output/'complete.txt').read_text().splitlines()[0])
        self.assertEqual((version/f'{U1}.{UNIT}.gpu').stat().st_size, PART_LIMIT)
        materials = [(i, f'{0x2000+i:016x}') for i in range(64)]
        items = [resource(U1, UNIT, unit(materials))]
        items.extend(resource(name, MATERIAL, material('3333333333333333')) for _, name in materials)
        game = self.root/'materials64'; fixture(game, {PREFERRED: items})
        result, output, _ = self.run_worker(game, output=self.root/'materials64-cache')
        self.assertEqual(result.returncode, 0, result.stderr)
        version = Path((output/'complete.txt').read_text().splitlines()[0])
        self.assertEqual(len((version/'resources.tsv').read_text().splitlines()), 65)
        ids = [f'{0x1000+i:016x}' for i in range(64)]
        items = [resource(name, UNIT, unit(((7, M1),))) for name in ids]
        items.append(resource(M1, MATERIAL, material('3333333333333333')))
        game = self.root/'units64'; fixture(game, {PREFERRED: items})
        result, output, _ = self.run_worker(game, output=self.root/'units64-cache',
                                          text=''.join(name+'\t'+PREFERRED+'\n' for name in ids))
        self.assertEqual(result.returncode, 0, result.stderr)
        version = Path((output/'complete.txt').read_text().splitlines()[0])
        self.assertEqual(len((version/'resources.tsv').read_text().splitlines()), 65)

    def test_set_budget_preflight_without_allocating_an_oversized_set(self):
        # Invoke the actual private preflight with a valid tiny TOC and retained
        # bytes at the limit. It must refuse before any reflected archive read.
        script = self.root/'set-budget.ps1'
        script.write_text("""$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText($args[0])+"`n"+[IO.File]::ReadAllText($args[1])
$imports=[regex]::Matches($source,'(?m)^using [^;]+;') | ForEach-Object {$_.Value} | Select-Object -Unique
$body=[regex]::Replace($source,'(?m)^using [^;]+;\\r?\\n?','')
Add-Type -TypeDefinition (($imports -join "`n")+"`n"+$body)
$toc=[byte[]]::new(80);$toc[56]=1
$method=[EpicBindingProvenanceReader].GetMethod('Load',[Reflection.BindingFlags]'NonPublic,Static')
$parameters=[object[]]@($null,$null,'bbbbbbbbbbbbbbbb',$toc,[int]0,'',[Diagnostics.Stopwatch]::StartNew(),[int]0,[long](256*1024*1024))
try {$method.Invoke($null,$parameters);throw 'Oversized set preflight was accepted'} catch {
 if($_.Exception.ToString() -notlike '*resource set byte budget exceeded*'){throw}
}
""", encoding='utf-8')
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                                 '-File', str(script), str(ROOT/'tools/original_snapshots.cs'),
                                 str(ROOT/'tools/binding_provenance_reader.cs')], capture_output=True, text=True, timeout=35)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def test_owner_heartbeat_changed_pid_and_cancellation(self):
        game = self.root/'game'; fixture(game)
        self.assert_refused(game, 'heartbeat expired', output=self.root/'no-heartbeat', owner=12345)
        output = self.root/'wrong-owner'; output.mkdir(); (output/'owner-heartbeat.txt').write_text('12346')
        self.assert_refused(game, 'owner changed', output=output, owner=12345)
        output = self.root/'right-owner'; output.mkdir(); (output/'owner-heartbeat.txt').write_text('12345')
        result, _, _ = self.run_worker(game, output=output, owner=12345)
        self.assertEqual(result.returncode, 0, result.stderr)
        canceled, request = self.root/'canceled', self.root/'request.tsv'
        process = subprocess.Popen(command(game, canceled, request), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic()+20
        while not (canceled/'progress.txt').exists() and process.poll() is None and time.monotonic()<deadline:
            time.sleep(0.01)
        self.assertTrue((canceled/'progress.txt').exists())
        (canceled/'progress.txt.cancel').write_text('cancel')
        stdout, stderr = process.communicate(timeout=35)
        self.assertNotEqual(process.returncode, 0, stdout+stderr)
        self.assertIn('canceled', (canceled/'error.txt').read_text())
        self.assertFalse((canceled/'complete.txt').exists())

    def test_output_and_request_cannot_write_into_game_or_redirect(self):
        game = self.root/'game'; fixture(game); before = hashes(game)
        result, _, _ = self.run_worker(game, output=game/'cache')
        self.assertNotEqual(result.returncode, 0); self.assertIn('cannot be inside game data', result.stderr)
        self.assertFalse((game/'cache').exists()); self.assertEqual(hashes(game), before)
        request = game/'request.tsv'; request.write_text(U1+'\t'+PREFERRED)
        result, output, _ = self.run_worker(game, output=self.root/'request-game', request=request)
        self.assertNotEqual(result.returncode, 0); self.assertFalse(output.exists())
        link = self.root/'cache-link'
        creation = subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                                  "New-Item -ItemType Junction -Path '"+str(link)+"' -Target '"+str(game)+"' | Out-Null"],
                                  capture_output=True, text=True, timeout=30)
        self.assertEqual(creation.returncode, 0, creation.stderr); self.addCleanup(link.rmdir)
        result, _, _ = self.run_worker(game, output=link)
        self.assertNotEqual(result.returncode, 0); self.assertIn('path is redirected', ' '.join(result.stderr.split()))
        self.assertFalse((game/'error.txt').exists())


if __name__ == '__main__':
    unittest.main()
