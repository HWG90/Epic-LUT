"""Stock Lua 5.1 checks. Native runtime acceptance is deliberately separate.
Run with the existing Python 3.14 environment containing lupa.lua51.
"""
import io
import json
import os
import re
from pathlib import Path
import zipfile
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
PURE_TESTS = ('appearance_recovery_events', 'appearance_state', 'export_pairing', 'file_io', 'dds_file_portable', 'resource_labels', 'lut_editor_portable', 'binding_session_portable', 'cooperative', 'shared_publication_slices', 'shared_publication_cache', 'shared_publication_portable', 'shared_publication_large_portable', 'shared_lut_codec_portable', 'clipboard_portable', 'loader_input_portable', 'loader_store_portable', 'paths_portable', 'frontend_loader_portable')

PURE_TESTS += ('ui_font_portable', 'ui_font', 'ui_font_render', 'native_text_metrics', 'table_groups_portable')

PURE_TESTS += ('windows_portable', 'direct_setup_portable')
PURE_TESTS += ('public_engine_api_inventory', 'gear_buffers_portable', 'preset_file_io_portable', 'update_check_portable', 'export_provenance_portable')

def runtime():
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""
        assert(_VERSION == 'Lua 5.1')
        ffi, bit, jit = nil, nil, nil
        local original_require = require
        function require(name)
            assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Nonportable dependency: ' .. name)
            return original_require(name)
        end
    """)
    return lua

def main():
    os.chdir(ROOT)
    os.environ['EPIC_LUT_TEST_ROOT'] = str(ROOT)
    (ROOT / 'tests/tmp/presets').mkdir(parents=True, exist_ok=True)
    syntax_errors = {}
    compile_lua = runtime().eval(b"function(source, name) local f, e = loadstring(source, name); return f ~= nil, e end")
    files = sorted([*ROOT.glob('src/**/*.lua'), *ROOT.glob('vendor/**/*.lua')])
    for path in files:
        ok, error = compile_lua(path.read_bytes(), str(path.relative_to(ROOT)).encode())
        if not ok:
            syntax_errors[str(path.relative_to(ROOT))] = error.decode(errors='replace')
    results = {}
    for name in PURE_TESTS:
        try:
            runtime().execute((ROOT / 'tests' / (name + '.lua')).read_bytes())
            results[name] = 'PASS'
        except Exception as error:
            results[name] = str(error)
    # Real ZIP output, not a mocked bit library or a reimplementation of exporter logic.
    lua = runtime()
    patch = lua.execute((ROOT / 'src/presets/patch_export.lua').read_bytes())
    payloads = {b'empty': b'', b'crc-vector': b'123456789', b'all-bytes': bytes(range(256)) * 64}
    entries = lua.table_from([lua.table_from([name, payload]) for name, payload in payloads.items()])
    archive = patch.zip_entries(entries)
    with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
        assert zipped.testzip() is None
        for name, payload in payloads.items():
            assert zipped.read(name.decode()) == payload
        assert zipped.getinfo('crc-vector').CRC == 0xcbf43926
    results['portable_patch_zip'] = 'PASS'
    boundaries = {}
    for path in files:
        text = path.read_text(encoding='utf-8')
        dependencies = sorted(set(re.findall(r"require\s*\(?\s*['\"](ffi|bit|jit)['\"]", text)))
        if dependencies:
            boundaries[str(path.relative_to(ROOT))] = dependencies
    report = {'native_boundaries': boundaries, 'runtime': 'Lua 5.1 (lupa.lua51)', 'syntax_files': len(files),
              'syntax_errors': syntax_errors, 'tests': results,
              'native_api_compatibility': 'NOT VALIDATED: native FFI boundaries remain',
              'game_build': '25988413 target; no in-game execution'}
    output = ROOT / 'dist/lua51-portability.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return 1 if syntax_errors or any(value != 'PASS' for value in results.values()) else 0

if __name__ == '__main__':
    raise SystemExit(main())
