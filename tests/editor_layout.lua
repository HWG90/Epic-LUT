-- Exercise the actual menu composer and its hit targets, not a second layout implementation.
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
local document = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
for i = 0, 23 * 8 * 4 - 1 do
    document.data[i] = (i % 17) / 16
end
local exports = {}
local debug_loads = 0
local modules = {
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    scratch_tool = dofile('src/editor/scratch_tool.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    ui_core = core,
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(
    modules,
    function()
        return document
    end,
    function(value)
        return value
    end,
    function(name)
        exports[#exports + 1] = { name = name, kind = 'dds' }
        return true
    end,
    'tests/tmp/presets',
    nil,
    function()
        return true
    end,
    function(name, all)
        exports[#exports + 1] = { name = name, kind = all and 'all' or 'selected' }
        return true
    end,
    function(name, naming)
        exports[#exports + 1] = { name = name, kind = 'bulk', naming = naming }
        return true
    end
)
local pages = editor.pages()
local pattern = dofile('src/editor/pattern_luts.lua').new({
    session = {
        owned = {},
        restore = function()
            return true
        end,
    },
    discover = function()
        return {}
    end,
    key = tostring,
    binding = function()
        return nil
    end,
    original = function()
        return nil
    end,
    rgb = modules.palette.rgb,
    swatch = modules.palette.swatch,
    resource_id = tostring,
    note = function(value)
        return value
    end,
    export = function()
        return true
    end,
})
for _, control in ipairs(pattern.controls()) do
    pages[1].controls[#pages[1].controls + 1] = control
end
table.insert(pages, 1, {
    id = 'import',
    name = 'Import / Apply',
    require_confirmation = false,
    controls = {
        {
            id = 'lut',
            type = 'choice',
            presentation = 'dropdown',
            label = 'Live LUT',
            choices = { 'Armor LUT 1' },
            default = 1,
        },
        { id = 'palette', type = 'choice', label = 'Imported LUT', choices = { 'lut001.dds' }, default = 1 },
        { id = 'target_armor', type = 'toggle', label = 'Armor', default = true },
        { id = 'target_helmet', type = 'toggle', label = 'Helmet', default = true },
        {
            id = 'browse',
            type = 'button',
            label = 'Import',
            on_activate = function()
                return true
            end,
        },
        {
            id = 'save_palette',
            type = 'button',
            label = 'Send to LUT Editor',
            on_activate = function()
                return true
            end,
        },
        {
            id = 'apply_editor',
            type = 'button',
            label = 'Apply',
            on_activate = function()
                return true
            end,
        },
        {
            id = 'restore',
            type = 'button',
            label = 'Restore Original',
            on_activate = function()
                return true
            end,
        },
        {
            id = 'reset_custom',
            type = 'button',
            label = 'Reset Custom',
            on_activate = function()
                return true
            end,
        },
        {
            id = 'save_setup',
            type = 'button',
            label = 'Save applied setup',
            on_activate = function()
                return true
            end,
        },
        {
            id = 'load_debug_lut',
            type = 'button',
            label = 'Load Debug LUT',
            on_activate = function()
                debug_loads = debug_loads + 1
                return true
            end,
        },
    },
})
local handle = api.register({ id = 'editor_layout', name = 'Epic LUT', pages = pages })
editor.attach(api, handle)
pattern.attach(handle, api.mods[handle.id].controls)
editor.pattern_editor = pattern
api.mods[handle.id].tabs_top = true
local menu = dofile('vendor/menu/menu.lua').new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.selected, menu.page = true, 1, 2
menu.window_width, menu.window_height = 1800, 1000
menu.compact_fonts = true
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('Editor control missing:', 1, true)), command.text)
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    return commands
end
local function label(commands, text)
    for _, command in ipairs(commands) do
        if command.full_text == text or command.text == text then
            return command
        end
    end
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
local function tap(x, y)
    input(x, y, true)
    input(x, y, false)
end
local function tap_label(text)
    local command = assert(label(compose(), text), 'Missing usable control: ' .. text)
    tap(command.x + 3, command.y + 2)
end

local commands = compose()
assert(not editor.preview_inspector and not editor.mesh_popup, 'Removed preview debug inspector was initialized')
local header = assert(label(commands, 'v Row 1') or label(commands, '> Row 1'))
input(header.x + 80, header.y + 3, false)
for _, command in ipairs(compose()) do
    assert(type(command.a) == 'number', 'Hovered row leaked its boolean state into renderer opacity')
end
-- These compact controls are ordinary dropdowns, including the right edge
-- formerly reserved for steppers. Exercise the actual editor composer.
for _, item in ipairs({ { 'Select', 'grid_tool' }, { 'RGB', 'grid_channel' }, { 'Armor LUT 1', 'lut' } }) do
    local field = assert(label(commands, item[1]))
    local caret
    for _, command in ipairs(commands) do
        if
            command.type == 'text'
            and math.abs(command.y - field.y) < 0.1
            and command.x > field.x
            and command.x < field.x + field.text_width + 40 * menu.window_bounds.scale
        then
            assert(command.text ~= '<' and command.text ~= '>', 'LUT toolbar dropdown still has steppers: ' .. item[2])
            if command.text == 'v' then
                caret = command
            end
        end
    end
    assert(caret, 'LUT toolbar dropdown lost its caret: ' .. item[2])
    local previous = handle.get(item[2])
    tap(caret.x + 2, caret.y + 2)
    assert(
        menu.dropdown and menu.dropdown.control.id == item[2] and handle.get(item[2]) == previous,
        'LUT toolbar right edge stepped rather than opened: ' .. item[2]
    )
    menu.key(27)
    commands = compose()
end
assert(editor.grid_bounds and editor.grid_bounds.h >= 480, 'Removed tool panels did not return usable grid height')
assert(editor.value_bounds and label(commands, 'Value Editor'), 'Value editor missing initially')
assert(not label(commands, 'Scratch Pixel'), 'Closed Scratch still occupies the editor')
local initial_width = editor.grid_bounds.w
local value = editor.value_bounds
tap_label('Hide Values')
commands = compose()
assert(not editor.value_bounds, 'Hidden inspector retained active scroll bounds')
assert(editor.grid_bounds.w >= initial_width + 400, 'Hiding inspector failed to return its usable width')
assert(not label(commands, 'Value Editor'), 'Hidden inspector still rendered')
-- The former inspector region now belongs to the grid, not its old value scroll handler.
editor.value_scroll = 0
editor.wheel(value.x + 10, value.y + 20, -120)
assert(editor.value_scroll == 0, 'Collapsed inspector still consumed wheel input')
tap_label('Show Values')
compose()
assert(editor.value_bounds and editor.grid_bounds.w == initial_width, 'Restoring Values did not restore layout')

local function palette_cells(commands)
    local counts, maximum = {}, 0
    for _, command in ipairs(commands) do
        if command.popup and command.type == 'rect' then
            local key = string.format('%.3f:%.3f', command.w, command.h)
            counts[key] = (counts[key] or 0) + 1
            maximum = math.max(maximum, counts[key])
        end
    end
    return maximum
end
local closed_count = #compose()
for _, hidden in ipairs({ 'Import', 'Rows', 'Export', 'Options' }) do
    assert(not label(compose(), hidden), 'Closed Tools left a child shortcut visible: ' .. hidden)
end
local function shortcut_color(text)
    local commands = compose()
    for i, command in ipairs(commands) do
        if not command.popup and command.full_text == text then
            local surface = commands[i - 1]
            assert(surface and surface.type == 'rect', 'No shortcut surface: ' .. text)
            return table.concat(surface.c, ':')
        end
    end
    error('No shortcut surface: ' .. text)
end
tap_label('Tools')
commands = compose()
assert(editor.tools.is_open() and menu.floating_bounds, 'Tools button did not open an actual floating window')
assert(shortcut_color('Import') ~= shortcut_color('Rows'), 'Active tool shortcut is not highlighted')
tap_label('Tools')
assert(editor.tools.is_open(), 'Re-clicking Tools closed its window')
tap_label('Import')
tap_label('Import')
assert(editor.tools.is_open() and editor.tools.tab == 'import', 'Clicking an active shortcut closed its popout')
tap_label('Scratch')
commands = compose()
assert(
    editor.scratch_tool.is_open() and editor.tools.is_open() and editor.tools.tab == 'import',
    'Scratch shortcut replaced or closed Toolbox'
)
assert(
    label(commands, 'LUT Editor Tools') and label(commands, 'Scratch Pixel'),
    'Both independent windows did not compose'
)
assert(palette_cells(commands) >= 400, 'Open Scratch did not render its 20 by 20 color palette')
local original_hsv, hsv_calls = core.hsv_rgb, 0
core.hsv_rgb = function(...)
    hsv_calls = hsv_calls + 1
    return original_hsv(...)
end
compose()
assert(hsv_calls <= 20, 'Scratch rebuilt its 400 cached palette colors without a hue change')
-- Keep both surfaces apart while testing their independent ownership.
menu.floating_positions.editor_tools.x, menu.floating_positions.editor_tools.y = 650, 250
menu.floating_positions.editor_scratch.x, menu.floating_positions.editor_scratch.y = 1340, 400
commands = compose()
local scratch_window
for _, window in ipairs(menu.floating_windows or {}) do
    if window.id == 'editor_scratch' then
        scratch_window = window
    end
end
assert(scratch_window and #menu.floating_windows == 2, 'Composer did not retain both floating owners')
local scale = menu.window_bounds.scale
local alpha_x = scratch_window.x + 392 * scale
local alpha_y = scratch_window.y + (95 + 253 * 0.25) * scale
tap(alpha_x, alpha_y)
assert(
    math.abs(handle.get('scratch_alpha') - 0.25) < 0.02,
    'Independent Scratch alpha did not update the shared control'
)
assert(editor.tools.is_open() and editor.scratch_tool.is_open(), 'Scratch interaction closed Toolbox')

tap_label('Rows')
assert(editor.tools.tab == 'rows')
local preset_arrow
for _, command in ipairs(compose()) do
    if command.popup and command.text == 'v' then
        preset_arrow = command
    end
end
assert(preset_arrow, 'Rows preset dropdown has no rendered arrow')
tap(preset_arrow.x + 2, preset_arrow.y + 2)
assert(
    menu.dropdown and menu.dropdown.control.id == 'row_preset_select' and menu.dropdown.owner,
    'Rows preset dropdown did not inherit its Tools owner'
)
commands = compose()
local above = false
for _, command in ipairs(commands) do
    if command.popup and command.layer == 230 and command.text then
        above = true
    end
end
assert(above, 'Rows preset dropdown is behind Tools')
local title = assert(label(commands, 'LUT Editor Tools'))
local before_x, before_top = menu.dropdown.x, menu.dropdown.top
input(title.x + 60, title.y + 3, true)
input(title.x - 10, title.y + 23, true)
input(title.x - 10, title.y + 23, false)
compose()
assert(
    menu.dropdown and menu.dropdown.x < before_x and menu.dropdown.top > before_top,
    'Dragging Tools did not carry the preset dropdown with it'
)
menu.key(27)
assert(not menu.dropdown and menu.visible, 'Dismissing preset dropdown closed the editor')
assert(handle.set('edit_row', 1))
local copied_row = ffi.string(document.data, document.width * 16)
tap_label('Copy row')
assert(handle.set('edit_row', 2))
tap_label('Paste row')
assert(
    ffi.string(document.data + document.width * 4, document.width * 16) == copied_row,
    'Row tools did not paste every raw RGBA value into the chosen row'
)
assert(handle.activate('undo'))
tap_label('Export')
commands = compose()
assert(
    editor.tools.tab == 'export' and editor.scratch_tool.is_open() and palette_cells(commands) >= 400,
    'Changing Toolbox tabs hid the independent Scratch window'
)

-- Preserve the user's export format selector and invoke its existing export callback.
local formats = api.mods[handle.id].controls.export_format.choices
assert(formats[1] == 'DDS' and formats[2] == 'Selected LUT Patch' and formats[3] == 'Entire Palette Patch')
assert(label(commands, 'DDS'), 'Export selector is absent from Tools')
tap_label('DDS')
assert(menu.dropdown and menu.dropdown.control.id == 'export_format', 'Export selector cannot open its dropdown')
menu.key(40)
menu.key(40)
menu.key(13)
assert(handle.get('export_format') == 3, 'Export selector no longer selects an entire palette patch')
tap_label('Export...')
assert(#exports == 1 and exports[1].kind == 'all', 'Export Tools bypassed the existing entire-palette exporter')
assert(formats[4] == 'All Custom LUTs (DDS)', 'Bulk DDS format was not appended without renumbering old choices')
for _, format in ipairs({ 1, 2, 3 }) do
    assert(handle.set('export_format', format))
    assert(not label(compose(), 'LUT# + HEX'), 'DDS naming leaked into a different export format')
end
assert(handle.set('export_format', 1))
tap_label('Export...')
assert(exports[2].kind == 'dds', 'DDS format stopped invoking its original exporter')
assert(handle.set('export_format', 2))
tap_label('Export...')
assert(exports[3].kind == 'selected', 'Selected patch format stopped invoking its original exporter')
assert(handle.set('export_format', 4))
tap_label('LUT# + HEX')
assert(menu.dropdown and menu.dropdown.control.id == 'dds_naming', 'Bulk naming chooser did not open')
for i = 1, 4 do
    menu.key(40)
end
menu.key(13)
assert(handle.get('dds_naming') == 5, 'Bulk naming dropdown did not choose Decimal')
tap_label('Export...')
assert(exports[4].kind == 'bulk' and exports[4].naming == 5, 'Bulk DDS callback lost the selected naming policy')
for _, font in ipairs({ 12, 20 }) do
    menu.font_size = font
    local bulk_commands = compose()
    local naming = assert(label(bulk_commands, 'Decimal'))
    local export = assert(label(bulk_commands, 'Export...'))
    local folder = assert(label(bulk_commands, 'Open Export Location'))
    assert(
        naming.y > export.y + export.size and export.y > folder.y + folder.size,
        'Bulk naming/Export/Folder controls collide after font resizing'
    )
end
local current_doc = document
document = nil
editor.sync()
tap_label('Export...')
assert(exports[5].kind == 'bulk' and exports[5].naming == 5, 'Bulk DDS was disabled without an active editor table')
document = current_doc
editor.sync()
menu.font_size = 12

local function close_window(id)
    compose()
    local window
    for _, item in ipairs(menu.floating_windows or {}) do
        if item.id == id then
            window = item
        end
    end
    assert(window, 'Missing close target: ' .. id)
    tap(window.x + window.w - 12 * menu.window_bounds.scale, window.y + window.h - 16 * menu.window_bounds.scale)
end
close_window('editor_tools')
commands = compose()
assert(
    not editor.tools.is_open() and editor.scratch_tool.is_open() and menu.floating_bounds,
    'Closing Toolbox also closed Scratch'
)
assert(palette_cells(commands) >= 400 and not label(commands, 'Rows'), 'Toolbox close did not remove only its flyout')
close_window('editor_scratch')
local before_closed = hsv_calls
commands = compose()
assert(not menu.floating_bounds and not editor.scratch_tool.is_open(), 'Scratch close retained floating input capture')
assert(
    palette_cells(commands) < 400 and hsv_calls == before_closed,
    'Closed Scratch still composes or polls its palette'
)
core.hsv_rgb = original_hsv
-- Flyout targets fit between Tools and the stable right-side footer controls.
menu.text_metrics = function(size, text)
    local descends = text and text:find('[gjpqy]')
    return {
        min_y = descends and -size * 0.25 or 0,
        max_y = size * 0.75,
        height = descends and size or size * 0.75,
    }
end
local footer_padding_ratio
for _, settings in ipairs({ { 12, 1, 1800 }, { 20, 0.85, 1420 }, { 20, 0.85, 1100 } }) do
    menu.font_size, menu.ui_scale, menu.window_width = settings[1], settings[2], settings[3]
    editor.tools.open('rows')
    commands = compose()
    local tools_label = assert(label(commands, 'Tools'))
    local ink = menu.text_metrics(tools_label.size, 'Tools')
    local body
    for i = #commands, 1, -1 do
        local command = commands[i]
        if
            command.type == 'rect'
            and command.c[1] == 244
            and command.c[2] == 202
            and command.w > 40
            and command.h >= ink.height
            and command.x <= tools_label.x
            and command.x + command.w >= tools_label.x
            and command.y <= tools_label.y + ink.min_y
            and command.y + command.h >= tools_label.y + ink.max_y
        then
            body = command
            break
        end
    end
    assert(body, 'Footer control body missing')
    local bottom = tools_label.y + ink.min_y - body.y
    local upper = body.y + body.h - tools_label.y - ink.max_y
    assert(math.abs(bottom - upper) < 0.01, 'Footer visible ink is not vertically centered')
    local ratio = bottom / tools_label.size
    assert(
        not footer_padding_ratio or math.abs(ratio - footer_padding_ratio) < 0.01,
        'Font resizing lost footer padding'
    )
    footer_padding_ratio = ratio
    assert(editor.grid_bounds.y >= body.y + body.h, 'Growing footer overlaps the pixel grid')
    local previous = assert(label(commands, 'Tools'))
    for _, child in ipairs({ 'Import', 'Rows', 'Export', 'Options', 'Scratch', 'Hide Values' }) do
        local current = assert(label(commands, child), 'Footer child missing at scale: ' .. child)
        assert(
            current.x > previous.x and previous.x + previous.text_width <= current.x,
            'Footer labels collide at larger fonts: ' .. child
        )
        previous = current
    end
    assert(shortcut_color('Rows') ~= shortcut_color('Import'), 'Flyout lost its active child highlight')
    editor.tools.close()
    commands = compose()
    assert(
        not label(commands, 'Import') and label(commands, 'Scratch'),
        'Closed flyout retained children or removed Scratch'
    )
end
menu.text_metrics = nil
menu.font_size, menu.ui_scale, menu.window_width, menu.window_height = 12, 1, 1800, 1000

-- A custom table can reach its last row after the inspector is collapsed.
document = { width = 23, height = 32, data = ffi.new('float[?]', 23 * 32 * 4) }
editor.sync()
tap_label('Hide Values')
editor.focus_cell(32, 23)
commands = compose()
assert(label(commands, 'Row 32') and editor.grid_first > 1, 'Expanded custom grid cannot reach its last row')
assert(editor.grid_max > 0 and not editor.value_bounds, 'Custom grid scrolling revived the hidden inspector')

-- Imported and Pattern tools remain reachable before a regular LUT is loaded.
document = nil
editor.sync()
tap_label('Tools')
tap_label('Options')
assert(label(compose(), 'Load Debug LUT'), 'Debug LUT is inaccessible without an imported table')
tap_label('Load Debug LUT')
assert(debug_loads == 1 and editor.tools.tab == 'options', 'Options debug action is not clickable')
assert(not label(compose(), 'Preview Materials / Meshes'), 'Removed preview debugging control remains in Options')
tap_label('Import')
commands = compose()
assert(
    editor.tools.is_open() and editor.tools.tab == 'import' and label(commands, 'Import DDS / ZIP / RAR...'),
    'Empty editor returned before composing Import tools'
)
pattern.show('armor')
commands = compose()
assert(
    editor.tools.is_open()
        and pattern.open
        and menu.floating_bounds
        and label(commands, 'Pattern LUT Editor')
        and label(commands, 'LUT Editor Tools'),
    'Opening Pattern closed or replaced the independent Toolbox'
)
tap_label('Helmet')
compose()
assert(pattern.gear == 'armor', 'Empty Pattern tabs must stay disabled before data loads')
tap_label('Load Current Patterns')
commands = compose()
assert(
    menu.visible and pattern.open and label(commands, 'No pattern resource selected'),
    'Empty Pattern reload closed the editor or left stale resource data'
)
assert(pattern.import({ width = 3, height = 1, data = ffi.new('float[12]') }))
tap_label('Helmet')
compose()
assert(pattern.gear == 'helmet', 'A valid imported Pattern failed to enable gear selection')
assert(editor.tools.is_open() and pattern.open, 'Pattern interaction closed the independent Toolbox')
editor.tools.close()
compose()
assert(pattern.open, 'Closing Toolbox closed Pattern')
tap_label('Tools')
commands = compose()
assert(
    editor.tools.is_open()
        and pattern.open
        and label(commands, 'Pattern LUT Editor')
        and label(commands, 'LUT Editor Tools'),
    'Opening Toolbox closed the independent Pattern window'
)
editor.scratch_tool.open()
commands = compose()
assert(
    editor.tools.is_open() and pattern.open and editor.scratch_tool.is_open() and #menu.floating_windows == 3,
    'Pattern, Toolbox and Scratch could not coexist'
)
print(
    'PASS editor layout: expandable Toolbox shortcuts, independent Scratch/alpha, popup ownership, lazy palette cache, roomy grid and preserved exports'
)
