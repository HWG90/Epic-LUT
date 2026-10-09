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
local callbacks = setmetatable({}, {
    __index = function(_, key)
        return function(value)
            calls[key] = (calls[key] or 0) + 1
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
for _, width in ipairs({ 1100, 1800 }) do
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
            assert(
                math.abs(helmet.y - armor.y) < 0.1
                    and math.abs(armor.y - pattern_button.y) < 0.1
                    and math.abs(load.y - armor.y) < 0.1,
                'Gear/Pattern/Load are not on the same header row'
            )
            assert(
                pattern_button.x > armor.x + armor.w and pattern_button.x + pattern_button.w < load.x,
                'Pattern control is not adjacent to the gear tabs'
            )
            assert(
                selector.y + selector.h < helmet.y and selector.x > helmet.x + 10 * menu.window_bounds.scale,
                'LUT selector is not visibly below and indented from its gear tabs'
            )
            assert(
                tool.y + tool.h < selector.y and math.abs(tool.y - channel.y) < 0.1,
                'Grid tool/channel row was not moved below the gear selector'
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
            tap_label('Pattern LUT Editor')
            assert(pattern.open and pattern.gear == 'armor', 'Pattern header control did not use the current gear')
            pattern.open = false
            local tools = control(compose(), 'Tools')
            assert(tools.c[1] == 244 and tools.c[2] == 202, 'Tools entry lost its gold affordance')
            tap(tools)
            assert(editor.tools.is_open(), 'Gold Tools button does not open the menu')
            commands = compose()
            local all_armor = label(commands, 'Apply to All Armor LUTs', true)
            local selected_apply = label(commands, 'Apply to Armor LUT ' .. handle.get('basic_armor_lut'), true)
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
print(
    'PASS LUT editor hierarchy: production registry, two fonts/scales/widths, ordered gear/Pattern/teal LUT/tool rows, plain dropdowns, gear callbacks, gold Tools and hovered value opacity'
)
