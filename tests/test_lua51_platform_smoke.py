"""One-shot production bootstrap/smoke runner with the actual Windows DLL.

Runs in private temporary directories in this Python process, never the game.
The loader config surface is explicit; the real loader contract has its own test.
"""
import hashlib
import json
import os
from pathlib import Path
import tempfile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def main():
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    dll = Path(receipt['dll'])
    assert hashlib.sha256(dll.read_bytes()).hexdigest() == receipt['sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['source_sha256']
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.globals()[b'PROCESS_ID'] = os.getpid()
    lua.execute(b"""ffi,bit,jit=nil,nil,nil
        local original=require
        function require(name)
            assert(name~='ffi' and name~='bit' and name~='jit','Unexpected native dependency')
            return original(name)
        end
        stingray={Application={process_id=function()return PROCESS_ID end}}
    """)
    load = lua.eval(b'dofile')
    modules = lua.table()
    for name, source in {
        b'native_platform': 'src/platform/native_platform.lua',
        b'loader_store': 'src/platform/loader_store.lua',
        b'runtime_services': 'src/platform/runtime_services.lua',
        b'file_io': 'src/core/file_io.lua',
    }.items():
        modules[name] = load(str(ROOT / source).encode())
    modules[b'native_platform_name'] = dll.name.encode()
    lua.globals()[b'modules'] = modules
    lua.globals()[b'LIBRARY_DIRECTORY'] = str(dll.parent).encode()
    host = lua.execute(b"""local host={dir=LIBRARY_DIRECTORY,config={unrelated='retained'}}
        function host.set(key,value)host.config[key]=value;return true end
        return host
    """)
    smoke = load(str(ROOT / 'tools/lua51_platform_smoke.lua').encode())
    expected = hashlib.sha256(b'\0Epic LUT Lua 5.1\xff\r\n' * 64).hexdigest().encode()
    with tempfile.TemporaryDirectory(prefix='epic-platform-smoke-') as folder:
        root = Path(folder)
        report = smoke.run(modules, host, str(root / 'owned').encode())
        assert report[b'sha256'] == expected and report[b'bytes'] == 1280
        for key in (b'unicode', b'atomic_replace', b'rename', b'loader_store', b'cleanup_complete', b'platform_closed'):
            assert report[key] is True, key
        assert not list(root.iterdir())
        assert host[b'config'][b'unrelated'] == b'retained'
        assert host[b'platform'] is None and host[b'storage'] is None
        assert modules[b'platform'] is None and modules[b'storage'] is None
        assert modules[b'platform_probe_lease'] is None
        # A pre-existing directory is foreign; a refused probe cannot remove it.
        occupied = root / 'occupied'
        occupied.mkdir()
        sentinel = occupied / 'foreign.txt'
        sentinel.write_bytes(b'preserved')
        try:
            smoke.run(modules, host, str(occupied).encode())
        except Exception as error:
            assert 'operation 7 failed (183)' in str(error), str(error)
        else:
            raise AssertionError('Probe accepted an existing directory')
        assert sentinel.read_bytes() == b'preserved'
        assert modules[b'platform_probe_lease'] is None
        assert host[b'platform'] is None and modules[b'platform'] is None
        for _ in range(1000):
            assert smoke.close(modules) is True
    print('PASS actual Lua5.1/DLL bootstrap smoke: Unicode binary IO, atomic rename/replace, independent SHA256, loader storage, scoped cleanup and foreign-directory refusal; no game calls')


if __name__ == '__main__':
    main()
