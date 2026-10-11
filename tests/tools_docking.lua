-- Actual menu/controller coverage for the shared floating and docked Tools.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local disk, writes, fail_save, notes = {}, 0, false, {}
local store = {
    load = function(id)
        return disk[id] or {}
    end,
    save = function(id, values)
        if fail_save and id == 'epic_lut_preferences' then
            return false, 'Preference save unavailable'
        end
        writes = writes + 1
        disk[id] = values
        return true
    end,
}
local api = Core.new(store)
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
    notes[#notes + 1] = value
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
    button('imported_map_gear'),
    button('imported_map_armor'),
    button('imported_map_helmet'),
    button('imported_map_cape'),
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
local preferences = dofile('src/platform/preferences.lua').new()
local mount_writes = writes
preferences.mount(api)
editor.tools.mount_preferences(preferences)
assert(preferences.tools_docked() and writes == mount_writes, 'Default Tools layout read/mount wrote preferences')
assert(editor.tools.is_open() and editor.tools.tab == 'import', 'Docked Tools did not start open on Import')
local function restored_layout(expected)
    local count = writes
    local restored_preferences = dofile('src/platform/preferences.lua').new()
    restored_preferences.mount(Core.new(store))
    local restored_tools = modules.editor_tools.new({
        editor = editor,
        document = function()
            return document
        end,
        default_open_docked = true,
    })
    restored_tools.mount_preferences(restored_preferences)
    assert(
        restored_tools.is_open() == expected and restored_tools.tab == 'import',
        'Startup Tools visibility did not follow the saved Dock preference'
    )
    restored_tools.close()
    restored_tools.mount_preferences(restored_preferences)
    assert(not restored_tools.is_open(), 'Preference remount reopened manually closed Tools')
    restored_tools.open('rows')
    restored_tools.mount_preferences(restored_preferences)
    assert(restored_tools.is_open() and restored_tools.tab == 'rows', 'Preference remount reset an active Tools tab')
    assert(
        restored_preferences.tools_docked() == expected and restored_tools.is_docked() == expected,
        'Tools layout did not survive a new preferences/controller instance'
    )
    assert(writes == count, 'Reading/restoring Tools layout wrote or replaced the saved choice')
end
do
    local utility = modules.editor_tools.new({
        editor = editor,
        document = function()
            return document
        end,
    })
    utility.mount_preferences(preferences)
    assert(not utility.is_open(), 'Generic Tools utility unexpectedly opted into editor startup visibility')
    local restored = modules.editor_tools.new({
        editor = editor,
        document = function()
            return document
        end,
        default_open_docked = true,
    })
    restored.mount_preferences({
        tools_docked = function()
            return false
        end,
    })
    assert(not restored.is_open() and not restored.is_docked(), 'Saved Undock auto-opened a floating window')
    restored.set_docked(true)
    assert(not restored.is_open(), 'Redocking reopened closed Tools without an explicit open action')
    restored.open('rows')
    restored.close()
    restored.mount_preferences(preferences)
    assert(not restored.is_open(), 'Later preference attachment lost the session close choice')
end
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
local function docking_icon(commands, popup)
    local left, bottom, right, top, count = math.huge, math.huge, -math.huge, -math.huge, 0
    for _, c in ipairs(commands) do
        if
            c.type == 'rect'
            and c.ui_role == 'control_icon'
            and not not c.popup == popup
            and (not popup or c.floating_id == 'editor_tools')
        then
            left, bottom = math.min(left, c.x), math.min(bottom, c.y)
            right, top = math.max(right, c.x + c.w), math.max(top, c.y + c.h)
            count = count + 1
        end
    end
    assert(count >= 2 and right > left and top > bottom, 'Docking window icon missing')
    return { x = left, y = bottom, w = right - left, h = top - bottom }
end
local function click_icon(popup, mode)
    local commands = compose()
    local icon = docking_icon(commands, popup)
    local x, y = icon.x + icon.w / 2, icon.y + icon.h / 2
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
    compose()
    menu.tooltip_started = -1
    local helped = false
    for _, c in ipairs(compose()) do
        helped = helped or c.type == 'text' and (c.full_text or c.text or ''):find('^' .. mode .. ':') ~= nil
    end
    assert(helped, 'Docking icon hover lost its action tooltip: ' .. mode)
    local position = menu.floating_positions and menu.floating_positions.editor_tools
    local old_x, old_y = position and position.x, position and position.y
    tap(x, y)
    assert(
        menu.visible and editor.tools.is_open() and not menu.is_interacting(),
        'Docking icon dragged/closed the window'
    )
    assert(not position or position.x == old_x and position.y == old_y, 'Docking icon moved the floating window')
end
local initial_pixels = ffi.string(document.data, document.width * document.height * 16)
local startup_commands = compose()
assert(editor.tools.bounds and label(startup_commands, 'Import', false), 'Startup dock did not render its Import tab')
for _, window in ipairs(menu.floating_windows or {}) do
    assert(window.id ~= 'editor_tools', 'Startup dock created a floating Tools window')
end
editor.tools.open('rows')
assert(editor.tools.is_docked(), 'Tools did not start docked by default')
compose()
local initial_bounds = assert(editor.tools.bounds)
local before_layout = writes
fail_save = true
click_icon(false, 'Undock')
assert(
    editor.tools.is_docked() and writes == before_layout and preferences.tools_docked(),
    'Failed Tools layout save changed or persisted the layout'
)
assert(
    notes[#notes] == 'Could not save Tools layout: Preference save unavailable'
        and editor.tools.bounds.x == initial_bounds.x
        and editor.tools.bounds.y == initial_bounds.y
        and editor.tools.bounds.w == initial_bounds.w
        and editor.tools.bounds.h == initial_bounds.h,
    'Failed Tools layout save lost its error or changed geometry'
)
fail_save = false
click_icon(false, 'Undock')
assert(
    writes == before_layout + 1 and disk.epic_lut_preferences.tools_docked == false,
    'Actual Undock icon did not persist exactly one choice'
)
restored_layout(false)
do
    local floating_rows = compose()
    local icon = docking_icon(floating_rows, true)
    local close = assert(label(floating_rows, 'X', true))
    local window = assert(menu.floating_bounds)
    assert(
        icon.x + icon.w < close.x and icon.y + icon.h <= window.y + window.h,
        'Floating Dock icon is not in the header beside Close'
    )
    local title = assert(label(floating_rows, 'LUT Editor Tools', true))
    assert(
        icon.y < title.y + title.size and icon.y + icon.h > title.y,
        'Floating Dock icon is not aligned with the title bar'
    )
    local previous = assert(label(floating_rows, 'my-row', true))
    for _, name in ipairs({
        'Save selected row',
        'Apply preset to row',
        'Copy row',
        'Reset row',
        'Import Paydex JSON...',
    }) do
        local current = assert(label(floating_rows, name, true))
        assert(
            previous.y > current.y + current.size
                or math.abs(previous.y - current.y) < 0.01
                    and previous.x + #previous.text * previous.size * 0.5 < current.x,
            'Rows controls are out of order/overlap: ' .. name
        )
        previous = current
    end
end
click_icon(true, 'Dock')
assert(
    writes == before_layout + 2 and disk.epic_lut_preferences.tools_docked == true,
    'Actual Dock icon did not persist exactly one choice'
)
restored_layout(true)
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
    local footer_title =
        assert(label(compose(), 'LUT Editor Tools', false), 'Docked Tools heading did not move into the footer')
    assert(footer_title.y + footer_title.size < wb.y + b.y * scale, 'Docked Tools title still occupies body height')
    for _, c in ipairs(compose()) do
        if c.type == 'text' and (c.full_text or c.text) == 'LUT Editor Tools' then
            assert(c.y == footer_title.y, 'Duplicate Tools title remains in the docked body')
        end
    end
    for _, command in ipairs(compose()) do
        if
            command.ui_role == 'swatch_fill'
            and not command.popup
            and command.x >= wb.x + b.x * scale
            and command.x < wb.x + (b.x + b.w) * scale
        then
            local preview = editor.tools.row_preview_bounds
            local in_preview = preview
                and preview.document
                and preview.document.read_only
                and command.x >= wb.x + preview.x * scale
                and command.x + command.w <= wb.x + (preview.x + preview.w) * scale + 0.01
                and command.y >= wb.y + preview.y * scale
                and command.y + command.h <= wb.y + (preview.y + preview.h) * scale + 0.01
            assert(
                in_preview or command.y >= wb.y + (b.y + b.h) * scale,
                'An actual swatch renders through docked Tools'
            )
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
menu.window_height = 820
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
menu.window_height = 1000
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
    docking_icon(compose(), false)
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
click_icon(false, 'Undock')
commands = compose()
tab_sets(commands, 0, 1)
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
assert(floating and editor.tools.tab == 'rows' and docking_icon(commands, true), 'Undock lost tabs/window controls')
document = current
assert(ffi.string(document.data, document.width * document.height * 16) == initial_pixels)
click_icon(true, 'Dock')
commands = compose()
local closing_bounds = assert(editor.tools.bounds)
local close_button
for _, c in ipairs(commands) do
    if
        c.type == 'text'
        and (c.full_text or c.text) == 'X'
        and not c.popup
        and c.x >= menu.window_bounds.x + closing_bounds.x * menu.window_bounds.scale
        and c.x < menu.window_bounds.x + (closing_bounds.x + closing_bounds.w) * menu.window_bounds.scale
        and c.y >= menu.window_bounds.y + closing_bounds.y * menu.window_bounds.scale
    then
        close_button = c
    end
end
assert(close_button, 'Docked Tools lost its visible Close control')
tap(close_button.x + 2, close_button.y + 2)
assert(not editor.tools.is_open() and menu.visible, 'Dock Close dismissed the whole editor instead of Tools')
commands = compose()
tab_sets(commands, 0, 0)
assert(
    label(commands, 'Tools', false) and label(commands, 'Scratch', false),
    'Closing Tools removed persistent footer actions'
)
assert(not editor.tools.bounds, 'Closed Tools retained dock wheel ownership')
local original_pages = mod.pages
mod.pages = { original_pages[1], { id = 'other', name = 'Other', controls = {}, pending = {}, actions = {} } }
menu.page = 2
compose()
menu.page = 1
compose()
mod.pages = original_pages
assert(not editor.tools.is_open(), 'Returning to LUT Editor reopened manually closed Tools')
-- Wide Tools retain their frame space, but navigation and individual controls
-- use bounded/content-sized widths. Efficient action groups share a row.
local palette_control = mod.controls.palette
palette_control.choices = {}
for index = 1, 32 do
    palette_control.choices[index] = 'Imported LUT ' .. index
end
local browse_hits = 0
local mapped = {}
mod.controls.browse.on_activate = function()
    browse_hits = browse_hits + 1
end
mod.controls.imported_map_gear.on_activate = function()
    mapped[#mapped + 1] = 'gear'
end
assert(handle.set('value_editor_visible', false))
editor.tools.split_ratio = 0.75
editor.tools.set_docked(true)
for _, font in ipairs({ 12, 20 }) do
    for _, canvas_width in ipairs({ 1200, 2200 }) do
        menu.font_size, menu.window_width, menu.window_height, menu.ui_scale = font, canvas_width, 1200, 0.7
        for _, tab in ipairs({ 'import', 'rows', 'export', 'options' }) do
            editor.tools.open(tab)
            editor.tools.scroll = 0
            local commands = compose()
            local outer, content, wb =
                assert(editor.tools.bounds), assert(editor.tools.content_bounds), menu.window_bounds
            local function body_label(value)
                for _, c in ipairs(commands) do
                    if
                        c.full_text == value
                        and not c.popup
                        and c.x >= wb.x + content.x * wb.scale
                        and c.x < wb.x + (content.x + content.w) * wb.scale
                        and c.y >= wb.y + content.y * wb.scale
                        and c.y <= wb.y + (content.y + content.h) * wb.scale
                    then
                        return c
                    end
                end
            end
            assert(
                content.w <= 760 and content.x + content.w <= outer.x + outer.w,
                'Tools expandable content consumes a giant full-pane width'
            )
            local previous
            for _, bounds in ipairs(editor.tools.tab_bounds) do
                assert(
                    bounds.w <= 180 and bounds.x >= outer.x and bounds.x + bounds.w <= outer.x + outer.w,
                    'Tools tab escaped its content-sized header width cap'
                )
                if previous and math.abs(previous.y - bounds.y) < 0.01 then
                    assert(previous.x + previous.w < bounds.x, 'Content-sized Tools tabs overlap')
                end
                previous = bounds
            end
            for _, c in ipairs(commands) do
                if
                    c.type == 'rect'
                    and c.ui_role == 'control_fill'
                    and not c.popup
                    and c.x >= wb.x + content.x * wb.scale
                    and c.x < wb.x + (content.x + content.w) * wb.scale
                    and c.y >= wb.y + content.y * wb.scale
                    and c.y + c.h <= wb.y + (content.y + content.h) * wb.scale
                then
                    assert(c.w / wb.scale <= 760 + 0.01, 'Tools body control escaped its width cap')
                end
            end
            if tab == 'import' then
                local import = assert(body_label('Import DDS / ZIP / RAR...'))
                local load = assert(body_label('Load Current Gear'))
                if canvas_width == 2200 then
                    assert(
                        math.abs(import.y - load.y) < 0.01 and import.x + #import.text * import.size * 0.5 < load.x,
                        'Wide Tools wasted a second row for compact import/load actions'
                    )
                    local source = assert(label(commands, 'Imported LUT 1', false))
                    local preview = assert(label(commands, 'Preview Palette', false))
                    local send = assert(label(commands, 'Send to LUT Editor', false))
                    assert(math.abs(preview.y - send.y) < 0.01, 'Wide Tools Preview/Send actions were not packed')
                    tap(import.x + 2, import.y + 2)
                    assert(browse_hits > 0, 'Content-sized Tools import button lost its hit target')
                    tap(source.x + 2, source.y + 2)
                    assert(
                        menu.dropdown and menu.dropdown.control.id == 'palette',
                        'Bounded Tools source dropdown did not open'
                    )
                    assert(menu.dropdown.width <= 760, 'Tools source popup restored an unbounded width')
                    menu.key(27)
                    local target =
                        assert(body_label('Map LUTs to Gear'), 'Tools shared Gear mapping chooser is missing')
                    local before = #mapped
                    tap(target.x + 2, target.y + 2)
                    assert(
                        #mapped == before + 1 and mapped[#mapped] == 'gear',
                        'Tools mapping hit bypassed the shared Gear chooser'
                    )
                    for _, old in ipairs({ 'Map LUTs to Armor', 'Map LUTs to Helmet', 'Map LUTs to Cape' }) do
                        assert(not body_label(old), 'Tools still exposes duplicate per-kind mapping actions')
                    end
                end
            elseif tab == 'rows' and canvas_width == 2200 then
                local save = assert(label(commands, 'Save selected row', false))
                local apply = assert(label(commands, 'Apply preset to row', false))
                assert(
                    math.abs(save.y - apply.y) < 0.01 and save.x + #save.text * save.size * 0.5 < apply.x,
                    'Wide Tools row-preset actions did not share a readable row'
                )
            elseif tab == 'options' then
                local target = assert(body_label('Map LUTs to Gear'), 'Tools Options lost the shared Gear chooser')
                local before = #mapped
                tap(target.x + 2, target.y + 2)
                assert(
                    #mapped == before + 1 and mapped[#mapped] == 'gear',
                    'Tools Options mapping routes through a different callback'
                )
                for _, old in ipairs({ 'Map LUTs to Armor', 'Map LUTs to Helmet', 'Map LUTs to Cape' }) do
                    assert(not body_label(old), 'Tools Options retained duplicate per-kind mapping actions')
                end
            end
        end
    end
end
assert(
    ffi.string(document.data, document.width * document.height * 16) == initial_pixels,
    'Tools responsive navigation/layout changed LUT pixels'
)
package.loaded['epic.player_preview.v1'] = prior_preview
print(
    'PASS Tools widths: measured capped tabs, bounded fields/actions, packed semantic pairs,32-source dropdown anchors and actual hits across wide/narrow panes and fonts'
)
print(
    'PASS Tools docking: persisted docked default and icon choices, no-write restoration/save failure, actual window icons/header tooltips, shared tabs/state, scroll containment, exact no-apply, docked dropdown ownership, independent Pattern/preview, font/scale variants and busy JSON import'
)
