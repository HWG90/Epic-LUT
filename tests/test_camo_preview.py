"""Bounded C# atlas extraction on synthetic, read-only game archives."""
from pathlib import Path
import hashlib
import struct
import subprocess
import tempfile
import unittest
from test_authored_preview import dsar

ROOT = Path(__file__).resolve().parents[1]
ATLAS, TEXTURE, OWNER = 'eecf271273d7090c', 'cd4238c6a0c69e32', '18235e0c9ec0e636'
STRIDE, OFFSET, TOTAL = 349524, 348160, 2097144


def fixture(folder, wrong_format=False, wrong_layers=False, missing=False, fallback=False, short_gpu=False):
    folder.mkdir(parents=True)
    header = bytearray(340)
    for offset, value in {192:0x20534444,196:124,204:256,208:256,220:9,268:32,
                          276:0x30315844,320:2 if wrong_format else 28,324:3,332:5 if wrong_layers else 6}.items():
        struct.pack_into('<I', header, offset, value)
    gpu = bytearray(TOTAL)
    expected = {}
    for layer in range(6):
        mask = bytes((i + layer * 19) % 256 for i in range(1024))
        gpu[layer * STRIDE + OFFSET:layer * STRIDE + OFFSET + 1024] = mask
        expected[f'mask-{layer}.rgba'] = mask
    main = bytearray(184) + header
    struct.pack_into('<III', main, 0, 0xf0000011, 1, 1)
    struct.pack_into('<QQQ', main, 104, int(ATLAS if not missing else '0000000000000001',16), int(TEXTURE,16), 184)
    struct.pack_into('<I', main, 104+56, len(header))
    struct.pack_into('<I', main, 104+64, TOTAL-1 if short_gpu else TOTAL)
    archive_name = 'aaaaaaaaaaaaaaaa' if fallback else OWNER
    archives = [(archive_name, bytes(main)), (archive_name+'.gpu_resources', bytes(gpu))]
    if fallback:
        empty = bytearray(72)
        struct.pack_into('<I', empty, 0, 0xf0000011)
        archives.append((OWNER, bytes(empty)))
    archives.sort()
    bundle = bytearray()
    records = []
    for name, data in archives:
        records.append((name, len(bundle), len(data))); bundle.extend(data)
    bundle_name = 'bundles.00.nxa'
    index = bytearray(24 + 24 * len(records) + 4)
    struct.pack_into('<6I', index, 0, 0x41415344, 0, 0, 1, len(records), 0)
    offsets = {}
    for name in [*(name for name,_,_ in records), bundle_name]:
        offsets[name] = len(index); index.extend(name.encode()+b'\0')
    for i,(name,logical,size) in enumerate(records):
        entries = len(index); index.extend(struct.pack('<IIII',0,0,logical,0))
        struct.pack_into('<QIIQ', index, 24+i*24, size, offsets[name], 1, entries)
    struct.pack_into('<I', index, 24+24*len(records), offsets[bundle_name])
    (folder/'bundles.nxa').write_bytes(dsar(bytes(index),17))
    (folder/bundle_name).write_bytes(dsar(bytes(bundle),8192))
    return expected


def command(game, output, owner=0):
    return ['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
            '-File',str(ROOT/'tools/camo_preview.ps1'),'-GameData',str(game),'-Output',str(output),'-OwnerPID',str(owner)]


class CamoPreviewTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='epic-camo-worker-')
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def test_exact_mip_slices_marker_and_source_immutability(self):
        game, output = self.root/'game', self.root/'cache'
        expected = fixture(game)
        before = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in game.iterdir()}
        for _ in range(2):
            result = subprocess.run(command(game,output),capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            marker = (output/'complete.txt').read_text().splitlines()
            self.assertEqual(marker[1:],['1'])
            version = Path(marker[0])
            self.assertEqual(version,output/hashlib.sha256((game/'bundles.nxa').read_bytes()).hexdigest().upper())
            self.assertEqual({p.name:p.read_bytes() for p in version.iterdir()},expected)
            self.assertFalse(list(output.rglob('*.pending')))
        self.assertEqual({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in game.iterdir()},before)

    def test_header_gpu_missing_and_fallback_boundaries(self):
        for name, options, error in [
            ('format',{'wrong_format':True},'format changed'),('layers',{'wrong_layers':True},'format changed'),
            ('gpu',{'short_gpu':True},'GPU layout changed'),('missing',{'missing':True},'resource missing'),
        ]:
            game, output = self.root/name,self.root/(name+'-cache')
            fixture(game,**options)
            result = subprocess.run(command(game,output),capture_output=True,text=True,timeout=30)
            self.assertNotEqual(result.returncode,0)
            self.assertIn(error,(output/'error.txt').read_text())
            self.assertFalse((output/'complete.txt').exists())
            self.assertFalse(list(output.rglob('*.rgba')))
        game, output = self.root/'fallback', self.root/'fallback-cache'
        expected = fixture(game,fallback=True)
        result = subprocess.run(command(game,output),capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        version = Path((output/'complete.txt').read_text().splitlines()[0])
        self.assertEqual({p.name:p.read_bytes() for p in version.iterdir()},expected)

    def test_game_root_and_redirected_cache_are_protected(self):
        game, link = self.root/'game',self.root/'cache-link'
        fixture(game)
        result = subprocess.run(command(game,game/'cache'),capture_output=True,text=True,timeout=30)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse((game/'cache').exists())
        created = subprocess.run(['powershell.exe','-NoProfile','-Command',
            "New-Item -ItemType Junction -Path '"+str(link)+"' -Target '"+str(game)+"' | Out-Null"],capture_output=True,text=True)
        self.assertEqual(created.returncode,0,created.stderr)
        self.addCleanup(link.rmdir)
        result = subprocess.run(command(game,link),capture_output=True,text=True,timeout=30)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('cache path is redirected',result.stderr)
        self.assertFalse((game/'error.txt').exists())

    def test_missing_owner_heartbeat_publishes_no_mips(self):
        game, output = self.root/'game', self.root/'cache'
        fixture(game)
        result = subprocess.run(command(game,output,12345),capture_output=True,text=True,timeout=30)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('heartbeat expired',(output/'error.txt').read_text())
        self.assertFalse((output/'complete.txt').exists())
        self.assertFalse(list(output.rglob('*.rgba')))


if __name__ == '__main__':
    unittest.main()
