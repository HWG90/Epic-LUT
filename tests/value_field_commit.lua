-- Numeric blur must commit through the same owner before changing a Value
-- Editor row/column. The real menu geometry exercises its outside-click path.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local fail_save, saves = false, 0
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        saves = saves + 1
        return not fail_save, fail_save and 'Commit refused' or nil
    end,
})
local doc = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
for index = 0, 23 * 8 * 4 - 1 do
    doc.data[index] = index + 0.125
end
local m = {
    ui_core = Core,
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return doc
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local handle = api.register({ id = 'value_blur', name = 'Epic LUT', pages = editor.pages() })
editor.attach(api, handle)
local mod = api.mods[handle.id]
mod.tabs_top = true
assert(handle.set('unlock', true))
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, Text)
menu.visible, menu.epic_typography, menu.compact_fonts = true, true, true
menu.window_width, menu.window_height, menu.ui_scale = 1550, 1000, 0.8
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    return commands
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
    }, 0)
end
local function click(x, y)
    input(x, y, true)
    input(x, y, false)
end
local function target_label(text, values_only)
    local bounds, scale = menu.window_bounds, menu.window_bounds.scale
    local viewport = editor.value_viewport
    for _, command in ipairs(compose()) do
        if (command.full_text or command.text) == text then
            if not values_only or viewport and command.x >= bounds.x + viewport.x * scale then
                return command
            end
        end
    end
    error('Missing rendered Value target ' .. text)
end
local function field(row, column, channel)
    editor.focus_cell(row, column)
    compose()
    local at = m.semantics.index(row, column, channel, doc.width, doc.height)
    local text = string.format('%.7g', doc.data[at])
    local command = target_label(text, true)
    click(command.x + 3, command.y + 3)
    assert(menu.text_edit and menu.text_edit.control.id == ({ 'cell_r', 'cell_g', 'cell_b', 'cell_a' })[channel])
    compose()
    return at, menu.text_edit
end
local function type_number(value)
    menu.key(65, true)
    for character in value:gmatch('.') do
        local key = character:match('%d') and string.byte(character)
            or ({ ['-'] = 189, ['.'] = 190, ['e'] = 69, ['+'] = 187 })[character]
        assert(key, 'Unsupported test numeric character')
        menu.key(key)
    end
end
local function exact_change(before, at, value)
    local expected = ffi.new('float[1]', value)
    local bytes = ffi.string(doc.data, doc.width * doc.height * 16)
    assert(
        bytes:sub(1, at * 4) == before:sub(1, at * 4)
            and bytes:sub(at * 4 + 5) == before:sub(at * 4 + 5)
            and bytes:sub(at * 4 + 1, at * 4 + 4) == ffi.string(expected, 4),
        'Numeric blur rounded/clamped the float or changed another RGBA/material channel'
    )
end
local function grid_point(row, column)
    local cells, commands = {}, compose()
    local grid, bounds = assert(editor.grid_bounds), menu.window_bounds
    for _, command in ipairs(commands) do
        if
            command.type == 'rect'
            and command.ui_role == 'swatch_border'
            and command.x >= bounds.x + grid.x * bounds.scale
            and command.x + command.w <= bounds.x + (grid.x + grid.w) * bounds.scale + 0.01
            and command.y >= bounds.y + grid.y * bounds.scale - 0.01
            and command.y + command.h <= bounds.y + (grid.y + grid.h) * bounds.scale + 0.01
        then
            cells[#cells + 1] = command
        end
    end
    table.sort(cells, function(a, b)
        return math.abs(a.y - b.y) > 0.01 and a.y > b.y or math.abs(a.y - b.y) <= 0.01 and a.x < b.x
    end)
    local cell = assert(cells[(row - (editor.grid_first or 1)) * doc.width + column], 'Requested grid row is hidden')
    return cell.x + cell.w / 2, cell.y + cell.h / 2
end

-- Every editable channel retains its exact float32 representation, including
-- HDR/scientific notation and a typed value outside its useful drag range.
for channel, value in ipairs({ '1234567.875', '-12.3456789', '1.23456789e+12', '-0.03125' }) do
    local at = field(1, 3, channel)
    local before, history, revision = ffi.string(doc.data, doc.width * doc.height * 16), #editor.undo, doc.revision or 0
    type_number(value)
    assert(
        ffi.string(doc.data, doc.width * doc.height * 16) == before and #editor.undo == history,
        'Typing a draft committed before blur'
    )
    click(menu.window_bounds.x + 6, menu.window_bounds.y + 6)
    assert(
        not menu.text_edit and doc.revision == revision + 1 and #editor.undo == history + 1,
        'Clicking outside a numeric field discarded its draft or duplicated history'
    )
    exact_change(before, at, tonumber(value))
    assert(
        handle.get('edit_row') == 1 and handle.get('edit_column') == 3,
        'Blank-area blur moved the selected Value target'
    )
    compose()
end

-- Clicking another grid row must first write the old field's row/column.
local at = field(1, 3, 2)
local before, history = ffi.string(doc.data, doc.width * doc.height * 16), #editor.undo
type_number('77.03125')
click(grid_point(2, 3))
assert(
    not menu.text_edit and handle.get('edit_row') == 2 and handle.get('edit_column') == 3,
    'Next grid click did not select its target after numeric blur'
)
exact_change(before, at, 77.03125)
assert(#editor.undo == history + 1, 'Moving targets duplicated/missed the previous numeric commit')

-- Invalid drafts and failed owner commits keep the original field and block
-- the clicked target. Escape still explicitly discards the unfinished draft.
for _, failure in ipairs({ 'invalid', 'nonfinite', 'store', 'disabled' }) do
    local index, editing = field(1, 3, 1)
    local snapshot, count, revision = ffi.string(doc.data, doc.width * doc.height * 16), #editor.undo, doc.revision or 0
    if failure == 'invalid' then
        type_number('-')
    elseif failure == 'nonfinite' then
        type_number('1e+99')
    else
        type_number('99.125')
        if failure == 'disabled' then
            editing.control.disabled = true
        else
            fail_save = true
        end
    end
    click(grid_point(2, 3))
    fail_save = false
    editing.control.disabled = false
    assert(
        menu.text_edit == editing and handle.get('edit_row') == 1 and handle.get('edit_column') == 3,
        'Invalid/failed numeric blur lost field ownership or clicked the next target'
    )
    assert(
        ffi.string(doc.data, doc.width * doc.height * 16) == snapshot
            and #editor.undo == count
            and doc.revision == revision,
        'Invalid/failed numeric blur changed pixels/history'
    )
    menu.key(27)
    assert(
        not menu.text_edit and menu.visible and tonumber(doc.data[index]) ~= 99.125,
        'Escape committed the refused numeric draft or closed the editor'
    )
end

local index = field(1, 3, 1)
local snapshot = ffi.string(doc.data, doc.width * doc.height * 16)
type_number('88.125')
menu.key(27)
click(menu.window_bounds.x + 6, menu.window_bounds.y + 6)
assert(
    ffi.string(doc.data, doc.width * doc.height * 16) == snapshot,
    'Escape-cancelled Value draft later committed on blur'
)

-- The normal live-edit throttle consumes the committed revision after focus
-- releases. It must flush the last number once, without a synthetic callback.
local gate = dofile('src/editor/live_edit.lua').new()
local uploaded_revision, uploads = doc.revision, 0
local final_at = field(1, 3, 1)
type_number('216.625')
gate.ready(false, true, 0)
click(menu.window_bounds.x + 6, menu.window_bounds.y + 6)
assert(not menu.is_interacting(), 'Successful numeric blur retained a transient edit owner')
if gate.ready(doc.revision ~= uploaded_revision, menu.is_interacting(), 0) then
    uploaded_revision, uploads = doc.revision, uploads + 1
end
assert(
    uploads == 1
        and doc.data[final_at] == 216.625
        and not gate.ready(doc.revision ~= uploaded_revision, menu.is_interacting(), 0),
    'Final numeric blur revision did not flush exactly once'
)

-- A bounded numeric slider field uses its normal range/step validation too.
local plain = Core.new()
local range_handle = plain.register({
    id = 'bounded_blur',
    name = 'Bounded',
    pages = {
        {
            id = 'p',
            name = 'Page',
            require_confirmation = false,
            controls = {
                { id = 'number', type = 'slider', label = 'Number', min = 0, max = 1, step = 0.01, default = 0.2 },
            },
        },
    },
})
plain.mods[range_handle.id].pages[1].render_layout = function(ui)
    ui.number('number', ui.x + 20, ui.y + 70, 320, range_handle.get('number'), nil, true, nil, nil, true)
end
local range_menu = Menu.new(plain, function(text, size)
    return #text * size * 0.5
end, Text)
range_menu.visible = true
local numeric
for _, command in ipairs(range_menu.compose(1920, 1080)) do
    if (command.full_text or command.text) == '0.2' then
        numeric = command
    end
end
assert(numeric)
local function range_click(x, y)
    for _, down in ipairs({ true, false }) do
        range_menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return x, y
            end,
        }, 0)
    end
end
range_click(numeric.x + 3, numeric.y + 3)
assert(range_menu.text_edit)
range_menu.text_edit.text = '0.734'
range_click(0, 0)
assert(
    not range_menu.text_edit and math.abs(range_handle.get('number') - 0.73) < 1e-9,
    'Bounded numeric blur skipped its ordinary step normalization'
)
print(
    'PASS numeric blur: real Value Editor click geometry, exact HDR RGBA channels, old-target commit before navigation, invalid/failed commit retention, Escape and final live-edit flush'
)
