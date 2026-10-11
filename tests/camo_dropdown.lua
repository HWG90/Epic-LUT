-- Actual Menu thumbnails drawn through retained native View primitives. A
-- refreshed hover background must remain below unchanged masks and labels.
local Camo, Menu = dofile('src/editor/basic_camo.lua'), dofile('vendor/menu/menu.lua')
local mask = string.char(255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 255)
local layers = {}
for i = 1, 6 do
    layers[i] = mask
end
local previews = assert(Camo.thumbnails({ width = 2, height = 2, layers = layers }))
assert(previews[3].colors[1][1] == 218 and previews[3].colors[2][1] == 142)
assert(previews[3].colors[3][1] == 80 and previews[3].colors[4][1] == 35)
for _, color in ipairs(previews[3].colors) do
    assert(color[1] == color[2] and color[2] == color[3], 'Mask thumbnail is not neutral')
end
local api = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local choices = {}
for i, label in ipairs(Camo.CHOICES) do
    choices[i] = label
end
local handle = api.register({
    id = 'camo_thumbnail',
    name = 'Camo',
    pages = {
        {
            id = 'main',
            name = 'Camo',
            require_confirmation = false,
            controls = {
                {
                    id = 'camo',
                    type = 'choice',
                    presentation = 'dropdown',
                    label = 'Camo',
                    default = 2,
                    choices = choices,
                    choice_pattern_previews = previews,
                },
            },
        },
    },
})
api.mods[handle.id].pages[1].render_layout = function(ui)
    ui.choice('camo', ui.x + 20, ui.y + ui.h - 90, 420)
end
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
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
local function label(commands, wanted, popup)
    for _, c in ipairs(commands) do
        if (c.full_text or c.text) == wanted and not not c.popup == popup then
            return c
        end
    end
    error('Missing composed camo label ' .. wanted)
end
local off = label(menu.compose(1920, 1080), 'Off', false)
input(off.x + 4, off.y + 4, true)
input(off.x + 4, off.y + 4, false)
assert(menu.dropdown and menu.dropdown.control.id == 'camo')
local commands = menu.compose(1920, 1080)
local option = label(commands, 'Pattern 0', true)
local row, swatches = nil, {}
for _, c in ipairs(commands) do
    if
        c.popup
        and c.type == 'rect'
        and c.ui_role == 'control_fill'
        and c.w > 100
        and option.y >= c.y
        and option.y < c.y + c.h
    then
        row = c
    end
end
assert(row, 'Pattern option has no background')
for _, c in ipairs(commands) do
    if c.popup and c.type == 'rect' and c.ui_role == 'swatch_fill' and c.y >= row.y and c.y + c.h <= row.y + row.h then
        swatches[#swatches + 1] = c
        assert(c.x >= row.x and c.x + c.w <= row.x + row.w, 'Mask rectangle escaped its option')
        assert(c.paint_span == 20 and c.paint_plane >= 300, 'Mask lost its reserved popup plane')
    end
end
assert(#swatches == 4, 'A bounded 2x2 mask did not emit four color cells')
assert(swatches[1].c[1] == 218 and swatches[2].c[1] == 142 and swatches[3].c[1] == 80 and swatches[4].c[1] == 35)
assert(
    swatches[1].y == swatches[2].y and swatches[1].y > swatches[3].y and swatches[3].y == swatches[4].y,
    'RGBA rows were vertically inverted'
)
assert(swatches[1].x < swatches[2].x and swatches[1].x == swatches[3].x)
local world, items, next_id, allocations = {}, {}, 0, 0
local function allocate(item)
    local z = math.floor(tonumber(item.z))
    assert(z == item.z, 'Fractional camo dropdown depth reached native Gui')
    item.z = z
    next_id, allocations = next_id + 1, allocations + 1
    item.order = next_id
    items[next_id] = item
    return next_id
end
local sr = {
    Application = {
        worlds = function()
            return { world }
        end,
        main_world = function()
            return world
        end,
    },
    World = {
        create_screen_gui = function()
            return {}
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
        return { a = a, r = r, g = g, b = b }
    end,
    Gui = {
        rect = function(_, p, s, color)
            return allocate({ x = p.x, y = p.y, z = p.z, w = s.x, h = s.y, color = color })
        end,
        text = function(_, text, _, size, _, p, color)
            return allocate({ x = p.x, y = p.y, z = p.z, w = #text * size * 0.5, h = size, color = color, text = text })
        end,
        destroy_rect = function(_, id)
            items[id] = nil
        end,
        destroy_text = function(_, id)
            items[id] = nil
        end,
    },
}
local view = dofile('vendor/menu/view.lua').new(sr, true)
local function pixel(x, y)
    local winner
    for _, item in pairs(items) do
        if
            x >= item.x
            and x < item.x + item.w
            and y >= item.y
            and y < item.y + item.h
            and (not winner or item.z > winner.z or item.z == winner.z and item.order > winner.order)
        then
            winner = item
        end
    end
    return assert(winner, 'No native primitive at camo preview pixel')
end
view.draw(commands)
local retained = {}
for i, cell in ipairs(swatches) do
    local item = pixel(cell.x + cell.w / 2, cell.y + cell.h / 2)
    assert(item.color.r == cell.c[1] and item.color.g == cell.c[2] and item.color.b == cell.c[3])
    retained[i] = item
end
local retained_label = pixel(option.x + 2, option.y + 2)
assert(retained_label.text == 'Pattern 0', 'Initial camo label is covered')
local hover_x, hover_y = row.x + row.w - 3, row.y + row.h - 2
local old_background = pixel(hover_x, hover_y)
input(hover_x, hover_y, false)
view.draw(menu.compose(1920, 1080))
local fresh = pixel(hover_x, hover_y)
assert(fresh ~= old_background and fresh.order > old_background.order, 'Hover did not refresh the row fill')
for i, cell in ipairs(swatches) do
    assert(
        pixel(cell.x + cell.w / 2, cell.y + cell.h / 2) == retained[i],
        'Fresh fill covered or rebuilt the retained mask'
    )
    assert(
        retained[i].z > fresh.z and retained[i].z == math.floor(retained[i].z),
        'Mask did not remain above fresh integer-depth fill'
    )
end
assert(
    pixel(option.x + 2, option.y + 2) == retained_label and retained_label.z > fresh.z,
    'Hover erased or rebuilt the camo option label'
)
local before = allocations
view.draw(menu.compose(1920, 1080))
assert(allocations == before, 'Stable mask hover allocated new native primitives')
local last = swatches[4]
input(last.x + last.w / 2, last.y + last.h / 2, true)
input(last.x + last.w / 2, last.y + last.h / 2, false)
assert(handle.get('camo') == 3 and not menu.dropdown, 'Clicking a preview did not select its camo option')
view.release()

-- A uniform full 16x16 mask merges each horizontal scanline into one bounded
-- run, rather than submitting a rectangle for every texel.
local full_layers = {}
for i = 1, 6 do
    full_layers[i] = string.rep(string.char(255, 0, 0, 255), 16 * 16)
end
local full = assert(Camo.thumbnails({ width = 16, height = 16, layers = full_layers }))
local runs = {}
Menu.pattern_thumbnail(full[3], function(x, y, w, h, color, _, role)
    runs[#runs + 1] = { x = x, y = y, w = w, h = h, color = color, role = role }
end, 10, 20, 24)
assert(#runs == 16, 'Uniform 16x16 mask failed horizontal run merging')
for i, run in ipairs(runs) do
    assert(run.x == 10 and run.w == 24 and run.h == 1.5 and run.y == 20 + (16 - i) * 1.5 and run.role == 'swatch_fill')
    assert(run.color[1] == 218 and run.color[2] == 218 and run.color[3] == 218)
end
print(
    'PASS camo dropdown: neutral top-down masks, bounded run merging, labels and retained previews above fresh integer-depth fills, stable allocations and preview selection'
)
