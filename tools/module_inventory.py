"""Maintained Lua bundle inventory. Vendor adaptations retain upstream attribution."""
VENDOR = ['bingus_runtime', 'bingus_memory', 'engine', 'avatar', 'lobby_sync', 'armory_watch']
MENU = ['core', 'store', 'menu', 'view', 'capture']
OWN = ['binding_patch_export', 'binding_provenance', 'binding_source_cache', 'outfit_targets', 'texture_lifetime', 'live_edit', 'basic_camo', 'camo_patterns', 'ui_font', 'export_pairing', 'appearance_state', 'text_editor', 'clipboard', 'bulk_dds_export', 'scratch_tool', 'sdk_catalog', 'file_io', 'lut_files', 'paydex_rows', 'patch_export', 'dds', 'palette', 'semantics', 'windows', 'paths', 'preferences', 'frontend', 'lut_editor_controls', 'editor_tools', 'lut_editor_view', 'lut_editor', 'direct_setup', 'import_view', 'table_groups', 'original_luts', 'basic_view', 'armory_view', 'outfit_presets', 'basic_state', 'resource_ids', 'import_matches', 'import_protocol', 'import_job', 'import_picker', 'table_index', 'binding_session', 'gear_catalog', 'configuration', 'configuration_view', 'mcm_settings', 'preset_export', 'editor_registry', 'armory_collection', 'control_help', 'region_indicator', 'action_history', 'update_check', 'shared_lut_codec', 'shared_appearance', 'pattern_luts', 'armory_mirror']
PREVIEW = ['player_authored_clip', 'player_authored_source', 'player_animation', 'player_preview_ui', 'limb_caps', 'player_model', 'player_preview', 'player_preview_native', 'player_preview_submit', 'player_preview_controls', 'player_preview_input']

# StyLua 2.5.2 AST verification warns on FFI declarations and embedded worker literals.
# update_check.lua and the LuaJIT lobby fixture trigger verifier panics; preserve their source.
FORMAT_EXCEPTIONS = {'src/gear/sdk_catalog.lua', 'src/platform/windows.lua', 'src/platform/standalone_frontend.lua', 'tests/native_ipc.lua', 'src/gear/shared_lut_codec.lua', 'src/platform/update_check.lua', 'tests/lobby_sync.lua'}

SOURCE_GROUPS = {'binding_patch_export':'presets', 'binding_provenance':'presets', 'binding_source_cache':'presets', 'outfit_targets':'presets', 'texture_lifetime':'gear', 'live_edit':'editor', 'basic_camo':'editor', 'camo_patterns':'preview', 'ui_font':'platform', 'export_pairing':'presets', 'player_authored_clip':'preview', 'player_authored_source':'preview', 'player_animation':'preview', 'appearance_state':'gear', 'text_editor':'platform', 'clipboard':'platform', 'bulk_dds_export':'presets', 'scratch_tool':'editor', 'player_preview_ui':'preview', 'sdk_catalog':'gear', 'configuration_view': 'editor','mcm_settings':'platform','preset_export':'presets','editor_tools': 'editor', 'limb_caps': 'preview', 'patch_export': 'presets', 'armory_mirror': 'gear', 'pattern_luts': 'editor', 'shared_lut_codec': 'gear', 'shared_appearance': 'gear', 'action_history': 'core', 'basic_state': 'core', 'dds': 'core', 'file_io': 'core', 'palette': 'core', 'resource_ids': 'core', 'semantics': 'core', 'table_groups': 'core', 'armory_view': 'editor', 'basic_view': 'editor', 'configuration': 'editor', 'control_help': 'editor', 'direct_editor': 'editor', 'editor_registry': 'editor', 'import_view': 'editor', 'lut_editor': 'editor', 'lut_editor_controls': 'editor', 'lut_editor_view': 'editor', 'binding_session': 'gear', 'direct_setup': 'gear', 'gear_catalog': 'gear', 'original_luts': 'gear', 'region_indicator': 'gear', 'import_job': 'imports', 'import_picker': 'imports', 'import_matches': 'imports', 'import_protocol': 'imports', 'table_index': 'imports', 'armory_collection': 'presets', 'lut_files': 'presets', 'paydex_rows': 'presets', 'outfit_presets': 'presets', 'paths': 'platform', 'preferences': 'platform', 'standalone_frontend': 'platform', 'update_check': 'platform', 'windows': 'platform', 'player_model': 'preview', 'player_preview': 'preview', 'player_preview_candidate': 'preview', 'player_preview_controls': 'preview', 'player_preview_input': 'preview', 'player_preview_native': 'preview', 'player_preview_submit': 'preview', 'startup_bridge': 'loaders', 'startup_bsl': 'loaders', 'bindings': 'legacy', 'catalog': 'legacy', 'document': 'legacy', 'editor': 'legacy', 'editor_features': 'legacy', 'frontend': 'legacy', 'native_import': 'legacy', 'open_companion': 'legacy', 'presets': 'legacy', 'provider_menu': 'legacy', 'session': 'legacy'}

OWN = ['gear_edit', 'editor_actions', 'gear_export', 'outfit_capture', 'import_summary', 'editor_composition', 'armory_apply', 'export_provenance', 'import_mapping', 'session_history', 'binding_names', 'unit_identity', 'material_identity', 'binding_unit_layout'] + OWN
SOURCE_GROUPS.update({'binding_names': 'gear', 'unit_identity': 'gear', 'material_identity': 'gear',
                      'binding_unit_layout': 'presets'})

def source_path(name):
    actual = 'standalone_frontend' if name == 'frontend' else name
    return f'src/{SOURCE_GROUPS[actual]}/{actual}.lua'

SOURCE_GROUPS.update({'gear_edit': 'editor', 'editor_actions': 'editor', 'gear_export': 'presets', 'outfit_capture': 'presets', 'import_summary': 'editor', 'editor_composition': 'editor', 'armory_apply': 'presets', 'export_provenance': 'presets', 'import_mapping': 'editor', 'session_history': 'editor'})

OWN.append('shared_targets')
SOURCE_GROUPS['shared_targets']='gear'

OWN += ['appearance_events', 'appearance_event_binary']
SOURCE_GROUPS.update({'appearance_events':'gear','appearance_event_binary':'gear'})

OWN += ['appearance_recovery','editor_registration']
SOURCE_GROUPS.update({'appearance_recovery':'editor','editor_registration':'editor'})

OWN.append('setup_restore')
SOURCE_GROUPS['setup_restore'] = 'editor'

# Shared numeric-buffer boundary for stock Lua 5.1 and legacy native adapters.
OWN.insert(0, 'float_buffer')
SOURCE_GROUPS['float_buffer'] = 'core'

# Portable wire compression precedes the Shared LUT codec.
OWN.insert(0, 'lznt1')
SOURCE_GROUPS['lznt1'] = 'core'
OWN.insert(0, 'xpress')
SOURCE_GROUPS['xpress'] = 'core'

OWN.insert(0, 'cooperative')
SOURCE_GROUPS['cooperative'] = 'core'

# Portable host adapters precede frontend construction.
OWN.insert(0, 'loader_input')
SOURCE_GROUPS['loader_input'] = 'platform'
OWN.insert(0, 'loader_store')
SOURCE_GROUPS['loader_store'] = 'platform'
OWN.insert(0, 'native_platform')
SOURCE_GROUPS['native_platform'] = 'platform'
OWN.insert(0, 'legacy_frontend_input')
SOURCE_GROUPS['legacy_frontend_input'] = 'platform'

OWN.insert(0, 'legacy_clipboard')
SOURCE_GROUPS['legacy_clipboard'] = 'platform'

OWN.insert(0, 'legacy_paths')
SOURCE_GROUPS['legacy_paths'] = 'platform'

OWN.insert(0, 'legacy_windows')
SOURCE_GROUPS['legacy_windows'] = 'platform'
