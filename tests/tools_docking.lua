-- Actual menu/controller coverage for the shared floating and docked Tools.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local document = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
for i = 0, 23 * 64 * 4 - 1 do
    document.data[i] = (i % 17) / 16
end
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
            return { 'Example' }
        end,
    },
}
local imports = 0
local editor = dofile('src/editor/lut_editor.lua').new(modules, function()
    return document
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local pages = editor.pages()
local registered = {}
local function collect(controls)
    for _, control in ipairs(controls) do
        if control.id then
            registered[control.id] = control
        end
        if control.children then
            collect(control.children)
        end
    end
end
for _, page in ipairs(pages) do
    collect(page.controls)
end
local function button(id)
    return {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            return true
        end,
    }
end
for _, control in ipairs({
    button('browse'),
    button('save_palette'),
    button('populate_worn'),
    button('editor_load_armor'),
    button('editor_load_helmet'),
    button('editor_apply_armor'),
    button('editor_all_armor'),
    button('restore'),
    button('reset_custom'),
    button('save_setup'),
    button('load_debug_lut'),
    { id = 'palette', type = 'choice', label = 'Palette', choices = { 'Imported' }, default = 1 },
    {
        id = 'basic_armor_lut',
        type = 'choice',
        presentation = 'dropdown',
        label = 'Armor',
        choices = { 'LUT 1' },
        default = 1,
    },
    {
        id = 'basic_helmet_lut',
        type = 'choice',
        presentation = 'dropdown',
        label = 'Helmet',
        choices = { 'LUT 1' },
        default = 1,
    },
}) do
    if not registered[control.id] then
        pages[1].controls[#pages[1].controls + 1] = control
    end
end
local import_control = registered.import_paydex_rows
if not import_control then
    import_control = button('import_paydex_rows')
    pages[1].controls[#pages[1].controls + 1] = import_control
end
import_control.disabled = false
import_control.on_activate = function()
    imports = imports + 1
end
local handle = api.register({ id = 'dock_test', name = 'Epic LUT', pages = pages })
editor.attach(api, handle)
local mod = api.mods[handle.id]
import_control = mod.controls.import_paydex_rows
mod.tabs_top = true
local prior_preview = package.loaded['epic.player_preview.v1']
local preview_bounds
package.loaded['epic.player_preview.v1'] = {
    is_docked = function()
        return true
    end,
    dock = function(bounds)
        preview_bounds = bounds
    end,
}
local pattern_open = false
editor.pattern_editor = {
    popup = function(ui)
        if pattern_open then
            ui.floating(
                'pattern_test',
                function(x, y, w, h)
                    ui.rect(x, y, w, h, ui.theme.panel)
                    ui.bounded(x + 10, y + h - 27, 'Pattern LUT Editor', 14, ui.theme.white, w - 40)
                end,
                420,
                220,
                function()
                    pattern_open = false
                end,
                40
            )
        end
    end,
}
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end, dofile('src/platform/text_editor.lua'))
menu.epic_typography, menu.visible = true, true
menu.window_width, menu.window_height = 1800, 1000
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, c in ipairs(commands) do
        assert(not (c.text and c.text:find('attempt to ', 1, true)), c.text)
    end
    return commands
end
local function label(commands, value, popup)
    for _, c in ipairs(commands) do
        if c.type == 'text' and (c.full_text or c.text) == value and (popup == nil or not not c.popup == popup) then
            return c
        end
    end
end
local function tab_sets(commands, main, floating)
    for _, name in ipairs({ 'Import', 'Rows', 'Export', 'Options' }) do
        local counts = { main = 0, floating = 0 }
        for _, command in ipairs(commands) do
            if command.type == 'text' and (command.full_text or command.text) == name then
                local kind = command.popup and 'floating' or 'main'
                counts[kind] = counts[kind] + 1
            end
        end
        assert(counts.main == main and counts.floating == floating, 'Unexpected duplicate/restored Tools tab: ' .. name)
    end
end
local function tap(x, y)
    for _, down in ipairs({ true, false }) do
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
end
local function click(value, popup)
    local c = assert(label(compose(), value, popup), 'Missing control: ' .. value)
    tap(c.x + 2, c.y + 2)
end
local initial_pixels = ffi.string(document.data, document.width * document.height * 16)
editor.tools.open('rows')
assert(not editor.tools.is_docked(), 'Tools no longer defaults to its independent window')
do
    local floating_rows = compose()
    local previous = assert(label(floating_rows, 'my-row', true))
    for _, name in ipairs({ 'Save selected row', 'Apply preset to row', 'Import Paydex JSON...', 'Copy row' }) do
        local current = assert(label(floating_rows, name, true))
        assert(previous.y > current.y + current.size, 'Rows controls are out of order/overlap: ' .. name)
        previous = current
    end
end
click('Dock', true)
local commands = compose()
tab_sets(commands, 1, 0)
assert(editor.tools.is_open() and editor.tools.is_docked() and editor.tools.bounds, 'Dock did not retain active Tools')
for _, window in ipairs(menu.floating_windows) do
    assert(window.id ~= 'editor_tools', 'Docked Tools kept a floating owner')
end
assert(
    editor.tools.tab == 'rows' and ffi.string(document.data, document.width * document.height * 16) == initial_pixels
)
local function contained()
    local b = assert(editor.tools.bounds)
    assert(editor.grid_bounds.y >= b.y + b.h, 'Docked Tools overlaps swatches/grid scroll region')
    assert(b.x + b.w <= preview_bounds.x, 'Docked Tools overlaps the Player Preview')
    assert(b.x + b.w < editor.value_bounds.x, 'Docked Tools overlaps the value inspector')
    local scale, wb = menu.window_bounds.scale, menu.window_bounds
    local footer = assert(label(compose(), 'Tools', false))
    assert(wb.y + b.y * scale > footer.y + footer.size, 'Docked Tools overlaps the footer')
    for _, command in ipairs(compose()) do
        if
            command.ui_role == 'swatch_fill'
            and not command.popup
            and command.x >= wb.x + b.x * scale
            and command.x < wb.x + (b.x + b.w) * scale
        then
            assert(command.y >= wb.y + (b.y + b.h) * scale, 'An actual swatch renders through docked Tools')
        end
    end
end
contained()
local function reveal(value)
    for _ = 1, 64 do
        local commands = compose()
        if label(commands, value, false) then
            return commands
        end
        local b, wb = assert(editor.tools.bounds), menu.window_bounds
        local grid_first, value_scroll = editor.grid_first, editor.value_scroll
        menu.wheel(-120, wb.x + (b.x + b.w / 2) * wb.scale, wb.y + (b.y + b.h / 2) * wb.scale)
        assert(
            editor.grid_first == grid_first and editor.value_scroll == value_scroll,
            'Tools wheel scrolled another panel'
        )
    end
    error('Dock scroll cannot reach ' .. value)
end
reveal('Reset row')
assert(editor.tools.scroll > 0 and editor.tools.maximum > 0, 'Tight dock did not expose its scrollable body')
editor.tools.scroll = 0
commands = reveal('my-row')
local preset = assert(label(commands, 'my-row', false))
local arrow
for _, c in ipairs(commands) do
    if c.text == 'v' and c.y == preset.y and c.x > preset.x then
        arrow = c
    end
end
assert(arrow, 'Docked row preset lost its dropdown')
tap(arrow.x + 2, arrow.y + 2)
assert(
    menu.dropdown and menu.dropdown.control.id == 'row_preset_select' and not menu.dropdown.owner,
    'Docked preset retained an obsolete floating owner'
)
commands = compose()
local option = assert(label(commands, 'Example', true))
assert(option.paint_plane >= 300, 'Docked dropdown did not render above main controls')
tap(option.x + 2, option.y + 2)
assert(
    handle.get('row_preset') == 'Example' and editor.tools.is_docked(),
    'Docked preset selection lost its name/state'
)
assert(
    ffi.string(document.data, document.width * document.height * 16) == initial_pixels,
    'Dock/selection applied rows automatically'
)
-- A focused name loses caret hit priority as soon as its row scrolls away.
editor.tools.scroll = 0
commands = reveal('Example')
local editable = assert(label(commands, 'Example', false))
tap(editable.x + 2, editable.y + 2)
compose()
local editing = assert(menu.text_edit, 'Docked preset name did not start editing')
local old_field = assert(editing.field_bounds)
commands = reveal('Reset row')
assert(menu.text_edit == editing and not editing.field_bounds, 'Hidden preset name kept stale caret hit bounds')
local reset = assert(label(commands, 'Reset row', false))
local reset_body
for i = #commands, 1, -1 do
    local c = commands[i]
    if
        c.ui_role == 'control_fill'
        and c.h <= 60 * menu.window_bounds.scale
        and c.x <= reset.x
        and c.x + c.w >= reset.x
        and c.y <= reset.y
        and c.y + c.h >= reset.y
    then
        reset_body = c
        break
    end
end
assert(reset_body, 'Docked Reset button body missing')
local shared_left, shared_right =
    math.max(old_field.x, reset_body.x), math.min(old_field.x + old_field.w, reset_body.x + reset_body.w)
local shared_bottom, shared_top =
    math.max(old_field.y, reset_body.y), math.min(old_field.y + old_field.h, reset_body.y + reset_body.h)
assert(
    shared_left < shared_right and shared_bottom < shared_top,
    'Stale caret fixture needs an overlapping Reset target'
)
local before_reset = #editor.undo
tap((shared_left + shared_right) / 2, (shared_bottom + shared_top) / 2)
assert(not menu.text_edit and #editor.undo == before_reset + 1, 'Hidden name caret intercepted the docked Reset action')
assert(handle.activate('undo'))
assert(ffi.string(document.data, document.width * document.height * 16) == initial_pixels)
pattern_open = true
commands = compose()
local pattern_window
for _, window in ipairs(menu.floating_windows) do
    if window.id == 'pattern_test' then
        pattern_window = window
    end
end
assert(pattern_window and editor.tools.is_docked(), 'Docking Tools replaced the independent Pattern window')
pattern_open = false
local custom = document
document = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
editor.sync()
commands = compose()
assert(
    editor.grid_max == 0 and label(commands, 'Row 8', false),
    'Roomy dock unnecessarily hid standard eight-row swatches'
)
document = custom
editor.sync()
editor.focus_cell(64, 1)
commands = compose()
assert(label(commands, 'Row 64', false), 'Docked grid cannot reach the last custom row')
for _, scenario in ipairs({ { 12, 0.7, 1000 }, { 20, 0.85, 1000 }, { 12, 1.15, 840 }, { 20, 1, 840 } }) do
    menu.font_size, menu.ui_scale, menu.window_height = scenario[1], scenario[2], scenario[3]
    editor.tools.scroll = 0
    compose()
    contained()
    assert(label(compose(), 'Undock', false), 'Dock toggle disappeared after font/scale change')
    reveal('Reset row')
end
-- A taller editor must give the dock all free height, beyond the old 260 cap.
menu.font_size, menu.ui_scale, menu.window_height = 12, 0.65, 1200
editor.tools.scroll = 0
commands = compose()
contained()
tab_sets(commands, 1, 0)
local filled = assert(editor.tools.bounds)
assert(filled.h > 300, 'Tall editor retained an arbitrary dock height cap')
assert(document.height - editor.grid_max == 8, 'Tall dock did not retain its normal eight-row grid viewport')
local lowest_swatch = math.huge
for _, command in ipairs(commands) do
    if
        command.ui_role == 'swatch_fill'
        and not command.popup
        and command.x >= menu.window_bounds.x + filled.x * menu.window_bounds.scale
        and command.x < menu.window_bounds.x + (filled.x + filled.w) * menu.window_bounds.scale
    then
        lowest_swatch = math.min(lowest_swatch, command.y)
    end
end
local gap_below_grid = (lowest_swatch - menu.window_bounds.y) / menu.window_bounds.scale - filled.y - filled.h
assert(math.abs(gap_below_grid - 47) < 0.01, 'Dock left unused height below the grid navigation/padding')
local tools_footer = assert(label(commands, 'Tools', false))
assert(
    (menu.window_bounds.y + filled.y * menu.window_bounds.scale - tools_footer.y) / menu.window_bounds.scale < 50,
    'Dock left unused height above the persistent footer'
)
menu.font_size, menu.ui_scale, menu.window_height = 12, 1, 1000
local current = document
document = nil
editor.sync()
editor.tools.scroll = 0
commands = compose()
tab_sets(commands, 1, 0)
assert(label(commands, 'Import Paydex JSON...', false), 'Rows JSON import requires an active LUT')
click('Import Paydex JSON...', false)
assert(imports == 1)
import_control.disabled = true
click('Import Paydex JSON...', false)
assert(imports == 1, 'Busy Paydex import button still activated')
import_control.disabled = false
click('Undock', false)
commands = compose()
tab_sets(commands, 1, 1)
assert(
    editor.tools.is_open() and not editor.tools.is_docked() and not editor.tools.bounds,
    'Undock closed Tools or kept stale wheel bounds'
)
local floating
for _, window in ipairs(menu.floating_windows) do
    if window.id == 'editor_tools' then
        floating = window
    end
end
assert(floating and editor.tools.tab == 'rows' and label(commands, 'Dock', true), 'Undock lost tabs/window controls')
document = current
assert(ffi.string(document.data, document.width * document.height * 16) == initial_pixels)
editor.tools.close()
commands = compose()
tab_sets(commands, 0, 0)
assert(
    label(commands, 'Tools', false) and label(commands, 'Scratch', false),
    'Closing Tools removed persistent footer actions'
)
assert(not editor.tools.bounds, 'Closed Tools retained dock wheel ownership')
package.loaded['epic.player_preview.v1'] = prior_preview
print(
    'PASS Tools docking: shared tabs/state, scroll containment, exact no-apply, docked dropdown ownership, independent Pattern/preview, font/scale variants and busy JSON import'
)
