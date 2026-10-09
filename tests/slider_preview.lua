local api = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local changes = 0
local h = api.register({
    id = 'slider_test',
    name = 'Slider',
    pages = {
        {
            id = 'p',
            name = 'Page',
            require_confirmation = false,
            controls = {
                {
                    id = 'value',
                    type = 'slider',
                    label = 'Value',
                    min = 0,
                    max = 1,
                    step = 0.01,
                    default = 0.2,
                    on_change = function()
                        changes = changes + 1
                    end,
                },
            },
        },
    },
})
api.mods[h.id].pages[1].render_layout = function(ui)
    ui.number('value', ui.x + 10, ui.y + 100, 400, h.get('value'), function() end, true, 0, 1)
    ui.number('value', ui.x + 10, ui.y + 50, 400, 0.2, function() end, true, 0, 1)
end
local Menu = dofile('vendor/menu/menu.lua')
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
local function input(x, y, down)
    menu.tick({
        down = function(k)
            return down and k == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local bar
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.type == 'rect' and c.c == Menu.palette.focus and c.h == 5 then
        if not bar then
            bar = c
        end
    end
end
assert(bar)
local x, y = bar.x + (bar.w / 0.2) * 0.8, bar.y + 5
input(x, y, true)
assert(menu.is_interacting(), 'Active value drag is invisible to automatic gear refresh')
local displayed = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == '0.8' or c.text == '0.8' then
        displayed = true
    end
end
local other = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == '0.2' or c.text == '0.2' then
        other = true
    end
end
assert(other, 'Dragging one channel previewed its value in another column')
assert(displayed and math.abs(h.get('value') - 0.8) < 1e-9 and changes == 1, 'Slider did not update live while held')
input(x, y, false)
assert(not menu.is_interacting(), 'Released value drag keeps automatic gear refresh blocked')
assert(math.abs(h.get('value') - 0.8) < 1e-9 and changes == 1, 'Release duplicated the live update')
print('PASS slider preview: live numeric/bar display and live commit without duplicate release')
