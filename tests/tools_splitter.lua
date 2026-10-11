-- Actual menu mouse ownership and layout for the docked grid/Tools divider.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local doc = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
for i = 0, 23 * 64 * 4 - 1 do
    doc.data[i] = (i % 17) / 16
end
local writes = 0
local modules = {
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    ui_core = Core,
    windows = {
        row_presets = function()
            return {}
        end,
    },
    engine = {
        create_texture = function()
            writes = writes + 1
        end,
        bind = function()
            writes = writes + 1
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(modules, function()
    return doc
end, function(value)
    return value
end, function()
    writes = writes + 1
end, 'tests/tmp/presets')
local pages = editor.pages()
for _, id in ipairs({ 'editor_load_armor', 'editor_load_helmet', 'populate_worn', 'editor_apply_armor' }) do
    pages[1].controls[#pages[1].controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            writes = writes + 1
        end,
    }
end
for _, id in ipairs({ 'basic_armor_lut', 'basic_helmet_lut' }) do
    pages[1].controls[#pages[1].controls + 1] =
        { id = id, type = 'choice', presentation = 'dropdown', label = id, choices = { 'LUT 1' }, default = 1 }
end
local handle = api.register({ id = 'splitter_test', name = 'Epic LUT', pages = pages })
editor.attach(api, handle)
api.mods[handle.id].tabs_top = true
local prior_preview, preview = package.loaded['epic.player_preview.v1']
package.loaded['epic.player_preview.v1'] = {
    is_docked = function()
        return true
    end,
    dock = function(bounds)
        preview = bounds
    end,
}
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end, dofile('src/platform/text_editor.lua'))
menu.visible, menu.epic_typography = true, true
menu.ui_scale, menu.window_width, menu.window_height = 0.85, 1800, 1100
editor.tools.open('rows')
editor.tools.set_docked(true)
local selection = { r1 = 2, r2 = 3, c1 = 1, c2 = 23 }
editor.selection = selection
local pixels = ffi.string(doc.data, doc.width * doc.height * 16)
local revision, undo, edit_row, edit_column =
    doc.revision, #editor.undo, handle.get('edit_row'), handle.get('edit_column')
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, c in ipairs(commands) do
        assert(not (c.text and c.text:find('attempt to ', 1, true)), c.text)
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
    })
end
local function point(x, y)
    local b = menu.window_bounds
    return b.x + x * b.scale, b.y + y * b.scale
end
local function start()
    compose()
    local d = assert(editor.tools_splitter, 'Docked divider missing')
    local x, y = point(d.x + d.w / 2, d.line_y)
    input(x, y, true)
    assert(editor.tools.splitter_dragging and menu.is_interacting(), 'Divider did not acquire custom drag ownership')
    return d
end
local function move(y, down)
    local d = assert(editor.tools_splitter)
    local x, py = point(d.x + d.w / 2, y)
    input(x, py, down)
    compose()
end
local function drag(y)
    start()
    move(y, true)
    move(y, false)
    assert(
        not editor.tools.splitter_dragging and not menu.is_interacting(),
        'Released divider retained input ownership'
    )
end
local function unchanged()
    assert(
        ffi.string(doc.data, doc.width * doc.height * 16) == pixels
            and doc.revision == revision
            and #editor.undo == undo,
        'Divider altered LUT pixels/revision/history'
    )
    assert(
        editor.selection == selection
            and handle.get('edit_row') == edit_row
            and handle.get('edit_column') == edit_column,
        'Divider altered editing selection'
    )
    assert(writes == 0, 'Divider activated a gear/GPU-writing action')
end
local function contained()
    compose()
    local d, t, g = assert(editor.tools_splitter), assert(editor.tools.bounds), assert(editor.grid_bounds)
    assert(t.h >= d.minimum - 0.01 and t.h <= d.maximum + 0.01, 'Divider escaped its usable size clamps')
    assert(d.y + d.h <= g.y - 27 + 0.01, 'Divider hit strip overlaps grid navigation')
    assert(d.x + d.w <= preview.x + 0.01 and d.x + d.w < editor.value_bounds.x, 'Divider overlaps preview/inspector')
    assert(d.y > t.y and g.y >= t.y + t.h, 'Divider overlaps footer or Tools consumes the grid')
    assert(doc.height - editor.grid_max >= 2, 'Divider shrank the grid below two usable rows')
    local tabs, title = { Import = 0, Rows = 0, Export = 0, Options = 0 }, 0
    for _, c in ipairs(compose()) do
        local text = c.full_text or c.text
        if c.type == 'text' and tabs[text] then
            tabs[text] = tabs[text] + 1
        end
        if text == 'LUT Editor Tools' then
            title = title + 1
        end
    end
    for name, count in pairs(tabs) do
        assert(count == 1, 'Divider duplicated Tools tabs: ' .. name)
    end
    assert(title == 1, 'Divider duplicated/moved the Tools footer title')
    unchanged()
end
compose()
assert(
    editor.tools.split_ratio == nil and doc.height - editor.grid_max == 8,
    'Initial split no longer uses automatic eight-row allocation'
)
contained()
local initial = editor.tools.bounds.h
drag(editor.tools_splitter.line_y + 70)
assert(editor.tools.bounds.h > initial and editor.tools.split_ratio, 'Upward drag did not expand Tools')
contained()
local expanded = editor.tools.bounds.h
drag(editor.tools_splitter.line_y - 100)
assert(editor.tools.bounds.h < expanded, 'Downward drag did not expand the LUT table')
contained()
drag(100000)
assert(math.abs(editor.tools.bounds.h - editor.tools_splitter.maximum) < 0.01, 'Upper pointer endpoint did not clamp')
contained()
drag(-100000)
assert(math.abs(editor.tools.bounds.h - editor.tools_splitter.minimum) < 0.01, 'Lower pointer endpoint did not clamp')
contained()

-- Release outside the window still commits the chosen bounded split and frees input.
start()
move(editor.tools_splitter.line_y + 40, true)
input(-50, -50, false)
compose()
assert(not editor.tools.splitter_dragging and not menu.is_interacting(), 'Outside release leaked divider ownership')
contained()
-- Escape/focus loss stop future pointer updates while preserving the last layout choice.
start()
move(editor.tools_splitter.line_y + 30, true)
menu.key(27)
local stopped = editor.tools.split_ratio
assert(menu.visible and not editor.tools.splitter_dragging, 'Escape closed the editor or retained divider drag')
move(100000, true)
move(100000, false)
assert(editor.tools.split_ratio == stopped, 'Canceled divider still followed the pointer')
start()
move(editor.tools_splitter.line_y + 30, true)
menu.input_focus(false, {
    down = function()
        return false
    end,
})
local unfocused = editor.tools.split_ratio
assert(not editor.tools.splitter_dragging and not menu.is_interacting(), 'Focus loss did not release divider ownership')
menu.input_focus(true, {
    down = function()
        return false
    end,
})
compose()
move(-100000, false)
assert(editor.tools.split_ratio == unfocused, 'Focus restoration replayed a divider gesture')
contained()

local ratio = editor.tools.split_ratio
for _, scenario in ipairs({ { 12, 0.65, 1200 }, { 20, 0.85, 1100 }, { 20, 1.15, 1000 }, { 12, 1, 900 } }) do
    menu.font_size, menu.ui_scale, menu.window_height = scenario[1], scenario[2], scenario[3]
    compose()
    local d = assert(editor.tools_splitter)
    local expected = math.max(d.minimum, math.min(d.maximum, ratio * d.total))
    assert(
        math.abs(editor.tools.bounds.h - expected) < 0.01 and editor.tools.split_ratio == ratio,
        'Resize/font/scale lost the chosen split ratio'
    )
    contained()
    drag(editor.tools_splitter.line_y + 20)
    ratio = editor.tools.split_ratio
    contained()
end
editor.tools.set_docked(false)
compose()
assert(
    not editor.tools_splitter and editor.tools.split_ratio == ratio,
    'Floating Tools lost the saved split or kept a divider'
)
editor.tools.set_docked(true)
compose()
assert(editor.tools.split_ratio == ratio and editor.tools_splitter, 'Redocking did not restore the split')
contained()

-- Scroll each pane independently, then reach all remaining grid rows.
menu.font_size, menu.ui_scale, menu.window_height = 12, 0.85, 1100
compose()
drag(-100000)
editor.tools.scroll = 0
local t, b = editor.tools.bounds, menu.window_bounds
local first = editor.grid_first
menu.wheel(-120, b.x + (t.x + t.w / 2) * b.scale, b.y + (t.y + t.h / 2) * b.scale)
compose()
assert(editor.tools.scroll > 0 and editor.grid_first == first, 'Tools wheel affected the table or became unusable')
local tools_scroll = editor.tools.scroll
for _ = 1, 30 do
    local g = editor.grid_bounds
    menu.wheel(-120, b.x + (g.x + g.w / 2) * b.scale, b.y + (g.y + g.h / 2) * b.scale)
    compose()
end
assert(
    editor.grid_first == editor.grid_max + 1 and editor.tools.scroll == tools_scroll,
    'Grid wheel did not remain independent/reach the final row'
)
local last = false
for _, c in ipairs(compose()) do
    if (c.full_text or c.text) == 'Row 64' then
        last = true
    end
end
assert(last, 'Resized table cannot display its final row')
unchanged()
-- Closing Tools during a held drag clears its view/controller state on compose.
start()
editor.tools.close()
compose()
assert(not editor.tools_splitter and not editor.tools.splitter_dragging, 'Closing Tools retained a splitter gesture')
input(-50, -50, false)
assert(not menu.is_interacting(), 'Closed Tools retained mouse drag ownership')
unchanged()
package.loaded['epic.player_preview.v1'] = prior_preview
print(
    'PASS Tools splitter: actual bidirectional drag, usable clamps, ratio across font/scale/resize/redock, independent scroll, all rows, Escape/focus/outside-release cleanup and unchanged LUT/selection/bindings'
)
