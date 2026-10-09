local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local handle = api.register({
    id = 'floating_test',
    name = 'Floating',
    pages = {
        {
            id = 'main',
            name = 'Main',
            controls = {
                {
                    id = 'floating_selector',
                    type = 'choice',
                    label = 'Choice',
                    choices = { 'Alpha', 'Beta' },
                    default = 1,
                },
            },
        },
    },
})
local page = api.mods[handle.id].pages[1]
page.render_layout = function(ui)
    ui.floating('test_popup', function(x, y, w, h)
        ui.rect(x, y, w, h, { 24, 30, 35 })
        ui.rect(x, y + h - 40, w, 40, { 35, 62, 90 })
        ui.bounded(x + 10, y + h - 27, 'Floating title', 14, { 255, 255, 255 }, w - 40)
        ui.choice('floating_selector', x + 15, y + h - 110, w - 30)
    end, 400, 260, function() end, 40)
end
local menu = dofile('vendor/menu/menu.lua').new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
menu.window_width, menu.window_height = 1200, 880
local function input(x, y, pressed)
    menu.tick({
        down = function(key)
            return pressed and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local commands = menu.compose(1920, 1080)
local selector
for _, c in ipairs(commands) do
    if c.full_text == 'Alpha' then
        selector = c
    end
end
assert(selector, 'Floating selector not rendered')
input(selector.x + 12, selector.y + 5, true)
input(selector.x + 12, selector.y + 5, false)
assert(menu.dropdown and menu.dropdown.owner, 'Floating dropdown has no owner')
commands = menu.compose(1920, 1080)
local above = false
for _, c in ipairs(commands) do
    if c.popup and c.text == 'Alpha' and c.layer == 230 then
        above = true
    end
end
assert(above, 'Dropdown is behind floating window')
local position = menu.floating_positions.test_popup
local oldx, oldtop = menu.dropdown.x, menu.dropdown.top
position.x = position.x - 50
position.y = position.y + 20
menu.compose(1920, 1080)
assert(menu.dropdown.x < oldx and menu.dropdown.top > oldtop, 'Dropdown anchor did not follow popup')
local owner = menu.dropdown.owner
local scale = (menu.window_bounds and menu.window_bounds.scale) or 1
-- The rendered title text supplies physical coordinates independent of UI scale.
local title
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.text == 'Floating title' then
        title = c
    end
end
assert(title)
local before = position.x
input(title.x + 30, title.y + 5, true)
input(title.x - 10, title.y + 5, true)
input(title.x - 10, title.y + 5, false)
assert(position.x < before, 'Open dropdown blocked title-bar dragging')
assert(menu.dropdown, 'Dragging title unexpectedly discarded dropdown')
print('PASS floating dropdown: foreground layer, moving anchor and accessible title drag')

local previous_layer
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.popup and c.type == 'rect' and c.layer >= 210 and c.layer < 230 then
        assert(
            not previous_layer or c.layer > previous_layer,
            'Floating rectangles share depth and can reorder after movement'
        )
        previous_layer = c.layer
    end
end

local underlying = 0
page.on_wheel = function()
    underlying = underlying + 1
    return true
end
menu.dropdown = nil
menu.compose(1920, 1080)
local floating = assert(menu.floating_bounds)
menu.wheel(-120, floating.x + 20, floating.y + 20)
assert(underlying == 0, 'Floating popup scrolled underlying page')
menu.color_picker = {}
menu.wheel(-120, menu.window_bounds.x + 200, menu.window_bounds.y + 250)
assert(underlying == 0, 'Color picker scrolled underlying page')
menu.color_picker = nil

-- One control appears at two authored locations. Each actual hit must anchor
-- its dropdown locally, including subsequent redraws and moving popup owners.
page.render_layout = function(ui)
    ui.choice('floating_selector', ui.x + 20, ui.y + 200, 180)
    ui.choice('floating_selector', ui.x + 420, ui.y + 200, 180)
end
local function duplicate_labels(commands)
    local labels = {}
    for _, c in ipairs(commands) do
        if c.full_text == 'Alpha' then
            labels[#labels + 1] = c
        end
    end
    assert(#labels == 2)
    return labels
end
local duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[1].x + 3, duplicate[1].y + 3, true)
input(duplicate[1].x + 3, duplicate[1].y + 3, false)
assert(menu.dropdown and menu.dropdown.widget)
local left_anchor = menu.dropdown.x
menu.compose(1920, 1080)
assert(menu.dropdown.x == left_anchor, 'Redrawing the right duplicate stole the left dropdown anchor')
menu.key(27)
duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[2].x + 3, duplicate[2].y + 3, true)
input(duplicate[2].x + 3, duplicate[2].y + 3, false)
assert(menu.dropdown.x > left_anchor + 200, 'Right duplicate opened below the left widget')
menu.key(27)
page.render_layout = function(ui)
    ui.floating('test_popup', function(x, y, w, h)
        ui.rect(x, y, w, h, ui.theme.panel)
        ui.choice('floating_selector', x + 10, y + 100, 180)
        ui.choice('floating_selector', x + 210, y + 100, 180)
    end, 420, 260, function() end, 40)
end
duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[1].x + 3, duplicate[1].y + 3, true)
input(duplicate[1].x + 3, duplicate[1].y + 3, false)
left_anchor = menu.dropdown.x
position = menu.floating_positions.test_popup
position.x = position.x - 50
menu.compose(1920, 1080)
assert(
    menu.dropdown.owner.id == 'test_popup' and menu.dropdown.x < left_anchor,
    'Duplicate dropdown lost its own moving window anchor'
)
print('PASS duplicate choice anchors: left/right hits keep separate anchors and follow their own popup')
