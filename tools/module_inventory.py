"""Maintained Lua bundle inventory. Upstream vendor sources remain unchanged."""
VENDOR = ['bingus_runtime', 'bingus_memory', 'engine', 'avatar']
MENU = ['core', 'store', 'menu', 'view', 'capture']
OWN = ['file_io', 'lut_files', 'dds', 'palette', 'semantics', 'windows', 'paths', 'preferences', 'frontend', 'lut_editor_controls', 'lut_editor_view', 'lut_editor', 'direct_setup', 'import_view', 'table_groups', 'original_luts', 'basic_view', 'armory_view', 'outfit_presets', 'basic_state', 'resource_ids', 'import_matches', 'import_protocol', 'import_job', 'table_index', 'binding_session', 'gear_catalog', 'configuration', 'editor_registry', 'armory_collection', 'control_help', 'region_indicator', 'action_history', 'update_check']
PREVIEW = ['player_model', 'player_preview', 'player_preview_native', 'player_preview_submit', 'player_preview_controls', 'player_preview_input']

# StyLua 2.5.2 AST verification warns on FFI string declarations in these files.
FORMAT_EXCEPTIONS = {'src/windows.lua', 'src/standalone_frontend.lua', 'tests/native_ipc.lua'}
