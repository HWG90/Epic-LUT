local Core = dofile('vendor/menu/core.lua')
local Menu = dofile('vendor/menu/menu.lua')
local writes, changes = 0, 0
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        writes = writes + 1
        return true
    end,
})
local choices = {}
for i = 1, 40 do
    choices[i] = 'Choice ' .. i
end
local controls = {
    { id = 'immediate', type = 'toggle', label = 'Immediate', default = false, require_confirmation = false },
    { id = 'choice', type = 'choice', label = 'Choice', choices = choices, default = 2 },
    {
        id = 'selector',
        type = 'choice',
        label = 'Selector',
        choices = { 'One', 'Two' },
        default = 1,
        presentation = 'selector',
    },
    {
        id = 'disabled',
        type = 'choice',
        label = 'Unavailable',
        choices = { 'Unavailable' },
        default = 1,
        disabled = true,
    },
}
for i = 1, 40 do
    controls[#controls + 1] = { id = 'value_' .. i, type = 'toggle', label = 'Value ' .. i, default = false }
end
local handle = api.register({
    id = 'port_test',
    name = 'Port',
    pages = { { id = 'settings', name = 'Settings', require_confirmation = true, controls = controls } },
})
local page = api.mods.port_test.pages[1]
page.tab_color = { 144, 80, 160 }
api.mods.port_test.tabs_top = true
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
menu.focus = 'settings'
local function input(x, y, pressed)
    menu.tick({
        down = function(key)
            return pressed and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local commands = menu.compose(1920, 1080)
menu.key(13)
assert(handle.get('immediate') == true and writes == 1, 'Immediate control was wrongly staged on confirming page')
assert(menu.notice == 'Saved', 'Immediate change was reported as pending')
menu.row = 2
menu.compose(1920, 1080)
menu.key(13)
assert(
    menu.dropdown and menu.dropdown.selected == 2 and handle.get('choice') == 2,
    'Enter should open, not cycle/save dropdown'
)
menu.key(40)
menu.key(13)
assert(
    handle.get('choice') == 2 and handle.preview('choice') == 3 and menu.notice == 'Changes ready to apply',
    'Deferred dropdown bypassed confirmation'
)
menu.row = 3
menu.compose(1920, 1080)
menu.key(13)
assert(not menu.dropdown and handle.preview('selector') == 2, 'Selector-only Enter should retain stepping')
menu.row = 4
menu.compose(1920, 1080)
menu.key(13)
assert(not menu.dropdown and handle.get('disabled') == 1, 'Disabled selector became interactive')

-- Hover feedback is purely visual and never publishes a setting.
menu.row = 1
local row
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.ui_role == 'setting_row' and not c.focused then
        row = c
        break
    end
end
assert(row)
input(row.x + 4, row.y + 4, false)
local before = writes
local hovered = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.ui_role == 'setting_row' and c.hovered then
        hovered = true
    end
end
assert(hovered and writes == before, 'Hover must be visible without writing settings')

-- The settings thumb drags with the cursor, including stationary hold/release.
local thumb
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.scrollbar == 'settings' then
        thumb = c
    end
end
assert(thumb, 'Scrollable page did not provide thumb')
input(thumb.x + 2, thumb.y + thumb.h / 2, true)
input(thumb.x + 2, thumb.y - 120, true)
assert(menu.scroll > 0, 'Settings thumb did not drag')
local offset = menu.scroll
menu.input_focus(false, {
    down = function()
        return false
    end,
})
menu.input_focus(true, {
    down = function(key)
        return key == 1
    end,
})
input(thumb.x + 2, thumb.y - 200, true)
assert(menu.scroll == offset, 'Focus loss did not cancel scrollbar drag')
input(thumb.x, thumb.y, false)
menu.input_focus(true, {
    down = function()
        return false
    end,
})

-- Dropdown scrolling uses the same draggable thumb, preserving its selection.
menu.row = 2
menu.scroll = 0
menu.compose(1920, 1080)
menu.key(13)
local drop = menu.dropdown
thumb = nil
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.scrollbar == 'dropdown' then
        thumb = c
    end
end
assert(thumb)
input(thumb.x + 2, thumb.y + thumb.h / 2, true)
input(thumb.x + 2, thumb.y - 60, true)
assert(
    drop.scroll > 0 and drop.selected == 3 and handle.preview('choice') == 3,
    'Dropdown drag changed choice or failed to scroll'
)
menu.key(27)
input(thumb.x + 2, thumb.y - 120, true)
assert(not menu.dropdown, 'Escape did not cancel dropdown ownership')
input(thumb.x, thumb.y, false)

-- Default/Apply/Discard are visible actions; function keys cannot commit an
-- unrelated settings draft when F9 is used to open Basic Mode.
local function tap_button(label)
    local command
    for _, item in ipairs(menu.compose(1920, 1080)) do
        if item.full_text == label or item.text == label then
            command = item
            break
        end
    end
    assert(command, 'Missing action: ' .. label)
    input(command.x + 3, command.y + 3, true)
    input(command.x + 3, command.y + 3, false)
end
menu.row, menu.scroll = 1, 0
assert(handle.set('immediate', true))
menu.compose(1920, 1080)
before = writes
menu.key(36)
assert(handle.get('immediate') == true and writes == before, 'Home still reset a setting')
tap_button('RESET SETTING')
assert(handle.get('immediate') == false and writes == before + 1, 'Immediate reset did not save exactly once')
assert(menu.notice == 'Default restored; Saved')
menu.row = 2
assert(handle.set('choice', 4) and handle.edit('choice', 3))
menu.compose(1920, 1080)
before = writes
menu.key(119)
menu.key(120)
assert(
    handle.get('choice') == 4 and handle.preview('choice') == 3 and writes == before,
    'Legacy F8/F9 shortcut discarded or committed the draft'
)
tap_button('RESET SETTING')
assert(
    handle.get('choice') == 4 and handle.preview('choice') == 2 and writes == before,
    'Deferred reset bypassed Apply'
)
assert(menu.notice == 'Default restored; Changes ready to apply')
tap_button('APPLY')
assert(handle.get('choice') == 2 and writes == before + 1)
assert(handle.edit('choice', 3))
tap_button('DISCARD')
assert(handle.preview('choice') == 2 and writes == before + 1)
menu.row = 4
before = writes
tap_button('RESET SETTING')
assert(writes == before and handle.get('disabled') == 1, 'Disabled setting was reset')
for _, command in ipairs(menu.compose(1920, 1080)) do
    assert(
        not (command.full_text and command.full_text:find('Home Default', 1, true)),
        'Footer still advertises the removed default shortcut'
    )
end

-- Configuration accents and unavailable custom choices remain visible.
commands = menu.compose(1920, 1080)
local purple = false
for _, c in ipairs(commands) do
    if c.type == 'rect' and c.c[1] == 144 and c.c[2] == 80 and c.c[3] == 160 then
        purple = true
    end
end
assert(purple, 'Tab custom settings color was ignored')
page.render_layout = function(ui)
    ui.choice('disabled', ui.x + 15, ui.y + 100, 300)
end
local gray = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Unavailable' then
        gray = c.c[1] == Menu.palette.disabled[1]
    end
end
assert(gray, 'Disabled custom choice did not render muted')

-- Custom dropdowns devote the whole field to opening the list. Presentation
-- must not leak step arrows or invisible step hit targets into this surface.
local choice_control = api.mods.port_test.controls.choice
choice_control.presentation = 'dropdown'
page.render_layout = function(ui)
    ui.choice('choice', ui.x + 15, ui.y + 100, 300)
end
local function custom_choice_row()
    local commands = menu.compose(1920, 1080)
    local label
    for _, c in ipairs(commands) do
        if c.full_text == 'Choice ' .. handle.get('choice') then
            label = c
        end
    end
    assert(label)
    local caret, steps
    steps = 0
    for _, c in ipairs(commands) do
        if c.type == 'text' and math.abs(c.y - label.y) < 0.1 then
            if c.text == '<' or c.text == '>' then
                steps = steps + 1
            end
            if c.text == 'v' then
                caret = c
            end
        end
    end
    return label, caret, steps
end
local chosen = handle.get('choice')
local choice_label, caret, steps = custom_choice_row()
assert(caret and steps == 0, 'Plain custom dropdown still draws step arrows')
input(caret.x + 3, caret.y + 3, true)
input(caret.x + 3, caret.y + 3, false)
assert(
    menu.dropdown and menu.dropdown.control == choice_control and handle.get('choice') == chosen,
    'Right edge of dropdown stepped instead of opening'
)
menu.key(40)
menu.key(13)
assert(
    not menu.dropdown and handle.preview('choice') == chosen + 1 and handle.get('choice') == chosen,
    'Dropdown keyboard selection changed confirmation behavior'
)
handle.discard('settings')
menu.row, menu.focus = 2, 'settings'
menu.compose(1920, 1080)
menu.key(13)
assert(menu.dropdown and menu.dropdown.control == choice_control, 'Enter no longer opens a custom dropdown')
menu.key(27)
choice_control.presentation = nil
local _, combined_caret, combined_steps = custom_choice_row()
assert(combined_caret and combined_steps == 2, 'Default combined choices lost their steppers')
choice_control.presentation = 'selector'
local selector_label, selector_caret, selector_steps = custom_choice_row()
assert(not selector_caret and selector_steps == 2, 'Selector-only choice gained a dropdown caret')
input(selector_label.x + 3, selector_label.y + 3, true)
input(selector_label.x + 3, selector_label.y + 3, false)
assert(not menu.dropdown and handle.preview('choice') == chosen + 1, 'Selector body does not step')
handle.discard('settings')
choice_control.presentation = nil

-- A hierarchy accent belongs to the field; it must remain a dropdown and
-- preserve visible hover/disabled feedback. Invalid metadata falls back safely.
choice_control.presentation = 'dropdown'
choice_control.field_color = { 24, 132, 140 }
input(0, 0, false)
local function custom_choice_surface()
    local commands = menu.compose(1920, 1080)
    local label
    for _, c in ipairs(commands) do
        if c.full_text == 'Choice ' .. handle.get('choice') then
            label = c
        end
    end
    assert(label)
    local s = menu.window_bounds.scale
    for _, c in ipairs(commands) do
        if c.type == 'rect' and math.abs(c.w - 300 * s) < 0.1 and math.abs(c.y + 5 * s - label.y) < 0.1 then
            return c, label
        end
    end
    error('Missing colored dropdown surface')
end
local colored, colored_label = custom_choice_surface()
assert(colored.c[1] == 24 and colored.c[2] == 132 and colored.c[3] == 140, 'LUT hierarchy field color was ignored')
input(colored_label.x + 3, colored_label.y + 3, false)
local colored_hover = custom_choice_surface()
assert(
    colored_hover.c[2] > colored.c[2] and colored_hover.c[3] > colored.c[3],
    'Colored LUT field has no hover feedback'
)
choice_control.disabled = true
local colored_disabled, disabled_label = custom_choice_surface()
assert(
    colored_disabled.c == Menu.palette.panel and disabled_label.c == Menu.palette.disabled,
    'Field accent made an unavailable LUT selector appear enabled'
)
input(colored_label.x + 3, colored_label.y + 3, true)
input(colored_label.x + 3, colored_label.y + 3, false)
assert(not menu.dropdown, 'Disabled colored selector opened a dropdown')
choice_control.disabled = nil
input(0, 0, false)
for _, invalid in ipairs({ '#0099AA', { 24, 132 }, { -1, 132, 140 }, { 0 / 0, 132, 140 }, { math.huge, 132, 140 } }) do
    choice_control.field_color = invalid
    assert(custom_choice_surface().c == Menu.palette.field, 'Invalid field metadata reached the renderer')
end
choice_control.field_color, choice_control.presentation = nil, nil

-- Custom panels use the same scrollbar primitive without a second drag handler.
local custom_scroll = 0
page.render_layout = function(ui)
    ui.scrollbar('custom', ui.x + 300, ui.y + 30, 240, 1000, 200, custom_scroll, function(value)
        custom_scroll = value
    end)
end
thumb = nil
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.scrollbar == 'custom' then
        thumb = c
    end
end
assert(thumb)
input(thumb.x + 2, thumb.y + thumb.h / 2, true)
input(thumb.x + 2, thumb.y - 80, true)
input(thumb.x + 2, thumb.y - 80, false)
assert(custom_scroll > 0, 'Custom panel scrollbar did not share thumb dragging')

-- A configured character shortcut belongs to an active text editor, not menu close.
page.render_layout = nil
menu.toggle_key = 65
menu.text_edit = { mod = api.mods.port_test, control = { type = 'input' }, text = '', replace = true }
menu.key(65)
assert(menu.visible and menu.text_edit.text == 'A', 'Menu shortcut stole text entry')
menu.text_edit = nil
menu.key(65)
assert(not menu.visible, 'Shortcut failed after text edit ended')
menu.key(65)
assert(menu.visible, 'Configured shortcut did not reopen menu')

-- Configuration's custom controls select the setting they edit. Linked defaults
-- come from the owner rather than the alias's registration snapshot.
local settings_api = Core.new()
local owner = settings_api.register({
    id = 'preferences',
    name = 'Preferences',
    pages = {
        {
            id = 'owner',
            name = 'Owner',
            require_confirmation = false,
            controls = { { id = 'bold', type = 'toggle', label = 'Bold text', default = true } },
        },
    },
})
settings_api.mods.preferences.hidden = true
assert(owner.set('bold', false))
local settings = settings_api.register({
    id = 'settings',
    name = 'Settings',
    pages = {
        {
            id = 'save',
            name = 'Configuration',
            require_confirmation = false,
            controls = {
                { id = 'other', type = 'slider', label = 'Other setting', default = 2, min = 0, max = 10, step = 1 },
                {
                    id = 'linked_bold',
                    type = 'toggle',
                    label = 'Bold text',
                    default = false,
                    source_mod_id = 'preferences',
                    source_control_id = 'bold',
                },
            },
        },
    },
})
assert(settings.set('other', 5))
local settings_menu = Menu.new(settings_api)
settings_menu.visible, settings_menu.focus = true, 'settings'
local control_hit
settings_api.mods.settings.pages[1].render_layout = function(ui)
    control_hit = { x = ui.x + 20, y = ui.y + 120 }
    ui.hit(control_hit.x, control_hit.y, 180, 28, function()
        ui.activate('linked_bold')
    end)
end
local function settings_tap(x, y)
    for _, pressed in ipairs({ true, false }) do
        settings_menu.tick({
            down = function(key)
                return pressed and key == 1
            end,
            mouse = function()
                return x, y
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
settings_menu.compose(1920, 1080)
local bounds = settings_menu.window_bounds
settings_tap(bounds.x + (control_hit.x + 3) * bounds.scale, bounds.y + (control_hit.y + 3) * bounds.scale)
assert(owner.get('bold') and settings_menu.row == 2, 'Custom settings did not select the edited control')
local reset
for _, command in ipairs(settings_menu.compose(1920, 1080)) do
    if command.full_text == 'RESET SETTING' then
        reset = command
    end
end
assert(reset)
settings_tap(reset.x + 3, reset.y + 3)
assert(owner.get('bold') and settings.get('other') == 5, 'Reset used a stale alias default or unrelated selection')

local Capture = dofile('vendor/menu/capture.lua')
local flags = { focus = true, cursor = false, clip = false }
local silent, sticky, gate = false, false, 0
local window = {}
for _, pair in ipairs({ { 'mouse_focus', 'focus' }, { 'show_cursor', 'cursor' }, { 'clip_cursor', 'clip' } }) do
    local key, name = pair[1], pair[2]
    window[key] = function()
        return flags[name]
    end
    window['set_' .. key] = function(v)
        if not silent then
            flags[name] = v
        end
    end
end
local native = {
    mcm_install = function()
        return 1
    end,
    mcm_capture = function()
        gate = 1
        return 1
    end,
    mcm_captured = function()
        return gate
    end,
    mcm_release = function()
        if not sticky then
            gate = 0
        end
    end,
}
local capture = Capture.new(native, window, function() end)
flags.focus = false
local ok, why = capture.sync(true, true, 1)
assert(not ok and gate == 0 and why:find('already disabled', 1, true), 'Stale cursor baseline was accepted')
flags.focus = true
assert(capture.sync(true, true, 1))
silent = true
ok, why = capture.release()
assert(
    not ok and capture.status().pending_restore and why:find('readback', 1, true),
    'Silent setter failure discarded cursor ownership'
)
silent = false
assert(capture.sync(false, true, 1) and flags.focus and not flags.cursor and not flags.clip)
assert(capture.sync(true, true, 1))
sticky = true
ok, why = capture.release()
assert(not ok and capture.status().pending_restore and gate == 1, 'Native capture release failure was not retained')
sticky = false
assert(capture.sync(false, true, 1) and flags.focus and gate == 0)
print(
    'PASS MCM UI port: immediate/deferred feedback, keyboard dropdowns, hover, draggable scrollbars, focus cancellation, accents, disabled choices and capture readbacks'
)
