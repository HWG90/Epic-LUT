local C = dofile('src/editor/configuration.lua')
local stored = { menu_key = 121, font_size = 12 }
local saved
local owner = {
    id = 'preferences',
    controls = {
        menu_key = { id = 'menu_key', type = 'keybind', label = 'Open Advanced' },
        font_size = { id = 'font_size', type = 'slider', label = 'Font size' },
    },
    handle = {
        get = function(id)
            return stored[id]
        end,
        set = function(id, value)
            stored[id] = value
            return true
        end,
    },
}
local prefs = {
    mount = function() end,
    auto_updates = function()
        return false
    end,
    save_auto_updates = function(value)
        saved = value
    end,
}
local action_calls = 0
local refresh_calls = 0
local pages = { { controls = {} }, { controls = { { id = 'load', type = 'button' } } } }
local editor_action = { id = 'undo', type = 'button' }
C.append(pages, { { id = 'colors', controls = {} }, { id = 'save', controls = { editor_action } } }, {
    api = { mods = { epic_lut_preferences = owner } },
    preferences = prefs,
    resource_changed = function()
        refresh_calls = refresh_calls + 1
    end,
    updates = {
        status = 'Ready',
        check = function()
            return 'Checked'
        end,
        open = function()
            return 'Opened'
        end,
    },
    action = function(fn)
        action_calls = action_calls + 1
        return fn()
    end,
    message = function(value)
        return value
    end,
})
assert(pages[1].controls[1] == editor_action, 'Editor action was discarded')
local page = pages[3]
assert(page.name == 'Configuration')
assert(page.tab_color[1] == 110 and page.tab_color[2] == 69)
local controls = {}
for _, c in ipairs(page.controls) do
    controls[c.id] = c
end
assert(controls.configuration_menu_key.default == 121)
controls.configuration_menu_key.on_change(45)
controls.configuration_font_size.on_change(14)
assert(stored.menu_key == 45 and stored.font_size == 14, 'Configuration writes missed authoritative preference store')
assert(owner.controls.menu_key.id == 'menu_key', 'Preference definition mutated by aliasing')
assert(controls.manual_fallback.children[1].id == 'load', 'Manual fallback lost')
assert(controls.check_updates.on_activate() == 'Checked' and action_calls == 1)
controls.resource_format.on_change()
assert(refresh_calls == 1)
controls.auto_updates.on_change(true)
assert(saved == true)
assert(controls.auto_populate_worn.default == false and controls.disable_player_preview.default == false)

-- Compose the real menu, then exercise the same hit targets used in-game.
local core = dofile('vendor/menu/core.lua')
local Menu = dofile('vendor/menu/menu.lua')
local disk = { configuration_test = { configuration_font_bold = false, auto_updates = true } }
local writes, fail_owner = {}, false
local api = core.new({
    load = function(id)
        return disk[id] or {}
    end,
    save = function(id, values)
        if fail_owner and id == 'epic_lut_preferences' then
            return false, 'Preference save unavailable'
        end
        writes[#writes + 1] = id
        disk[id] = values
        return true
    end,
})
local preferences = dofile('src/platform/preferences.lua').new()
local automatic, preview_disabled, imports = false, false, 0
local spec = {
    {
        id = 'direct',
        name = 'Import / Apply',
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
                    error('Footer selected the legacy scale writer')
                end,
            },
        },
    },
    {
        id = 'manual',
        name = 'Manual file fallback',
        controls = {
            { type = 'text', label = 'Optional fallback: put the file in the Epic LUT files folder.' },
            { id = 'format', type = 'choice', label = 'File type', choices = { 'DDS', 'ZIP', 'RAR' }, default = 1 },
            { id = 'file', type = 'input', label = 'Filename', default = 'palette' },
            {
                id = 'load',
                type = 'button',
                label = 'Import local file',
                on_activate = function()
                    imports = imports + 1
                    return true
                end,
            },
        },
    },
}
C.append(spec, {
    { id = 'colors', name = 'LUT Editor', controls = {} },
    { id = 'save', name = 'Save', require_confirmation = false, controls = {} },
}, {
    api = api,
    preferences = preferences,
    auto_populate_changed = function(value)
        automatic = value
    end,
    preview_changed = function(value)
        preview_disabled = value
    end,
    updates = {
        status = 'Update check ready',
        check = function()
            return 'Checked'
        end,
        open = function()
            return 'Opened'
        end,
    },
    action = function(fn)
        return fn()
    end,
    message = tostring,
})
local definition = spec[#spec]
-- Sharing is appended by direct_editor after Configuration; the view discovers it.
definition.controls[#definition.controls + 1] = {
    id = 'share_appearance',
    type = 'toggle',
    label = 'Share full LUT appearance',
    default = true,
}
definition.controls[#definition.controls + 1] = {
    id = 'sharing_status',
    type = 'text',
    label = 'Sharing: waiting for a compatible squadmate',
}
local handle = api.register({ id = 'configuration_test', name = 'Epic LUT', pages = spec })
local view = assert(C.attach(api, handle, dofile('src/editor/configuration_view.lua'), Menu.key_name))
api.mods[handle.id].tabs_top = true
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible, menu.selected, menu.page = true, 1, 3
menu.window_width, menu.window_height, menu.compact_fonts, menu.font_size = 1420, 960, true, 20
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('Editor control missing:', 1, true)), command.text)
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    return commands
end
local function label(text)
    for _, command in ipairs(compose()) do
        if command.full_text == text or command.text == text then
            return command
        end
    end
end
local function tap(text)
    local command = assert(label(text), 'Missing setting: ' .. text)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return command.x + 3, command.y + 3
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
assert(label('Appearance') and label('Gear and Player Preview'), 'Configuration groups did not render')
local left, right = view.bounds[1], view.bounds[2]
assert(left.x + left.w < right.x and left.h == right.h, 'Settings columns overlap')
assert(
    label('Squad sharing') and label('Sharing: waiting for a compatible squadmate'),
    'Late sharing controls disappeared'
)
tap('[   ] Always populate all LUT slots from current gear')
tap('[   ] Turn off Player Preview')
assert(automatic and preview_disabled, 'Setting hit targets bypassed the registered callbacks')
assert(disk[handle.id].auto_populate_worn and disk[handle.id].disable_player_preview, 'Settings were not persisted')
tap('Open Basic Mode: F9')
assert(menu.capture and menu.capture.id == 'configuration_basic_key', 'Keybind button did not enter capture')
menu.key(45)
assert(
    preferences.basic_key() == 45 and label('Open Basic Mode: Insert'),
    'Shortcut was not saved with its proper key name'
)
assert(preferences.handle.set('font_size', 16))
assert(view.draw, 'Configuration view missing')
-- Sliders are still the menu's real editable number widgets, not duplicated settings.
local slider
for _, command in ipairs(compose()) do
    if command.text == '16' then
        slider = command
    end
end
assert(slider, 'Authoritative font preference change did not reach its displayed slider')

-- Footer arrows and Configuration use the same preference owner. The stale
-- legacy control deliberately differs so a duplicate writer cannot pass.
local function footer_step(symbol)
    local commands, footer = compose()
    for _, command in ipairs(commands) do
        if command.full_text and command.full_text:find('UI Scale:', 1, true) == 1 then
            footer = command
        end
    end
    assert(footer)
    local arrow
    for _, command in ipairs(commands) do
        if command.text == symbol and math.abs(command.y - footer.y) < 0.1 and command.x > footer.x then
            arrow = command
        end
    end
    assert(arrow, 'Missing footer scale arrow')
    for _, down in ipairs({ true, false }) do
        menu.tick({
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
end
assert(label('UI Scale: 100%') and math.abs(menu.window_bounds.scale - 1) < 1e-9)
local scale_writes = #writes
footer_step('>')
assert(
    preferences.scale() == 105 and handle.get('configuration_ui_scale') == 105 and handle.get('ui_scale') == 125,
    'Footer scale missed the canonical preference alias'
)
assert(
    #writes == scale_writes + 1 and writes[#writes] == 'epic_lut_preferences',
    'Footer scale persisted more than once'
)
assert(
    label('UI Scale: 105%') and math.abs(menu.window_bounds.scale - 1.05) < 1e-9,
    'Footer change did not resize immediately'
)
assert(api.mods[handle.id].values.configuration_ui_scale == nil, 'Footer created a second Configuration scale value')
assert(handle.set('configuration_ui_scale', 90))
assert(
    label('UI Scale: 90%') and math.abs(menu.window_bounds.scale - 0.9) < 1e-9,
    'Configuration scale left the footer stale'
)
fail_owner = true
scale_writes = #writes
footer_step('>')
assert(
    preferences.scale() == 90 and #writes == scale_writes and menu.notice:find('Could not save:', 1, true) == 1,
    'Failed footer save changed the preference or closed the menu'
)
assert(
    menu.visible and label('UI Scale: 90%') and math.abs(menu.window_bounds.scale - 0.9) < 1e-9,
    'Failed scale save changed geometry'
)
fail_owner = false
assert(preferences.handle.set('ui_scale', 100))
assert(
    label('UI Scale: 100%') and math.abs(menu.window_bounds.scale - 1) < 1e-9,
    'Owner change did not refresh footer geometry'
)

tap('> Manual file fallback')
compose()
if not label('Import local file') then
    assert(view.maximum[2] > 0 and view.wheel(right.x + 10, right.y + 10, -1200))
end
tap('Import local file')
assert(imports == 1, 'Manual file fallback lost its import action')
tap('File type') -- its label is informational, the actual dropdown is below it.
local dds = assert(label('DDS'))
for _, down in ipairs({ true, false }) do
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return dds.x + 3, dds.y + 3
        end,
        wheel = function()
            return 0
        end,
    })
end
assert(menu.dropdown and menu.dropdown.control.id == 'format', 'Manual fallback file-type selector is unreachable')
menu.key(27)
assert(menu.visible, 'Closing fallback dropdown closed Configuration')
assert(view.maximum[1] >= 0 and view.maximum[2] >= 0)

-- Visible aliases remain a single store even when old versions saved competing
-- Configuration values. A failed owner save must reach the menu unchanged.
local controls = api.mods[handle.id].controls
assert(controls.auto_updates.source_mod_id == 'epic_lut_preferences')
assert(handle.get('configuration_font_bold') == true and handle.get('auto_updates') == false)
assert(api.mods[handle.id].values.configuration_font_bold == nil, 'Alias retained a competing saved value')
local count = #writes
assert(handle.edit('configuration_font_bold', false))
assert(#writes == count + 1 and writes[#writes] == 'epic_lut_preferences', 'Alias persisted more than once')
assert(handle.get('configuration_font_bold') == false and not preferences.font_bold())
assert(preferences.handle.set('font_bold', true))
assert(handle.preview('configuration_font_bold') == true, 'External owner change left a stale alias')
count = #writes
fail_owner = true
local ok, why = handle.edit('configuration_font_bold', false)
assert(ok == false and why == 'Preference save unavailable')
assert(handle.get('configuration_font_bold') == true and #writes == count, 'Failed owner save committed alias data')
fail_owner = false
assert(handle.set_many({ configuration_font_bold = false, configuration_font_size = 18 }))
assert(handle.get('configuration_font_size') == 18 and handle.get('configuration_font_bold') == false)
count = #writes
assert(handle.set_many({ configuration_font_bold = true, disable_player_preview = false }) == false)
assert(#writes == count and not preferences.font_bold(), 'Mixed-owner batch partially committed')
assert(handle.reset('configuration_font_size') and handle.get('configuration_font_size') == 12)
assert(handle.set('auto_updates', true) and preferences.auto_updates())
assert(preferences.handle.set('auto_updates', false) and handle.get('auto_updates') == false)
assert(preferences.handle.set('menu_key', 45))
count = #writes
assert(handle.activate('configuration_reset_key'))
assert(#writes == count + 1 and preferences.key() == 121, 'Button alias did not execute its owner exactly once')
print(
    'PASS configuration: persisted preview/gear settings, two-column hit targets, authoritative shortcuts, sharing and manual fallback'
)
