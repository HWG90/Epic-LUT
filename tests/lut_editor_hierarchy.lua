-- The production registry/editor combination exercises the gear header branch,
-- including source-declared dropdown styling, rather than a duplicated layout.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local doc = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4), source = 'current-armor.dds' }
for i = 0, 23 * 8 * 4 - 1 do
    doc.data[i] = (i % 13) / 12
end
local m = {
    lut_files = dofile('src/presets/lut_files.lua'),
    lut_editor = dofile('src/editor/lut_editor.lua'),
    basic_state = dofile('src/core/basic_state.lua'),
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
        return doc
    end,
    function(v)
        return v
    end,
    function()
        return true
    end,
    'tests/tmp/hierarchy-presets',
    nil,
    function()
        return true
    end,
    function()
        return true
    end
)
local calls = {}
local armor_document = doc
local cape_document = { width = 23, height = 5, data = ffi.new('float[?]', 23 * 5 * 4), source = 'Cape LUT 1 (worn)' }
local callbacks = setmetatable({}, {
    __index = function(_, key)
        return function(value)
            calls[key] = (calls[key] or 0) + 1
            if key == 'basic_armor_lut_change' then
                doc = value == 3 and cape_document or armor_document
                editor.sync()
            end
            return true
        end
    end,
})
local registry = dofile('src/editor/editor_registry.lua')
local pages = registry.pages(callbacks, { ui_scale = 100, status = 'Ready' })
local editor_pages = editor.pages()
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
    rgb = m.palette.rgb,
    swatch = m.palette.swatch,
    resource_id = tostring,
    note = function(v)
        return v
    end,
    export = function()
        return true
    end,
    current_gear = function()
        return editor.gear
    end,
})
for _, c in ipairs(pattern.controls()) do
    editor_pages[1].controls[#editor_pages[1].controls + 1] = c
end
dofile('src/editor/configuration.lua').append(pages, editor_pages, { api = api })
pages[1].controls[#pages[1].controls + 1] = {
    id = 'include_capes_in_armor_exports',
    type = 'toggle',
    label = 'Include Capes in Armor Exports',
    default = true,
}
local handle = api.register({ id = 'hierarchy', name = 'Epic LUT', pages = pages })
local mod = api.mods[handle.id]
mod.tabs_top = true
editor.attach(api, handle)
pattern.attach(handle, mod.controls)
editor.pattern_editor = pattern
editor.can_select_gear = function()
    return true
end
editor.load_seen = function()
    return true
end
for _, kind in ipairs({ 'armor', 'helmet' }) do
    mod.controls['basic_' .. kind .. '_lut'].choices = { 'LUT 1', 'LUT 2' }
end
mod.controls.basic_armor_lut.choices[3] = 'Cape LUT 1'
mod.controls.basic_armor_lut.choice_details = { '[0x032abc9d5c9040ed]', '[0x032abc9d5c9040ed]', 'CapeSwirl' }
mod.controls.basic_armor_lut.choice_hashes = { '032abc9d5c9040ed', '032abc9d5c9040ed', 'fedcba9876543210' }
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible = true
for i, page in ipairs(mod.pages) do
    if page.id == 'colors' then
        menu.page = i
    end
end
menu.window_height = 1000
menu.compact_fonts = true
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, c in ipairs(commands) do
        assert(type(c.a) == 'number', 'Non-numeric opacity from a composed header or value row')
        assert(
            not (c.text and (c.text:find('Editor control missing:', 1, true) or c.text:find('attempt to ', 1, true))),
            c.text
        )
    end
    return commands
end
local function label(commands, value, popup)
    for i, c in ipairs(commands) do
        if (c.full_text == value or c.text == value) and (popup == nil or not not c.popup == popup) then
            return c, i
        end
    end
    error('Missing actual editor control: ' .. value)
end
local function control(commands, value)
    local text, index = label(commands, value, false)
    local s = menu.window_bounds.scale
    for i = index - 1, 1, -1 do
        local c = commands[i]
        if
            c.type == 'rect'
            and c.h >= 26 * s - 0.1
            and c.h <= 60 * s + 0.1
            and c.w > 40 * s
            and c.x <= text.x
            and c.x + c.w >= text.x + text.text_width - 0.1
            and c.y <= text.y
            and c.y + c.h >= text.y + text.size - 0.1
        then
            return c, text
        end
    end
    error('Missing composed control body: ' .. value)
end
local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
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
local function tap(rect)
    input(rect.x + rect.w / 2, rect.y + rect.h / 2, true)
    input(rect.x + rect.w / 2, rect.y + rect.h / 2, false)
end
local function tap_label(value)
    tap(control(compose(), value))
end
for _, width in ipairs({ 860, 1100, 1600 }) do
    for _, font in ipairs({ 12, 20 }) do
        for _, scale in ipairs({ 0.85, 1 }) do
            menu.window_width, menu.font_size, menu.ui_scale = width, font, scale
            editor.gear = 'armor'
            editor.tools.close()
            editor.tools.tab = 'import'
            editor.scratch_tool.close()
            pattern.open = false
            assert(handle.set('basic_armor_lut', 1))
            local commands = compose()
            local helmet = control(commands, 'Helmet LUT')
            local armor = control(commands, 'Armor LUT')
            local pattern_button = control(commands, 'Pattern LUT Editor')
            local load = control(commands, 'Load Current Gear')
            local selector, selector_text = control(commands, 'LUT 1')
            local tool = control(commands, 'Select')
            local channel = control(commands, 'RGB')
            assert(math.abs(helmet.y - armor.y) < 0.1, 'Helmet/Armor are not adjacent on the main gear header row')
            assert(
                pattern_button.y < armor.y or pattern_button.x > armor.x + armor.w,
                'Pattern control does not follow the gear tabs'
            )
            assert(
                selector.y + selector.h < math.min(helmet.y, pattern_button.y, load.y)
                    and selector.x > helmet.x + 10 * menu.window_bounds.scale,
                'LUT selector is not visibly below and indented from its gear tabs'
            )
            assert(
                tool.y + tool.h < selector.y and math.abs(tool.y - channel.y) < 0.1,
                'Grid tool/channel row was not moved below the gear selector'
            )
            local first_row = label(commands, 'Row 1', false)
            local column = label(commands, 'Base', false)
            assert(
                first_row.y + first_row.size < tool.y and column.y + column.size < tool.y,
                'Wrapped header or selector overlaps the grid'
            )
            local bounds = { helmet, armor, pattern_button, load, selector, tool, channel }
            for i, a in ipairs(bounds) do
                for j = i + 1, #bounds do
                    assert(
                        not overlaps(a, bounds[j]),
                        'Gear hierarchy controls overlap at ' .. width .. 'px / font ' .. font
                    )
                end
            end
            assert(
                selector.c[2] > selector.c[1] and selector.c[3] > selector.c[1] and selector.c[1] < 80,
                'LUT selector does not retain its teal hierarchy color'
            )
            for _, field in ipairs({ selector, tool, channel }) do
                local carets = 0
                for _, c in ipairs(commands) do
                    if
                        c.type == 'text'
                        and c.x >= field.x
                        and c.x <= field.x + field.w
                        and c.y >= field.y
                        and c.y < field.y + field.h
                    then
                        assert(c.text ~= '<' and c.text ~= '>', 'A hierarchy dropdown still has step arrows')
                        if c.text == 'v' then
                            carets = carets + 1
                        end
                    end
                end
                assert(carets == 1, 'Plain hierarchy dropdown lost its down caret')
            end
            tap(selector)
            assert(menu.dropdown and menu.dropdown.control.id == 'basic_armor_lut', 'Indented LUT selector cannot open')
            menu.key(40)
            menu.key(13)
            assert(
                handle.get('basic_armor_lut') == 2 and calls.basic_armor_lut_change,
                'LUT dropdown selection did not reach the armor callback'
            )
            tap(helmet)
            assert(
                editor.gear == 'helmet' and calls.editor_load_helmet_activate,
                'Helmet tab did not switch the gear target'
            )
            commands = compose()
            local helmet_selector = control(commands, 'LUT 1')
            tap(helmet_selector)
            assert(
                menu.dropdown and menu.dropdown.control.id == 'basic_helmet_lut',
                'Helmet tab still routes the Armor selector'
            )
            menu.key(27)
            tap_label('Armor LUT')
            assert(editor.gear == 'armor' and calls.editor_load_armor_activate, 'Armor tab did not switch back')
            local main_grid_height = editor.grid_bounds.h
            tap_label('LUT 2')
            menu.key(40)
            menu.key(13)
            local cape_commands = compose()
            assert(doc == cape_document and editor.gear == 'armor', 'Cape did not use the shared Armor editor')
            control(cape_commands, 'Cape LUT 1')
            local alias = label(cape_commands, 'CapeSwirl', false)
            input(alias.x + 5, alias.y + 2, false)
            compose()
            menu.tooltip_started = -1
            local hover = compose()
            local hash_help = false
            for _, command in ipairs(hover) do
                if (command.full_text or command.text or ''):find('[0xfedcba9876543210]', 1, true) then
                    hash_help = true
                end
            end
            assert(hash_help, 'Named LUT tooltip lost the exact texture ID')
            input(alias.x + 5, alias.y + 2, true)
            input(alias.x + 5, alias.y + 2, false)
            assert(calls.rename_lut_activate, 'Clicking the LUT name did not open the naming action')
            assert(editor.grid_bounds.h == main_grid_height, 'Selecting Cape consumed extra editor space')
            for _, command in ipairs(cape_commands) do
                assert(
                    not (command.text and command.text:find('Cape Material', 1, true)),
                    'Separate Cape section remained'
                )
            end
            local main_pixels = ffi.string(armor_document.data, armor_document.width * armor_document.height * 16)
            local color = mod.controls.cell_color
            color.picker_begin(1)
            color.picker_preview({ 200, 50, 20 }, 1)
            color.picker_end(true)
            assert(
                ffi.string(armor_document.data, #main_pixels) == main_pixels and doc.revision,
                'Shared picker did not edit only the selected Cape document'
            )
            tap_label('Apply cape')
            assert(calls.editor_apply_armor_activate, 'Shared Apply Cape bypassed the regular editor action')
            tap_label('Pattern LUT Editor')
            assert(pattern.open and pattern.gear == 'armor', 'Pattern header control did not use the current gear')
            pattern.open = false
            local tools = control(compose(), 'Tools')
            assert(tools.c[1] == 244 and tools.c[2] == 202, 'Tools entry lost its gold affordance')
            tap(tools)
            assert(editor.tools.is_open(), 'Gold Tools button does not open the menu')
            commands = compose()
            local all_armor = label(commands, 'Apply to All Armor LUTs', true)
            local selected_apply = label(commands, 'Apply to Cape LUT 1', true)
            assert(all_armor.y < selected_apply.y, 'Apply All is not beneath the selected-LUT action')
            tap({ x = all_armor.x, y = all_armor.y, w = all_armor.text_width, h = all_armor.size })
            assert(calls.editor_all_armor_activate, 'Apply All Armor routes to the wrong callback')
            editor.gear = 'helmet'
            local all_helmet = label(compose(), 'Apply to All Helmet LUTs', true)
            tap({ x = all_helmet.x, y = all_helmet.y, w = all_helmet.text_width, h = all_helmet.size })
            assert(calls.editor_all_helmet_activate, 'Apply All Helmet routes to the wrong callback')
            editor.gear = 'armor'
            tap_label('Scratch')
            assert(
                editor.tools.is_open() and editor.tools.tab == 'import' and editor.scratch_tool.is_open(),
                'Independent Scratch shortcut closed or reset Toolbox'
            )
            tap_label('Tools')
            assert(
                editor.tools.is_open() and editor.scratch_tool.is_open() and editor.tools.tab == 'import',
                'Tools closed or reset an active Scratch shortcut'
            )
            tap_label('Rows')
            assert(
                editor.tools.is_open() and editor.tools.tab == 'rows',
                'Rows shortcut stopped routing while Tools was open'
            )
            editor.scratch_tool.close()
            tap_label('Export')
            local export_checkbox = label(compose(), '[ x ] Include Capes in Armor Exports', true)
            tap({
                x = export_checkbox.x,
                y = export_checkbox.y,
                w = export_checkbox.text_width,
                h = export_checkbox.size,
            })
            assert(
                not handle.get('include_capes_in_armor_exports'),
                'Export checkbox did not toggle its registered setting'
            )
            assert(handle.set('include_capes_in_armor_exports', true))
            editor.tools.close()
            editor.scratch_tool.close()
            commands = compose()
            local header
            for _, c in ipairs(commands) do
                if
                    c.full_text == 'v Row 1'
                    or c.full_text == '> Row 1'
                    or c.text == 'v Row 1'
                    or c.text == '> Row 1'
                then
                    header = c
                    break
                end
            end
            assert(header, 'Value row header missing in the gear layout')
            input(header.x + 40, header.y + 3, false)
            compose()
        end
    end
end
-- The shared editor has no extra Cape controls or second document UI.
for id in pairs(mod.controls) do
    assert(id:sub(1, 5) ~= 'cape_', 'Separate Cape editor controls remain registered')
end
for _, height in ipairs({ 600, 780 }) do
    menu.window_height, menu.window_width, menu.font_size, menu.ui_scale = height, 860, 20, 1
    assert(handle.set('basic_armor_lut', 3))
    compose()
    assert(editor.gear == 'armor' and doc == cape_document, 'Small viewport lost the selected Cape')
end
-- Empty documents use the actual responsive header bounds too. Cover both the
-- gear controller and the imported-palette editor, including wrapped headings.
assert(handle.set('basic_armor_lut', 1))
doc = nil
editor.sync()
editor.tools.close()
editor.scratch_tool.close()
pattern.open = false
editor.can_select_gear = function()
    return false
end
local function message_bounds(commands, value)
    local joined, bounds = '', nil
    for _, command in ipairs(commands) do
        if command.type == 'text' and not command.popup then
            local line = command.full_text or command.text
            local next_text = joined == '' and line or joined .. ' ' .. line
            if value:sub(1, #next_text) == next_text then
                joined = next_text
                local width = #line * command.size * 0.5
                if not bounds then
                    bounds = { x = command.x, y = command.y, w = width, h = command.size }
                else
                    local bottom = math.min(bounds.y, command.y)
                    bounds.h = math.max(bounds.y + bounds.h, command.y + command.size) - bottom
                    bounds.y, bounds.w = bottom, math.max(bounds.w, width)
                end
                if joined == value then
                    return bounds
                end
            else
                joined, bounds = '', nil
            end
        end
    end
    error('Missing complete empty-editor message: ' .. value)
end
local gear_control = mod.controls.editor_load_armor
local page = mod.pages[menu.page]
local old_minimum = page.minimum_width
page.minimum_width = 860
for _, gear in ipairs({ true, false }) do
    mod.controls.editor_load_armor = gear and gear_control or nil
    for _, width in ipairs({ 860, 1100, 1600 }) do
        for _, font in ipairs({ 10, 12, 20 }) do
            for _, scale in ipairs({ 0.85, 1, 1.3 }) do
                for _, height in ipairs({ 600, 1000 }) do
                    -- Keep the production minimum for short windows; use a truly
                    -- narrower frame to force header/message wrapping when taller.
                    page.minimum_width = height == 600 and (old_minimum or 1100) or 860
                    menu.window_width, menu.window_height, menu.font_size, menu.ui_scale = width, height, font, scale
                    editor.gear = 'armor'
                    local commands = compose()
                    local browse = control(commands, 'Choose file...')
                    local elements = { browse }
                    if gear then
                        local selector = control(commands, 'LUT 1')
                        local guidance =
                            message_bounds(commands, 'Load Current Gear to enable the Armor and Helmet selectors.')
                        local load = control(commands, 'Load Current Armor')
                        local explanation =
                            message_bounds(commands, 'Uses currently worn LUT values; a file import is optional.')
                        assert(guidance.y + guidance.h < selector.y, 'Empty guidance overlaps the gear selector')
                        assert(load.y + load.h < guidance.y, 'Empty guidance overlaps the current-gear load button')
                        assert(not overlaps(browse, load), 'Empty editor actions overlap')
                        assert(explanation.y + explanation.h < browse.y, 'Empty explanation overlaps file import')
                        elements[#elements + 1], elements[#elements + 2] = load, guidance
                        elements[#elements + 1], elements[#elements + 2] = explanation, selector
                    else
                        elements[#elements + 1] = message_bounds(commands, 'Choose a DDS or ZIP to begin.')
                        elements[#elements + 1] = control(commands, 'Populate editor with current applied palette')
                        elements[#elements + 1] = control(commands, 'Refresh first')
                        elements[#elements + 1] =
                            message_bounds(commands, 'Uses the applied values from the selected Live LUT.')
                    end
                    for i, a in ipairs(elements) do
                        local footer = control(commands, 'Tools')
                        assert(a.y > footer.y + footer.h, 'Empty content overlaps the footer')
                        for j = i + 1, #elements do
                            assert(not overlaps(a, elements[j]), 'Empty editor content overlaps at font ' .. font)
                        end
                    end
                    local before = calls.browse_activate or 0
                    tap(browse)
                    assert(calls.browse_activate == before + 1, 'Empty editor file action lost its hit target')
                end
            end
        end
    end
end
mod.controls.editor_load_armor, page.minimum_width = gear_control, old_minimum
print(
    'PASS LUT editor hierarchy: shared Cape controls, loaded/empty gear and palette layouts, fonts10/12/20, wrapped headers/messages, scales85/100/130, small-window footer clearance and clickable import'
)
