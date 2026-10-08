local G = dofile('src/gear/gear_catalog.lua')
local armor = { armor = true, helmet = false }
local helmet = { armor = false, helmet = true }
local shared = { object = 10, armor = true, helmet = true, bindings = { armor, helmet } }
local other = { object = 20, armor = true, helmet = false, bindings = { { armor = true } } }
local groups = { shared, other }
assert(#G.targets(groups, 1, 1, 'armor') == 1, 'Selected shared LUT must isolate Armor bindings')
assert(#G.targets(groups, 1, 1, nil, 'helmet') == 1, 'Basic Helmet selection spilled into Armor')
assert(#G.targets(groups, 2, 1, nil) == 2 and #G.targets(groups, 3, 1, nil) == 1, 'Gear-wide scopes mixed targets')
assert(#G.targets(groups, 4, 1, nil) == 3 and #G.targets(groups, 1, 3, nil) == 0, 'Combined/missing scope wrong')
local binding = { unit = 1, mesh = 2, material = 3, original = 10, current = 99, document = {} }
local object = 99
local catalog = G.new({
    identity = function()
        return {}
    end,
    units = function()
        return { { unit = 1, slot = 1, type = 0 } }
    end,
    materials = function()
        return { { mesh = 2, material = 3, mesh_index = 0, material_index = 0 } }
    end,
    present = function()
        return true
    end,
    binding = function()
        return object
    end,
    key = function(b)
        return b.unit .. ':' .. b.mesh .. ':' .. b.material
    end,
})
local found = catalog.refresh({ binding }, 10)
assert(
    found.owned[1] == binding and found.groups[1].object == 10 and found.groups[1].bindings[1].current == 99,
    'Refresh lost owned original identity'
)
object = 55
found = catalog.refresh({ binding }, 10)
assert(#found.owned == 0 and found.groups[1].object == 55, 'Foreign replacement retained stale ownership')
print('PASS gear catalog: selected/shared scopes, gear-wide targets and original/foreign identity refresh')
