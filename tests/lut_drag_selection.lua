-- Real LUT view + actual menu drag lease: selection never edits texture bytes.
local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local clipboard = ''
api.clipboard = {
    get = function()
        return clipboard
    end,
    set = function(value)
        clipboard = value
        return true
    end,
}
local document = { width = 23, height = 8, data = ffi.new('float[736]'), source = 'drag-test' }
for i = 0, 735 do
    document.data[i] = i / 127
end
local modules = {
    ui_core = core,
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    scratch_tool = dofile('src/editor/scratch_tool.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    dds = dofile('src/core/dds.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(modules, function()
    return document
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local handle = api.register({ id = 'drag_selection', name = 'Epic LUT', pages = editor.pages() })
editor.attach(api, handle)
api.mods[handle.id].tabs_top = true
local menu = dofile('vendor/menu/menu.lua').new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.selected, menu.page = true, 1, 1
menu.window_width, menu.window_height, menu.compact_fonts = 1800, 1000, true
assert(handle.set('value_editor_visible', false))
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('Editor control missing:', 1, true)), command.text)
    end
    return commands
end
local function cells()
    local out = {}
    local commands = compose()
    for _, item in ipairs(commands) do
        local color = item.c
        if
            item.type == 'rect'
            and math.abs(item.w - item.h) < 0.01
            and color
            and (
                (color[1] == 75 and color[2] == 78 and color[3] == 82)
                or (color[1] == 244 and color[2] == 202 and color[3] == 53)
            )
        then
            out[#out + 1] = item
        end
    end
    table.sort(out, function(a, b)
        if math.abs(a.y - b.y) > 0.01 then
            return a.y > b.y
        end
        return a.x < b.x
    end)
    assert(#out == 23 * 8, 'Composer did not expose the complete grid')
    return out
end
local function input(x, y, left, shift, middle)
    menu.tick({
        down = function(key)
            return (key == 1 and left) or (key == 16 and shift) or (key == 4 and middle) or false
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local function point(items, row, col)
    local cell = items[(row - 1) * 23 + col]
    return cell.x + cell.w * 0.5, cell.y + cell.h * 0.5
end
local function select(row, col, shift)
    local items = cells()
    local x, y = point(items, row, col)
    input(x, y, true, shift)
    input(x, y, false, shift)
end
local before = ffi.string(document.data, 23 * 8 * 16)
local undo = #editor.undo
local items = cells()
local x, y = point(items, 2, 3)
input(x, y, true)
assert(menu.owns_pointer(-100, -100), 'Selection drag relinquished pointer ownership outside the grid')
x, y = point(items, 5, 8)
input(x, y, true)
assert(editor.selection.r1 == 2 and editor.selection.r2 == 5 and editor.selection.c1 == 3 and editor.selection.c2 == 8)
x, y = point(items, 1, 1)
input(x, y, true)
assert(editor.selection.anchor_row == 2 and editor.selection.anchor_col == 3)
assert(editor.selection.r1 == 1 and editor.selection.r2 == 2 and editor.selection.c1 == 1 and editor.selection.c2 == 3)
input(5000, -5000, true)
assert(editor.selection.r2 == 8 and editor.selection.c2 == 23, 'Drag escaped visible grid bounds')
input(5000, -5000, false)
assert(not menu.owns_pointer(-100, -100), 'Release retained selection drag ownership')
assert(ffi.string(document.data, 23 * 8 * 16) == before and #editor.undo == undo and not document.revision)
-- Shift preserves the original click anchor; ordinary clicks reset it.
select(3, 4)
select(6, 7, true)
assert(editor.selection.anchor_row == 3 and editor.selection.anchor_col == 4)
assert(editor.selection.r1 == 3 and editor.selection.r2 == 6 and editor.selection.c1 == 4 and editor.selection.c2 == 7)
-- Escape, focus loss and closing stop the lease without applying pixels.
items = cells()
x, y = point(items, 2, 2)
input(x, y, true)
menu.key(27)
assert(not menu.owns_pointer(-100, -100))
local selection = editor.selection
input(5000, -5000, true)
assert(editor.selection == selection)
input(x, y, false)
items = cells()
x, y = point(items, 3, 3)
input(x, y, true)
menu.input_focus(false)
assert(not menu.owns_pointer(-100, -100))
input(x, y, false)
items = cells()
x, y = point(items, 4, 4)
input(x, y, true)
menu.key(27)
input(x, y, false)
items = cells()
x, y = point(items, 5, 5)
input(x, y, true)
menu.visible = false
compose()
assert(not menu.owns_pointer(-100, -100))
input(x, y, false)
menu.visible = true
-- Changing the tool or document invalidates the old source closure.
items = cells()
x, y = point(items, 2, 2)
input(x, y, true)
assert(handle.set('grid_tool', 2))
compose()
assert(not menu.owns_pointer(-100, -100))
input(x, y, false)
assert(handle.set('grid_tool', 1))
items = cells()
x, y = point(items, 2, 2)
input(x, y, true)
local original_document = document
document = { width = 23, height = 8, data = ffi.new('float[736]'), source = 'replacement' }
editor.sync()
compose()
assert(not menu.owns_pointer(-100, -100) and editor.selection == nil, 'Old drag selected the replacement document')
input(x, y, false)
document = original_document
editor.sync()
-- Middle-copy and double-click retain their original picker/clipboard paths.
items = cells()
x, y = point(items, 1, 1)
input(x, y, false, false, true)
input(x, y, false)
assert(editor.clip and editor.clip.width == 1 and editor.clip.height == 1)
select(1, 1)
select(1, 1)
assert(menu.color_picker and menu.color_picker.control.id == 'cell_color', 'Double-click no longer opens the picker')
menu.key(27)
assert(ffi.string(document.data, 23 * 8 * 16) == before and #editor.undo == 0)
-- Scalar actions share the existing header instead of shortening its scroll
-- viewport; numeric preparation selects the exact value, not just the cell.
assert(handle.set('value_editor_visible', true))
editor.open_row, editor.focus_column, editor.value_scroll = 1, nil, 0
local commands = compose()
local function label(text)
    for _, command in ipairs(commands) do
        if command.full_text == text or command.text == text then
            return command
        end
    end
end
local title, copy, paste = assert(label('Value Editor')), assert(label('Copy Value')), assert(label('Paste Value'))
assert(title.x + (title.text_width or 0) <= copy.x and copy.x < paste.x, 'Value actions overlapped the header title')
local numeric = assert(label(string.format('%.7g', tonumber(document.data[1]))))
input(numeric.x + 2, numeric.y + 2, true)
input(numeric.x + 2, numeric.y + 2, false)
assert(
    editor.value_target
        and editor.value_target.row == 1
        and editor.value_target.column == 1
        and editor.value_target.channel == 2
)
menu.key(27)
commands = compose()
copy = assert(label('Copy Value'))
input(copy.x + 2, copy.y + 2, true)
input(copy.x + 2, copy.y + 2, false)
assert(ffi.string(ffi.new('float[1]', tonumber(clipboard)), 4) == ffi.string(document.data + 1, 4))
clipboard = '0.5'
commands = compose()
paste = assert(label('Paste Value'))
input(paste.x + 2, paste.y + 2, true)
input(paste.x + 2, paste.y + 2, false)
assert(document.data[1] == 0.5 and handle.activate('undo'))
assert(ffi.string(document.data, 23 * 8 * 16) == before)
assert(
    handle.set('value_editor_visible', false) and handle.set('scratch_color', '#123456') and handle.set('grid_tool', 2)
)
menu.last_click_key = nil -- Programmatic tool changes bypass the ordinary dropdown click.
items = cells()
x, y = point(items, 1, 1)
input(x, y, true)
assert(not menu.owns_pointer(-100, -100), 'Draw mode unexpectedly started selection capture')
input(x, y, false)
assert(math.abs(document.data[0] - 0x12 / 255) < 0.00001 and handle.activate('undo'))
assert(handle.set('grid_tool', 1))
menu.last_click_key = nil
select(1, 1)
assert(handle.set('grid_tool', 3))
items = cells()
x, y = point(items, 2, 1)
input(x, y, true)
assert(not menu.owns_pointer(-100, -100), 'Move mode unexpectedly started selection capture')
input(x, y, false)
assert(document.data[23 * 4] == 0 and handle.activate('undo'))
assert(ffi.string(document.data, 23 * 8 * 16) == before, 'Other grid modes lost exact Undo restoration')
print(
    'PASS actual grid drag selection, stable anchors, clipping, cancellation, source guards, unchanged bytes/history and picker/copy paths'
)
