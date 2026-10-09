import os
from tools.runtime_guard import require_physical_runtime,blocked_path
require_physical_runtime()
assert blocked_path('C:/Users/test/AppData/Local/Microsoft/WindowsApps/python.exe')
assert blocked_path('C:/Users/test/AppData/Local/Packages/PythonSoftwareFoundation.Python/LocalCache/Local/LLL/mod.lua')
assert not blocked_path('C:/runtimes/python/python.exe')
from pathlib import Path
ROOT=Path(__file__).resolve().parent;os.chdir(ROOT)
os.environ['EPIC_LUT_TEST_ROOT']=str(ROOT)
(ROOT/'tests/presets').mkdir(exist_ok=True)
(ROOT/'tests/tmp/files').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/tmp/cache').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/tmp/direct-state').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/tmp/presets').mkdir(exist_ok=True)
os.environ.setdefault('MCM_SOURCE_DIR',str(ROOT.parent/'DBF-MCM'))
from tools.lua_runner import LuaRunner

TESTS = (
    'sdk_catalog', 'ui_styling', 'window_frames',
    'tooltip_wrapping', 'lut_editor_hierarchy', 'floating_windows', 'picker_permissions',
    'contracts', 'float_lut', 'provider_menu', 'full_editor', 'native_ipc',
    'frontend', 'startup_bridge', 'bindings', 'catalog_split_read', 'catalog_worker',
    'startup_apply_gate', 'direct_editor', 'palette_editor', 'standalone_frontend',
    'import_view', 'table_groups', 'original_luts', 'basic_view', 'update_check',
    'editor_state', 'direct_setup', 'outfit_presets', 'armory_view', 'import_matches', 'import_protocol', 'configuration', 'import_job', 'armory_collection', 'gear_catalog', 'file_io', 'table_index', 'lut_files', 'patch_export', 'shared_lut_codec', 'shared_appearance', 'lobby_sync', 'pattern_luts', 'floating_dropdown', 'slider_preview', 'input_preview', 'editor_layout', 'mcm_ui_port', 'mcm_settings', 'preset_export', 'bulk_dds_export', 'armory_mirror', 'limb_caps',
)
runner = LuaRunner()
for path in sorted([*ROOT.glob('src/**/*.lua'), *ROOT.glob('vendor/*.lua'), *ROOT.glob('vendor/menu/*.lua')]):
    runner.check(path)
for path in (ROOT/'dist/armor_lut_editor/mod.lua', ROOT/'dist/Epic-LUT-BSL-startup.lua'):
    runner.check(path)
for name in TESTS:
    runner.check(ROOT/'tests'/f'{name}.lua', execute=True)
print('PASS: source and bundled LuaJIT syntax; isolated editor contracts')
