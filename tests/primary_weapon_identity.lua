local I = dofile('src/weapons/primary_identity.lua')
local function unhex(value)
    return (value:gsub('..', function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
local function u(value)
    local bytes = {}
    for index = 1, 4 do
        bytes[index] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(bytes)
end
local function fixture()
    local cells, regions, next_address = {}, {}, 0x10000000
    local function alloc(size)
        local address = next_address
        next_address = address + size + 32
        regions[#regions + 1] = { address, address + size }
        return address
    end
    local function put(address, bytes)
        for index = 1, #bytes do
            cells[address + index - 1] = bytes:byte(index)
        end
    end
    local function U(address, value)
        put(address, u(value))
    end
    local function P(address, value)
        put(address, u(value) .. u(0))
    end
    local function read(address, size)
        local bytes = {}
        for offset = 0, size - 1 do
            local value = cells[address + offset]
            if value == nil then
                for _, region in ipairs(regions) do
                    if address + offset >= region[1] and address + offset < region[2] then
                        value = 0
                        break
                    end
                end
            end
            if value == nil then
                return nil
            end
            bytes[#bytes + 1] = string.char(value)
        end
        return table.concat(bytes)
    end
    local function map(address, entries)
        local data = alloc(64)
        P(address, data)
        U(address + 8, 8)
        U(address + 12, 0xffffffff)
        U(address + 16, 1)
        for index = 0, 7 do
            U(data + index * 8, 0xffffffff)
        end
        for key, value in pairs(entries) do
            local index = key % 8
            while read(data + index * 8, 4) ~= u(0xffffffff) do
                index = (index + 1) % 8
            end
            U(data + index * 8, key)
            U(data + index * 8 + 4, value)
        end
    end
    local game = 0x100000
    put(game, 'MZ' .. string.rep('\0', 62))
    U(game + 0x3c, 0x100)
    put(game + 0x100, 'PE\0\0' .. string.rep('\0', 124))
    U(game + 0x108, 0x6ab3b43f)
    U(game + 0x150, 0x4744000)
    for _, entry in ipairs({
        { 0x607200, '488b0561f2d10283b88400000000' },
        { 0x6066ed, '8b9410a8030000' },
        { 0xfd9c93, '4c8b15fe224902' },
        { 0xfd9cc5, '498b9ac82ef200' },
        { 0xfd9d83, '498b9ab0aef100' },
        { 0x9a83e0, '4c8b1551e39702' },
    }) do
        put(game + entry[1], unhex(entry[2]))
    end
    local players, owner, inv = alloc(0x500), alloc(0xf40000), alloc(0x100)
    P(game + 0x3326468, players)
    P(game + 0x346bf98, owner)
    P(game + 0x3326738, inv)
    local player = alloc(24)
    U(player + 8, 9)
    cells[player + 20] = 1
    U(players + 0x84, 1)
    P(players + 0xe8, player)
    map(players + 0xd0, { [9] = 0 })
    U(players + 0x3a8, 77)
    local avatar, primary, secondary = owner + 0xf32f18, owner + 0xf32f18 + 24, owner + 0xf32f18 + 48
    U(avatar, 0x294dfa97)
    U(avatar + 4, 0x4d1c334d)
    U(avatar + 8, 10)
    U(avatar + 16, 77)
    cells[avatar + 20] = 1
    local ref = 3 * 0x400000 + 2
    -- Public DBF-HUD/src/weapon_names.lua:49: 5fecab819f96a3e8 = BR-14 Adjudicator.
    U(primary, 0x9f96a3e8)
    U(primary + 4, 0x5fecab81)
    U(primary + 8, 20)
    U(primary + 12, ref)
    U(primary + 16, 88)
    cells[primary + 20] = 1
    U(secondary, 0x12345678)
    U(secondary + 8, 21)
    cells[secondary + 20] = 1
    map(owner + 0xf22ec8, { [77] = 0 })
    map(owner + 0xf1aeb0, { [10] = 0, [20] = 1, [21] = 2 })
    map(inv + 0x28, { [10] = 0 })
    U(inv + 0x14, 1)
    local inv_registry, inventory = alloc(8), alloc(48)
    P(inv + 0x40, inv_registry)
    P(inv_registry, avatar)
    P(inv + 0x50, inventory)
    U(inventory, 20)
    U(inventory + 4, 21)
    U(inventory + 28, 2)
    local api, unit_api, getter, resolver, registry_slot = alloc(32), alloc(0x100), alloc(64), alloc(128), alloc(8)
    local registry, objects, generations, object = alloc(0xb0), alloc(32), alloc(4), alloc(16)
    P(game + 0x3326308, api)
    P(api + 0x18, unit_api)
    P(unit_api + 0x90, getter)
    put(getter, unhex('40534883ec204863da'))
    cells[getter + 9] = 0xe8
    U(getter + 10, resolver - getter - 14)
    put(getter + 14, unhex('488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3'))
    put(resolver, unhex('48895c24084889742410574883ec20488b35'))
    U(resolver + 0x12, registry_slot - resolver - 0x16)
    put(
        resolver + 0x25,
        unhex('8bc325ffff3f003b8698000000720433dbeb1c8bc8488b86a0000000c1eb16381c0175eb488b8688000000488b1cc8')
    )
    P(registry_slot, registry)
    U(registry + 0x98, 4)
    P(registry + 0x88, objects)
    P(registry + 0xa0, generations)
    P(objects + 16, object)
    cells[generations + 2] = 3
    U(object + 8, ref)
    local build_ok, read_hook = true, nil
    local deps = {
        module = function(name)
            assert(name == 'game.dll')
            return game
        end,
        verify_build = function(expected)
            assert(expected.exe_sha256 == I.BUILD.exe_sha256 and expected.game_sha256 == I.BUILD.game_sha256)
            return build_ok, 'Unsupported game build'
        end,
        read = function(address, size)
            if read_hook then
                read_hook(address, size)
            end
            return read(address, size)
        end,
    }
    return {
        probe = I.new(deps),
        U = U,
        P = P,
        put = put,
        cells = cells,
        game = game,
        inv = inv,
        players = players,
        avatar = avatar,
        player = player,
        primary = primary,
        inventory = inventory,
        inv_registry = inv_registry,
        ref = ref,
        registry = registry,
        object = object,
        getter = getter,
        resolver = resolver,
        generations = generations,
        objects = objects,
        deps = deps,
        set_build = function(value)
            build_ok = value
        end,
        hook = function(value)
            read_hook = value
        end,
    }
end
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
local function refusal(f, pattern)
    local value, why = f.probe.snapshot()
    assert(value == nil and tostring(why):find(pattern, 1, true), tostring(why))
end
test('primary slot remains selected while secondary or support is held', function()
    local f = fixture()
    for _, slot in ipairs({ 1, 2, 3, 6, 0 }) do
        f.U(f.inventory + 28, slot)
        f.U(f.inventory + 8, 23)
        f.U(f.inventory + 12, 24)
        local value = assert(f.probe.snapshot())
        assert(value.primary_entity == 20 and value.primary_resource_hex == '5fecab819f96a3e8')
        assert(value.primary_unit_ref == f.ref and value.primary_native_ref == 88 and value.primary_object == f.object)
        assert(value.avatar_entity == 10 and value.player_entity == 9 and value.provenance == 'inventory_slot_1')
        assert(value.inventory_slot == slot and value.reads < 512 and value.bytes < 65536)
        if slot == 2 then
            assert(value.inventory_held_entity == 21)
        end
        if slot == 3 then
            assert(value.inventory_held_entity == 23)
        end
    end
end)
test('executable hashes, PE stamp and instruction signatures are mandatory', function()
    local f = fixture()
    f.set_build(false)
    refusal(f, 'Unsupported game build')
    f = fixture()
    f.U(f.game + 0x108, 0)
    refusal(f, 'Unsupported game PE build')
    f = fixture()
    f.cells[f.game + 0xfd9d83] = 0
    refusal(f, 'layout signature changed')
end)
test('inventory bounds, component identity and avatar type are enforced', function()
    local f = fixture()
    f.U(f.inv + 0x14, 4097)
    refusal(f, 'Inventory bounds changed')
    f = fixture()
    f.P(f.inv_registry, f.primary)
    refusal(f, 'Inventory avatar identity changed')
    f = fixture()
    f.U(f.avatar, 0)
    refusal(f, 'Local avatar type or ownership changed')
    f = fixture()
    f.cells[f.avatar + 20] = 0
    refusal(f, 'Local avatar type or ownership changed')
end)
test('invalid, unowned and avatar-as-weapon candidates are refused', function()
    local f = fixture()
    f.U(f.inventory, 0xffffffff)
    refusal(f, 'No primary inventory candidate')
    f = fixture()
    f.cells[f.primary + 20] = 0
    refusal(f, 'Primary entity identity or ownership changed')
    f = fixture()
    f.U(f.primary + 8, 99)
    refusal(f, 'Primary entity identity or ownership changed')
    f = fixture()
    f.U(f.primary, 0x294dfa97)
    f.U(f.primary + 4, 0x4d1c334d)
    refusal(f, 'Primary entity identity or ownership changed')
end)
test('UnitRef generation, object identity and native resolver are checked', function()
    local f = fixture()
    f.cells[f.generations + 2] = 4
    refusal(f, 'Primary Unit generation changed')
    f = fixture()
    f.U(f.object + 8, f.ref + 1)
    refusal(f, 'Primary Unit object identity changed')
    f = fixture()
    f.U(f.registry + 0x98, 0x400001)
    refusal(f, 'Native Unit index bounds')
    f = fixture()
    f.cells[f.getter] = 0
    refusal(f, 'Unknown native Unit getter')
    f = fixture()
    f.cells[f.resolver] = 0
    refusal(f, 'Unknown native Unit resolver')
    f = fixture()
    f.U(f.primary + 12, 0xffffffff)
    refusal(f, 'Invalid primary Unit reference')
end)
test('ownership and generation changes during reads invalidate the whole result', function()
    local f = fixture()
    local times = 0
    f.hook(function(address)
        if address == f.inventory then
            times = times + 1
            if times == 2 then
                f.U(f.inventory, 21)
            end
        end
    end)
    refusal(f, 'Primary ownership changed during snapshot')
    f = fixture()
    times = 0
    f.hook(function(address)
        if address == f.generations + 2 then
            times = times + 1
            if times == 2 then
                f.cells[address] = 4
            end
        end
    end)
    refusal(f, 'Primary Unit recycled during snapshot')
end)
test('unreadable bytes and changed game module fail without native calls', function()
    local f = fixture()
    f.deps.read = function()
        return nil
    end
    refusal(f, 'Unreadable primary identity memory')
    f = fixture()
    assert(f.probe.validate())
    f.deps.module = function()
        return f.game + 1
    end
    refusal(f, 'game.dll changed')
end)
print('PASS primary weapon read-only identity: ' .. cases .. ' focused contracts')
