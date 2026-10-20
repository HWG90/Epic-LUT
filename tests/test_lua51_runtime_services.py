"""Actual runtime bootstrap + native helper + production LLL project/config.
All files/settings/DLLs are private temporary fixtures; no game/UI/clipboard.
"""
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
LLL = Path(os.environ.get('EPIC_LLL_TEST_ROOT', ROOT.parent / 'DBF-Suite/LLL'))


def worker(directory, library):
    root = Path(directory)
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    assert hashlib.sha256(Path(library).read_bytes()).hexdigest() == receipt['sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['source_sha256']
    project_dir, settings_dir = root / 'project', root / 'loader-settings'
    (project_dir / 'config').mkdir(parents=True)
    (project_dir / 'main.lua').write_bytes(b'return mod')
    (project_dir / 'config/defaults.cfg').write_bytes(b'{"unrelated":{"enabled":true}}')
    packaged = project_dir / Path(library).name
    shutil.copyfile(library, packaged)
    local_data = root / 'private-localappdata'
    local_data.mkdir()
    os.environ['LOCALAPPDATA'] = str(local_data)
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""assert(_VERSION=='Lua 5.1');ffi,bit,jit=nil,nil,nil
        local previous=require
        function require(name)
            assert(name~='ffi' and name~='bit' and name~='jit','Unexpected native Lua dependency: '..name)
            return previous(name)
        end
    """)
    load = lua.eval(b'dofile')
    lua.globals()[b'LLL_METADATA'] = load(str(LLL / 'src/metadata.lua').encode())
    lua.globals()[b'LLL_CONFIG'] = load(str(LLL / 'src/config.lua').encode())
    project = load(str(LLL / 'src/project.lua').encode())
    writes = 0

    def read(path, limit):
        try:
            data = Path(os.fsdecode(path)).read_bytes()
        except FileNotFoundError:
            return None
        return data if len(data) <= limit else None

    def write(path, data):
        nonlocal writes
        target = Path(os.fsdecode(path))
        temporary = Path(str(target) + '.bootstrap-pending')
        temporary.write_bytes(data)
        os.replace(temporary, target)
        writes += 1
        return True

    def mkdir(path):
        Path(os.fsdecode(path)).mkdir(parents=True, exist_ok=True)
        return True

    host_platform = lua.table_from({b'native_ffi': False, b'settings': str(settings_dir).encode(),
                                    b'read': read, b'write': write, b'mkdir': mkdir})
    entry = lua.table_from({b'id': b'epic_lut_bootstrap', b'dir': str(project_dir).encode()})
    spec = lua.table_from({b'entry': b'main.lua', b'defaults': b'config/defaults.cfg', b'modules': lua.table()})

    def host():
        definition, public_api = project.instantiate(host_platform, entry, project.snapshot(host_platform, entry, spec), lambda *_: None)
        assert lua.eval(b'rawequal')(definition, public_api)
        return public_api

    def successful(value):
        return value is True or isinstance(value, tuple) and value[0] is True

    native = load(str(ROOT / 'src/platform/native_platform.lua').encode())
    store = load(str(ROOT / 'src/platform/loader_store.lua').encode())
    runtime = load(str(ROOT / 'src/platform/runtime_services.lua').encode())
    # Outside the game, supply its already verified public process_id shape
    # with the real test process PID. This invokes no game engine operation.
    lua.globals()[b'process_identity'] = os.getpid()
    lua.execute(b'stingray={Application={process_id=function()return process_identity end}}')

    def model():
        result = lua.table_from({b'native_platform': native, b'native_platform_name': packaged.name.encode(),
                                 b'loader_store': store})
        lua.globals()[b'm'] = result
        result[b'file_io'] = load(str(ROOT / 'src/core/file_io.lua').encode())
        result[b'ui_store'] = lua.eval(b'{new=function()error("Bootstrap selected the legacy settings store")end}')
        return result

    current, context = model(), host()
    lease = runtime.start(current, context)
    lua.globals()[b'bootstrap'], lua.globals()[b'host'], lua.globals()[b'lease'] = current, context, lease
    lua.execute(b"""assert(lease.ready and lease.owned_platform and lease.owned_storage)
        assert(rawequal(lease.platform,bootstrap.platform) and rawequal(host.platform,bootstrap.platform))
        assert(rawequal(lease.storage,bootstrap.storage) and rawequal(host.storage,bootstrap.storage))
    """)
    paths = load(str(ROOT / 'src/platform/paths.lua').encode()).new(current)
    lua.globals()[b'paths'] = paths
    lua.execute(b'assert(rawequal(paths.storage,lease.storage))')
    filename = paths[b'files'] + '/palette \u8863\u88c5 \U0001f986.bin'.encode()
    payload = b'bootstrap\0\xff\r\n' * 4096
    assert current[b'file_io'].write(filename, payload) is True
    assert current[b'file_io'].read(filename, len(payload)) == payload
    assert successful(lease.storage.save(b'epic_lut_preferences', lua.table_from({b'ui_scale': 115})))
    assert context[b'config'][b'unrelated'][b'enabled'] is True and writes == 1
    assert successful(lease.storage.save(b'epic_lut_preferences', lua.table_from({b'ui_scale': 115}))) and writes == 1
    assert lease.close(False)[0] is False
    assert lease.platform.stat(filename)[b'directory'] is False
    assert lease.close(True) is True
    assert current[b'platform'] is None and context[b'platform'] is None
    assert current[b'storage'] is None and context[b'storage'] is None

    current, context = model(), host()
    lease = runtime.start(current, context)
    assert lease.storage.load(b'epic_lut_preferences')[b'ui_scale'] == 115
    borrowed_model = lua.table_from({b'platform': lease.platform, b'storage': lease.storage})
    borrowed_context = lua.table()
    borrowed = runtime.start(borrowed_model, borrowed_context)
    assert borrowed[b'owned_platform'] is False and borrowed[b'owned_storage'] is False
    assert borrowed.close(True) is True and lease.platform.stat(filename)[b'directory'] is False
    assert lease.close(True) is True

    current, context = model(), host()
    original = context[b'config'][b'epic_lut_ui']
    context[b'config'][b'epic_lut_ui'] = lua.table_from({b'version': 999, b'stores': lua.table()})
    try:
        runtime.start(current, context)
    except LuaError as error:
        assert 'Unsupported or damaged' in str(error)
    else:
        raise AssertionError('Damaged loader storage was silently replaced')
    assert current[b'platform'] is None and context[b'platform'] is None
    context[b'config'][b'epic_lut_ui'] = original
    lease = runtime.start(current, context)
    assert lease[b'ready'] is True and lease.close(True) is True, 'Failed constructor stranded native ownership'
    assert writes == 1 and not list(root.rglob('*.bootstrap-pending'))
    print('PASS actual runtime_services bootstrap: real Lua5.1/native helper + production LLL project/config, '
          'pre-path shared scopes, private Unicode file IO, atomic settings restart, no-op save, '
          'owned/borrowed cleanup, pending consumers and native ownership rollback after schema failure')


def main():
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    with tempfile.TemporaryDirectory(prefix='epic-runtime-services-') as directory:
        root = Path(directory).resolve()
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-runtime-services-')
        library = root / Path(receipt['dll']).name
        shutil.copyfile(receipt['dll'], library)
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--worker', str(root), str(library)],
                                capture_output=True, text=True, timeout=30)
        print(result.stdout, end='');print(result.stderr, end='', file=sys.stderr)
        assert result.returncode == 0, 'Actual runtime bootstrap failed or exceeded its deadline'


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        worker(sys.argv[2], sys.argv[3])
    else:
        main()
