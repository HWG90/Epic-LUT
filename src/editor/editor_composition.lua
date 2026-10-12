-- Composes registered pages, view mounts and picker presentation.
-- Session changes and preset persistence remain explicit host callbacks.
local C = {}

function C.new(deps)
    local self = {}

    function self.pages(callbacks, api, options)
        local pages = deps.registry.pages(callbacks, options)
        local palette_editor = deps.palette_editor()
        if palette_editor then
            deps.configuration.append(pages, palette_editor.pages(), {
                api = api,
                preferences = deps.preferences,
                updates = deps.updates,
                action = deps.action,
                message = deps.message,
                auto_populate_changed = deps.auto_populate_changed,
                resource_changed = deps.resource_changed,
            })
        end
        -- Keep Value Editor controls registered without a duplicate material tab.
        local colors_page
        for _, page in ipairs(pages) do
            if page.id == 'colors' then
                colors_page = page
            end
        end
        for i = #pages, 1, -1 do
            if pages[i].id == 'advanced' and colors_page then
                for _, control in ipairs(pages[i].controls) do
                    colors_page.controls[#colors_page.controls + 1] = control
                end
                table.remove(pages, i)
            end
        end
        if deps.basic_view then
            table.insert(pages, 1, {
                id = 'basic',
                name = 'Basic',
                require_confirmation = false,
                controls = deps.basic_camo and deps.basic_camo.controls(deps.apply_camo) or {},
            })
        end
        if deps.armory_view then
            table.insert(pages, #pages, {
                id = 'armory',
                name = 'The Armory',
                require_confirmation = false,
                controls = {
                    {
                        id = 'armory_search',
                        type = 'input',
                        allow_empty = true,
                        label = 'Search Armory',
                        default = '',
                        on_change = deps.search_armory,
                    },
                    {
                        id = 'armory_sort',
                        type = 'choice',
                        label = 'Sort presets',
                        choices = { 'Name A-Z', 'Name Z-A' },
                        default = 1,
                        on_change = deps.sort_armory,
                    },
                },
            })
        end
        local pattern_editor = deps.pattern_editor()
        if deps.weapon_editor then
            table.insert(pages, #pages, deps.weapon_editor().controller().page())
            if colors_page then
                colors_page.controls[#colors_page.controls + 1] = {
                    id = 'editor_load_weapon',
                    type = 'button',
                    label = 'Weapon LUT',
                    on_activate = deps.open_weapons,
                }
                colors_page.controls[#colors_page.controls + 1] = {
                    id = 'editor_apply_weapon',
                    type = 'button',
                    label = 'Apply weapon',
                    on_activate = deps.apply_weapon_document,
                }
            end
        end
        if pattern_editor then
            for _, page in ipairs(pages) do
                if page.id == 'colors' then
                    for _, control in ipairs(pattern_editor.controls()) do
                        page.controls[#page.controls + 1] = control
                    end
                end
            end
        end
        if deps.sharing_enabled then
            for _, page in ipairs(pages) do
                if page.id == 'save' then
                    page.controls[#page.controls + 1] = {
                        id = 'share_appearance',
                        type = 'toggle',
                        label = 'Share full LUT appearance with Epic LUT users',
                        default = true,
                        description = 'Shares equipped Armor and Helmet tables with compatible Epic LUT squadmates. Both players need this version. Oversized appearances remain local.',
                    }
                    page.controls[#page.controls + 1] =
                        { id = 'sharing_status', type = 'text', label = 'Sharing: waiting for lobby' }
                end
            end
        end
        return pages
    end

    function self.mount(api, handle)
        local mod = api.mods[handle.id]
        if deps.configuration.attach then
            deps.configuration.attach(api, handle, deps.configuration_view, deps.key_name)
        end
        for _, page in ipairs(mod.pages) do
            for _, control in ipairs(page.controls) do
                if control.id == 'sharing_status' then
                    deps.sharing_status_control(control)
                end
            end
        end
        local pattern_editor = deps.pattern_editor()
        if pattern_editor then
            pattern_editor.attach(handle, mod.controls)
        end
        mod.tabs_top = true
        mod.minimum_width = 1420
        mod.minimum_height = 960
        if deps.weapon_editor then
            local weapons = deps.weapon_editor().controller()
            weapons.attach(handle, mod.controls)
            local view = deps.weapon_view.new(weapons)
            for _, page in ipairs(mod.pages) do
                if page.id == 'weapons' then
                    page.minimum_width, page.minimum_height =
                        deps.weapon_view.minimum_width, deps.weapon_view.minimum_height
                    page.render_layout, page.on_wheel = view.draw, view.wheel
                end
            end
        end
        deps.default_mod(handle.id)
        if deps.remove_outfit_choice and mod.controls.outfit_preset then
            mod.controls.outfit_preset.on_delete_choice = deps.remove_outfit_choice
        end
        local palette_editor = deps.palette_editor()
        if palette_editor then
            palette_editor.pattern_editor = pattern_editor
            palette_editor.can_select_gear = function(kind)
                if kind == 'weapon' and deps.weapon_editor then
                    return true
                end
                local control = mod.controls['basic_' .. kind .. '_lut']
                control.disabled = not deps.gear_ready() or control.choices[1] == 'Waiting for gear...'
                return not control.disabled
            end
            palette_editor.load_seen = deps.load_seen
            palette_editor.attach(api, handle)
            if palette_editor.tools and palette_editor.tools.mount_preferences then
                palette_editor.tools.mount_preferences(deps.preferences)
            end
            if deps.basic_camo then
                for _, container in ipairs({ 'armor', 'helmet' }) do
                    for color = 1, 4 do
                        local control = mod.controls['basic_' .. container .. '_camo_color_' .. color]
                        if control then
                            control.can_open_picker = deps.camo_picker_guard(control, container)
                        end
                    end
                end
            end
            local quick, cell = mod.controls.quick_color, mod.controls.cell_color
            if quick and cell then
                quick.can_open_picker = function()
                    local q = deps.quick_selection()
                    if not q or q.document ~= deps.loaded_document() then
                        return false, 'Select an editable region first'
                    end
                    local current, why = deps.validate_quick_target()
                    if not current then
                        return false, why
                    end
                    return palette_editor.can_pick(q.row, q.column, 1)
                end
                quick.picker_begin = function()
                    local allowed, why = quick.can_open_picker()
                    if not allowed then
                        return false, why
                    end
                    local q = deps.quick_selection()
                    palette_editor.focus_cell(q.row, q.column)
                    return cell.picker_begin(1)
                end
                quick.picker_preview = function(color)
                    local allowed, why = quick.can_open_picker()
                    assert(allowed, why)
                    return cell.picker_preview(color, cell.picker_alpha())
                end
                quick.picker_end = function(commit)
                    if cell.picker_end then
                        return cell.picker_end(commit)
                    end
                end
                quick.picker_channel_enabled = function(channel, mode)
                    return cell.picker_channel_enabled and cell.picker_channel_enabled(channel, mode)
                end
                quick.picker_commit = function(color)
                    quick.picker_preview(color)
                    return true
                end
            end
        end
        if deps.armory_view then
            local armory = deps.armory_view.new(deps.info, palette_editor and palette_editor.preview)
            for _, page in ipairs(mod.pages) do
                if page.id == 'armory' then
                    page.render_layout = armory.draw
                    page.on_wheel = armory.wheel
                end
            end
        end
        if deps.refresh_outfits then
            deps.refresh_outfits()
        end
        local direct_page
        for _, page in ipairs(mod.pages) do
            if page.id == 'direct' then
                direct_page = page
            end
        end
        if deps.basic_view then
            local basic = deps.basic_view.new(deps.info, deps.select_basic, deps.control_help, deps.set_camo_row)
            local page = mod.pages[1]
            page.minimum_width = 1100
            page.minimum_height = deps.basic_view.minimum_height or 1000
            page.render_layout = basic.draw
            page.on_wheel = basic.wheel
        end
        if mod.controls.basic_preset then
            deps.initialize_basic_presets()
        end
        local import_view
        if deps.import_view then
            import_view = deps.import_view.new(
                deps.info,
                deps.table_groups,
                deps.select_import_cell,
                deps.ui_core,
                deps.control_help,
                deps.value_tooltip
            )
            direct_page.render_layout = import_view.draw
            direct_page.on_wheel = import_view.wheel
        end
        return import_view
    end

    return self
end

return C
