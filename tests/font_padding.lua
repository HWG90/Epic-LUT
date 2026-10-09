local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local View = dofile('vendor/menu/view.lua')
local world, gui = {}, {}
local metric_calls = 0
local function native_metrics(size, label)
    local lo = label == 'Tools' and -0.2 * size or -0.3 * size
    local hi = label == 'Tools' and 0.55 * size or 0.65 * size
    return lo, hi
end
local sr = {
    Application = {
        worlds = function()
            return { world }
        end,
        main_world = function()
            return world
        end,
        can_get = function()
            return false
        end,
    },
    World = {
        create_screen_gui = function()
            return gui
        end,
        destroy_gui = function() end,
    },
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Color = function(a, r, g, b)
        return { a, r, g, b }
    end,
    Gui = {
        rect = function()
            return 1
        end,
        text = function()
            return 2
        end,
        destroy_rect = function() end,
        destroy_text = function() end,
        text_extents = function(_, label, _, size)
            metric_calls = metric_calls + 1
            local lo, hi = native_metrics(size, label)
            return { x = 0, y = lo }, { x = #label * size * 0.62, y = hi }
        end,
    },
}
local view = View.new(sr, true)
view.draw({ { type = 'rect', x = 0, y = 0, w = 1, h = 1, c = { 0, 0, 0 }, a = 1 } })
local metric = view.text_metrics(20, 'Tools')
assert(metric.min_y == -4 and metric.max_y == 11 and metric.height == 15, 'Native font bearings were not exposed')
local count = metric_calls
assert(view.text_metrics(20, 'Tools') == metric and metric_calls == count, 'Font metrics did not cache')
local api = Core.new()
local h = api.register({
    id = 'padding',
    name = 'Padding',
    pages = {
        {
            id = 'p',
            name = 'Page',
            controls = {
                {
                    id = 'choice',
                    type = 'choice',
                    presentation = 'dropdown',
                    label = 'Choice',
                    choices = { 'One' },
                    default = 1,
                },
                { id = 'number', type = 'slider', label = 'Number', min = 0, max = 1, step = 0.01, default = 0.25 },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
local button_box, choice_box, number_box
mod.pages[1].render_layout = function(ui)
    local height = ui.control_height(14, 5, 'Tools')
    button_box = { x = ui.x + 20, y = ui.y + 180, w = 180, h = height }
    ui.button(button_box.x, button_box.y, button_box.w, height, 'Tools', function() end)
    choice_box = { x = ui.x + 20, y = ui.y + 120, w = 220, h = 26 }
    ui.choice('choice', choice_box.x, choice_box.y, choice_box.w)
    number_box = { x = ui.x + 20 + 400 - 92, y = ui.y + 60, w = 92, h = math.max(21, ui.text_size(14) + 8) }
    ui.number('number', ui.x + 20, number_box.y, 400, h.get('number'), nil, true, nil, nil, true)
end
local menu = Menu.new(api, view.measure)
menu.text_metrics = view.text_metrics
menu.visible, menu.compact_fonts = true, true
menu.window_width, menu.window_height = 1400, 900
local function assert_padding(commands, label, box)
    local c
    for _, item in ipairs(commands) do
        if item.full_text == label then
            c = item
        end
    end
    assert(c, 'Missing padded label: ' .. label)
    local s = menu.window_bounds.scale
    local lo, hi = native_metrics(c.size, label)
    local bottom = c.y + lo - (menu.window_bounds.y + box.y * s)
    local top = menu.window_bounds.y + (box.y + box.h) * s - (c.y + hi)
    assert(math.abs(top - bottom) < 0.01 and top >= 0, 'Visible glyph padding is unbalanced for ' .. label)
    return bottom / s
end
for _, scale in ipairs({ 0.85, 1 }) do
    local small_pad
    for _, font in ipairs({ 12, 20 }) do
        menu.ui_scale, menu.font_size = scale, font
        local commands = menu.compose(1920, 1080)
        local pad = assert_padding(commands, 'Tools', button_box)
        assert_padding(commands, 'One', choice_box)
        assert_padding(commands, '0.25', number_box)
        assert(math.abs(pad - 5 * font / 14) < 0.01, 'Button padding did not scale with its font')
        if font == 12 then
            small_pad = pad
        else
            assert(pad > small_pad, 'Large font consumed its preserved padding')
        end
    end
end
print(
    'PASS font padding: native ink bearings, cached label metrics, balanced visible button/choice/number insets and font-scaled logical padding at12/20 and85/100'
)
