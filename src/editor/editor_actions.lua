-- Registry actions: history boundaries, dialogs, source selection and draft copies.
-- Activation state changes pass through semantic host callbacks.
local A = {}
local ffi = require('ffi')

local function copy_document(source, label)
    local data = ffi.new('float[?]', source.width * source.height * 4)
    ffi.copy(data, source.data, source.width * source.height * 16)
    return { data = data, width = source.width, height = source.height, source = label }
end

function A.new(deps)
    local function sync_palette()
        local editor = deps.palette_editor()
        if editor then
            editor.sync()
        end
    end
    local function protected(fn, ...)
        local ok, value = pcall(fn, ...)
        return ok and value or deps.message(tostring(value))
    end
    local function choose_current(kind)
        if deps.current_page() == 'colors' then
            deps.queue_editor_target(kind)
            deps.action(function()
                return deps.load_editor_target(kind)
            end)
        end
    end
    local function load_current(kind)
        deps.mark_current_load()
        return deps.action(function()
            deps.queue_editor_target(kind)
            return deps.load_editor_target(kind)
        end)
    end
    local function apply_editor(kind, all)
        return deps.action(function()
            if all == nil then
                return deps.apply_editor_target(kind)
            end
            return deps.apply_editor_target(kind, all)
        end)
    end
    local function apply_import(kind)
        return deps.action(function()
            return deps.apply_import_to(kind)
        end)
    end
    local function apply_file(kind, scope)
        return deps.action(function()
            assert(deps.imported_document(), 'Import a palette first')
            assert(deps.stop_identification(), 'Highlight restoration pending')
            deps.refresh(true)
            assert(deps.handle().set('scope', scope))
            return deps.apply(deps.imported_document(), kind)
        end)
    end
    return {
        rename_lut_activate = function()
            local hash = assert(deps.lut_label_resource(), 'Load a current LUT with a known texture ID first')
            local labels = assert(deps.lut_labels(), 'Local LUT naming is unavailable')
            local menu = assert(deps.frontend().menu, 'Open the LUT Editor first')
            local name = labels.get(hash) or ''
            local handle = deps.handle()
            assert(handle.set('lut_label', name))
            local mod = deps.mod()
            menu.outfit_dialog = {
                phase = 'name',
                title = 'Name This LUT',
                mod = mod,
                control = mod.controls.lut_label,
                action_label = 'Save Name',
                initial_text = name,
                placeholder = 'Click to enter a LUT name',
                description = 'Clear the name to show the texture ID again.',
                on_save = function(value)
                    labels.set(hash, value)
                    deps.import_state()
                    menu.outfit_dialog, menu.text_edit = nil, nil
                    return deps.message(
                        not labels.get(hash) and 'LUT name cleared; texture ID restored.' or 'LUT name saved locally.'
                    )
                end,
            }
            menu.text_edit = { mod = mod, control = mod.controls.lut_label, text = name, replace = true }
            return true
        end,
        browse_activate = function()
            return deps.action(function()
                return deps.load(true)
            end)
        end,
        load_debug_lut_activate = function()
            return deps.load_debug_lut()
        end,
        cancel_import_activate = function()
            return deps.action(function()
                return deps.cancel_import(false)
            end)
        end,
        retry_import_activate = function()
            return deps.action(function()
                return deps.cancel_import(true)
            end)
        end,
        ui_scale_change = function(value)
            deps.frontend().menu.ui_scale = value / 100
            local preferences = deps.preferences()
            if preferences.save_scale then
                preferences.save_scale(value)
            end
        end,
        quick_color_change = function(hex)
            local q = deps.quick_selection()
            if not q then
                return
            end
            return deps.paint_quick(q, hex)
        end,
        apply_matching_activate = function()
            return deps.action(function()
                return deps.apply_matching()
            end)
        end,
        basic_advanced_activate = function()
            return deps.frontend().open_advanced()
        end,
        open_editor_activate = function()
            return deps.open_editor()
        end,
        outfit_rename_activate = function()
            return deps.manage_outfit('rename')
        end,
        outfit_delete_activate = function()
            return deps.manage_outfit('delete')
        end,
        outfit_preset_change = deps.select_outfit,
        armory_export_format_change = deps.sync_armory_export,
        armory_import_activate = function()
            return deps.action(function()
                return deps.load(true)
            end)
        end,
        armory_export_activate = function()
            return deps.action(deps.export_armory)
        end,
        outfit_apply_armor_activate = function()
            return deps.action(function()
                return deps.apply_outfit('armor')
            end)
        end,
        outfit_apply_helmet_activate = function()
            return deps.action(function()
                return deps.apply_outfit('helmet')
            end)
        end,
        outfit_apply_cape_activate = function()
            return deps.action(function()
                return deps.apply_outfit('cape')
            end)
        end,
        outfit_apply_selected_activate = function()
            return deps.action(function()
                local handle = deps.handle()
                return deps.apply_outfit({
                    armor = handle.get('outfit_target_armor'),
                    helmet = handle.get('outfit_target_helmet'),
                    cape = handle.get('outfit_target_cape')
                        and deps.armory_cape_available(deps.armory_collection().selected),
                })
            end)
        end,
        outfit_choose_luts_activate = function()
            return protected(deps.choose_outfit_luts)
        end,
        imported_map_gear_activate = function()
            return protected(deps.open_import_map, 'gear')
        end,
        imported_map_armor_activate = function()
            return protected(deps.open_import_map, 'armor')
        end,
        imported_map_helmet_activate = function()
            return protected(deps.open_import_map, 'helmet')
        end,
        imported_map_cape_activate = function()
            return protected(deps.open_import_map, 'cape')
        end,
        global_undo_activate = function()
            local history = assert(deps.history(), 'Action history unavailable')
            history.undo_action()
            return deps.message('Last action undone; palettes and gear refreshed.')
        end,
        global_redo_activate = function()
            local history = assert(deps.history(), 'Action history unavailable')
            history.redo_action()
            return deps.message('Last action redone; palettes and gear refreshed.')
        end,
        basic_armor_lut_change = function()
            choose_current('armor')
        end,
        basic_helmet_lut_change = function()
            choose_current('helmet')
        end,
        editor_load_armor_activate = function()
            return load_current('armor')
        end,
        editor_load_helmet_activate = function()
            return load_current('helmet')
        end,
        editor_apply_armor_activate = function()
            return apply_editor('armor')
        end,
        editor_apply_helmet_activate = function()
            return apply_editor('helmet')
        end,
        editor_all_armor_activate = function()
            return apply_editor('armor', true)
        end,
        editor_all_both_activate = function()
            return apply_editor(nil, true)
        end,
        editor_all_helmet_activate = function()
            return apply_editor('helmet', true)
        end,
        apply_import_armor_activate = function()
            return apply_import('armor')
        end,
        apply_import_helmet_activate = function()
            return apply_import('helmet')
        end,
        basic_copy_helmet_activate = function()
            return deps.action(function()
                return deps.copy_basic_palette('armor', 'helmet')
            end)
        end,
        basic_copy_helmet_all_activate = function()
            return deps.action(deps.copy_helmet_all)
        end,
        basic_copy_armor_activate = function()
            return deps.action(function()
                return deps.copy_basic_palette('helmet', 'armor')
            end)
        end,
        identify_region_activate = function()
            return deps.action(deps.identify_region)
        end,
        stop_identify_activate = function()
            return deps.action(function()
                assert(deps.stop_identification(), 'Highlight restoration pending')
                return deps.message('Highlight stopped; previous bindings restored.')
            end)
        end,
        populate_worn_activate = function()
            deps.mark_current_load()
            return deps.action(function()
                deps.request_population()
                if not deps.populate_worn() then
                    return deps.message('Reading worn gear colors; editor will populate when ready.')
                end
                return true
            end)
        end,
        basic_preset_change = function(index)
            if deps.refreshing_basic_presets() then
                return
            end
            deps.select_outfit(1)
            local handle = deps.handle()
            if index == 1 then
                assert(handle.set('basic_preset_name', ''))
                return
            end
            deps.action(function()
                local name = assert(deps.basic_preset_name(index))
                local file = assert(io.open(deps.presets_directory() .. '/palette-' .. name .. '.dds', 'rb'))
                local bytes = file:read(deps.dds.MAX_BYTES + 1)
                file:close()
                local data, w, h = deps.dds.decode(bytes)
                assert(w == 23)
                deps.accept_basic_preset({ data = data, width = w, height = h, source = 'Preset ' .. name })
                assert(handle.set('basic_preset_name', name))
                sync_palette()
                return deps.message('Palette preset loaded: ' .. name)
            end)
        end,
        basic_save_activate = function()
            return deps.action(function()
                local name = deps.handle().get('basic_preset_name')
                assert(name:match('^[%w _-]+$') and #name > 0 and #name <= 48, 'Enter a preset name')
                assert(deps.loaded_document(), 'Import a palette first')
                deps.preset_files().save(name, deps.loaded_document(), 'palette-')
                deps.refresh_basic_presets(name)
                return deps.message('Palette preset saved: ' .. name)
            end)
        end,
        basic_export_activate = function()
            local handle = deps.handle()
            assert(
                handle.set(
                    'save_name',
                    handle.get('basic_preset_name') ~= '' and handle.get('basic_preset_name') or 'my-palette'
                )
            )
            return handle.activate('save_dds')
        end,
        populate_applied_activate = function()
            return deps.action(function()
                deps.refresh()
                local handle = deps.handle()
                local group = assert(deps.group(handle.get('lut')), 'No live LUT selected')
                local source
                for _, binding in ipairs(group.bindings) do
                    if binding.document and binding.texture and binding.current == binding.texture.object then
                        source = binding.document
                        break
                    end
                end
                assert(
                    source,
                    'No Epic LUT palette is applied to this Live LUT. Select another Live LUT or apply a file first.'
                )
                deps.accept_applied_draft(copy_document(source, 'Current applied Live LUT ' .. handle.get('lut')))
                sync_palette()
                return deps.message('Editor populated from the selected applied Live LUT; game bindings unchanged.')
            end)
        end,
        save_palette_activate = function()
            return deps.action(deps.save_palette)
        end,
        apply_checked_activate = function()
            return deps.action(deps.apply_checked)
        end,
        apply_file_armor_activate = function()
            return apply_file('armor', 2)
        end,
        apply_file_helmet_activate = function()
            return apply_file('helmet', 3)
        end,
        apply_file_cape_activate = function()
            return apply_file('cape', 5)
        end,
        apply_file_both_activate = function()
            return deps.action(function()
                assert(deps.imported_document(), 'Import a palette first')
                assert(deps.handle().set('scope', 4))
                return deps.apply(deps.imported_document())
            end)
        end,
        apply_editor_activate = function()
            return deps.action(function()
                return deps.apply_checked(assert(deps.loaded_document(), 'Save a LUT to Palette first'))
            end)
        end,
        palette_change = function(index)
            local path = deps.palette_path(index)
            if path then
                deps.action(function()
                    return deps.resume_palette(path)
                end)
            end
        end,
        refresh_activate = function()
            return deps.action(deps.refresh)
        end,
        lut_change = function(index)
            if deps.live_selection_suppressed() then
                return
            end
            deps.action(function()
                assert(deps.stop_identification(), 'Highlight restoration pending')
                local group = deps.group(index)
                local source
                if group then
                    for _, b in ipairs(group.bindings) do
                        source = deps.basic_document(b) or b.document or deps.original(b.original)
                        if source then
                            break
                        end
                    end
                end
                deps.clear_live_draft()
                deps.accept_live_draft(source and copy_document(source, 'Live LUT ' .. index) or nil)
                local view = deps.import_view()
                if view then
                    view.selected = nil
                    view.scroll = 0
                end
                sync_palette()
                return deps.message(
                    source and ('Loaded Live LUT ' .. index .. ' into editor')
                        or 'Selected Live LUT colors unavailable; waiting for original snapshot'
                )
            end)
        end,
        apply_activate = function()
            return deps.action(deps.apply)
        end,
        apply_armor_activate = function()
            return deps.action(function()
                assert(deps.handle().set('scope', 2))
                return deps.apply(nil, 'armor')
            end)
        end,
        apply_helmet_activate = function()
            return deps.action(function()
                assert(deps.handle().set('scope', 3))
                return deps.apply(nil, 'helmet')
            end)
        end,
        remove_lut_activate = function()
            return deps.action(function()
                deps.remove_lut()
                deps.clear_removed_draft()
                sync_palette()
                return deps.message('LUT removed; original bindings restored.')
            end)
        end,
        save_setup_activate = function()
            local frontend, outfits = deps.frontend(), deps.outfits()
            if not frontend.menu or not outfits then
                return deps.action(deps.save_setup)
            end
            assert(deps.stop_identification(), 'Highlight restoration pending')
            local mod = deps.mod()
            frontend.menu.outfit_dialog = {
                phase = 'scope',
                save_kind = { armor = true, helmet = true, cape = true },
                weapon_options = deps.weapon_enabled == true,
                mod = mod,
                control = mod.controls.outfit_name,
                names = outfits.names(),
                on_save = deps.keep_outfit,
            }
            return deps.message(
                deps.weapon_enabled and 'Choose gear and weapon LUTs to keep as a named preset.'
                    or 'Choose Armor, Helmet and Cape LUTs to keep as a named preset.'
            )
        end,
        restore_activate = function()
            return deps.action(function()
                local selected, selected_kind = deps.restoration_selection()
                deps.remove_lut()
                deps.clear_restoration_draft()
                deps.refresh(true)
                local panels = deps.import_state().raw.basic
                local document, restored_selection
                if
                    deps.frontend().basic_mode
                    and selected
                    and panels[selected.container or (selected.kind == 'cape' and 'armor' or selected.kind)]
                then
                    local panel = panels[selected.container or (selected.kind == 'cape' and 'armor' or selected.kind)]
                    local proof = deps.appearance_proof()
                    local original = panel.group and deps.group_original(panel.group)
                    document = panel.document
                    restored_selection = document
                            and {
                                kind = panel.kind,
                                key = panel.key,
                                group = panel.group,
                                container = selected.container,
                                cape_proof = panel.kind == 'cape' and proof and proof.cape or nil,
                                resource = original and original.resource,
                            }
                        or nil
                    if
                        panel.kind == 'cape'
                        and not (restored_selection and restored_selection.cape_proof and restored_selection.resource)
                    then
                        document, restored_selection = nil, nil
                    end
                else
                    deps.clear_basic_selection()
                    local group = deps.group(deps.handle().get('lut'))
                    if group then
                        for _, b in ipairs(group.bindings) do
                            local source = (not selected_kind or b[selected_kind]) and deps.original(b.original)
                            if source then
                                document = copy_document(source, 'Original game LUT')
                                break
                            end
                        end
                    end
                end
                deps.accept_restored_draft(document, restored_selection)
                local view = deps.import_view()
                if view then
                    view.selected = nil
                end
                sync_palette()
                return deps.message(
                    deps.loaded_document()
                            and 'Original bindings and displayed colors restored; imported file retained.'
                        or 'Original bindings restored; original colors are not available yet.'
                )
            end)
        end,
        reset_custom_activate = function()
            return deps.action(function()
                return assert(deps.palette_editor(), 'Palette editor unavailable').reset()
            end)
        end,
        restore_imported_activate = function()
            return deps.action(function()
                return assert(deps.palette_editor(), 'Save an import to the editor first').reset()
            end)
        end,
        load_activate = function()
            return deps.action(function()
                return deps.load(false)
            end)
        end,
    }
end

return A
