"""Build the explicit external OS service; no installation or game interaction."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VCVARS = Path('C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/native-lua51-platform-service')
    parser.add_argument('--test-block', action='store_true', help='Private test-only blocked-dispatch injection; never package')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    assert VCVARS.is_file(), 'Existing MSVC toolchain unavailable; no installation attempted'
    source = ROOT / 'native/lua51_platform_service.c'
    common = ROOT / 'native/lua51_platform.c'
    for item in [source, common, output, VCVARS]:
        assert not any(c in str(item) for c in '%!\r\n'), 'Unsupported build path'
    script = output / 'build-service.cmd'
    script.write_text('@echo off\ncall "' + str(VCVARS) + '" >nul\n'
        'if errorlevel 1 exit /b %errorlevel%\n'
        'cl /nologo /MT /O2 /W4 /WX ' + ('/DEPIC_PLATFORM_TEST_BLOCK ' if args.test_block else '') + '"' + str(source) + '" /link '
        '/OUT:EpicLutLua51Service.exe /SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup '
        '/DYNAMICBASE /NXCOMPAT /INCREMENTAL:NO /Brepro user32.lib shell32.lib bcrypt.lib\n', newline='\r\n')
    subprocess.run(['cmd.exe', '/d', '/c', str(script)], cwd=output, check=True)
    binary = output / 'EpicLutLua51Service.exe'
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    addressed = output / ('EpicLutLua51Service-' + digest[:16] + '.exe')
    shutil.copyfile(binary, addressed)
    receipt = {'exe': str(addressed), 'sha256': digest,
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'shared_source_sha256': hashlib.sha256(common.read_bytes()).hexdigest(),
        'protocol': 'ELP1/ELR1 operations shared with DLL; external auth29/close30',
        'startup_timeout_ms': 8000, 'active_transfer_timeout_ms': 3000,
        'idle': 'overlapped read waits on pipe event and retained client process; no timer',
        'auth': 'private 256-bit token, both actual pipe-client PIDs, retained client process/image',
        'max_payload': 1048576, 'max_owned_workers': 8, 'max_owned_files': 8, 'max_owned_hashes': 8,
        'game_memory_access': False, 'deployed': False}
    receipt['test_block_injection'] = args.test_block
    (output / 'build.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    (output / 'SHA256SUMS.txt').write_text(digest + '  ' + addressed.name + '\n', encoding='ascii')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
