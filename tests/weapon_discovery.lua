local fixture = dofile('tests/weapon_fixture.lua')
local D = dofile('src/weapons/weapon_discovery.lua')
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
test('local slot receipts require genuine Unit handles and preserve stable resource identities', function()
    local f = fixture()
    local primary, secondary = assert(f.discovery.capture(1)), assert(f.discovery.capture(2))
    assert(primary.unit == 100 and primary.weapon_slot == 1 and primary.weapon_resource64 == '5fecab819f96a3e8')
    assert(secondary.unit == 200 and secondary.weapon_slot == 2 and secondary.weapon_resource64 == '1234567812345678')
    local missing, why = f.discovery.capture(3)
    assert(not missing and why:find('Weapon inventory slot is empty', 1, true))
    f.world_units.main[1] = 100
    missing, why = f.discovery.capture(1)
    assert(not missing and why:find('No genuine live Lua Unit', 1, true), why)
end)
test('descriptors preserve every LOD locator and distinguish texture slot from weapon slot', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local rows = f.discovery.materials(receipt)
    assert(#rows == 10)
    for _, row in ipairs(rows) do
        local b = assert(f.discovery.descriptor(receipt, row, D.LUT))
        assert(b.kind == 'weapon' and b.weapon and b.type == 3 and b.slot == D.LUT and b.weapon_slot == 1)
        assert(b.save_key == '3:1:' .. row.mesh_index .. ':' .. row.material_index)
        assert(f.discovery.present(b) and f.discovery.binding(b) == (row.material_index == 0 and f.A or f.B))
    end
end)
test('shared texture objects are allowed but foreign material-pointer aliases are refused', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then
            targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT)
        end
    end
    assert(f.discovery.prove_private(targets), 'Shared stock texture was mistaken for a shared material')
    f.units[300].meshes[1].materials[1] = targets[1].material
    local private, why = f.discovery.prove_private(targets)
    assert(not private and why:find('aliases another destination', 1, true), why)
    assert(#f.writes == 0 and f.allocations == 0)
end)
test('same-material LOD aliases must all be inside the selected write scope', function()
    local f = fixture()
    local model = f.units[100]
    model.meshes[2].materials[1] = model.meshes[1].materials[1]
    local receipt = assert(f.discovery.capture(1))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then
            targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT)
        end
    end
    assert(f.discovery.prove_private(targets))
    table.remove(targets, 2)
    local private, why = f.discovery.prove_private(targets)
    assert(not private and why:find('aliases another destination', 1, true), why)
end)
test('altered receipts, material replacement, recycled identity and ambiguous worlds fail closed', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    receipt.weapon_slot = 2
    assert(not f.discovery.validate(receipt))
    f = fixture()
    receipt = assert(f.discovery.capture(1))
    local b = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    f.units[100].meshes[1].materials[1] = f.units[300].meshes[1].materials[1]
    assert(not f.discovery.present(b))
    f = fixture()
    receipt = assert(f.discovery.capture(1))
    b = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    b.original = f.B
    assert(not f.discovery.present(b), 'Original binding source was mutable')
    f = fixture()
    receipt = assert(f.discovery.capture(1))
    f.snapshots[1].weapon_object = f.snapshots[1].weapon_object + 1
    assert(not f.discovery.validate(receipt))
    f = fixture()
    f.worlds[2] = 'foreign'
    f.world_units.foreign = { f.units[100].handle }
    local missing, why = f.discovery.capture(1)
    assert(not missing and why:find('Ambiguous weapon Unit reference', 1, true), why)
end)
test('dead proof requires both genuine Lua and native unit death', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local b = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    f.snapshots[1] = nil
    assert(not f.discovery.present(b) and not f.discovery.dead(b), 'Dropped live weapon was called dead')
    f.units[100].alive = false
    assert(f.discovery.dead(b))
end)
print('PASS weapon discovery: ' .. cases .. ' focused contracts')
