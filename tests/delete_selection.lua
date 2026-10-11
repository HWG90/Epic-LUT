local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local api = Core.new()
local document = { width = 23, height = 8, data = ffi.new('float[736]') }
for index = 0, 735 do
    document.data[index] = index / 64 - 0.5
end
ffi.cast('uint32_t *', document.data)[23 * 4 * 2 + 11] = 0x80000000
document.data[(5 * 23 + 21) * 4], document.data[(5 * 23 + 21) * 4 + 3] = 216.625, 3
local m = {
    ui_core = Core,
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    dds = dofile('src/core/dds.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return document
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local handle = api.register({ id = 'delete_selection', name = 'Epic LUT', pages = editor.pages() })
editor.attach(api, handle)
local mod = api.mods[handle.id]
mod.tabs_top = true
assert(handle.set('value_editor_visible', false))
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, Text)
menu.visible, menu.epic_typography, menu.compact_fonts = true, true, true
menu.window_width, menu.window_height = 1800, 1000
local function bytes()
    return ffi.string(document.data, document.width * document.height * 16)
end
local baseline = ffi.string(document.original, 2944)
for index = 0, 735 do
    document.data[index] = document.original[index] + 0.875
end
editor.sync()
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    return commands
end
local function point(row, column)
    local cells, commands = {}, compose()
    local b, w = assert(editor.grid_bounds), menu.window_bounds
    for _, command in ipairs(commands) do
        if
            command.type == 'rect'
            and command.ui_role == 'swatch_border'
            and command.x >= w.x + b.x * w.scale
            and command.x + command.w <= w.x + (b.x + b.w) * w.scale
            and command.y >= w.y + b.y * w.scale - 0.01
            and command.y + command.h <= w.y + (b.y + b.h) * w.scale + 0.01
        then
            cells[#cells + 1] = command
        end
    end
    table.sort(cells, function(a, b)
        return math.abs(a.y - b.y) > 0.01 and a.y > b.y or math.abs(a.y - b.y) <= 0.01 and a.x < b.x
    end)
    local cell = assert(cells[(row - (editor.grid_first or 1)) * 23 + column])
    return cell.x + cell.w / 2, cell.y + cell.h / 2
end
local function select(row, column, shift)
    local x, y = point(row, column)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1 or shift and key == 16
            end,
            mouse = function()
                return x, y
            end,
        }, 0)
    end
end
local function expected(before, selected)
    local output = {}
    for row = 1, document.height do
        for column = 1, document.width do
            local at = ((row - 1) * document.width + column - 1) * 16 + 1
            local source = row >= selected.r1
                    and row <= selected.r2
                    and column >= selected.c1
                    and column <= selected.c2
                    and baseline
                or before
            output[#output + 1] = source:sub(at, at + 15)
        end
    end
    return table.concat(output)
end
select(2, 3)
select(4, 6, true)
local selected = editor.selection
assert(selected.r1 == 2 and selected.r2 == 4 and selected.c1 == 3 and selected.c2 == 6)
local before, history, revision = bytes(), #editor.undo, document.revision or 0
menu.key(46)
local reset = expected(before, selected)
assert(
    bytes() == reset
        and #editor.undo == history + 1
        and document.revision == revision + 1
        and editor.selection == selected
        and menu.visible,
    'Delete did not reset exactly the rectangular full-RGBA selection'
)
local gate = dofile('src/editor/live_edit.lua').new()
local uploaded_revision, uploads = revision, 0
if gate.ready(document.revision ~= uploaded_revision, menu.is_interacting(), 0) then
    uploaded_revision, uploads = document.revision, uploads + 1
end
assert(
    uploads == 1 and not gate.ready(document.revision ~= uploaded_revision, menu.is_interacting(), 0),
    'Delete did not produce exactly one final live-update revision'
)
assert(handle.activate('undo') and bytes() == before, 'Delete rectangle was not one exact Undo action')
assert(handle.activate('redo') and bytes() == reset, 'Delete rectangle Redo changed its restored baseline')
local same_history, same_revision = #editor.undo, document.revision
menu.key(46)
assert(#editor.undo == same_history and document.revision == same_revision, 'No-op Delete added history/native updates')

editor.select_rows(6, 8)
compose()
menu.shortcut_context = {}
before, history, revision = bytes(), #editor.undo, document.revision
menu.key(46)
assert(
    bytes() == expected(before, editor.selection)
        and #editor.undo == history + 1
        and document.revision == revision + 1
        and document.data[(5 * 23 + 21) * 4] == 216.625
        and document.data[(5 * 23 + 21) * 4 + 3] == 3,
    'Delete whole rows zeroed metadata/camo or missed alpha/columns'
)
assert(handle.activate('undo') and bytes() == before)
assert(handle.activate('redo'))
editor.focus_cell(1, 1)
editor.selection = nil
compose()
menu.shortcut_context = {}
before, history = bytes(), #editor.undo
menu.key(46)
assert(
    bytes() == baseline:sub(1, 16) .. before:sub(17) and #editor.undo == history + 1,
    'Delete without a rectangle did not use its focused cell baseline'
)

-- Readonly/stale/bounds/source guards run before remember() or any pixel write.
for _, guard in ipairs({ 'read_only', 'stale', 'original', 'bounds', 'fractional', 'reversed' }) do
    editor.selection = { r1 = 1, r2 = 2, c1 = 1, c2 = 3 }
    local old_original = document.original
    if guard == 'bounds' then
        editor.selection.r2 = 9
    elseif guard == 'fractional' then
        editor.selection.c1 = 1.5
    elseif guard == 'reversed' then
        editor.selection.r1, editor.selection.r2 = 2, 1
    elseif guard == 'original' then
        document.original = nil
    else
        document[guard] = true
    end
    local snapshot, count, rev = bytes(), #editor.undo, document.revision
    assert(not pcall(editor.reset_selection), 'Delete accepted ' .. guard .. ' target')
    assert(
        bytes() == snapshot and #editor.undo == count and document.revision == rev,
        'Rejected Delete changed pixels/history before validation'
    )
    document.original = old_original
    document[guard] = nil
end
local old_document = document
document = { width = 23, height = 8, data = ffi.new('float[736]'), original = ffi.new('float[736]') }
assert(not pcall(editor.reset_selection), 'Delete reused an old document selection before sync')
document = old_document
editor.selection = { r1 = 2, r2 = 4, c1 = 3, c2 = 6 }

-- Menu ownership prevents the grid shortcut from seeing Delete in a field,
-- picker, dropdown or either modal. Text Delete retains ordinary caret behavior.
local snapshot, count, rev = bytes(), #editor.undo, document.revision
for _, id in ipairs({ 'row_preset', 'cell_r' }) do
    local text = id == 'row_preset' and 'ABCD' or '123.5'
    menu.text_edit = { mod = mod, control = mod.controls[id], text = text, replace = false, cursor = 2, anchor = 2 }
    menu.key(46)
    assert(
        menu.text_edit and menu.text_edit.text == (id == 'row_preset' and 'ABD' or '12.5'),
        'Grid Delete replaced ordinary text-field Delete'
    )
    menu.text_edit = nil
end
menu.color_picker = { mod = mod, control = mod.controls.cell_color, rgb = { 1, 2, 3 } }
menu.key(46)
assert(menu.color_picker)
menu.close_color(false)
menu.dropdown = { mod = mod, control = mod.controls.grid_channel, selected = 1, scroll = 0 }
menu.key(46)
assert(menu.dropdown)
menu.dropdown = nil
menu.outfit_dialog = { phase = 'scope', mod = mod, control = mod.controls.row_preset }
menu.key(46)
assert(menu.outfit_dialog)
menu.outfit_dialog = nil
menu.lut_apply_dialog = { mode = 'mapping', columns = {} }
menu.key(46)
assert(menu.lut_apply_dialog)
menu.lut_apply_dialog = nil
for _, context in ipairs({
    { floating = 'editor_tools' },
    { floating = 'editor_scratch' },
    { floating = 'pattern_lut_editor' },
    { control = 'cell_r' },
    { control = 'row_preset_select' },
}) do
    assert(editor.key(46, false, false, context) == false, 'Delete ignored another focused control/window owner')
end
local grid_bounds = editor.grid_bounds
editor.grid_bounds = nil
assert(editor.key(46, false) == false, 'Delete operated while the material grid was hidden')
editor.grid_bounds = grid_bounds
assert(
    bytes() == snapshot and #editor.undo == count and document.revision == rev,
    'Modal/text/control-owned Delete reset the selected LUT'
)
print(
    'PASS Delete selection: actual grid rectangle/rows/focus, exact loaded RGBA/signed-zero/HDR/camo baseline, one Undo/Redo, atomic protected guards and unchanged text/modal focus ownership'
)
