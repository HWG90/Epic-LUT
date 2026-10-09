local Text = dofile('src/platform/text_editor.lua')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local h = api.register({
    id = 'text',
    name = 'Text',
    pages = {
        {
            id = 'p',
            name = 'Text',
            require_confirmation = false,
            controls = {
                { id = 'name', type = 'input', label = 'Name', default = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' },
                { id = 'number', type = 'slider', label = 'Number', min = 0, max = 1, step = 0.01, default = 0.25 },
                { id = 'color', type = 'color', label = 'Color', default = '#123456' },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
local clip, copies, hooks = '', 0, 0
local clipboard = {
    get = function()
        return clip
    end,
    set = function(v)
        clip = v
        copies = copies + 1
        return true
    end,
}
mod.pages[1].render_layout = function(ui)
    ui.button(ui.x + 20, ui.y + 120, 220, 30, 'Name: ' .. ui.input_value('name'), function()
        ui.activate('name')
    end)
    ui.number('number', ui.x + 20, ui.y + 70, 320, h.get('number'), nil, true, nil, nil, true)
    ui.button(ui.x + 20, ui.y + 20, 200, 30, 'Color', function()
        ui.activate('color')
    end)
end
mod.pages[1].on_key = function()
    hooks = hooks + 1
    return true
end
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, Text)
menu.clipboard = clipboard
menu.visible = true
menu.ui_scale = 0.85
menu.window_width = 1400
menu.window_height = 900
local function compose()
    return menu.compose(1920, 1080)
end
local function input(x, y, down, keys, dt)
    keys = keys or {}
    menu.tick({
        down = function(k)
            return (down and k == 1) or keys[k] or false
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    }, dt or 0)
end
local function tap(value)
    local c
    for _, v in ipairs(compose()) do
        if v.full_text == value then
            c = v
        end
    end
    assert(c, 'Missing field: ' .. value)
    input(c.x + 3, c.y + 3, true)
    input(c.x + 3, c.y + 3, false)
end
tap('Name: ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
compose()
local e = assert(menu.text_edit)
assert(Text.selected(e) == e.text, 'Initial focus did not select the editable value')
menu.key(36, false, false)
for i = 1, 5 do
    menu.key(39, false, true)
end
assert(Text.selected(e) == 'ABCDE', 'Shift arrows did not extend selection')
menu.key(67, true)
assert(clip == 'ABCDE' and hooks == 0, 'Ctrl+C copied more than the selection or escaped the field')
menu.key(88, true)
assert(e.text:sub(1, 5) == 'FGHIJ' and clip == 'ABCDE', 'Ctrl+X did not cut only selected text')
clip = 'HELLO'
menu.key(86, true)
assert(e.text:sub(1, 10) == 'HELLOFGHIJ', 'Paste did not insert at the caret')
local pasted = e.text
menu.key(90, true, false)
assert(e.text:sub(1, 5) == 'FGHIJ')
menu.key(90, true, true)
assert(e.text == pasted, 'Ctrl+Shift+Z did not redo text editing')
menu.key(36, false, false)
menu.key(39, false, false)
menu.key(46, false, false)
assert(e.text:sub(1, 4) == 'HLLO', 'Delete cleared the field rather than the next character')
e.text = 'A' .. string.char(226, 152, 131) .. 'B'
e.cursor, e.anchor = 4, 4
e.replace = false
menu.key(8, false, false)
assert(e.text == 'AB' and e.cursor == 1, 'Backspace split a UTF-8 glyph')

-- Mouse interactions use the rendered field itself. Re-clicking must retain
-- the existing draft/identity and dragging must highlight only the selected span.
e.text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
e.cursor, e.anchor = 0, 0
e.scroll = 0
compose()
local box = e.field_bounds
local glyph = box.measure('A')
local x = box.text_x + 3.1 * glyph * box.scale
local y = box.y + box.h / 2
input(x, y, true)
assert(menu.text_edit == e and e.cursor == 3 and e.anchor == 3, 'Re-click finalized/reset the draft or misplaced caret')
input(box.text_x + 8.1 * glyph * box.scale, y, true)
input(box.text_x + 8.1 * glyph * box.scale, y, false)
assert(Text.selected(e) == 'DEFGH', 'Mouse drag did not select the expected characters')
local selected, caret = false, false
for _, c in ipairs(compose()) do
    if c.ui_role == 'text_selection' or c.ui_role == 'text_caret' then
        assert(
            c.x >= box.x - 0.1
                and c.x + c.w <= box.x + box.w + 0.1
                and c.y >= box.y - 0.1
                and c.y + c.h <= box.y + box.h + 0.1,
            'Selection/caret overflowed the field'
        )
        selected = selected or c.ui_role == 'text_selection'
        caret = caret or c.ui_role == 'text_caret'
    end
end
assert(selected and caret, 'Active text field did not draw selection/caret')
menu.key(35, false, false)
compose()
assert(e.scroll > 0, 'Long field did not scroll horizontally to its caret')

e.text = '1234567890'
e.cursor, e.anchor = 10, 10
e.replace = false
input(0, 0, false, { [8] = true }, 0)
assert(e.text == '123456789')
for i = 1, 3 do
    input(0, 0, false, { [8] = true }, 0.1)
end
assert(e.text == '123456789', 'Backspace repeated before its delay')
input(0, 0, false, { [8] = true }, 0.1)
assert(e.text == '12345678', 'Held Backspace did not begin repeating')
input(0, 0, false, { [8] = true }, 0.081)
assert(e.text == '123456', 'Held Backspace interval was not deterministic')
input(0, 0, false, {}, 0.1)
local held = e.text
input(0, 0, false, {}, 0.1)
assert(e.text == held, 'Released Backspace continued deleting')
input(0, 0, false, { [8] = true }, 0)
menu.input_focus(false, {
    down = function()
        return false
    end,
})
menu.input_focus(true, {
    down = function(k)
        return k == 8
    end,
})
held = e.text
input(0, 0, false, { [8] = true }, 0.1)
assert(e.text == held, 'Focus restoration replayed held Backspace')
input(0, 0, false, {}, 0)
menu.key(27)
assert(not menu.text_edit and menu.visible, 'Text Escape closed the menu')
local old_copies = copies
menu.color_picker = { mod = mod, control = mod.controls.color, rgb = { 18, 52, 86 } }
input(0, 0, false, { [67] = true, [17] = true }, 0.1)
input(0, 0, false, { [67] = true, [17] = true }, 0.1)
assert(copies == old_copies and hooks == 0, 'Held Ctrl shortcut escaped a modal guard')
menu.close_color(false)

-- Numeric/HEX validation still commits through their existing safe paths.
tap('0.25')
menu.key(65, true)
clip = '.75'
menu.key(86, true)
assert(h.get('number') == 0.75 and menu.text_edit, 'Selected numeric paste lost live validation/ownership')
menu.key(65, true)
clip = '10'
menu.key(86, true)
assert(h.get('number') == 0.75, 'Invalid numeric selection paste was committed')
menu.key(27)
tap('Color')
local hex, idle_hex
for _, c in ipairs(compose()) do
    if c.text == 'HEX' then
        hex = c
    elseif c.text == '#123456' then
        idle_hex = c
    end
end
assert(hex and idle_hex)
local s = menu.window_bounds.scale
input(hex.x + 60 * s, hex.y + 3, true)
input(hex.x + 60 * s, hex.y + 3, false)
compose()
local hex_edit = assert(menu.text_edit)
assert(hex_edit.text == '#123456', 'Focusing HEX removed its visible prefix')
assert(hex_edit.field_bounds.text_x == idle_hex.x, 'HEX text origin shifted on focus')
menu.key(65, true)
menu.key(67, true)
assert(clip == '#123456', 'Select All copied an incomplete HEX color')
local bounds = hex_edit.field_bounds
local prefix_width = bounds.measure('#') * bounds.scale
local full_width = bounds.measure('#123456') * bounds.scale
input(bounds.text_x + full_width, bounds.y + 8 * s, true)
input(bounds.text_x + prefix_width, bounds.y + 8 * s, true)
input(bounds.text_x + prefix_width, bounds.y + 8 * s, false)
menu.key(67, true)
assert(clip == '123456', 'HEX mouse selection skipped or added a color digit')
menu.key(65, true)
clip = '#ABCDEF'
menu.key(86, true)
assert(menu.color_picker.rgb[1] == 171 and menu.text_edit, 'HEX selection paste lost preview/field ownership')

-- Production measure() is glyph-oriented. Its no-GUI fallback deliberately
-- returns one glyph's advance even for a whole string, unlike the old mocks.
local GlyphView = dofile('vendor/menu/view.lua').new({
    Gui = {},
    Application = {
        worlds = function()
            return {}
        end,
    },
})
assert(GlyphView.measure('', 12) == 0)
local metric_calls = 0
local glyph_menu = Menu.new(api, function(value, size)
    metric_calls = metric_calls + 1
    return GlyphView.measure(value, size)
end, Text)
glyph_menu.visible, glyph_menu.window_width, glyph_menu.window_height = true, 1400, 900
glyph_menu.compact_fonts = true
assert(h.set('name', 'ABCDE'))
local function glyph_input(x, y, down)
    glyph_menu.tick({
        down = function(k)
            return down and k == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    }, 0)
end
local function glyph_compose()
    return glyph_menu.compose(1920, 1080)
end
local function glyph_tap(value)
    local label
    for _, c in ipairs(glyph_compose()) do
        if c.full_text == value then
            label = c
        end
    end
    assert(label, 'Glyph fixture field missing: ' .. value)
    glyph_input(label.x + 3, label.y + 3, true)
    glyph_input(label.x + 3, label.y + 3, false)
    return label
end
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.85, 1 }) do
        glyph_menu.font_size, glyph_menu.ui_scale = font, scale
        for _, spec in ipairs({ { 'Name: ABCDE', 'ABCDE', 'Name: ' }, { '0.75', '0.75', '' } }) do
            local idle = glyph_tap(spec[1])
            local field = glyph_menu.text_edit
            local drawn = glyph_compose()
            local b = field.field_bounds
            local advance = font * 0.62 * b.scale
            assert(
                math.abs(b.text_x - idle.x - #spec[3] * advance) < 0.01,
                'Text origin shifted on focus with glyph-only metrics'
            )
            assert(
                b.measure('') == 0 and math.abs(b.measure(spec[2]) * b.scale - #spec[2] * advance) < 0.01,
                'Field width still treated a whole string as one glyph'
            )
            local cached_calls = metric_calls
            b.measure(spec[2])
            b.measure('')
            assert(metric_calls == cached_calls, 'Repeated field measurements bypassed the glyph cache')
            local selection, caret
            for _, c in ipairs(drawn) do
                if c.ui_role == 'text_selection' then
                    selection = c
                elseif c.ui_role == 'text_caret' then
                    caret = c
                end
            end
            assert(
                selection and math.abs(selection.w - #spec[2] * advance) < 0.01,
                'Select All missed characters with glyph-only metrics'
            )
            assert(
                selection.c == Menu.palette.text_selection and selection.a == 1 and selection.c[3] > 140,
                'Text selection is not clearly visible and opaque'
            )
            assert(
                caret and math.abs(caret.x - b.text_x - #spec[2] * advance) < 0.01,
                'Caret is not at the actual end of the field'
            )
            glyph_input(b.text_x + advance, b.y + b.h / 2, true)
            glyph_input(b.text_x + advance, b.y + b.h / 2, false)
            assert(field.cursor == 1, 'Mouse hit did not match the rendered glyph advance')
            glyph_menu.key(27)
        end
        glyph_tap('Color')
        local label, value
        for _, c in ipairs(glyph_compose()) do
            if c.text == 'HEX' then
                label = c
            elseif c.text == h.get('color') then
                value = c
            end
        end
        assert(label and value)
        local s = glyph_menu.window_bounds.scale
        glyph_input(label.x + 60 * s, label.y + 3, true)
        glyph_input(label.x + 60 * s, label.y + 3, false)
        local active = glyph_compose()
        local field = glyph_menu.text_edit
        local b = field.field_bounds
        local advance = font * 0.62 * s
        assert(
            field.text == h.get('color') and math.abs(b.text_x - value.x) < 0.01,
            'HEX prefix/origin mismatch under production metrics'
        )
        local selection
        for _, c in ipairs(active) do
            if c.ui_role == 'text_selection' then
                selection = c
            end
        end
        assert(
            selection and math.abs(selection.w - 7 * advance) < 0.01,
            'HEX Select All did not cover # and six digits'
        )
        glyph_menu.key(27)
        glyph_menu.close_color(false)
    end
end
print(
    'PASS text editing: UTF-8 caret/selection, Shift navigation, selected copy/cut/paste/redo, mouse drag, bounded scroll/caret, deterministic Backspace and modal/focus-safe validation'
)
