-- Native retained GUI IDs draw by depth, then allocation order at equal depth.
-- Hovering recreates row backgrounds while retaining unchanged preview fills.
local api = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local handle = api.register({
    id = 'armory_hover',
    name = 'Armory',
    pages = {
        {
            id = 'main',
            name = 'The Armory',
            require_confirmation = false,
            controls = {
                {
                    id = 'outfit_preset',
                    type = 'choice',
                    label = 'Saved outfit',
                    default = 2,
                    choices = { 'Choose saved outfit...', 'Armor Gold', 'Armor Blue' },
                    choice_details = { [2] = 'Armor + Helmet', [3] = 'Armor Only' },
                    choice_previews = {
                        [2] = { armor = { { 221, 177, 11 }, { 15, 35, 55 } }, helmet = { { 71, 91, 111 } } },
                        [3] = { armor = { { 31, 101, 211 }, { 19, 41, 79 } }, helmet = {} },
                    },
                },
            },
        },
    },
})
api.mods[handle.id].pages[1].render_layout = function(ui)
    ui.choice('outfit_preset', ui.x + 20, ui.y + ui.h - 90, 420)
end
local menu = dofile('vendor/menu/menu.lua').new(api, function(text, size)
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
    for _, command in ipairs(commands) do
        if (command.full_text or command.text) == wanted and not not command.popup == popup then
            return command
        end
    end
    error('Missing dropdown label: ' .. wanted)
end
local selected = label(menu.compose(1920, 1080), 'Armor Gold', false)
input(selected.x + 8, selected.y + 5, true)
input(selected.x + 8, selected.y + 5, false)
assert(menu.dropdown and menu.dropdown.control.id == 'outfit_preset')
local commands = menu.compose(1920, 1080)
local hovered_label = label(commands, 'Armor Blue', true)
local backgrounds, swatches = {}, {}
local preview_colors = {
    ['221,177,11'] = true,
    ['15,35,55'] = true,
    ['71,91,111'] = true,
    ['31,101,211'] = true,
    ['19,41,79'] = true,
    ['65,76,85'] = true,
    ['145,156,165'] = true,
}
for _, command in ipairs(commands) do
    if command.popup and command.type == 'rect' then
        if preview_colors[table.concat(command.c, ',')] then
            swatches[#swatches + 1] = command
        end
        if command.h == 30 * menu.window_bounds.scale then
            backgrounds[#backgrounds + 1] = command
        end
    end
end
assert(#swatches == 8, 'Armory dropdown omitted RGB, empty Helmet preview or divider')
local row
for _, command in ipairs(backgrounds) do
    if command.w > 100 and hovered_label.y >= command.y and hovered_label.y < command.y + command.h then
        row = command
    end
end
assert(row, 'Hover row background unavailable')

local world, items, next_id, allocations = {}, {}, 0, 0
local function allocate(item)
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
        rect = function(_, pos, size, color)
            return allocate({ x = pos.x, y = pos.y, z = pos.z, w = size.x, h = size.y, color = color })
        end,
        text = function(_, text, _, size, _, pos, color)
            return allocate({
                x = pos.x,
                y = pos.y,
                z = pos.z,
                w = #text * size * 0.5,
                h = size,
                color = color,
                text = text,
            })
        end,
        destroy_rect = function(_, id)
            items[id] = nil
        end,
        destroy_text = function(_, id)
            items[id] = nil
        end,
    },
}
local native = dofile('vendor/menu/view.lua').new(sr, true)
local function pixel(x, y)
    local winner
    for _, item in pairs(items) do
        if
            x >= item.x
            and x < item.x + item.w
            and y >= item.y
            and y < item.y + item.h
            and (not winner or item.z > winner.z or (item.z == winner.z and item.order > winner.order))
        then
            winner = item
        end
    end
    return assert(winner, 'No primitive at sampled dropdown pixel')
end
native.draw(commands)
local retained = {}
for index, swatch in ipairs(swatches) do
    retained[index] = pixel(swatch.x + swatch.w / 2, swatch.y + swatch.h / 2)
end
local label_item = pixel(hovered_label.x + 2, hovered_label.y + 2)
assert(label_item.text == 'Armor Blue', 'Initial preset label is covered')
input(row.x + row.w - 3, row.y + row.h - 2, false)
local hovered_commands = menu.compose(1920, 1080)
native.draw(hovered_commands)
for index, swatch in ipairs(swatches) do
    assert(
        pixel(swatch.x + swatch.w / 2, swatch.y + swatch.h / 2) == retained[index],
        'Hover background covered or rebuilt retained Armory swatches'
    )
end
assert(pixel(hovered_label.x + 2, hovered_label.y + 2) == label_item, 'Hover covered or rebuilt the preset label')
local hover_background = pixel(row.x + row.w - 3, row.y + row.h - 2)
assert(hover_background.color.r == 35 and hover_background.color.g == 46, 'Live hover feedback disappeared')
local before = allocations
native.draw(menu.compose(1920, 1080))
assert(allocations == before, 'Stable dropdown hover recreated GUI primitives')
input(row.x - 20, row.y - 20, false)
native.draw(menu.compose(1920, 1080))
for index, swatch in ipairs(swatches) do
    assert(
        pixel(swatch.x + swatch.w / 2, swatch.y + swatch.h / 2) == retained[index],
        'Leaving hover covered retained Armory swatches'
    )
end
native.release()
print(
    'PASS Armory dropdown hover: retained native IDs, RGB/empty previews and labels above refreshed backgrounds, live hover feedback and stable allocation count'
)
