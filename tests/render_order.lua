-- Fake GUI obeys native depth, then creation order at equal depth. Retained IDs
-- therefore reproduce the live bug when only a cell's border color changes.
local View = dofile('vendor/menu/view.lua')
local world, items, next_id, allocations, destroyed = {}, {}, 0, 0, 0
local function allocate(item)
    next_id = next_id + 1
    allocations = allocations + 1
    item.order = next_id
    items[next_id] = item
    return next_id
end
local gui = {}
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
        return { a = a, r = r, g = g, b = b }
    end,
    Gui = {
        rect = function(_, pos, size, color)
            return allocate({ x = pos.x, y = pos.y, z = pos.z, w = size.x, h = size.y, color = color })
        end,
        text = function(_, text, _, size, _, pos, color)
            return allocate({ text = text, z = pos.z, color = color })
        end,
        destroy_rect = function(_, id)
            items[id] = nil
            destroyed = destroyed + 1
        end,
        destroy_text = function(_, id)
            items[id] = nil
            destroyed = destroyed + 1
        end,
    },
}
local view = View.new(sr, true)
local function rect(x, y, w, h, color, role, layer)
    return { type = 'rect', x = x, y = y, w = w, h = h, c = color, a = 1, ui_role = role, layer = layer }
end
local border = rect(0, 0, 10, 10, { 75, 78, 82 }, 'swatch_border')
local fill = rect(1, 1, 8, 8, { 240, 30, 20 }, 'swatch_fill')
local commands = { border, fill }
local function pixel(x, y)
    local winner
    for _, item in pairs(items) do
        if
            item.x
            and x >= item.x
            and x < item.x + item.w
            and y >= item.y
            and y < item.y + item.h
            and (not winner or item.z > winner.z or (item.z == winner.z and item.order > winner.order))
        then
            winner = item
        end
    end
    return assert(winner).color, winner
end
view.draw(commands)
local original = allocations
local _, retained_fill = pixel(5, 5)
border.c = { 244, 202, 53 }
view.draw(commands)
local center, still_fill = pixel(5, 5)
assert(
    center.r == 240 and center.g == 30 and still_fill == retained_fill,
    'Recreated gold border covered the retained RGB center'
)
assert(pixel(0.2, 0.2).r == 244, 'Selected cell edge did not become gold')
assert(allocations == original + 1 and destroyed == 1, 'Selection rebuilt unaffected cell primitives')
original = allocations
view.draw(commands)
assert(allocations == original, 'Stable selection frame reallocated GUI primitives')
-- Layout command counts cannot alter cell depth. This deliberately shifts the
-- ID slots while keeping geometry and roles fixed.
local before_z = still_fill.z
table.insert(commands, 1, rect(30, 30, 10, 10, { 20, 30, 40 }))
view.draw(commands)
local color, shifted_fill = pixel(5, 5)
assert(color.r == 240 and shifted_fill.z == before_z, 'Sidebar/layout count changed swatch depth')
local outline = rect(0, 0, 10, 1, { 244, 202, 53 }, 'selection_outline')
commands[#commands + 1] = outline
view.draw(commands)
assert(pixel(0.2, 0.2).r == 244 and pixel(5, 5).r == 240, 'Selection outline crossed a cell center')
-- Role offsets stay within each authored window plane: a modal above the grid
-- must still occlude it regardless of the grid's roles.
commands[#commands + 1] = rect(0, 0, 10, 10, { 25, 35, 45 }, nil, 300)
view.draw(commands)
assert(pixel(5, 5).r == 25, 'Swatch role depth escaped the modal plane')
original = allocations
view.draw(commands)
assert(allocations == original, 'Unchanged modal frame reallocated primitives')
print(
    'PASS retained render ordering: gold edges behind unchanged RGB fills, no stable-frame allocations, no count-based depth drift, scoped outlines and modal occlusion'
)
