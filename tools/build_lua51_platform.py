"""Build the source-only stock Lua5.1 platform helper; never installs or deploys."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VCVARS = Path('C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat')

def exports(data):
    assert data[:2] == b'MZ'
    pe = struct.unpack_from('<I', data, 60)[0]
    assert data[pe:pe+4] == b'PE\0\0' and struct.unpack_from('<H', data, pe+4)[0] == 0x8664
    count, optional_size = struct.unpack_from('<H', data, pe+6)[0], struct.unpack_from('<H', data, pe+20)[0]
    optional = pe+24
    assert struct.unpack_from('<H', data, optional)[0] == 0x20b
    sections = [struct.unpack_from('<IIII', data, optional+optional_size+i*40+8) for i in range(count)]
    def offset(rva):
        for virtual_size, virtual_at, raw_size, raw_at in sections:
            if virtual_at <= rva < virtual_at+max(virtual_size,raw_size):
                assert rva-virtual_at < raw_size
                return raw_at+rva-virtual_at
        raise ValueError('Unmapped PE export address')
    export_rva = struct.unpack_from('<I', data, optional+112)[0]
    directory = offset(export_rva)
    names_count, names_rva = struct.unpack_from('<I', data, directory+24)[0], struct.unpack_from('<I', data, directory+32)[0]
    assert names_count <= 128
    names = []
    for i in range(names_count):
        at = offset(struct.unpack_from('<I', data, offset(names_rva)+i*4)[0])
        end = data.index(0,at,at+256)
        names.append(data[at:end].decode('ascii'))
    return names

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'dist/native-lua51-platform')
    args = parser.parse_args()
    output = args.output.resolve(); output.mkdir(parents=True,exist_ok=True)
    assert VCVARS.is_file(), 'Existing Visual Studio2022 C build tools unavailable; no installation attempted'
    source = ROOT/'native/lua51_platform.c'
    for path in [VCVARS,source,output]:
        assert not any(char in str(path) for char in '%!\r\n'), 'Unsupported command path'
    build = output/'build-platform.cmd'
    build.write_text('@echo off\ncall "'+str(VCVARS)+'" >nul\nif errorlevel 1 exit /b %errorlevel%\n'
        +'cl /nologo /LD /MT /O2 /W4 /WX "'+str(source)+'" /link /OUT:EpicLutLua51Platform.dll /DYNAMICBASE /NXCOMPAT /INCREMENTAL:NO /Brepro user32.lib shell32.lib\n',newline='\r\n')
    subprocess.run(['cmd.exe','/d','/c',str(build)],cwd=output,check=True)
    data=(output/'EpicLutLua51Platform.dll').read_bytes()
    names=exports(data)
    assert names == ['epic_lut_platform','epic_lut_platform_close','epic_lut_platform_open'], names
    digest=hashlib.sha256(data).hexdigest()
    dll=output/('EpicLutLua51Platform-'+digest[:16]+'.dll')
    if dll.exists(): assert hashlib.sha256(dll.read_bytes()).hexdigest()==digest
    else: shutil.copyfile(output/'EpicLutLua51Platform.dll',dll)
    receipt={'abi':'Lua5.1 zero-result C callback; opaque state untouched',
        'protocol':'ELP1/ELR1 v1 over local same-process named pipes','max_payload':1048576,'dll':str(dll),
        'sha256':digest,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'exports':names,'game_api_calls':False,'deployed':False,
        'verification':'PE x64 and export checked; native platform tests remain separate'}
    (output/'build.json').write_text(json.dumps(receipt,indent=2),encoding='utf8')
    (output/'SHA256SUMS.txt').write_text(digest+'  '+dll.name+'\n',encoding='ascii')
    print(json.dumps(receipt,indent=2))

if __name__=='__main__':main()
