import os
import subprocess
import sys
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
    'primary_weapon_identity', 'weapon_lut_probe', 'weapon_lut_catalog_match', 'weapon_discovery',
    'remote_weapon_discovery', 'weapon_runtime', 'weapon_controller', 'weapon_view', 'weapon_pattern_quick', 'weapon_bridge',
    'weapon_mapping', 'weapon_presets', 'weapon_workflow', 'outfit_capture', 'armory_apply',
    'shared_weapon_authorization', 'weapon_shared', 'weapon_provenance', 'weapon_setup', 'weapon_editor_integration',
    'export_provenance', 'import_mapping', 'session_history', 'import_summary',
    'unit_identity', 'material_identity', 'binding_unit_layout',
    'sdk_catalog', 'resource_labels', 'armory_dropdown_hover', 'ui_styling', 'typography', 'window_frames', 'player_authored_clip', 'player_authored_source', 'player_animation',
    'tooltip_wrapping', 'lut_editor_hierarchy', 'editor_surface_typography', 'floating_windows', 'window_render_order', 'picker_permissions', 'editor_clipboard', 'lut_drag_selection', 'lut_row_selection', 'row_clipboard', 'render_order', 'integer_layers', 'clipboard', 'menu_clipboard_drag', 'text_editing', 'native_text_metrics', 'ui_font', 'ui_font_render', 'font_padding', 'custom_layout_space', 'value_editor_scroll', 'viewport_clipping', 'tools_splitter', 'camo_region_indicator',
    'contracts', 'float_lut', 'provider_menu', 'full_editor', 'native_ipc', 'pattern_workspace', 'pattern_workspace_layout', 'lut_apply_dialog', 'value_field_commit', 'control_width_caps', 'rgb_only_picker', 'preset_name_completion', 'selected_preset_save', 'overwrite_dialog', 'cursor_modes', 'row_preset_preview', 'delete_selection', 'binding_patch_export', 'binding_provenance', 'binding_source_cache',
    'frontend', 'frontend_suspension', 'startup_bridge', 'bindings', 'catalog_split_read', 'catalog_worker',
    'startup_apply_gate', 'appearance_state', 'appearance_persistence', 'direct_appearance_runtime', 'binding_session_rollback', 'texture_budget', 'texture_lifetime', 'texture_retirement_certificate', 'live_edit', 'cape_editor', 'direct_editor', 'palette_editor', 'standalone_frontend',
    'import_view', 'table_groups', 'original_luts', 'basic_view', 'basic_camo', 'camo_patterns', 'camo_dropdown', 'update_check',
    'editor_state', 'direct_setup', 'outfit_targets', 'outfit_presets', 'armory_view', 'import_matches', 'import_protocol', 'configuration', 'import_job', 'import_picker', 'armory_collection', 'gear_catalog', 'file_io', 'table_index', 'lut_files', 'paydex_rows', 'patch_export', 'shared_lut_codec', 'shared_appearance', 'shared_recovery', 'lobby_sync', 'pattern_luts', 'pattern_import_matching', 'floating_dropdown', 'preset_dropdown', 'preset_removal', 'tools_docking', 'slider_preview', 'input_preview', 'editor_layout', 'mcm_ui_port', 'mcm_settings', 'preset_export', 'export_pairing', 'bulk_dds_export', 'armory_mirror', 'limb_caps',
)
runner = LuaRunner()
for path in sorted([*ROOT.glob('src/**/*.lua'), *ROOT.glob('vendor/*.lua'), *ROOT.glob('vendor/menu/*.lua')]):
    runner.check(path)
for path in (ROOT/'dist/armor_lut_editor/mod.lua', ROOT/'dist/Epic-LUT-BSL-startup.lua'):
    runner.check(path)
for name in TESTS:
    runner.check(ROOT/'tests'/f'{name}.lua', execute=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_paydex_worker.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_camo_preview.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_binding_provenance.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_weapon_effective_sources.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tools/links_weapon_probe/test_prepare.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_binding_names.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_original_row_cache.py')], cwd=ROOT, check=True)
subprocess.run([sys.executable, str(ROOT/'tests/test_original_patched_cache.py')], cwd=ROOT, check=True)
print('PASS: source and bundled LuaJIT syntax; isolated editor contracts')
