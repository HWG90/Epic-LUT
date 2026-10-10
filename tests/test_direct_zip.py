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
    assert result.read_text().splitlines()==['ok','lut001.dds']
    data=(folder/'out/lut001.dds').read_bytes()
    assert struct.unpack_from('<I',data,28)[0]==1 and data[148:]==PIXELS
    assert (folder/'out/resources.tsv').read_text()=='lut001.dds\t0000000000000001'
    assert len(list((folder/'out').iterdir()))==3

    for index, unsafe in enumerate(('../escape.dds','/absolute.dds','file:stream.dds')):
        with zipfile.ZipFile(package,'w')as archive:archive.writestr(unsafe,data)
        result=folder/f'bad{index}.txt'
        completed=run(package,folder/f'bad{index}',result)
        assert completed.returncode!=0 and result.read_text().startswith('error\nUnsafe ZIP member')

    with zipfile.ZipFile(package,'w')as archive:archive.writestr('palette.dds',data)
    completed=run(package,folder/'dds',folder/'dds.txt')
    assert completed.returncode==0,completed.stderr
    assert (folder/'dds/lut001.dds').read_bytes()==data

    # The complete custom-row range imports intact; row 65 remains unsupported.
    tall_header=bytearray(data[:148]);struct.pack_into('<I',tall_header,12,64)
    tall_pixels=struct.pack('<'+'e'*(23*64*4),*[(i%109-50)/9 for i in range(23*64*4)])
    tall_dds=bytes(tall_header)+tall_pixels
    with zipfile.ZipFile(package,'w')as archive:archive.writestr('tall.dds',tall_dds)
    result=folder/'tall.txt';completed=run(package,folder/'tall',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert (folder/'tall/lut001.dds').read_bytes()==tall_dds
    struct.pack_into('<I',tall_header,12,65)
    with zipfile.ZipFile(package,'w')as archive:archive.writestr('too-tall.dds',bytes(tall_header)+tall_pixels)
    result=folder/'too-tall.txt';completed=run(package,folder/'too-tall',result)
    assert completed.returncode!=0 and result.read_text().startswith('error\n'), 'ZIP import accepted row 65'

    # Shared Armory bundles preserve exact manifest IDs, metadata and Pattern bytes.
    pattern_header=bytearray(data[:148])
    for offset,value in {12:1,16:3,20:48,128:2}.items():struct.pack_into('<I',pattern_header,offset,value)
    pattern_dds=bytes(pattern_header)+struct.pack('<12f',*[i/9-1 for i in range(12)])
    manifest='EPIC-OUTFIT\t2\narmor\t0:1:0:0\tlut001.dds\t0000000000000001\t23\t8\tlut001.patch-source\nhelmet\tp:0:0:0:0\tlut002.dds\t0000000000000002\t3\t1\tlut002.patch-source'
    material_meta=b'0123456789abcdef\n'+bytes(192)+data[:148]
    pattern_meta=b'0123456789abcdef\n'+bytes(192)+pattern_dds[:148]
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        for name,payload in [('preset.tsv',manifest.encode()),('lut001.dds',data),('lut002.dds',pattern_dds),('lut001.patch-source',material_meta),('lut002.patch-source',pattern_meta),('ignored.lua',b'error("never execute")')]:archive.writestr(name,payload)
    result=folder/'preset.txt';completed=run(package,folder/'preset',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert result.read_text().splitlines()==['preset','preset.tsv','mod']
    assert (folder/'preset/preset.tsv').read_text()==manifest and (folder/'preset/lut002.dds').read_bytes()==pattern_dds
    assert (folder/'preset/lut001.patch-source').read_bytes()==material_meta and len(list((folder/'preset').iterdir()))==5
    fixture=ROOT/'tests/tmp/files/armorytest.zip'
    fixture.write_bytes(package.read_bytes())
    cape_dds=bytearray(data)
    struct.pack_into('<f',cape_dds,148,.875)
    cape_manifest=manifest+'\ncape\t0:2:1:0\tlut003.dds\t0000000000000001\t23\t8\tlut003.patch-source'
    with zipfile.ZipFile(package,'w')as archive:
        for name,payload in [('preset.tsv',cape_manifest.encode()),('lut001.dds',data),('lut002.dds',pattern_dds),('lut003.dds',cape_dds),('lut001.patch-source',material_meta),('lut002.patch-source',pattern_meta),('lut003.patch-source',material_meta)]:archive.writestr(name,payload)
    result=folder/'cape-preset.txt';completed=run(package,folder/'cape-preset',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert (folder/'cape-preset/preset.tsv').read_text()==cape_manifest and (folder/'cape-preset/lut003.dds').read_bytes()==cape_dds
    assert len(list((folder/'cape-preset').iterdir()))==7,'Cape bundle lost shared-ID variant or metadata'
    tall_manifest=manifest.replace('\t23\t8\t','\t23\t64\t')
    tall_meta=b'0123456789abcdef\n'+bytes(192)+tall_dds[:148]
    with zipfile.ZipFile(package,'w')as archive:
        for name,payload in [('preset.tsv',tall_manifest.encode()),('lut001.dds',tall_dds),('lut002.dds',pattern_dds),('lut001.patch-source',tall_meta),('lut002.patch-source',pattern_meta)]:archive.writestr(name,payload)
    result=folder/'tall-preset.txt';completed=run(package,folder/'tall-preset',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert (folder/'tall-preset/lut001.dds').read_bytes()==tall_dds and (folder/'tall-preset/lut001.patch-source').read_bytes()==tall_meta
    invalid_tall_manifest=tall_manifest.replace('\t23\t64\t','\t23\t65\t')
    with zipfile.ZipFile(package,'w')as archive:
        for name,payload in [('preset.tsv',invalid_tall_manifest.encode()),('lut001.dds',tall_dds),('lut002.dds',pattern_dds),('lut001.patch-source',tall_meta),('lut002.patch-source',pattern_meta)]:archive.writestr(name,payload)
    result=folder/'too-tall-preset.txt';completed=run(package,folder/'too-tall-preset',result)
    assert completed.returncode!=0 and 'Invalid shared preset patch metadata' in result.read_text(), 'Preset import accepted row-65 metadata'
    for index,bad_manifest in enumerate((manifest.replace('lut001.dds','../outside.dds'),manifest.replace('0000000000000001','not-a-texture-id'),manifest+'\n'+manifest.splitlines()[1])):
        with zipfile.ZipFile(package,'w')as archive:
            for name,payload in [('preset.tsv',bad_manifest.encode()),('lut001.dds',data),('lut002.dds',pattern_dds),('lut001.patch-source',material_meta),('lut002.patch-source',pattern_meta)]:archive.writestr(name,payload)
        result=folder/f'bad-preset{index}.txt';completed=run(package,folder/f'bad-preset{index}',result)
        assert completed.returncode!=0 and result.read_text().startswith('error\n'),'Unsafe shared preset accepted'

    # Transmog aliases retain all 4,096 targets while extracting shared payloads once.
    # Same resource ID with different bytes stays distinct; shared bytes with different
    # destination metadata also retain the metadata belonging to each manifest row.
    many_cape=bytearray(tall_dds);struct.pack_into('<e',many_cape,148,.875)
    alternate_meta=b'fedcba9876543210\n'+bytes(192)+tall_dds[:148]
    payloads={
        'armor.dds':tall_dds,'pattern.dds':pattern_dds,'cape.dds':many_cape,
        'armor.patch-source':tall_meta,'alternate.patch-source':alternate_meta,
        'pattern.patch-source':pattern_meta,'cape.patch-source':tall_meta,
    }
    many_rows=['EPIC-OUTFIT\t2']
    for index in range(4096):
        if index%4==0:
            fields=('armor',f'0:{index}:0:0','armor.dds','0000000000000001','23','64','armor.patch-source')
        elif index%4==1:
            fields=('armor',f'0:{index}:0:0','armor.dds','0000000000000003','23','64','alternate.patch-source')
        elif index%4==2:
            fields=('helmet',f'p:0:{index}:0:0','pattern.dds','0000000000000002','3','1','pattern.patch-source')
        else:
            fields=('cape',f'0:{index}:0:0','cape.dds','0000000000000001','23','64','cape.patch-source')
        many_rows.append('\t'.join(fields))
    many_manifest='\n'.join(many_rows)
    assert len(many_manifest.encode())>65536 and len(tall_dds)*4096>8*1024*1024
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        archive.writestr('preset.tsv',many_manifest)
        for name,payload in payloads.items():archive.writestr(name,payload)
    result=folder/'many-preset.txt';completed=run(package,folder/'many-preset',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert result.read_text().splitlines()==['preset','preset.tsv','mod']
    assert (folder/'many-preset/preset.tsv').read_text()==many_manifest,'Transmog target rows were discarded'
    assert {file.name for file in (folder/'many-preset').iterdir()}=={'preset.tsv',*payloads}
    for name,payload in payloads.items():assert (folder/'many-preset'/name).read_bytes()==payload

    # The target, manifest, member and unique extracted-payload bounds fail before
    # publishing an output folder. Aliased material files cannot bypass Pattern checks.
    failure_packages=[
        ('target-overflow',many_manifest+'\narmor\t0:4096:0:0\tarmor.dds\t-\t-\t-\t-',payloads,'Invalid shared preset manifest'),
        ('manifest-overflow','EPIC-OUTFIT\t2\n'+'x'*(2*1024*1024),{},'Preset manifest budget exceeded'),
        ('alias-shape','\n'.join((many_rows[0],many_rows[1],many_rows[1].replace('0:0:0:0','p:0:9:0:0'))),payloads,'Invalid shared preset LUT shape'),
        ('alias-duplicate','\n'.join((many_rows[0],many_rows[1],many_rows[1])),payloads,'Duplicate shared preset target'),
        ('alias-metadata','\n'.join((many_rows[0],many_rows[3].replace('\t3\t1\t','\t3\t2\t'))),payloads,'Invalid shared preset patch metadata'),
    ]
    for name,bad_manifest,members,error in failure_packages:
        with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
            archive.writestr('preset.tsv',bad_manifest)
            for member,payload in members.items():archive.writestr(member,payload)
        result=folder/f'{name}.txt';output=folder/name;completed=run(package,output,result)
        assert completed.returncode!=0 and error in result.read_text(),(name,completed.stderr,result.read_text())
        assert not output.exists(),f'{name} published a partially validated preset'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        archive.writestr('preset.tsv','EPIC-OUTFIT\t1\narmor\t0:0:0:0\tlarge0.dds')
        for index in range(8192):archive.writestr(f'large{index}.dds',data)
    result=folder/'members-boundary.txt';completed=run(package,folder/'members-boundary',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert len(list((folder/'members-boundary').iterdir()))==2,'Unreferenced shared preset members were extracted'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        archive.writestr('preset.tsv','EPIC-OUTFIT\t1\narmor\t0:0:0:0\tlarge0.dds')
        for index in range(8193):archive.writestr(f'large{index}.dds',data)
    result=folder/'members-overflow.txt';completed=run(package,folder/'members-overflow',result)
    assert completed.returncode!=0 and 'Shared preset has too many members' in result.read_text()
    assert not (folder/'members-overflow').exists()
    budget_rows=['EPIC-OUTFIT\t1']
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        for index in range(8):
            name=f'large{index}.dds';budget_rows.append(f'armor\t0:{index}:0:0\t{name}')
            archive.writestr(name,data+bytes(1024*1024-len(data)))
        archive.writestr('preset.tsv','\n'.join(budget_rows))
    result=folder/'payloads-boundary.txt';completed=run(package,folder/'payloads-boundary',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert len(list((folder/'payloads-boundary').iterdir()))==9,'Manifest consumed the independent payload budget'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        for index in range(9):archive.writestr(f'large{index}.dds',data+bytes(1024*1024-len(data)))
        archive.writestr('preset.tsv','\n'.join((*budget_rows,'armor\t0:8:0:0\tlarge8.dds')))
    result=folder/'payloads-overflow.txt';completed=run(package,folder/'payloads-overflow',result)
    assert completed.returncode!=0 and 'Shared preset extraction budget exceeded' in result.read_text()
    assert not (folder/'payloads-overflow').exists()

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
    assert (folder/'large/lut001.dds').read_bytes()[148:]==PIXELS

    # Palette collections are no longer stopped at the previous 32-LUT cap.
    with zipfile.ZipFile(package,'w')as archive:
        for index in range(40):archive.writestr(f'palette{index}.dds',data)
    result=folder/'many.txt';completed=run(package,folder/'many',result)
    assert completed.returncode==0,(completed.stderr,result.read_text())
    assert len(list((folder/'many').glob('*.dds')))==40
    assert not (folder/'many/resources.tsv').read_text().strip(), 'Plain DDS files must not acquire guessed IDs'

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
    assert (folder/'mixed/lut001.dds').read_bytes()[148:]==PIXELS
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
        assert (folder/'rar/lut001.dds').read_bytes()==data
    result=folder/'cancel.txt';Path(str(result)+'.cancel').write_text('cancel')
    completed=run(package,folder/'cancel',result)
    assert result.read_text()=='cancel','Cancellation was not acknowledged'

print('PASS no-Python ZIP worker: exact pixels, 4,096 aliased preset targets, per-target metadata, bounded unique extraction, 65 MB sidecar range, 270 MB irrelevant member ignored, 40 palettes and unsafe path rejection')
