-- Page/action composition only. Native mutation is delegated through explicit session ports.
local R = {}
function R.register(m, host, current)
    if host.api() == current and host.handle() then
        return
    end
    if host.handle() then
        host.handle().unregister()
    end
    host.set_api(current)
    local callbacks = m.editor_actions.new({
        action = host.action,
        message = host.message,
        dds = m.dds,
        handle = function()
            return host.handle()
        end,
        mod = function()
            return host.api().mods[host.handle().id]
        end,
        frontend = function()
            return host.frontend()
        end,
        preferences = function()
            return host.preferences()
        end,
        palette_editor = function()
            return host.palette_editor()
        end,
        import_view = function()
            return host.import_view()
        end,
        history = function()
            return host.history()
        end,
        armory_collection = function()
            return host.armory_collection()
        end,
        outfits = function()
            return host.outfits()
        end,
        quick_selection = function()
            return host.edit.quick_selection
        end,
        loaded_document = function()
            return host.edit.loaded
        end,
        imported_document = function()
            return host.edit.imported
        end,
        group = function(index)
            return host.groups()[index]
        end,
        original = function(object)
            return host.original_luts() and host.original_luts().get(object)
        end,
        group_original = function(index)
            return host.original_luts() and host.original_luts().get(host.groups()[index].object)
        end,
        basic_document = function(b)
            return host.basic_documents()[m.gear_catalog.kind(b) .. ':' .. tostring(b.original)]
        end,
        current_page = function()
            return host.frontend().menu and host.api().mods[host.handle().id].pages[host.frontend().menu.page].id
        end,
        lut_label_resource = function()
            local panel = host.import_state().raw.basic[host.palette_editor() and host.palette_editor().gear or 'armor']
            local original = panel and panel.group and host.original_luts() and host.original_luts().get(host.groups()[panel.group].object)
            return original and original.resource
        end,
        lut_labels = function()
            return host.operations.lut_names
        end,
        import_state = host.import_state,
        load = host.load,
        cancel_import = host.cancel_import,
        load_debug_lut = host.operations.load_debug_lut,
        paint_quick = host.operations.paint_quick,
        apply_matching = host.operations.apply_matching,
        open_editor = function()
            return host.api().focus_page(host.handle().id, 'colors')
        end,
        manage_outfit = host.operations.manage_outfit,
        select_outfit = host.select_outfit,
        sync_armory_export = host.sync_armory_export,
        apply_outfit = host.apply_outfit,
        armory_cape_available = host.operations.armory_cape_available,
        choose_outfit_luts = host.operations.choose_outfit_luts,
        open_import_map = host.operations.open_import_map,
        mark_current_load = host.mark_current_load,
        load_editor_target = host.load_editor_target,
        apply_editor_target = host.apply_editor_target,
        apply_import_to = host.apply_import_to,
        copy_basic_palette = host.copy_basic_palette,
        copy_helmet_all = host.copy_helmet_all,
        identify_region = host.identify_region,
        stop_identification = function()
            return host.stop_identification()
        end,
        populate_worn = host.populate_worn,
        reload_weapon_editor = host.operations.reload_weapon_editor,
        refreshing_basic_presets = function()
            return host.edit.refreshing_basic_presets
        end,
        basic_preset_name = function(index)
            return host.basic_names()[index - 1]
        end,
        presets_directory = function()
            return host.paths().presets
        end,
        preset_files = function()
            return host.operations.preset_files
        end,
        refresh_basic_presets = function(name)
            return host.operations.refresh_basic_presets(name)
        end,
        save_palette = host.save_palette,
        apply_checked = host.apply_checked,
        refresh = host.refresh,
        apply = host.apply,
        remove_lut = host.remove_lut,
        save_setup = host.save_setup,
        keep_outfit = host.keep_outfit,
        weapon_enabled = m.weapon_bridge ~= nil,
        appearance_proof = function()
            return host.operations.appearance_proof()
        end,
        live_selection_suppressed = function()
            return host.live_select_suppressed()
        end,
        palette_path = function(index)
            return not host.select_suppressed() and not host.pending() and host.palettes()[index] or nil
        end,
        queue_editor_target = function(kind)
            host.queue_editor_target(kind)
        end,
        request_population = function()
            if host.original_luts() and host.original_luts().retry then
                host.original_luts().retry()
            end
            host.request_population()
            host.edit.populate_manual_request = true
        end,
        accept_basic_preset = function(document)
            host.edit.loaded = document
        end,
        resume_palette = function(path)
            host.stop_resume()
            return host.load_dds(path)
        end,
        clear_live_draft = function()
            host.edit.loaded = nil
            host.clear_basic_selection()
            host.edit.quick_selection = nil
        end,
        accept_live_draft = function(document)
            host.edit.loaded = document
            host.edit.preview_document = host.edit.loaded
            host.edit.preview_revision = 0
        end,
        accept_applied_draft = function(document)
            host.edit.loaded = document
            host.edit.preview_document = host.edit.loaded
            host.edit.preview_revision = 0
            host.edit.quick_selection = nil
        end,
        clear_removed_draft = function()
            host.edit.loaded = nil
            host.edit.imported = nil
            host.clear_palettes()
        end,
        restoration_selection = function()
            return host.basic_selected(),
                (host.edit.editor_target and host.edit.editor_target.kind) or (host.basic_selected() and host.basic_selected().kind)
        end,
        clear_restoration_draft = function()
            host.basic_state().clear()
            host.clear_missing()
            host.edit.quick_selection = nil
            host.edit.loaded = nil
        end,
        clear_basic_selection = function()
            host.clear_basic_selection()
        end,
        accept_restored_draft = function(document, selected)
            host.edit.loaded = document
            host.select_basic(selected)
            host.sync_basic_imported()
            host.edit.preview_document = host.edit.loaded
            host.edit.preview_revision = host.edit.loaded and (host.edit.loaded.revision or 0) or 0
        end,
        export_armory = function()
            local preset = assert(host.armory_collection() and host.armory_collection().selected, 'Choose a saved Armory preset first')
            local include_capes, include_patterns = host.operations.include_capes_in_exports(), host.operations.include_patterns_in_exports()
            local function factory(snapshot)
                return assert(m.preset_export, 'Armory exporter unavailable').new(m, host.paths(), {
                    lut_label = function(hash) return host.operations.lut_names and host.operations.lut_names.get(hash) end,
                    include_capes = function() return include_capes end,
                    include_patterns = function() return include_patterns end,
                    binding_provenance = host.operations.binding_export_provider(snapshot),
                    original_patch = host.operations.export_original_patch,
                    material_source = host.operations.export_material_source,
                    unit_layout = m.binding_unit_layout,
                    weapon_patch_archive = function(entries) return host.operations.weapon_sources().patch_archive(entries) end,
                    weapon_export_batch = function(entries, serialize) return host.operations.weapon_sources().with_export_batch(entries, serialize) end,
                    resource_id_available = host.operations.export_id_available,
                })
            end
            local name, format, lut, naming = host.handle().get('armory_export_name'), host.handle().get('armory_export_format'),
                host.handle().get('armory_export_lut'), host.handle().get('armory_dds_naming')
            if m.weapon_workflow and m.weapon_mapping then
                return host.operations.weapon_workflow().export_saved(preset, name, format, lut, naming, factory)
            end
            -- Garment-only/legacy hosts do not load the optional weapon workflow.
            local output, description, sharefile = factory(preset).save(name, preset, format, lut, naming)
            return host.message('Exported ' .. preset.name .. ' (' .. description .. ') to ' .. (sharefile or output))
        end,
    })
    local composition = m.editor_composition.new({
        registry = m.editor_registry,
        configuration = m.configuration,
        configuration_view = m.configuration_view,
        basic_view = m.basic_view,
        basic_camo = m.basic_camo,
        armory_view = m.armory_view,
        import_view = m.import_view,
        table_groups = m.table_groups,
        ui_core = m.ui_core,
        control_help = m.control_help,
        value_tooltip = m.palette.value_tooltip,
        key_name = m.ui_menu and m.ui_menu.key_name,
        sharing_enabled = not not m.shared_appearance,
        preferences = host.preferences(),
        updates = host.updates(),
        action = host.action,
        message = host.message,
        info = host.import_state,
        palette_editor = function()
            return host.palette_editor()
        end,
        pattern_editor = function()
            return host.pattern_editor()
        end,
        weapon_editor = m.weapon_bridge and host.weapon_editor or nil,
        weapon_view = m.weapon_view,
        open_weapons = host.operations.reload_weapon_editor,
        apply_weapon_document = function()
            return host.action(function()
                local target = host.operations.weapon_document_target(host.edit.loaded)
                host.edit.editor_target = target
                return host.weapon_editor().apply(target, host.edit.loaded)
            end)
        end,
        auto_populate_changed = function(enabled)
            host.edit.auto_signature = nil
            if enabled then
                host.edit.populate_manual_request = nil
                host.request_population()
                host.reset_population_delay()
            end
            return true
        end,
        resource_changed = function()
            if host.handle() then
                host.import_state()
                if host.frontend().menu then
                    host.frontend().menu.redraw_revision = (host.frontend().menu.redraw_revision or 0) + 1
                end
            end
        end,
        apply_camo = function(kind, value, mode, color)
            if not host.operations.syncing_basic_camo then
                local completed
                local result = host.action(function()
                    local text = host.operations.apply_basic_camo(kind, value, mode, color)
                    completed = true
                    return text
                end)
                if mode == 'color' then
                    return completed == true, result
                end
                return result
            end
        end,
        search_armory = function(value)
            host.armory_collection().filter(value, host.handle().get('armory_sort'))
        end,
        sort_armory = function(value)
            host.armory_collection().filter(host.handle().get('armory_search'), value)
        end,
        sharing_status_control = function(control)
            host.edit.sharing_status_control = control
        end,
        default_mod = function(id)
            host.frontend().default_mod_id = id
        end,
        remove_outfit_choice = host.armory_collection() and function(index, label)
            local ok, result = host.armory_collection().remove_choice(index, label)
            host.sync_armory_export()
            return ok, result
        end,
        gear_ready = function()
            return host.edit.loaded ~= nil or host.edit.imported ~= nil
        end,
        load_seen = function()
            return host.edit.load_seen or (host.preferences() and host.preferences().load_seen and host.preferences().load_seen(false)) or false
        end,
        camo_picker_guard = function(control, container)
            return host.operations.basic_camo_picker_guard(control, container)
        end,
        quick_selection = function()
            return host.edit.quick_selection
        end,
        loaded_document = function()
            return host.edit.loaded
        end,
        validate_quick_target = function()
            if host.edit.editor_target then
                return pcall(host.operations.checked_editor_target, host.edit.editor_target)
            end
            return true
        end,
        refresh_outfits = m.outfit_presets and host.refresh_outfits or nil,
        select_basic = function(row, kind)
            if kind then
                local panel = host.import_state().raw.basic[kind]
                if not panel or not panel.document then
                    host.message('Reading worn ' .. kind .. ' colors; try again when ready.')
                    return false
                end
                local proof = host.operations.appearance_proof()
                local original = host.original_luts() and host.original_luts().get(host.groups()[panel.group].object)
                if panel.kind == 'cape' then
                    assert(
                        proof and proof.cape and original and original.resource,
                        'Current Cape identity is still loading; load current colors again'
                    )
                end
                host.edit.editor_target = nil
                host.select_basic({
                    kind = panel.kind or kind,
                    container = kind,
                    key = panel.key,
                    group = panel.group,
                    cape_proof = panel.kind == 'cape' and proof and proof.cape or nil,
                    resource = original and original.resource,
                })
                host.edit.loaded = panel.document
                host.sync_basic_imported()
                host.edit.preview_document = host.edit.loaded
                host.edit.preview_revision = host.edit.loaded.revision or 0
                host.palette_editor().sync()
            end
            if host.edit.loaded and host.palette_editor() then
                host.palette_editor().focus_cell(row, 1)
                return true
            end
        end,
        set_camo_row = function(...)
            return host.operations.set_basic_camo_row(...)
        end,
        initialize_basic_presets = function()
            host.operations.refresh_basic_presets = function(previous)
                local selector = host.api().mods[host.handle().id].controls.basic_preset
                previous = previous or selector.choices[host.handle().get('basic_preset')]
                host.set_basic_names({})
                local choices, selected = { 'New preset...' }, 1
                for _, file in
                    ipairs(m.windows and m.windows.files and m.windows.files(host.paths().presets, 'palette-*.dds') or {})
                do
                    local name = file:match('^palette%-([%w _-]+)%.dds$')
                    if name then
                        host.basic_names()[#host.basic_names() + 1] = name
                        choices[#choices + 1] = name
                        if name == previous then
                            selected = #choices
                        end
                    end
                end
                selector.choices = choices
                host.edit.refreshing_basic_presets = true
                local called, ok, why = pcall(host.handle().set, 'basic_preset', selected)
                host.edit.refreshing_basic_presets = false
                assert(called and ok, called and why or ok)
            end
            host.api().mods[host.handle().id].controls.basic_preset.on_delete_choice = function(index, label)
                local name = assert(host.basic_names()[index - 1], 'Choose a saved palette preset')
                assert(name == label, 'Preset list changed; reopen it before removing a preset')
                host.operations.preset_files.delete_palette(name)
                if host.handle().get('basic_preset_name') == name then
                    assert(host.handle().set('basic_preset_name', ''))
                end
                host.operations.refresh_basic_presets()
                return true, 'Removed saved palette preset: ' .. name
            end
            host.operations.refresh_basic_presets()
        end,
        select_import_cell = function(...)
            return host.operations.select_import_cell(...)
        end,
    })
    local pages = composition.pages(callbacks, current, {
        ui_scale = host.preferences().scale and host.preferences().scale() or 100,
        status = host.status(),
    })
    host.set_handle(host.api().register({ id = 'epic_direct_lut', name = 'Epic LUT', pages = pages }))
    local mounted_import_view = composition.mount(host.api(), host.handle())
    if m.import_view then
        host.set_import_view(mounted_import_view)
    end
    host.clear_groups()
end
return R
