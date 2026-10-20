local fixture = dofile('tests/weapon_fixture.lua')
local D = dofile('src/weapons/weapon_discovery.lua')
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
test('direct Unit world guards allocate no whole-world lists and reject moved or dead owners', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local b = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    local world, queries = 'main', 0
    f.E.Unit.world = function() queries = queries + 1; return world end
    f.E.World.units = function() error('Per-binding guard enumerated the entire World') end
    for _ = 1, 1000 do assert(f.discovery.present(b)) end
    assert(queries == 1000, 'World ownership was cached across guards')
    world = 'other'
    assert(not f.discovery.present(b), 'Moved Unit retained old World permission')
    f.units[100].alive = false
    f.E.Unit.world = function() error('Queried the World of a dead Unit') end
    assert(not f.discovery.present(b), 'Dead Unit retained permission')
    assert(#f.writes == 0 and f.allocations == 0)
end)
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
test('unchanged byte probes reuse decoding but never stale expected values or changed bytes', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local row = f.discovery.materials(receipt)[1]
    local b = f.discovery.descriptor(receipt, row, D.LUT)
    b.current = f.A
    local before = f.reads
    for _ = 1, 5 do
        assert(f.discovery.bindings_unchanged({ b }))
    end
    assert(f.reads == before + 10, 'Stable probes stopped reading fresh header and slot bytes')
    b.current = f.B
    assert(not f.discovery.bindings_unchanged({ b }), 'Changed desired value reused a cached comparison')
    f.textures[b.material][D.LUT] = f.B
    assert(f.discovery.bindings_unchanged({ b }), 'Changed native bytes failed to invalidate decoding')
    f.textures[b.material][D.LUT] = f.P
    assert(not f.discovery.bindings_unchanged({ b }), 'Foreign native bytes escaped the negative gate')
    assert(#f.writes == 0 and f.allocations == 0)
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

test('privacy census creates Lua mesh wrappers only for matching native materials', function()
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then
            targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT)
        end
    end
    local mesh, calls = f.E.Unit.mesh, 0
    f.E.Unit.mesh = function(handle, index)
        assert(handle == receipt.lua_unit, 'Unrelated mesh allocated a Lua wrapper during pointer census')
        calls = calls + 1
        return mesh(handle, index)
    end
    assert(f.discovery.prove_private(targets))
    assert(calls > 0, 'Matching native materials were never checked through the Lua API')
    f.E.Unit.mesh = function() return require('ffi').cast('void *', 65536) end
    local ok, why = f.discovery.prove_private(targets)
    assert(not ok and why:find('Mesh', 1, true), 'Matching material lost its Lua/native mesh proof')
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

do
    local f = fixture()
    local one = assert(f.discovery.capture(1))
    local two = assert(f.discovery.capture(1))
    local a = f.discovery.descriptor(one, f.discovery.materials(one)[1], D.LUT)
    local b = f.discovery.descriptor(two, f.discovery.materials(two)[1], D.LUT)
    local calls = 0
    f.identity_hook = function()
        calls = calls + 1
    end
    f.discovery.with_validation_batch(function()
        assert(f.discovery.present(a))
        assert(f.discovery.present(b))
    end)
    assert(calls == 2, 'Separate receipts for the same immutable Unit repeated its census')
    calls = 0
    assert(f.discovery.present(a))
    assert(f.discovery.present(b))
    assert(calls == 2, 'Read-only batch escaped into later write validation')
    f.identity_hook = nil
end

-- Count validation must precede the native allocation, including failure paths.
do
    local f = fixture()
    local enumerations = 0
    local list = f.E.World.units
    f.E.World.units = function(world) enumerations = enumerations + 1; return list(world) end
    f.E.World.num_units = function() return D.MAX_UNITS + 1 end
    local receipt, why = f.discovery.capture(1)
    assert(not receipt and why:find('count unavailable or out of bounds', 1, true) and enumerations == 0,
        'Oversized native count reached World.units allocation')
end
-- A normal mission is larger than the old ship-only privacy budget. Dead
-- unrelated units still count toward traversal bounds but cannot alias materials.
do
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT) end
    end
    local ffi = require('ffi')
    for i = #f.world_units.main + 1, 16348 do
        local ref = 10000 + i
        f.units[ref] = { alive = false }
        f.world_units.main[i] = ffi.cast('void *', ref * 4 + 1)
    end
    local enumerations, list = 0, f.E.World.units
    f.E.World.units = function(world) enumerations = enumerations + 1; return list(world) end
    assert(f.discovery.prove_private(targets), 'Normal mission-sized census refused the assigned weapon')
    assert(enumerations <= 5, 'Privacy proof enumerated the whole mission per binding')
end
print('PASS mission census size, pre-allocation count guard and bounded read-only receipt enumeration')

do
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local target = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    f.discovery.with_validation_batch(function()
        f.discovery.with_validation_batch(function() assert(f.discovery.present(target)) end)
    end)
    local ok = pcall(f.discovery.with_validation_batch, function()
        f.discovery.with_validation_batch(function() coroutine.yield() end)
    end)
    assert(not ok, 'Nested read-only census escaped across frames')
    f.snapshots[1].weapon_object = f.snapshots[1].weapon_object + 1
    assert(not f.discovery.present(target), 'Failed/yielded census retained stale receipt validation')
end
print('PASS nested read-only scopes reject yields and release cached identities on failure')

do
    local f = fixture()
    local receipt = assert(f.discovery.capture(1))
    local b = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    local w,h = f.discovery.shape(b)
    assert(w==23 and h==8)
    f.documents[f.A] = nil
    w,h = f.discovery.shape(b)
    assert(w==23 and h==8, 'Loaded metadata depended on archived pixels')
    f.texture_shapes[f.A][1]=22
    assert(not f.discovery.shape(b), 'Unsupported texture width accepted')
    f.texture_shapes[f.A][1]=23
    f.textures[b.material][D.LUT]=f.P
    assert(not f.discovery.shape(b), 'Foreign texture binding accepted as shape proof')
    assert(#f.writes==0 and f.allocations==0)
end
print('PASS loaded shape read is bounded, independent of archived pixels and refuses foreign bindings')
