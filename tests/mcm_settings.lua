local Bridge = dofile('src/platform/mcm_settings.lua')
local Core = dofile('vendor/menu/core.lua')
local mcm_dir = os.getenv('MCM_SOURCE_DIR') or '../DBF-MCM'
local MCMCore = dofile(mcm_dir .. '/src/core.lua')
local Grouping = dofile(mcm_dir .. '/src/grouping.lua')
local logs, writes, actions, failed_save = {}, 0, 0, false
local disk = {}
local own = Core.new({
    load = function(id)
        return disk[id] or {}
    end,
    save = function(id, values)
        if failed_save then
            return false, 'disk unavailable'
        end
        writes = writes + 1
        disk[id] = values
        return true
    end,
})
local prefs = own.register({
    id = 'preferences',
    name = 'Preferences',
    pages = {
        {
            id = 'preferences',
            name = 'Preferences',
            require_confirmation = false,
            controls = {
                { id = 'menu_key', type = 'keybind', label = 'Open Advanced Mode', default = 121 },
                { id = 'font_size', type = 'slider', label = 'Font size', min = 10, max = 20, step = 1, default = 12 },
                {
                    id = 'ui_scale',
                    type = 'slider',
                    label = 'UI scale (%)',
                    min = 70,
                    max = 130,
                    step = 5,
                    default = 100,
                },
                { id = 'auto_updates', type = 'toggle', label = 'Check for updates at launch', default = true },
                {
                    id = 'include_capes_in_armor_exports',
                    type = 'toggle',
                    label = 'Include Capes in Armor Exports',
                    default = true,
                },
                {
                    id = 'reset_key',
                    type = 'button',
                    label = 'Reset shortcut',
                    on_activate = function()
                        actions = actions + 1
                        return 'Reset'
                    end,
                },
            },
        },
    },
})
local share_status = 'Sharing: waiting'
local function register_source()
    return own.register({
        id = 'epic_direct_lut',
        name = 'Epic LUT',
        pages = {
            {
                id = 'save',
                name = 'Configuration',
                require_confirmation = false,
                controls = {
                    {
                        id = 'ui_scale',
                        type = 'slider',
                        label = 'Legacy scale',
                        min = 70,
                        max = 130,
                        step = 5,
                        default = 125,
                        on_change = function()
                            error('Legacy scale writer selected')
                        end,
                    },
                    {
                        id = 'configuration_ui_scale',
                        source_mod_id = 'preferences',
                        source_control_id = 'ui_scale',
                        type = 'slider',
                        label = 'UI scale (%)',
                        min = 70,
                        max = 130,
                        step = 5,
                        default = 100,
                    },
                    {
                        id = 'configuration_menu_key',
                        source_mod_id = 'preferences',
                        source_control_id = 'menu_key',
                        type = 'keybind',
                        label = 'Open Advanced Mode',
                        default = 121,
                    },
                    {
                        id = 'configuration_font_size',
                        source_mod_id = 'preferences',
                        source_control_id = 'font_size',
                        type = 'slider',
                        label = 'Font size',
                        min = 10,
                        max = 20,
                        step = 1,
                        default = 12,
                    },
                    {
                        id = 'configuration_reset_key',
                        source_mod_id = 'preferences',
                        source_control_id = 'reset_key',
                        type = 'button',
                        label = 'Reset shortcut',
                        on_activate = function()
                            error('Alias callback must route to its owner')
                        end,
                    },
                    {
                        id = 'auto_updates',
                        source_mod_id = 'preferences',
                        source_control_id = 'auto_updates',
                        type = 'toggle',
                        label = 'Check for updates at launch',
                        default = false,
                    },
                    {
                        id = 'auto_populate_worn',
                        type = 'toggle',
                        label = 'Always populate current gear',
                        default = false,
                        on_change = function()
                            actions = actions + 1
                        end,
                    },
                    {
                        id = 'disable_player_preview',
                        type = 'toggle',
                        label = 'Turn off Player Preview',
                        default = false,
                    },
                    {
                        id = 'include_capes_in_armor_exports',
                        source_mod_id = 'preferences',
                        source_control_id = 'include_capes_in_armor_exports',
                        type = 'toggle',
                        label = 'Include Capes in Armor Exports',
                        default = true,
                    },
                    { id = 'share_appearance', type = 'toggle', label = 'Share full LUT appearance', default = true },
                    { id = 'sharing_status', type = 'text', label = share_status },
                    {
                        id = 'manual_fallback',
                        type = 'section',
                        label = 'Manual',
                        children = {
                            { id = 'file', type = 'input', label = 'Filename', default = 'palette' },
                            {
                                id = 'load',
                                type = 'button',
                                label = 'Import local file',
                                on_activate = function()
                                    actions = actions + 1
                                    return 'Imported'
                                end,
                            },
                        },
                    },
                },
            },
        },
    })
end
local original = register_source()
local external, opened, close_ok = nil, 0, true
local bridge = Bridge.new({
    api = own,
    discover = function()
        return external
    end,
    log = function(text)
        logs[#logs + 1] = text
    end,
    open_advanced = function()
        opened = opened + 1
        return true
    end,
})
bridge.tick()
assert(#logs == 0, 'MCM absence must be quiet')
local external_writes = 0
local function framework()
    local api = MCMCore.new({
        load = function()
            return { configuration_menu_key = 0 }
        end,
        save = function()
            external_writes = external_writes + 1
            return true
        end,
    }, nil, Grouping)
    api.close = function()
        return close_ok, 'MCM still owns input'
    end
    return api
end
external = framework()
bridge.tick()
local mod = assert(external.mods.epic_lut_settings)
local handle = mod.handle
assert(#external.list() == 1 and mod.name == 'Epic LUT Settings')
assert(handle.get('configuration_menu_key') == 121, 'MCM loaded a competing saved preference')
assert(handle.edit('configuration_menu_key', 45))
assert(prefs.get('menu_key') == 45 and external.get('epic_lut_settings', 'configuration_menu_key') == 45)
assert(writes == 1 and external_writes == 0, 'A setting must persist exactly once through Epic LUT')
assert(handle.get('include_capes_in_armor_exports') == true)
assert(handle.edit('include_capes_in_armor_exports', false))
assert(
    prefs.get('include_capes_in_armor_exports') == false and original.get('include_capes_in_armor_exports') == false,
    'Cape export setting did not share its authoritative owner'
)
assert(handle.edit('include_capes_in_armor_exports', true))
local automatic_writes = writes
assert(handle.get('auto_updates') == true and original.get('auto_updates') == true)
assert(handle.edit('auto_updates', false))
assert(writes == automatic_writes + 1 and not prefs.get('auto_updates') and not original.get('auto_updates'))
assert(handle.reset('auto_updates') and prefs.get('auto_updates'))
assert(prefs.set('font_size', 18))
assert(handle.preview('configuration_font_size') == 18, 'External preference change left a stale MCM value')
assert(handle.set_many({ configuration_font_size = 16, configuration_menu_key = 44 }))
assert(prefs.get('font_size') == 16 and prefs.get('menu_key') == 44)
local before = writes
local mixed = handle.set_many({ configuration_menu_key = 43, disable_player_preview = true })
assert(
    mixed == false and writes == before and prefs.get('menu_key') == 44 and not original.get('disable_player_preview'),
    'Cross-store batch partially committed'
)
assert(handle.activate('configuration_reset_key'))
assert(handle.activate('load'))
assert(actions == 2, 'MCM actions bypassed the source or ran twice')
assert(handle.set('auto_populate_worn', true))
assert(original.get('auto_populate_worn') and actions == 3)
failed_save = true
local ok, why = handle.edit('disable_player_preview', true)
assert(ok == false and why == 'disk unavailable' and not handle.get('disable_player_preview'))
failed_save = false
own.mods.epic_direct_lut.controls.share_appearance.disabled = true
bridge.tick()
assert(mod.controls.share_appearance.disabled)
assert(not pcall(handle.set, 'share_appearance', false), 'Disabled source setting was writable through MCM')
own.mods.epic_direct_lut.controls.share_appearance.disabled = false
bridge.tick()
assert(not mod.controls.share_appearance.disabled)
local status
for _, control in ipairs(own.mods.epic_direct_lut.pages[1].controls) do
    if control.id == 'sharing_status' then
        status = control
    end
end
status.label = 'Sharing: sent 490 bytes'
bridge.tick()
local saw_status, manual, col1, col2 = false, false, false, false
for _, control in ipairs(mod.pages[1].controls) do
    if control.id == 'sharing_status' then
        saw_status = control.label == status.label
    end
    if control.id == 'file' then
        manual = control.groups[1] == 'manual'
    end
    if control.column == 1 then
        col1 = true
    elseif control.column == 2 then
        col2 = true
    end
end
assert(saw_status and manual and col1 and col2, 'MCM presentation lost its status, fallback or column groups')
close_ok = false
ok = handle.activate('open_advanced')
assert(ok == false and opened == 0, 'Editor opened before MCM restored input')
close_ok = true
assert(handle.queue('open_advanced') and opened == 1)
-- Exercise Epic's real footer against the MCM bridge rather than a second
-- settings copy. Changes from either surface immediately affect its geometry.
local FooterMenu = dofile('vendor/menu/menu.lua').new(own, function(text, size)
    return #text * size * 0.5
end)
FooterMenu.visible = true
for index, entry in ipairs(own.list()) do
    if entry.id == 'epic_direct_lut' then
        FooterMenu.selected = index
    end
end
local function footer_commands()
    return FooterMenu.compose(1920, 1080)
end
local function footer_label(commands, value)
    for _, command in ipairs(commands) do
        if command.full_text == value then
            return command
        end
    end
end
assert(footer_label(footer_commands(), 'UI Scale: 100%'))
assert(handle.edit('configuration_ui_scale', 90))
assert(
    prefs.get('ui_scale') == 90
        and handle.get('configuration_ui_scale') == 90
        and footer_label(footer_commands(), 'UI Scale: 90%')
        and math.abs(FooterMenu.window_bounds.scale - 0.9) < 1e-9,
    'MCM scale did not reach Epic footer/geometry'
)
local footer = footer_label(footer_commands(), 'UI Scale: 90%')
local arrow
for _, command in ipairs(footer_commands()) do
    if command.text == '>' and command.x > footer.x and math.abs(command.y - footer.y) < 0.1 then
        arrow = command
    end
end
assert(arrow)
before = writes
for _, down in ipairs({ true, false }) do
    FooterMenu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return arrow.x + 3, arrow.y + 3
        end,
        wheel = function()
            return 0
        end,
    })
end
assert(
    prefs.get('ui_scale') == 95
        and handle.preview('configuration_ui_scale') == 95
        and original.get('ui_scale') == 125
        and writes == before + 1
        and external_writes == 0,
    'Epic footer failed to update the MCM owner exactly once'
)
assert(footer_label(footer_commands(), 'UI Scale: 95%') and math.abs(FooterMenu.window_bounds.scale - 0.95) < 1e-9)
assert(own.mods.epic_direct_lut.values.configuration_ui_scale == nil, 'Scale alias stored a competing value')
local count = #logs
bridge.tick()
bridge.tick()
assert(#logs == count, 'Idle bridge re-registered or logged repeatedly')
local old_external, old_handle = external, handle
external = framework()
bridge.tick()
assert(not old_external.mods.epic_lut_settings and external.mods.epic_lut_settings, 'MCM reload leaked registrations')
assert(not pcall(old_handle.set, 'disable_player_preview', true), 'Retired MCM handle remained writable')
original.unregister()
bridge.tick()
assert(not external.mods.epic_lut_settings, 'Retired source left an active bridge')
original = register_source()
bridge.tick()
assert(external.mods.epic_lut_settings, 'Source reload did not recover')
bridge.close()
bridge.close()
assert(not external.mods.epic_lut_settings)
bridge.tick()
assert(not external.mods.epic_lut_settings, 'Closed bridge registered again')
assert(own.mods.preferences and own.mods.epic_direct_lut, 'Bridge cleanup removed source registrations')

-- An unrelated owner with the same ID is never replaced or repeatedly logged.
local blocker = external.register({
    id = 'epic_lut_settings',
    name = 'Other owner',
    pages = { { id = 'page', name = 'Page', controls = {} } },
})
local conflict = Bridge.new({
    api = own,
    discover = function()
        return external
    end,
    log = function(text)
        logs[#logs + 1] = text
    end,
})
count = #logs
conflict.tick()
conflict.tick()
assert(#logs == count + 1)
conflict.close()
assert(external.mods.epic_lut_settings.handle == blocker)
blocker.unregister()
local recovered = Bridge.new({
    api = own,
    discover = function()
        return external
    end,
})
recovered.tick()
assert(external.mods.epic_lut_settings)
recovered.close()
print(
    'PASS MCM settings: authoritative preferences/actions, failed saves, status, columns, input handoff, optional discovery and reload ownership'
)
