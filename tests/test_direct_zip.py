"""Exercise the no-Python ZIP worker using synthetic, data-only archives."""
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HEADER = bytearray(148)
for offset, value in {0:0x20534444,4:124,8:0x2100F,12:8,16:23,24:1,28:5,76:32,80:4,84:0x30315844,108:0x1000,128:10,132:3,140:1}.items():
    struct.pack_into('<I', HEADER, offset, value)
PIXELS = struct.pack('<' + 'e'*(23*8*4), *[(i-100)/9 for i in range(23*8*4)])
MAIN = bytes(192) + HEADER
PATCH = bytes(struct.pack('<III',0xF0000011,1,1)) + bytes(104-12)
PATCH += struct.pack('<7Q6I',1,0xCD4238C6A0C69E32,184,0,0,0,0,len(MAIN),0,len(PIXELS),0,0,0) + MAIN

# Generic fixture for the Lua -> Windows launcher -> worker -> Lua response test.
fixture=ROOT/'tests/tmp/files/importtest.zip'
fixture.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(fixture,'w',zipfile.ZIP_DEFLATED) as archive:
    archive.writestr('0123456789abcdef.patch_0',PATCH)
    archive.writestr('0123456789abcdef.patch_0.gpu_resources',PIXELS)


def run(package, output, result):
    return subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'tools/import_zip.ps1'),'-Package',str(package),'-Output',str(output),'-Result',str(result)], capture_output=True, text=True)


with tempfile.TemporaryDirectory(prefix='epic-direct-zip-') as temp:
    folder = Path(temp)
    package = folder/'mod.zip'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('Armor Vanilla/0123456789abcdef.patch_0',PATCH)
        archive.writestr('Armor Vanilla/0123456789abcdef.patch_0.gpu_resources',PIXELS)
        archive.writestr('ignored.exe',b'never executed or extracted')
    result=folder/'result.txt'
    completed=run(package,folder/'out',result)
    assert completed.returncode==0,(completed.stdout,completed.stderr,result.read_text())
    assert result.read_text().splitlines()==['ok','lut000.dds']
    data=(folder/'out/lut000.dds').read_bytes()
    assert struct.unpack_from('<I',data,28)[0]==1 and data[148:]==PIXELS
    assert len(list((folder/'out').iterdir()))==1

    for index, unsafe in enumerate(('../escape.dds','/absolute.dds','file:stream.dds')):
        with zipfile.ZipFile(package,'w')as archive:archive.writestr(unsafe,data)
        result=folder/f'bad{index}.txt'
        completed=run(package,folder/f'bad{index}',result)
        assert completed.returncode!=0 and result.read_text().startswith('error\nUnsafe ZIP member')

    with zipfile.ZipFile(package,'w')as archive:archive.writestr('palette.dds',data)
    completed=run(package,folder/'dds',folder/'dds.txt')
    assert completed.returncode==0,completed.stderr
    assert (folder/'dds/lut000.dds').read_bytes()==data

    # A large texture collection must not consume the LUT extraction budget.
    large_patch=bytearray(PATCH);offset=65*1024*1024
    struct.pack_into('<Q',large_patch,104+32,offset)
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        archive.writestr('0123456789abcdef.patch_0',large_patch)
        block=bytes(1024*1024)
        with archive.open('0123456789abcdef.patch_0.gpu_resources','w')as member:
            for _ in range(65):member.write(block)
            member.write(PIXELS)
        with archive.open('unrelated/huge-texture.bin','w')as member:
            for _ in range(270):member.write(block)
    result=folder/'large.txt';completed=run(package,folder/'large',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert (folder/'large/lut000.dds').read_bytes()[148:]==PIXELS

    # Palette collections are no longer stopped at the previous 32-LUT cap.
    with zipfile.ZipFile(package,'w')as archive:
        for index in range(40):archive.writestr(f'palette{index}.dds',data)
    result=folder/'many.txt';completed=run(package,folder/'many',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert len(list((folder/'many').glob('*.dds')))==40

    # Resource records follow 72 + 32 * type_count, not a fixed 104-byte header.
    types=3;start=72+32*types;main_at=start+80*3
    mixed=bytearray(main_at)
    struct.pack_into('<III',mixed,0,0xF0000011,types,3)
    # Material record, empty/reference-only texture record, then the actual LUT.
    struct.pack_into('<7Q6I',mixed,start,2,0xEAC0B497876ADEDF,0,0,0,0,0,0,0,0,0,0,0)
    struct.pack_into('<7Q6I',mixed,start+80,3,0xCD4238C6A0C69E32,0,0,0,0,0,0,0,0,0,0,0)
    struct.pack_into('<7Q6I',mixed,start+160,1,0xCD4238C6A0C69E32,main_at,0,0,0,0,len(MAIN),0,len(PIXELS),0,0,0)
    mixed.extend(MAIN)
    with zipfile.ZipFile(package,'w')as archive:
        archive.writestr('0123456789abcdef.patch_0',mixed)
        archive.writestr('0123456789abcdef.patch_0.gpu_resources',PIXELS)
    result=folder/'mixed.txt';completed=run(package,folder/'mixed',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert (folder/'mixed/lut000.dds').read_bytes()[148:]==PIXELS
    struct.pack_into('<Q',mixed,start+160+16,len(mixed)+100)
    with zipfile.ZipFile(package,'w')as archive:archive.writestr('0123456789abcdef.patch_0',mixed)
    result=folder/'invalid-offset.txt';completed=run(package,folder/'invalid-offset',result)
    assert completed.returncode!=0 and 'Invalid resource offset in' in result.read_text()

    sevenzip=Path(r'C:\Program Files\7-Zip\7z.exe')
    if sevenzip.exists():
        rar=folder/'fixture.rar'
        with zipfile.ZipFile(rar,'w')as archive:archive.writestr('palette.dds',data)
        result=folder/'rar.txt';completed=run(rar,folder/'rar',result)
        assert completed.returncode==0,(completed.stderr,result.read_text())
        assert (folder/'rar/lut000.dds').read_bytes()==data
    result=folder/'cancel.txt';Path(str(result)+'.cancel').write_text('cancel')
    completed=run(package,folder/'cancel',result)
    assert result.read_text()=='cancel','Cancellation was not acknowledged'

print('PASS no-Python ZIP worker: exact patch pixels, 65 MB sidecar range, 270 MB irrelevant member ignored, 40 palettes, direct DDS and unsafe path rejection')
