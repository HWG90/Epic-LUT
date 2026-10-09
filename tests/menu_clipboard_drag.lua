local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local clip, sets = '', 0
local clipboard = {
    get = function()
        return clip
    end,
    set = function(value)
        clip = value
        sets = sets + 1
        return true
    end,
}
api.clipboard = clipboard
local h = api.register({
    id = 'shortcuts',
    name = 'Shortcuts',
    pages = {
        {
            id = 'p',
            name = 'Page',
            require_confirmation = false,
            controls = {
                { id = 'value', type = 'slider', label = 'Value', min = -1, max = 1, step = 0.1, default = 0.2 },
                {
                    id = 'raw',
                    type = 'slider',
                    raw_numeric = true,
                    label = 'Raw',
                    min = -1,
                    max = 1,
                    step = 0.1,
                    default = 0,
                },
                { id = 'name', type = 'input', label = 'Name', default = 'Example' },
                { id = 'color', type = 'color', label = 'Color', default = '#000000' },
                { id = 'bind', type = 'keybind', label = 'Bind', default = 121 },
            },
        },
        { id = 'other', name = 'Other', controls = {} },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.clipboard = clipboard
menu.visible = true
menu.window_width, menu.window_height, menu.ui_scale = 1400, 960, 0.85
local area, moves, finished, cancelled, keys = {}, {}, 0, 0, 0
local cancel
mod.pages[1].render_layout = function(ui)
    assert(ui.clipboard == clipboard, 'Custom view received a different clipboard service')
    ui.number('value', ui.x + 10, ui.y + 250, 400, h.get('value'))
    ui.number('raw', ui.x + 10, ui.y + 210, 400, h.get('raw'))
    ui.button(ui.x + 10, ui.y + 160, 200, 28, 'Name', function()
        ui.activate('name')
    end)
    ui.button(ui.x + 10, ui.y + 120, 200, 28, 'Color', function()
        ui.activate('color')
    end)
    area = { x = ui.x + 20, y = ui.y + 20, w = 150, h = 70 }
    ui.rect(area.x, area.y, area.w, area.h, ui.theme.field)
    ui.hit(area.x, area.y, area.w, area.h, function()
        cancel = ui.begin_drag(function(x, y)
            moves[#moves + 1] = { x, y }
        end, function()
            finished = finished + 1
        end, function()
            cancelled = cancelled + 1
        end)
    end)
end
mod.pages[1].on_key = function(code, ctrl, shift, context)
    if ctrl and code == 67 then
        keys = keys + 1
        assert(context.clipboard == clipboard)
        assert(context.control == 'value' or context.control == nil)
        return true
    end
end
local function compose()
    return menu.compose(1920, 1080)
end
local function input(x, y, down)
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local function tap_label(value)
    local label
    for _, c in ipairs(compose()) do
        if c.full_text == value then
            label = c
        end
    end
    assert(label, 'Missing composed shortcut field: ' .. value)
    input(label.x + 3, label.y + 3, true)
    input(label.x + 3, label.y + 3, false)
end
tap_label('Name')
menu.key(67, true)
assert(clip == 'Example' and sets == 1 and keys == 0, 'Text Copy escaped its editor into page shortcuts')
clip = 'My Colors'
menu.key(86, true)
assert(
    menu.text_edit and menu.text_edit.text == 'My Colors' and h.get('name') == 'Example',
    'Name Paste changed ownership or committed early'
)
menu.key(13)
assert(h.get('name') == 'My Colors')
tap_label('0.2')
clip = '.7'
menu.key(86, true)
assert(math.abs(h.get('value') - 0.7) < 1e-9 and menu.text_edit, 'Numeric Paste did not update live in its field')
menu.key(65, true)
clip = '2.5'
menu.key(86, true)
assert(math.abs(h.get('value') - 0.7) < 1e-9, 'Out-of-range ordinary Paste was committed')
menu.key(27)
tap_label('0')
clip = '1e20'
menu.key(86, true)
assert(h.get('raw') == 1e20, 'Finite HDR paste was clamped/quantized to visual slider range')
menu.key(13)
assert(not menu.text_edit and h.get('raw') == 1e20, 'HDR Enter did not accept raw numeric data')
assert(not pcall(h.set, 'raw', math.huge) and not pcall(h.set, 'raw', 0 / 0), 'Raw schema accepted non-finite values')
tap_label('Color')
local hex
for _, c in ipairs(compose()) do
    if c.text == 'HEX' then
        hex = c
    end
end
assert(hex)
local s = menu.window_bounds.scale
input(hex.x + 60 * s, hex.y + 3, true)
input(hex.x + 60 * s, hex.y + 3, false)
assert(menu.text_edit and menu.text_edit.color_channel == 'hex')
clip = '#12ABCD'
menu.key(86, true)
assert(
    menu.color_picker and menu.text_edit and menu.color_picker.rgb[1] == 18 and menu.color_picker.rgb[2] == 171,
    'HEX Paste lost modal ownership or failed to preview'
)
menu.key(65, true)
clip = 'invalid'
menu.key(86, true)
assert(menu.color_picker.rgb[1] == 18, 'Invalid HEX paste altered preview')
menu.key(27)
menu.close_color(false)
menu.capture = mod.controls.bind
menu.key(67, true)
assert(keys == 0 and h.get('bind') == 67, 'Capture forwarded Ctrl+C to a page')
menu.outfit_dialog = { phase = 'confirm' }
menu.key(67, true)
assert(keys == 0, 'Preset modal forwarded Ctrl+C to a page')
menu.outfit_dialog = nil
menu.key(67, true)
assert(keys == 1, 'Page keyboard hook did not receive an unowned shortcut')

compose()
local b = menu.window_bounds
local x, y = b.x + (area.x + 10) * b.scale, b.y + (area.y + 10) * b.scale
input(x, y, true)
assert(#moves == 1 and math.abs(moves[1][1] - area.x - 10) < 0.01, 'Drag start did not receive logical coordinates')
assert(
    menu.is_interacting() and menu.owns_pointer(1910, 1070),
    'Active drag lost pointer ownership over Preview/outside window'
)
input(x + 100 * b.scale, y + 30 * b.scale, true)
assert(math.abs(moves[#moves][1] - area.x - 110) < 0.01)
input(x + 100 * b.scale, y + 30 * b.scale, false)
assert(finished == 1 and cancelled == 0 and not menu.owns_pointer(1910, 1070), 'Drag release did not finish its lease')
input(x, y, true)
menu.key(27)
assert(cancelled == 1 and menu.visible, 'Escape closed the menu rather than canceling its active drag')
input(x, y, false)
input(x, y, true)
cancel()
cancel()
assert(cancelled == 2, 'Returned cancellation callback was not idempotent')
input(x, y, false)
input(x, y, true)
menu.input_focus(false, {
    down = function()
        return false
    end,
})
assert(cancelled == 3 and not menu.owns_pointer(1910, 1070), 'Focus loss retained drag capture')
menu.input_focus(true, {
    down = function()
        return false
    end,
})
compose()
input(x, y, true)
menu.page = 2
compose()
assert(cancelled == 4 and not menu.owns_pointer(1910, 1070), 'Page change retained the previous grid drag')
print(
    'PASS menu clipboard/drag: mock text/numeric/HEX clipboard, live validated HDR values, modal hook guards, logical pointer lease, release/Escape/focus/page cancellation'
)
