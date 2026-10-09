local api = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local h = api.register({
    id = 'input_preview_test',
    name = 'Input',
    pages = {
        {
            id = 'p',
            name = 'Page',
            require_confirmation = false,
            controls = {
                { id = 'save_name', type = 'input', label = 'Name', default = 'OLD' },
            },
        },
    },
})
api.mods[h.id].pages[1].render_layout = function(ui)
    ui.rect(ui.x + 10, ui.y + 100, 400, 26, { 11, 22, 33 })
    ui.bounded(ui.x + 16, ui.y + 105, 'Name: ' .. ui.input_value('save_name'), 14, { 255, 255, 255 }, 380)
    ui.hit(ui.x + 10, ui.y + 100, 400, 26, function()
        ui.activate('save_name')
    end)
end
local menu = dofile('vendor/menu/menu.lua').new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
local field
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.type == 'rect' and c.c[1] == 11 then
        field = c
    end
end
assert(field)
local x, y = field.x + 20, field.y + 10
local function input(code)
    menu.tick({
        down = function(k)
            return k == code
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local function shown(value)
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.full_text == value or c.text == value then
            return true
        end
    end
end
input(1)
input(nil)
input(65)
input(nil)
input(66)
input(nil)
assert(shown('Name: AB|'), 'Draft label did not redraw with stationary pointer')
assert(h.get('save_name') == 'OLD', 'Draft was saved before confirmation')
input(27)
input(nil)
assert(shown('Name: OLD') and h.get('save_name') == 'OLD', 'Escape did not discard draft')
input(1)
input(nil)
input(67)
input(nil)
input(13)
input(nil)
assert(shown('Name: C') and h.get('save_name') == 'C', 'Enter did not save draft')
print('PASS input preview: stationary pointer live draft, Escape cancel and Enter commit')
