local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local long = 'Apply Imported DDS to Every Checked Current Material and Associated Pattern LUT'
local intercept
local primitive = Menu.custom_ui({
    text_width = function(label, size)
        return #label * size * 0.6
    end,
    text_size = function(size)
        return size
    end,
    rect = function() end,
    bounded = function() end,
    hit = function() end,
    text_button = function(x, y, w, h, label, callback, options)
        intercept = { x = x, y = y, w = w, h = h, options = options }
        return true
    end,
})
assert(primitive.width_cap(1500, 'Apply') == 360)
assert(primitive.width_cap(1500, long) > 360 and primitive.width_cap(1500, long) <= 620)
assert(primitive.width_cap(1500, 'Name', 'field') == 760)
assert(primitive.width_cap(80, long) == 80, 'Width cap expands beyond its allocated narrow span')
primitive.button(12, 34, 1500, 30, 'Name', function() end, { field = true })
assert(
    intercept.x == 12 and intercept.y == 34 and intercept.w == 760 and intercept.h == 30 and intercept.options.field,
    'Input intercept did not receive the capped field geometry/context'
)

for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.7, 1 }) do
        local actions = 0
        local api = Core.new()
        local handle = api.register({
            id = 'width_caps',
            name = 'Epic LUT',
            pages = {
                {
                    id = 'p',
                    name = 'Controls',
                    require_confirmation = false,
                    controls = {
                        {
                            id = 'choice',
                            type = 'choice',
                            label = 'Choice',
                            choices = { 'First choice', 'Second choice' },
                            default = 1,
                            dropdown_width = 1200,
                        },
                        { id = 'name', type = 'input', label = 'Name', default = 'Saved preset name' },
                        {
                            id = 'presets',
                            type = 'choice',
                            label = 'Presets',
                            choices = { 'Saved preset name', 'Other preset' },
                            default = 1,
                            dropdown_width = 1200,
                        },
                        {
                            id = 'number',
                            type = 'slider',
                            label = 'Number',
                            min = 0,
                            max = 1,
                            step = 0.001,
                            default = 0.125,
                        },
                    },
                },
            },
        })
        local mod = api.mods[handle.id]
        mod.tabs_top = true
        mod.pages[1].render_layout = function(ui)
            ui.button(ui.x + 10, ui.y + 350, 1500, 34, 'Apply', function()
                actions = actions + 1
            end)
            ui.button(ui.x + 10, ui.y + 305, 1500, 34, long, function()
                actions = actions + 1
            end)
            ui.choice('choice', ui.x + 10, ui.y + 250, 1500)
            ui.preset('name', 'presets', ui.x + 10, ui.y + 200, 1500)
            ui.number('number', ui.x + 10, ui.y + 145, 1500, handle.get('number'), nil, true, 0, 1, true)
            ui.button(ui.x + 10, ui.y + 90, 1500, 34, 'Name: ' .. ui.input_value('name'), function()
                ui.activate('name')
            end, { field = true })
        end
        local menu = Menu.new(api, function(label, size)
            return #label * size * 0.6
        end, Text)
        menu.visible, menu.epic_typography, menu.compact_fonts = true, true, true
        menu.font_size, menu.ui_scale = font, scale
        menu.window_width, menu.window_height = 1850, 1000
        local function compose()
            return menu.compose(2560, 1440)
        end
        local function click(x, y)
            for _, down in ipairs({ true, false }) do
                menu.tick({
                    down = function(key)
                        return down and key == 1
                    end,
                    mouse = function()
                        return x, y
                    end,
                }, 0)
            end
        end
        local function label(value)
            for _, command in ipairs(compose()) do
                if (command.full_text or command.text) == value then
                    return command
                end
            end
            error('Missing capped control ' .. value)
        end
        local first = label('Apply')
        local current_scale = menu.window_bounds.scale
        local left = first.x - 8 * font / 12 * current_scale
        local y = first.y + first.size / 2
        click(left + 359 * current_scale, y)
        assert(actions == 1, 'Useful right edge of action is not clickable')
        click(left + 370 * current_scale, y)
        assert(actions == 1, 'Action hit extends into the empty capped-off space')

        local choice = label('First choice')
        click(choice.x + 2, choice.y + 2)
        assert(
            menu.dropdown and menu.dropdown.control.id == 'choice' and menu.dropdown.width == 760,
            'Choice popup retained the old stretched width'
        )
        local popup_x = menu.dropdown.x
        compose()
        assert(
            menu.dropdown.x == popup_x and menu.dropdown.width == 760,
            'Capped choice popup anchor changes on redraw'
        )
        menu.key(27)
        compose()
        local number = label('0.125')
        click(number.x + 2, number.y + 2)
        assert(menu.text_edit and menu.text_edit.control.id == 'number', 'Capped numeric field lost its editable hit')
        compose()
        local numeric_field = assert(menu.text_edit.field_bounds)
        assert(
            numeric_field.x + numeric_field.w <= left + 760 * current_scale + 1,
            'Numeric caret/value field extends outside its bounded slider width'
        )
        menu.key(27)
        compose()

        -- The saved-name editable area and dropdown/step targets all fit the
        -- same actual 760px preset strip, without an oversized popup anchor.
        local name = label('Saved preset name')
        local open_x = left + 600 * current_scale
        click(open_x, name.y + 2)
        assert(
            menu.dropdown and menu.dropdown.control.id == 'presets' and menu.dropdown.width == 760,
            'Preset strip did not cap all dropdown anchors and opening targets'
        )
        menu.key(27)
        local field = label('Name: Saved preset name')
        click(field.x + 2, field.y + 2)
        compose()
        assert(
            menu.text_edit and menu.text_edit.control.id == 'name' and menu.text_edit.field_bounds,
            'Capped input button lost its native text/caret owner'
        )
        assert(
            menu.text_edit.field_bounds.x + menu.text_edit.field_bounds.w <= left + 760 * current_scale + 1,
            'Input caret field uses the pre-cap width'
        )
        menu.key(27)
    end
end
print(
    'PASS control width caps: measured actions, bounded narrow/large fields, exact hit/caret geometry, choice/preset popup anchors and font/scale variants'
)
