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

local cape_object = 99
local cape_catalog = G.new({
    identity = function()
        return {}
    end,
    units = function()
        return { { unit = 1, slot = 1, type = 0 }, { unit = 2, slot = 2, type = 0 } }
    end,
    materials = function(unit)
        return { { mesh = unit + 1, material = unit == 1 and 3 or 6, mesh_index = 0, material_index = 0 } }
    end,
    present = function()
        return true
    end,
    binding = function(b)
        return b.material == 3 and cape_object or 20
    end,
    key = function(b)
        return b.material
    end,
    is_cape = function(b)
        return b.material == 3
    end,
})
local result = cape_catalog.refresh({ { unit = 1, mesh = 2, material = 3, original = 10, current = 99 } }, nil)
assert(cape_object == 99 and #result.owned == 1, 'Refresh removed a deliberately applied Cape material LUT')
local cape = result.groups[1].bindings[1]
assert(cape.cape and not cape.armor and not cape.helmet, 'Cape was classified as Armor/Helmet')
assert(#result.groups == 2 and result.labels[1]:find('Cape material', 1, true), 'Cape material selector vanished')
assert(
    #G.targets(result.groups, 2, 1) == 1 and #G.targets(result.groups, 4, 1) == 1,
    'Armor/Both wide scopes include Cape'
)
assert(G.targets(result.groups, 1, 1, 'cape')[1] == cape, 'Explicit Cape selection has no application targets')
cape_object = 20
result = cape_catalog.refresh({}, nil)
assert(
    #result.groups == 1 and result.groups[1].cape and result.groups[1].armor,
    'Shared Armor/Cape resource split incorrectly'
)
assert(
    #G.targets(result.groups, 1, 1, 'cape') == 1 and #G.targets(result.groups, 2, 1) == 1,
    'Shared resource selection spills across gear kinds'
)

local calls = 0
local names = G.new({
    identity = function()
        return {}
    end,
    units = function()
        return { { unit = 9, slot = 0, type = 0 } }
    end,
    resource_name = function(unit)
        assert(unit == 9)
        calls = calls + 1
        return 'Helmet RS-40 Beast of Prey'
    end,
    materials = function()
        return { { mesh = 20, material = 30 }, { mesh = 21, material = 31 } }
    end,
    present = function()
        return true
    end,
    binding = function()
        return 77
    end,
    key = function(b)
        return b.material
    end,
})
local named = names.refresh({}, 77)
assert(
    calls == 1 and named.labels[1]:find('Helmet RS-40 Beast of Prey', 1, true),
    'SDK resource name was guessed or looked up repeatedly for each material'
)
assert(#named.groups[1].resource_names == 1 and named.signature)
