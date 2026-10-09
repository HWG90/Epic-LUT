-- Actual row gestures, exact clipboard ranges, and outline-only retained-render roles.
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
local clipboard, flash_row = '', nil
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
    document.data[i] = (i % 41 - 10) / 8
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
local pages = editor.pages()
local handle
pages[1].controls[#pages[1].controls + 1] = {
    id = 'identify_region',
    type = 'button',
    label = 'Flash Region',
    on_activate = function()
        flash_row = handle.get('edit_row')
        return true
    end,
}
handle = api.register({ id = 'row_selection', name = 'Epic LUT', pages = pages })
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
local function input(x, y, left, shift, middle, right)
    menu.tick({
        down = function(key)
            return (key == 1 and left)
                or (key == 16 and shift)
                or (key == 4 and middle)
                or (key == 2 and right)
                or false
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
assert(handle.set('unlock', true) and handle.set('show_alpha', true))
ffi.cast('uint32_t *', document.data)[23 * 4 + 3] = 0x80000000
local before = ffi.string(document.data, 23 * 8 * 16)
local function row_point(row)
    local items = cells()
    local x, y = point(items, row, 1)
    return items[1].x - 40 * menu.window_bounds.scale, y
end
local function row_click(row, shift)
    local x, y = row_point(row)
    input(x, y, true, shift)
    input(x, y, false, shift)
end
local function fill_signature(commands)
    local fills = {}
    for _, item in ipairs(commands) do
        if item.ui_role == 'swatch_fill' then
            fills[#fills + 1] = table.concat({ item.x, item.y, item.w, item.h, item.c[1], item.c[2], item.c[3] }, ':')
        end
    end
    assert(#fills > 184, 'Show Alpha failed to keep its checkerboard fill primitives')
    return table.concat(fills, '|')
end
local fills = fill_signature(compose())
row_click(2)
row_click(3, true)
assert(editor.selection.rows and editor.selection.r1 == 2 and editor.selection.r2 == 3)
assert(editor.selection.c1 == 1 and editor.selection.c2 == 23 and handle.get('edit_row') == 3)
assert(editor.paste_anchor.row == 2 and editor.paste_anchor.column == 1)
local commands = compose()
assert(fill_signature(commands) == fills, 'Selection altered RGB or alpha-checkerboard interiors')
local outlines = 0
local thickness = 2 * menu.window_bounds.scale
for _, item in ipairs(commands) do
    if item.ui_role == 'selection_outline' then
        outlines = outlines + 1
        assert(
            math.abs(item.w - thickness) < 0.001 or math.abs(item.h - thickness) < 0.001,
            'Selection added a filled gold surface'
        )
    elseif item.ui_role == 'swatch_border' then
        assert(
            item.c[1] == 75 and item.c[2] == 78 and item.c[3] == 82,
            'A background became an occluding selected fill'
        )
    end
end
assert(outlines == 27, 'Two complete rows did not outline every cell boundary')
menu.key(67, true)
assert(editor.clip.width == 23 and editor.clip.height == 2)
local copied = ffi.string(editor.clip.data, 23 * 2 * 16)
assert(copied == ffi.string(document.data + 23 * 4, 23 * 2 * 16))
row_click(5)
row_click(6, true)
assert(handle.get('edit_row') == 6 and editor.paste_anchor.row == 5)
menu.key(86, true)
assert(
    ffi.string(document.data + 4 * 23 * 4, 23 * 2 * 16) == copied,
    'Two-row paste used the drag endpoint rather than first destination row'
)
assert(#editor.undo == 1 and handle.activate('undo') and ffi.string(document.data, 23 * 8 * 16) == before)
-- Vertical label dragging selects three rows even while the cursor enters the swatches.
local x, y = row_point(2)
input(x, y, true)
local items = cells()
x, y = point(items, 4, 12)
input(x, y, true)
input(x, y, false)
assert(editor.selection.rows and editor.selection.r1 == 2 and editor.selection.r2 == 4 and editor.selection.c2 == 23)
assert(editor.selection.anchor_row == 2 and editor.paste_anchor.row == 2 and #editor.undo == 0)
menu.key(67, true)
copied = ffi.string(editor.clip.data, 23 * 3 * 16)
assert(editor.clip.height == 3 and copied == before:sub(23 * 16 + 1, 4 * 23 * 16))
row_click(4)
row_click(6, true)
menu.key(86, true)
assert(
    ffi.string(document.data + 3 * 23 * 4, 23 * 3 * 16) == copied,
    'Overlapping row paste corrupted its immutable clipboard'
)
assert(#editor.undo == 1 and handle.activate('undo') and ffi.string(document.data, 23 * 8 * 16) == before)
-- Right-click keeps region identification available and does not replace the row selection.
local selected = editor.selection
x, y = row_point(7)
input(x, y, false, false, false, true)
input(x, y, false)
assert(flash_row == 7 and editor.selection == selected and ffi.string(document.data, 23 * 8 * 16) == before)
-- Hover uses stored values, including negative RGB/alpha that display clamps.
local tooltip_x, tooltip_y = point(cells(), 1, 2)
input(tooltip_x, tooltip_y, false)
compose()
menu.advance(0.6)
local tooltip_text = {}
for _, command in ipairs(compose()) do
    if command.layer == 450 and command.text then
        tooltip_text[#tooltip_text + 1] = command.full_text or command.text
    end
end
local raw_tip = table.concat(tooltip_text, '\n')
assert(raw_tip:find('Row 1 / Col 2', 1, true) and raw_tip:find('R: -0.75', 1, true))
assert(raw_tip:find('A: -0.375', 1, true), 'Swatch tooltip lost raw alpha or clamped values')
print(
    'PASS actual whole-row Shift/drag selection, two/three-row exact RGBA/HDR paste and Undo, per-cell outline roles, unchanged alpha fills and retained region flash'
)
