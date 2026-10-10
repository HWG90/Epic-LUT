"""Exercise the runtime PowerShell/.NET worker with synthetic read-only archives."""
from pathlib import Path
import hashlib
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
AVATAR = '4d1c334d294dfa97'
UNIT = 'e0a48d0be9a7453f'
BONES = '18dead01056b72e9'
ANIMATION = '931e336d7646cc26'
CLIPS = ('759c08277f1296d0', '070b422612518deb', 'e32b270524630569', '39250e5b6313a0b2')
OWNER = '18235e0c9ec0e636'


def dsar(data, width=128):
    chunks = [data[i:i+width] for i in range(0, len(data), width)]
    result = bytearray(32+32*len(chunks))
    result[:4] = b'DSAR'
    struct.pack_into('<I', result, 8, len(chunks))
    logical = 0
    for i, chunk in enumerate(chunks):
        struct.pack_into('<QQIIB7x', result, 32+i*32, logical, len(result), len(chunk), len(chunk), 0)
        result.extend(chunk)
        logical += len(chunk)
    return bytes(result)


def bodies():
    unit = bytearray(56)
    struct.pack_into('<Q', unit, 8, int(AVATAR, 16))
    bone = struct.pack('<4I', 2, 0, 1, 2)+b'hips\0r_hand\0'
    result = {(AVATAR, UNIT): bytes(unit), (AVATAR, BONES): bone}
    for i, clip in enumerate(CLIPS):
        result[clip, ANIMATION] = struct.pack('<IIfIII', i, 2, 1.0+i, 24, 0, 0)
    return result


def fixture(folder, fallback=False, missing=False, oversized=False):
    folder.mkdir(parents=True)
    expected = bodies()
    resources = dict(expected)
    if missing:
        resources.pop((CLIPS[-1], ANIMATION))
    # Same name, wrong type must never be mistaken for the unit or bones.
    resources[AVATAR, '0000000000000011'] = b'decoy'
    archives = {OWNER: {}, 'aaaaaaaaaaaaaaaa': resources} if fallback else {OWNER: resources}
    combined = bytearray()
    records = []
    for name, items in archives.items():
        archive = bytearray(72+32+80*len(items))
        struct.pack_into('<III', archive, 0, 0xf0000011, 1, len(items))
        for i, ((resource, kind), body) in enumerate(items.items()):
            at = len(archive)
            archive.extend(body)
            p = 104+i*80
            struct.pack_into('<QQQ', archive, p, int(resource, 16), int(kind, 16), at)
            size = 16*1024*1024+1 if oversized and (resource, kind) == (AVATAR, UNIT) else len(body)
            struct.pack_into('<I', archive, p+56, size)
        records.append((name, len(combined), len(archive)))
        combined.extend(archive)
    bundle_name = 'bundles.00.nxa'
    index = bytearray(24+24*len(records)+4)
    struct.pack_into('<6I', index, 0, 0x41415344, 0, 0, 1, len(records), 0)
    offsets = {}
    for name in [*(name for name, _, _ in records), bundle_name]:
        offsets[name] = len(index)
        index.extend(name.encode()+b'\0')
    for i, (name, logical, size) in enumerate(records):
        spans = len(index)
        index.extend(struct.pack('<IIII', 0, 0, logical, 0))
        struct.pack_into('<QIIQ', index, 24+i*24, size, offsets[name], 1, spans)
    struct.pack_into('<I', index, 24+24*len(records), offsets[bundle_name])
    (folder/'bundles.nxa').write_bytes(dsar(bytes(index), 17))
    (folder/bundle_name).write_bytes(dsar(bytes(combined)))
    return {f'{resource}.{kind}.bin': body for (resource, kind), body in expected.items()}


def command(game, output, owner=0):
    return ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', str(ROOT/'tools/authored_preview.ps1'), '-GameData', str(game),
            '-Output', str(output), '-OwnerPID', str(owner)]


def hashes(folder):
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in folder.iterdir() if path.is_file()}


class AuthoredPreviewWorker(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='epic-authored-worker-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_exact_pairs_marker_source_immutability_and_atomic_refresh(self):
        game, output = self.root/'game', self.root/'cache'
        expected = fixture(game)
        before = hashes(game)
        for _ in range(2):
            result = subprocess.run(command(game, output), capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            lines = (output/'complete.txt').read_text().splitlines()
            self.assertEqual(lines[1:], ['1'])
            stamp = hashlib.sha256((game/'bundles.nxa').read_bytes()).hexdigest().upper()
            version = Path(lines[0])
            self.assertEqual(version, output/stamp)
            self.assertEqual({path.name: path.read_bytes() for path in version.iterdir()}, expected)
            self.assertFalse(list(output.rglob('*.pending')))
            self.assertEqual(hashes(game), before)
        self.assertIn('1 TOCs', (output/'progress.txt').read_text())

    def test_bounded_fallback_to_other_owner(self):
        game, output = self.root/'game', self.root/'cache'
        expected = fixture(game, fallback=True)
        result = subprocess.run(command(game, output), capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        folder = Path((output/'complete.txt').read_text().splitlines()[0])
        self.assertEqual({path.name: path.read_bytes() for path in folder.iterdir()}, expected)
        self.assertIn('2 TOCs', (output/'progress.txt').read_text())

    def test_incomplete_and_oversized_sets_publish_no_resources(self):
        for name, options, message in [('missing', {'missing': True}, 'resources missing'),
                                       ('oversized', {'oversized': True}, 'byte budget')]:
            game, output = self.root/name, self.root/(name+'-cache')
            fixture(game, **options)
            result = subprocess.run(command(game, output), capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, (output/'error.txt').read_text())
            self.assertFalse((output/'complete.txt').exists())
            self.assertFalse(list(output.rglob('*.bin')))

    def test_owner_heartbeat_and_cancellation(self):
        game, output = self.root/'game', self.root/'heartbeat-cache'
        fixture(game)
        result = subprocess.run(command(game, output, owner=12345), capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('heartbeat expired', (output/'error.txt').read_text())
        self.assertFalse((output/'complete.txt').exists())
        canceled = self.root/'cancel-cache'
        process = subprocess.Popen(command(game, canceled), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic()+20
        status = canceled/'progress.txt'
        while not status.exists() and process.poll() is None and time.monotonic()<deadline:
            time.sleep(0.01)
        self.assertTrue(status.exists(), 'Worker never published status')
        (canceled/'progress.txt.cancel').write_text('cancel')
        stdout, stderr = process.communicate(timeout=30)
        self.assertNotEqual(process.returncode, 0, stdout+stderr)
        self.assertIn('canceled', (canceled/'error.txt').read_text())
        self.assertFalse((canceled/'complete.txt').exists())

    def test_cache_cannot_write_into_game_data(self):
        game = self.root/'game'
        fixture(game)
        before = hashes(game)
        result = subprocess.run(command(game, game/'cache'), capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot be inside game data', ' '.join(result.stderr.split()))
        self.assertEqual(hashes(game), before)
        self.assertFalse((game/'cache').exists())

    def test_cache_junction_does_not_write_even_error_into_game_data(self):
        game, link = self.root/'game', self.root/'cache-link'
        fixture(game)
        before = hashes(game)
        creation = subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                                   "New-Item -ItemType Junction -Path '"+str(link)+"' -Target '"+str(game)+"' | Out-Null"],
                                  capture_output=True, text=True, timeout=30)
        self.assertEqual(creation.returncode, 0, creation.stderr)
        self.addCleanup(link.rmdir)
        result = subprocess.run(command(game, link), capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cache path is redirected', ' '.join(result.stderr.split()))
        self.assertEqual(hashes(game), before)


if __name__ == '__main__':
    unittest.main()
