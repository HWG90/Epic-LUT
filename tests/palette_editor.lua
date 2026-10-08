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
local d = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
for r = 0, 7 do
    for c = 0, 22 do
        local i = (r * 23 + c) * 4
        d.data[i], d.data[i + 1], d.data[i + 2], d.data[i + 3] = (r + c) % 5 / 4, c % 7 / 6, r % 3 / 2, 0.75
    end
end
local m = {
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    ui_core = core,
    windows = dofile('src/platform/windows.lua'),
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return d
end, function(s)
    return s
end, function()
    return true
end, 'tests/tmp/presets')
local pages = editor.pages()
table.insert(pages, 1, {
    id = 'import',
    name = 'Import / Apply',
    require_confirmation = false,
    controls = {
        { id = 'target_helmet', type = 'toggle', label = 'Helmet', default = true },
        { id = 'target_armor', type = 'toggle', label = 'Armor', default = true },
        { id = 'save_palette', type = 'button', label = 'Send to LUT Editor', on_activate = function() end },
        { id = 'apply_checked', type = 'button', label = 'Apply LUT', on_activate = function() end },
        { id = 'apply_editor', type = 'button', label = 'Apply edited palette', on_activate = function() end },
        { id = 'browse', type = 'button', label = 'Choose file', on_activate = function() end },
        { id = 'refresh', type = 'button', label = 'Refresh', on_activate = function() end },
        { id = 'lut', type = 'choice', label = 'Target', default = 1, choices = { 'Armor LUT 1', 'Helmet LUT 2' } },
        {
            id = 'palette',
            type = 'choice',
            label = 'Palette',
            default = 1,
            choices = { 'Imported palette 1', 'Imported palette 2' },
        },
        {
            id = 'scope',
            type = 'choice',
            label = 'Scope',
            default = 4,
            choices = { 'Selected LUT', 'All Armor LUTs', 'Helmet LUTs', 'All Armor + Helmet LUTs' },
        },
        { id = 'apply_armor', type = 'button', label = 'Apply Armor', on_activate = function() end },
        { id = 'apply_helmet', type = 'button', label = 'Apply Helmet', on_activate = function() end },
        { id = 'remove_lut', type = 'button', label = 'Remove LUT', on_activate = function() end },
        { id = 'reset_custom', type = 'button', label = 'Reset Custom LUT', on_activate = function() end },
        { id = 'save_setup', type = 'button', label = 'Save applied setup', on_activate = function() end },
        { id = 'apply', type = 'button', label = 'Apply', on_activate = function() end },
        { id = 'restore', type = 'button', label = 'Restore', on_activate = function() end },
    },
})
local h = api.register({ id = 'palette_test', name = 'Epic LUT', pages = pages })
editor.attach(api, h)
api.mods.palette_test.tabs_top = true
local alpha = d.data[3]
local other = d.data[4]
assert(h.set('cell_color', '#FF0080'))
assert(
    d.data[0] == 1
        and d.data[1] == 0
        and math.abs(d.data[2] - 128 / 255) < 1e-6
        and d.data[3] == alpha
        and d.data[4] == other
)
assert(h.activate('undo'))
assert(d.data[0] == 0 and d.data[3] == alpha)
assert(h.activate('redo'))
assert(d.data[0] == 1)
assert(h.set('advanced_row', 3))
assert(h.get('edit_row') == 3)
assert(h.set('edit_column', 22))
assert(h.set('unlock', true))
assert(h.set('cell_a', 4))
assert(d.data[((3 - 1) * 23 + 21) * 4 + 3] == 4)
assert(h.activate('copy_row'))
assert(h.set('edit_row', 4))
assert(h.activate('paste_row'))
assert(ffi.string(d.data + 2 * 23 * 4, 23 * 16) == ffi.string(d.data + 3 * 23 * 4, 23 * 16))
local before = d.data[2 * 23 * 4]
assert(h.activate('undo'))
assert(d.data[3 * 23 * 4] ~= before)
assert(h.activate('save_row'))
assert(h.set('edit_row', 5))
assert(h.activate('load_row'))
assert(ffi.string(d.data + 3 * 23 * 4, 23 * 16) == ffi.string(d.data + 4 * 23 * 4, 23 * 16))
assert(h.set('row_preset', 'new-test-row'))
assert(h.activate('save_row'))
local choices = api.mods.palette_test.controls.row_preset_select.choices
local selected
for i, name in ipairs(choices) do
    if name == 'new-test-row' then
        selected = i
    end
end
assert(selected, 'New row preset did not appear in the dropdown')
assert(h.set('row_preset', 'different-name'))
assert(h.set('row_preset_select', 1))
assert(h.set('row_preset_select', selected))
assert(h.get('row_preset') == 'new-test-row', 'Dropdown selection did not fill the editable preset name')
local commands, hits = {}, {}
local function command(t)
    commands[#commands + 1] = t
end
local ui = {
    x = 0,
    y = 0,
    w = 1300,
    h = 800,
    rect = function(x, y, w, h, c)
        command({ type = 'rect', x = x, y = y, w = w, h = h, c = c })
    end,
    text = function(x, y, text, size, c)
        command({ type = 'text', x = x, y = y, text = text, size = size, c = c })
    end,
    bounded = function(x, y, text, size, c, w)
        command({ type = 'text', x = x, y = y, text = text, size = size, c = c })
    end,
    hit = function(x, y, w, h, fn)
        hits[#hits + 1] = { x = x, y = y, w = w, h = h, click = fn }
    end,
    activate = function() end,
}
editor.layout(ui)
local cells = {}
for _, hit in ipairs(hits) do
    if hit.w == hit.h and hit.w < 40 then
        cells[#cells + 1] = hit
    end
end
assert(#cells == 8 * 23, 'Pixel grid did not expose every cell')
cells[23 * 2 + 7].click()
assert(h.get('edit_row') == 3 and h.get('edit_column') == 7 and h.get('color_field') == 4)
assert(h.set('scratch_color', '#123456'))
assert(h.set('grid_tool', 2))
cells[1].click()
assert(math.abs(d.data[0] - 0x12 / 255) < 1e-6 and d.data[3] == alpha, 'Draw changed an unselected alpha channel')
assert(h.set('grid_tool', 1))
cells[1].click()
ui.shift = function()
    return true
end
cells[25].click()
ui.shift = nil
assert(editor.selection.r2 == 2 and editor.selection.c2 == 2)
assert(h.activate('copy_selection'))
assert(editor.clip.width == 2 and editor.clip.height == 2)
assert(h.set('grid_tool', 3))
cells[4 * 23 + 3].click()
assert(d.data[0] == 0 and math.abs(d.data[(4 * 23 + 2) * 4] - 0x12 / 255) < 1e-6, 'Move did not preserve copied pixels')
assert(h.activate('undo'))
assert(math.abs(d.data[0] - 0x12 / 255) < 1e-6, 'Move was not one undoable operation')
assert(h.set('grid_tool', 1))
cells[23 * 2 + 1].click()
editor.value_scroll = 0
editor.focus_column = nil
commands, hits = {}, {}
editor.layout(ui)
-- Import scratch uses the editor's authoritative RGB edit path and Undo.
local scratch_at = ((3 - 1) * 23 + 6 - 1) * 4
local scratch_alpha = d.data[scratch_at + 3]
local scratch_before = d.data[scratch_at]
assert(editor.paint_rgb(3, 6, '#123456'))
assert(
    h.get('edit_row') == 3 and h.get('edit_column') == 6 and math.abs(d.data[scratch_at] - 0x12 / 255) < 1e-6,
    'Scratch paint missed its editor cell'
)
assert(d.data[scratch_at + 3] == scratch_alpha, 'Scratch paint changed alpha')
assert(h.activate('undo'))
assert(d.data[scratch_at] == scratch_before)
assert(h.set('edit_row', 1))
editor.focus_column = nil
local menu = dofile('vendor/menu/menu.lua').new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
menu.selected = 1
menu.page = 2
menu.window_width = 1800
menu.window_height = 1000
menu.compact_fonts = true
local rendered = menu.compose(1920, 1080)
local grid = false
local saved = false
for _, c in ipairs(rendered) do
    if c.text and c.text:find('Pixel Grid', 1, true) == 1 then
        grid = true
        assert(c.x < menu.window_bounds.x + 50, 'Sidebar still consumes editor width')
    end
    if c.full_text == 'Save applied setup' then
        saved = true
    end
    assert(c.text ~= 'MODS', 'Tabbed editor still shows a left mod selector')
end
assert(grid, 'Actual menu controller did not render the custom LUT workspace')
assert(saved, 'Custom renderer failed before drawing its action controls')
local function tap(x, y)
    menu.tick({
        down = function(k)
            return k == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
    menu.tick({
        down = function()
            return false
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
-- Custom preset input must show keystrokes and commit the typed name.
local preset_label
for _, c in ipairs(rendered) do
    if c.full_text == h.get('row_preset') then
        preset_label = c
        break
    end
end
assert(preset_label, 'Preset name field missing')
tap(preset_label.x + 3, preset_label.y + 2)
assert(menu.text_edit and menu.text_edit.control.id == 'row_preset', 'Preset field cannot be edited')
menu.key(65)
menu.key(66)
local typing = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'AB|' then
        typing = true
    end
end
assert(typing, 'Preset input does not display typed text')
menu.key(13)
assert(h.get('row_preset') == 'AB', 'Preset input did not save typed name')
local preview_button
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Preview Palette' then
        preview_button = c
    end
end
assert(preview_button, 'Palette preview button missing')
tap(preview_button.x + 2, preview_button.y + 2)
assert(menu.preview_window, 'Preview did not open a separate window')
local preview_commands = menu.compose(1920, 1080)
local values = 0
for _, c in ipairs(preview_commands) do
    if c.text and c.text:match('^[RGBA] ') then
        values = values + 1
    end
end
assert(values >= 23 * 8 * 4, 'Read-only preview missing RGBA values')
menu.key(27)
assert(not menu.preview_window and menu.visible, 'Closing preview did not return to editor')
-- A typed value must use its own field context, not a stale grid selection.
local numeric
for _, c in ipairs(rendered) do
    if c.full_text == '0.5' and c.x > menu.window_bounds.x + 1200 then
        numeric = c
        break
    end
end
assert(numeric, 'Typed float box was not rendered')
tap(numeric.x + 10, numeric.y + 2)
assert(menu.text_edit and menu.text_edit.control.type == 'slider', 'Float value did not open typed editing')
local typed_row, typed_column = h.get('edit_row'), h.get('edit_column')
menu.text_edit.text = '300'
menu.key(13)
assert(d.data[((typed_row - 1) * 23 + typed_column - 1) * 4] == 300, 'Typed shader value was limited by slider bounds')
assert(h.activate('undo'))
tap(numeric.x + 10, numeric.y + 2)
menu.text_edit.text = '0.125'
menu.key(13)
assert(d.data[((typed_row - 1) * 23 + typed_column - 1) * 4] == 0.125, 'Typed float affected the wrong cell')
assert(h.activate('undo'))
local slider_x, slider_y = numeric.x - 180, numeric.y + 2
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return slider_x, slider_y
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return slider_x + 40, slider_y
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function()
        return false
    end,
    mouse = function()
        return slider_x + 40, slider_y
    end,
    wheel = function()
        return 0
    end,
})
assert(menu.visible, 'Shader slider drag closed the menu')
assert(h.activate('undo'))
for _, c in ipairs(rendered) do
    if c.type == 'text' then
        assert(c.size <= 14, 'Compact editor font exceeded its cap')
    end
end
local initial_scroll = editor.value_scroll
local vb = editor.value_bounds
local wb = menu.window_bounds
menu.wheel(-120, wb.x + (vb.x + 10) * wb.scale, wb.y + (vb.y + 20) * wb.scale)
assert(editor.value_scroll > initial_scroll, 'Value editor did not scroll independently')
menu.wheel(120, wb.x + (vb.x + 10) * wb.scale, wb.y + (vb.y + 20) * wb.scale)
local combo
for _, c in ipairs(rendered) do
    if c.full_text == 'Armor LUT 1' then
        combo = c
        break
    end
end
assert(combo, 'Scope combo was not rendered')
tap(combo.x + 20, combo.y + 2)
assert(menu.dropdown and menu.dropdown.control.id == 'lut', 'Combo center did not open its dropdown')
menu.key(40)
menu.key(13)
assert(h.get('lut') == 2, 'Dropdown selection was not applied')
-- Tabs are real click targets and the rail remains absent.
local target_tab
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Material / camo' then
        target_tab = c
        break
    end
end
assert(target_tab)
tap(target_tab.x + 20, target_tab.y + 2)
assert(menu.page == 3, 'Top tab did not navigate to material editing')
menu.page = 2
editor.value_scroll = 0
rendered = menu.compose(1920, 1080)
commands = rendered
local function esc(s)
    return tostring(s):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
end
local f = assert(io.open('dist/lut-editor-layout-preview.svg', 'wb'))
f:write(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080"><rect width="1920" height="1080" fill="#101114"/>'
)
for _, c in ipairs(commands) do
    local color = string.format('#%02X%02X%02X', c.c[1], c.c[2], c.c[3])
    if c.type == 'rect' then
        f:write(
            string.format(
                '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',
                c.x,
                1080 - c.y - c.h,
                c.w,
                c.h,
                color
            )
        )
    else
        f:write(
            string.format(
                '<text x="%.2f" y="%.2f" font-family="Segoe UI, sans-serif" font-size="%.2f" fill="%s">%s</text>',
                c.x,
                1080 - c.y,
                c.size,
                color,
                esc(c.text)
            )
        )
    end
end
f:write('</svg>')
f:close()
print(
    'PASS palette editor: exact RGB/alpha isolation, float/camo edits, shared row navigation, undo/redo, row copy/paste, 184 selectable grid cells and source-derived layout preview'
)

-- Grid paste must retain shader/camo alpha even while the paint selector is RGB.
assert(h.set('unlock', true))
assert(h.set('grid_channel', 1))
assert(h.set('edit_row', 1))
assert(h.set('edit_column', 1))
editor.selection = { r1 = 1, r2 = 1, c1 = 1, c2 = 23 }
local copied = ffi.string(d.data, 23 * 16)
editor.copy_selection()
assert(h.set('edit_row', 2))
editor.paste_selection()
assert(ffi.string(d.data + 23 * 4, 23 * 16) == copied, 'RGB paint mode dropped clipboard alpha')

local picker = api.mods.palette_test.controls.cell_color
assert(picker.picker_commit({ 10, 20, 30 }, 4.25))
local at = dofile('src/core/semantics.lua').index(h.get('edit_row'), h.get('edit_column'), 1, d.width, d.height)
assert(math.abs(d.data[at] - 10 / 255) < 1e-6 and d.data[at + 3] == 4.25)
assert(picker.picker_alpha() == 4.25)
assert(h.activate('undo'))
assert(d.data[at + 3] ~= 4.25, 'Picker RGBA was not one undoable edit')

local target = (h.get('edit_row') - 1) * d.width * 4
local next_row = ffi.string(d.data + target + d.width * 4, d.width * 16)
d.data[target] = 9
assert(editor.is_dirty())
editor.reset_part(true)
assert(ffi.string(d.data + target, d.width * 16) == ffi.string(d.original + target, d.width * 16))
assert(ffi.string(d.data + target + d.width * 4, d.width * 16) == next_row, 'Row reset affected another row')
assert(h.activate('undo'))
assert(d.data[target] == 9)
local cell = dofile('src/core/semantics.lua').index(h.get('edit_row'), h.get('edit_column'), 1, d.width, d.height)
d.data[cell + 3] = 8
editor.reset_part(false)
assert(d.data[cell + 3] == d.original[cell + 3])

assert(h.set('edit_column', 2))
local raw_at = dofile('src/core/semantics.lua').index(h.get('edit_row'), 2, 1, d.width, d.height)
d.data[raw_at] = 12.5
editor.sync()
local raw_picker = api.mods.palette_test.controls.cell_color
local displayed = dofile('vendor/menu/core.lua').color_rgb(h.get('cell_color'))
assert(raw_picker.picker_commit(displayed, 0.25))
assert(d.data[raw_at] == 12.5 and d.data[raw_at + 3] == 0.25, 'Alpha edit quantized untouched raw channel')
local scratch_picker = api.mods.palette_test.controls.scratch_color
assert(scratch_picker.picker_commit({ 10, 20, 30 }, 0.4))
assert(h.get('scratch_alpha') == 0.4 and scratch_picker.picker_alpha() == 0.4)

-- Toolbar and Scratch readout remain clear of the preview and Paint button.
local prior_preview = package.loaded['epic.player_preview.v1']
local docked
package.loaded['epic.player_preview.v1'] = {dock = function(bounds) docked = bounds end}
commands, hits = {}, {}
editor.layout(ui)
local alpha_label, paint_label
for _, c in ipairs(commands) do
    if c.text and c.text:match('^A: ') then alpha_label = c end
    if c.text == 'Paint selected RGB' then paint_label = c end
end
assert(alpha_label and paint_label and alpha_label.y > paint_label.y + 16, 'Scratch alpha readout overlaps Paint')
assert(docked and docked.y + docked.h <= ui.y + ui.h - 140, 'Docked preview overlaps grid toolbar')
package.loaded['epic.player_preview.v1'] = prior_preview

local live_control = api.mods.palette_test.controls.cell_color
local before_live = ffi.string(d.data,d.width*d.height*16)
live_control.picker_begin()
live_control.picker_preview({ 13, 37, 59 }, .42)
assert(ffi.string(d.data,d.width*d.height*16)~=before_live,'Color picker preview did not update document')
live_control.picker_end(false)
assert(ffi.string(d.data,d.width*d.height*16)==before_live,'Cancel did not restore color picker starting values')
