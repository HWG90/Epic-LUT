local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local d = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
for i = 0, 23 * 8 * 4 - 1 do
    d.data[i] = (i % 7) / 6
end
d.data[3] = 2.5
local m = {
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    scratch_tool = dofile('src/editor/scratch_tool.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    ui_core = Core,
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(
    m,
    function()
        return d
    end,
    tostring,
    function()
        return true
    end,
    'tests/tmp/picker-permissions'
)
local pages = editor.pages()
local h = api.register({ id = 'permissions', name = 'Epic LUT', pages = pages })
local mod = api.mods[h.id]
mod.tabs_top = true
editor.attach(api, h)
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.window_width, menu.window_height = true, 1800, 1000
local function compose()
    return menu.compose(1920, 1080)
end
local function bytes()
    return ffi.string(d.data, d.width * d.height * 16)
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
local function twice(rect)
    for i = 1, 2 do
        input(rect.x + rect.w / 2, rect.y + rect.h / 2, true)
        input(rect.x + rect.w / 2, rect.y + rect.h / 2, false)
    end
end
local function cell(column)
    local commands = compose()
    local label
    for _, c in ipairs(commands) do
        if c.full_text == m.semantics.short_columns[column] then
            label = c
        end
    end
    assert(label)
    for _, c in ipairs(commands) do
        if
            c.type == 'rect'
            and math.abs(c.x - label.x) < 0.1
            and math.abs(c.w - c.h) < 0.1
            and c.w > 10
            and c.w < 70
            and c.y < label.y
        then
            return c
        end
    end
    error('Grid cell did not compose')
end
local before = bytes()
local history = #editor.undo
twice(cell(2))
assert(
    not menu.color_picker and menu.visible and bytes() == before and #editor.undo == history,
    'Locked raw double-click opened a picker or wrote pixels/history'
)
editor.open_row = 1
local inspector = compose()
local title, chip
for _, c in ipairs(inspector) do
    if c.full_text and c.full_text:find('Column 2:', 1, true) == 1 then
        title = c
    end
end
assert(title, 'Raw inspector column did not compose')
local scale = menu.window_bounds.scale
for _, c in ipairs(inspector) do
    if
        c.type == 'rect'
        and math.abs(c.w - 24 * scale) < 0.1
        and math.abs(c.h - 18 * scale) < 0.1
        and math.abs(c.y - title.y + 4 * scale) < 0.1
    then
        chip = c
    end
end
assert(chip, 'Raw inspector color chip did not compose')
input(chip.x + 3, chip.y + 3, true)
input(chip.x + 3, chip.y + 3, false)
assert(
    not menu.color_picker and bytes() == before and #editor.undo == history,
    'Raw inspector chip bypassed picker permission'
)
assert(h.set('grid_channel', 6))
twice(cell(1))
assert(not menu.color_picker and bytes() == before, 'Protected Alpha channel opened a color picker')
assert(h.set('grid_channel', 1))
twice(cell(1))
assert(menu.color_picker, 'Editable RGB double-click did not open its picker')
compose()
menu.color_picker.rgb = { 255, 0, 0 }
menu.color_picker.alpha = 0.1
menu.color_picker.next_preview = 0
compose()
assert(d.data[0] == 1 and d.data[3] == 2.5, 'RGB picker modified protected Alpha')
-- A read-only transition closes the popup and restores its transient preview.
d.read_only = true
compose()
assert(
    not menu.color_picker and menu.visible and bytes() == before and #editor.undo == history,
    'Read-only transition retained preview/picker/history'
)
d.read_only = nil
assert(h.set('unlock', true) and h.set('grid_channel', 2))
twice(cell(2))
assert(menu.color_picker, 'Unlocked RGBA raw cell is not editable')
compose()
menu.close_color(false)
assert(h.set('unlock', false) and h.set('grid_channel', 6))
-- Basic RGB retains its own origin without overwriting Advanced's channel mode.
mod.pages[1].render_layout = function(ui)
    ui.button(ui.x + 10, ui.y + 100, 200, 28, 'Basic RGB', function()
        ui.activate('cell_color', nil, 1)
    end)
end
assert(h.set('edit_column', 1))
local basic
for _, c in ipairs(compose()) do
    if c.full_text == 'Basic RGB' then
        basic = c
    end
end
input(basic.x + 3, basic.y + 3, true)
input(basic.x + 3, basic.y + 3, false)
assert(menu.color_picker and h.get('grid_channel') == 6, 'Basic RGB changed or inherited Advanced Alpha mode')
compose()
assert(
    editor.color_session and editor.color_session.mode == 1 and not mod.controls.cell_color.picker_channel_enabled(4),
    'Basic picker began outside its RGB permission mask'
)
menu.close_color(false)
local control = mod.controls.cell_color
control.read_only = true
input(basic.x + 3, basic.y + 3, true)
input(basic.x + 3, basic.y + 3, false)
assert(not menu.color_picker and bytes() == before, 'Read-only control opened a picker')
control.read_only = nil
control.can_open_picker = function()
    error('Target unavailable')
end
input(basic.x + 3, basic.y + 3, true)
input(basic.x + 3, basic.y + 3, false)
assert(menu.visible and not menu.color_picker and bytes() == before, 'Picker predicate error closed the menu')
control.can_open_picker = function()
    return true
end
control.picker_begin = function()
    return false, 'Reader unavailable'
end
input(basic.x + 3, basic.y + 3, true)
input(basic.x + 3, basic.y + 3, false)
assert(menu.visible and not menu.color_picker and bytes() == before, 'Rejected picker begin still opened a popup')
mod.pages[1].render_layout = function(ui)
    ui.button(ui.x + 10, ui.y + 100, 200, 28, 'Scratch', function()
        ui.activate('scratch_color')
    end)
end
local scratch
for _, c in ipairs(compose()) do
    if c.full_text == 'Scratch' then
        scratch = c
    end
end
input(scratch.x + 3, scratch.y + 3, true)
input(scratch.x + 3, scratch.y + 3, false)
assert(
    menu.color_picker and menu.color_picker.control.id == 'scratch_color',
    'Protected target disabled independent Scratch'
)
menu.close_color(false)
print(
    'PASS picker permissions: actual grid double-clicks, RGB Alpha preservation, read-only rollback, explicit Advanced unlock, Basic mode context, safe predicate failures and independent Scratch'
)
