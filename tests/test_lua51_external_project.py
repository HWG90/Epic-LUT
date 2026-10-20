"""Hermetic real LLL project/config + stock Lua5.1 + actual external OS service.

Declared packaged modules are the only Lua imports. The worker runs in private
Temp with empty package paths and global require/loadlib forbidden. No game,
clipboard, dialog, installation, or private prepared-probe files are used.
"""
import ctypes
from ctypes import wintypes as W
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from lupa.lua51 import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LLL = Path(os.environ.get('EPIC_LLL_TEST_ROOT', ROOT.parent / 'DBF-Suite/LLL')).resolve()
MODULES = ['src/platform/external_platform.lua', 'src/platform/native_platform.lua',
    'src/platform/loader_store.lua', 'src/platform/runtime_services.lua',
    'src/core/file_io.lua', 'src/core/cooperative.lua', 'tools/lua51_platform_smoke.lua']


def entry_source(service, digest, wire_cooperative=True):
    # Lua literals come from a validated ASCII content-addressed build receipt.
    assert service.startswith('EpicLutLua51Service-') and service.endswith('.exe')
    assert service[20:-4].isalnum() and len(digest) == 64 and all(c in '0123456789abcdef' for c in digest)
    prefix = ('local m={platform_backend="external",native_platform_name="' + service
        + '",native_platform_sha256="' + digest + '"}\nmod.scope.m=m\n')
    for name, path in [('external_platform', MODULES[0]), ('native_platform', MODULES[1]),
        ('loader_store', MODULES[2]), ('runtime_services', MODULES[3]), ('file_io', MODULES[4])]:
        prefix += 'm.' + name + '=mod.require("' + path + '")\n'
    if wire_cooperative:
        prefix += 'm.cooperative=mod.require("src/core/cooperative.lua")\n'
    return (prefix + '''local smoke=mod.require('tools/lua51_platform_smoke.lua')
local start=m.external_platform.start
m.external_platform.start=function(...)
    local channel=start(...);m.helper_pid=channel.server_pid;return channel
end
return {live_lua_api=1,on_enable=function()
    if mod.config.capture then return true end
    local ok,capture=pcall(smoke.run,m,mod,mod.dir..'/owned-smoke')
    if ok then capture.success=true
    else capture={success=false,error=tostring(capture),cleanup_pending=m.platform_probe_lease~=nil}end
    capture.helper_process_id=m.helper_pid
    assert(mod.set('capture',capture)~=false,'Cannot save owned capture')
    return true
end,on_disable=function()return smoke.close(m)end}
''').encode('utf8')


def retired(pid):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]; kernel.OpenProcess.restype = W.HANDLE
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    kernel.CloseHandle.argtypes = [W.HANDLE]
    handle = kernel.OpenProcess(0x100000, False, pid)
    if handle:
        try:
            assert kernel.WaitForSingleObject(handle, 5000) == 0, 'Owned helper survived project cleanup'
        finally:
            kernel.CloseHandle(handle)
    else:
        assert ctypes.get_last_error() == 87, 'Could not verify actual helper retirement'


def worker(directory, executable, digest):
    root = Path(directory).resolve()
    assert Path.cwd().resolve() == root and root.parent == Path(tempfile.gettempdir()).resolve()
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.globals()[b'fixture_process_id'] = os.getpid()
    lua.execute(b"""assert(_VERSION=='Lua 5.1');ffi,bit,jit=nil,nil,nil
        package.path='';package.cpath=''
        fixture_launches=0
        local launch=io.popen
        io.popen=function(...)fixture_launches=fixture_launches+1;return launch(...)end
        require=function(name)error('Undeclared checkout import: '..name)end
        package.loadlib=function()error('Unexpected DLL loading')end
        stingray={Application={process_id=function()return fixture_process_id end}}
    """)
    load = lua.eval(b'dofile')
    lua.globals()[b'LLL_METADATA'] = load(str(LLL / 'src/metadata.lua').encode('utf8'))
    lua.globals()[b'LLL_CONFIG'] = load(str(LLL / 'src/config.lua').encode('utf8'))
    project = load(str(LLL / 'src/project.lua').encode('utf8'))
    lua.execute(b"dofile=function(name)error('Undeclared dofile: '..tostring(name))end")
    settings = root / 'loader-settings'
    writes = [0]

    def owned(path):
        value = Path(os.fsdecode(path)).resolve()
        assert value.is_relative_to(root), 'LLL fixture escaped private Temp'
        return value

    def read(path, limit):
        try:
            data = owned(path).read_bytes()
        except FileNotFoundError:
            return None
        assert len(data) <= limit
        return data

    def write(path, data):
        target = owned(path)
        pending = target.with_suffix('.owned-pending')
        pending.write_bytes(data); os.replace(pending, target)
        writes[0] += 1
        return True

    def mkdir(path):
        owned(path).mkdir(parents=True, exist_ok=True)
        return True

    platform = lua.table_from({b'native_ffi': False, b'settings': str(settings).encode('utf8'),
        b'read': read, b'write': write, b'mkdir': mkdir})

    def prepare(identifier, wire=True, declare=True):
        directory = root / identifier
        (directory / 'config').mkdir(parents=True)
        for source in MODULES:
            destination = directory / source; destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / source, destination)
        shutil.copyfile(executable, directory / Path(executable).name)
        (directory / 'main.lua').write_bytes(entry_source(Path(executable).name, digest, wire))
        declared = MODULES if declare else [name for name in MODULES if name != 'src/core/cooperative.lua']
        (directory / 'manifest.json').write_text(json.dumps({'lll': {'entry': 'main.lua',
            'defaults': 'config/defaults.cfg', 'modules': declared}}), encoding='utf8')
        (directory / 'config/defaults.cfg').write_text('{"unrelated":{"enabled":true}}', encoding='ascii')
        entry = lua.table_from({b'id': identifier.encode(), b'dir': str(directory).encode('utf8')})
        spec = project.descriptor(platform, str(directory).encode('utf8'))
        return directory, entry, spec

    def instantiate(entry, spec):
        snapshot = project.snapshot(platform, entry, spec)
        return project.instantiate(platform, entry, snapshot, lambda *_: None)

    # A literal import absent from the descriptor fails before any process starts.
    _, missing, spec = prepare('missing_declaration', declare=False)
    try:
        project.snapshot(platform, missing, spec)
    except LuaError as error:
        assert 'undeclared import src/core/cooperative.lua' in str(error), str(error)
    else:
        raise AssertionError('Undeclared packaged import passed the production loader')
    assert lua.globals()[b'fixture_launches'] == 0 and writes[0] == 0

    # Reproduce the original omitted model dependency. Repository require must
    # not rescue digest after real bootstrap and file IO; cleanup still owns it.
    directory, entry, spec = prepare('missing_model_dependency', wire=False, declare=False)
    definition, public = instantiate(entry, spec)
    assert definition[b'on_update'] is None and definition[b'on_enable']() is True
    failed = json.loads((settings / 'missing_model_dependency/config.cfg').read_text())
    capture = failed['capture']
    assert capture['success'] is False and 'Undeclared checkout import: src.core.cooperative' in capture['error']
    assert capture['cleanup_pending'] is False and not (directory / 'owned-smoke').exists()
    assert definition[b'on_disable']() is True and public[b'scope'][b'm'][b'platform_probe_lease'] is None
    retired(capture['helper_process_id'])

    directory, entry, spec = prepare('complete_external_project')
    definition, public = instantiate(entry, spec)
    assert definition[b'live_lua_api'] == 1 and definition[b'on_update'] is None
    before = int(lua.globals()[b'fixture_launches'])
    assert definition[b'on_enable']() is True
    assert int(lua.globals()[b'fixture_launches']) == before + 1
    config = json.loads((settings / 'complete_external_project/config.cfg').read_text())
    capture = config['capture']
    assert capture['success'] is True and capture['runtime'] == 'Lua 5.1' and capture['bytes'] == 1280
    assert capture['sha256'] == '631fcc8b07826fc8fd9f48913968865ac099962543b2aadf52e1f2e239961d52'
    for name in ['unicode', 'atomic_replace', 'rename', 'loader_store', 'cleanup_complete', 'platform_closed']:
        assert capture[name] is True, name
    assert config['unrelated']['enabled'] is True
    assert not (directory / 'owned-smoke').exists()
    assert public[b'scope'][b'm'][b'cooperative'] is not None
    before = (writes[0], int(lua.globals()[b'fixture_launches']))
    for _ in range(3):
        assert definition[b'on_enable']() is True
    assert before == (writes[0], int(lua.globals()[b'fixture_launches'])), 'Repeat enable performed work'
    assert definition[b'on_disable']() is True and public[b'scope'][b'm'][b'platform_probe_lease'] is None
    retired(capture['helper_process_id'])
    restarted, public = instantiate(entry, spec)
    assert restarted[b'on_enable']() is True and restarted[b'on_disable']() is True
    assert before == (writes[0], int(lua.globals()[b'fixture_launches'])), 'Saved one-shot repeated after actual config reload'
    assert not list(root.rglob('*.owned-pending'))
    print('PASS hermetic external project: real Lua5.1/LLL project/config/EXE; private cwd, empty package paths, '
        'global require/dofile/loadlib forbidden; declared cooperative+Smoke; missing dependency regressions; '
        'full bootstrap/file/hash/store smoke, repeat-enable/restart idle, actual helper exit')


def main():
    receipt = json.loads((ROOT / 'dist/native-lua51-platform-service/build.json').read_text())
    assert receipt['test_block_injection'] is False
    executable = Path(receipt['exe'])
    assert hashlib.sha256(executable.read_bytes()).hexdigest() == receipt['sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform_service.c').read_bytes()).hexdigest() == receipt['source_sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['shared_source_sha256']
    for name in ['src/project.lua', 'src/config.lua', 'src/metadata.lua']:
        assert (LLL / name).is_file(), 'Set EPIC_LLL_TEST_ROOT to the maintained public LLL source checkout'
    with tempfile.TemporaryDirectory(prefix='epic-external-project-') as private:
        root = Path(private).resolve()
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--worker', str(root),
            str(executable), receipt['sha256']], cwd=root, capture_output=True, text=True, timeout=45,
            creationflags=subprocess.CREATE_NO_WINDOW)
        print(result.stdout, end=''); print(result.stderr, end='', file=sys.stderr)
        assert result.returncode == 0, 'Hermetic real external-project fixture failed or exceeded its deadline'


if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == '--worker':
        worker(*sys.argv[2:])
    else:
        main()
