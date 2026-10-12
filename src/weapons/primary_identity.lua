-- Bounded read-only identity probe. No engine calls, writes or forged Lua Units.
-- Contracts: public DBF-HUD src/reader.lua, src/pose.lua and WEAPON_BINDING.md.
-- Inventory enum 1 selects +0 in that reader; retain this candidate independently
-- of the held-weapon selector. Live confirmation supplies the semantic label.
local I = {}
local BUILD = {
    exe_sha256 = 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
    game_sha256 = '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
}
I.BUILD = { exe_sha256 = BUILD.exe_sha256, game_sha256 = BUILD.game_sha256 }
local L = {
    player = 0x3326468,
    owner = 0x346bf98,
    inventory = 0x3326738,
    entity_map = 0xf1aeb0,
    unit_map = 0xf22ec8,
    records = 0xf32f18,
}
local signatures = {
    { 0x607200, '488b0561f2d10283b88400000000' },
    { 0x6066ed, '8b9410a8030000' },
    { 0xfd9c93, '4c8b15fe224902' },
    { 0xfd9cc5, '498b9ac82ef200' },
    { 0xfd9d83, '498b9ab0aef100' },
    { 0x9a83e0, '4c8b1551e39702' },
}
local function unhex(value)
    return (value:gsub('..', function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
local function u32(bytes, offset)
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    assert(d, 'Short uint32')
    return a + b * 256 + c * 65536 + d * 16777216
end
local function i32(bytes, offset)
    local value = u32(bytes, offset)
    return value >= 0x80000000 and value - 4294967296 or value
end
local function owned(record)
    return record:byte(21) % 2 == 1
end
local function resource(record)
    return string.format('%08x%08x', u32(record, 4), u32(record, 0))
end
function I.new(deps)
    assert(
        type(deps) == 'table'
            and type(deps.module) == 'function'
            and type(deps.read) == 'function'
            and type(deps.verify_build) == 'function',
        'Read-only primary identity dependencies unavailable'
    )
    local self, game, checked = {}, nil, false
    local reads, total = 0, 0
    local function reset()
        reads, total = 0, 0
    end
    local function read(address, size)
        assert(
            type(address) == 'number' and address % 1 == 0 and address >= 65536 and address + size < 2 ^ 47,
            'Invalid read address'
        )
        assert(type(size) == 'number' and size % 1 == 0 and size >= 1 and size <= 4096, 'Invalid read size')
        reads, total = reads + 1, total + size
        assert(reads <= 512 and total <= 65536, 'Primary identity read budget exceeded')
        local bytes = deps.read(address, size)
        assert(type(bytes) == 'string' and #bytes == size, 'Unreadable primary identity memory')
        return bytes
    end
    local function pointer(address)
        local bytes = read(address, 8)
        local value = u32(bytes, 0) + u32(bytes, 4) * 4294967296
        assert(value >= 65536 and value < 2 ^ 47, 'Invalid pointer')
        return value
    end
    local function map(address, key, limit)
        local header = read(address, 20)
        local capacity, empty, mult = u32(header, 8), u32(header, 12), u32(header, 16)
        if capacity == 0 or key == empty or key == 0xffffffff then
            return nil
        end
        assert(capacity <= limit, 'Invalid map capacity')
        local power = capacity
        while power > 1 and power % 2 == 0 do
            power = power / 2
        end
        assert(power == 1, 'Invalid map capacity')
        local data = pointer(address)
        local start = (
            (key % 65536) * (mult % 65536)
            + ((math.floor(key / 65536) * (mult % 65536) + (key % 65536) * math.floor(mult / 65536)) % 65536)
                * 65536
        ) % 4294967296
        for probe = 0, math.min(capacity, 128) - 1 do
            local row = read(data + ((start + probe) % capacity) * 8, 8)
            local found = u32(row, 0)
            if found == empty then
                return nil
            end
            if found == key then
                local index = u32(row, 4)
                return index ~= 0xffffffff and index or nil
            end
        end
        error('Map probe limit', 0)
    end
    local function validate()
        reset()
        local ok, why = deps.verify_build({ exe_sha256 = BUILD.exe_sha256, game_sha256 = BUILD.game_sha256 })
        assert(ok == true, why or 'Unsupported game build')
        game = assert(deps.module('game.dll'), 'game.dll is unavailable')
        local dos = read(game, 64)
        assert(dos:sub(1, 2) == 'MZ', 'DOS signature changed')
        local pe = u32(dos, 0x3c)
        assert(pe < 0x100000, 'PE offset bounds')
        local header = read(game + pe, 0x80)
        assert(
            header:sub(1, 4) == 'PE\0\0' and u32(header, 8) == 0x6ab3b43f and u32(header, 0x50) == 0x4744000,
            'Unsupported game PE build'
        )
        for _, entry in ipairs(signatures) do
            local bytes = unhex(entry[2])
            assert(read(game + entry[1], #bytes) == bytes, 'Primary identity layout signature changed')
        end
        checked = true
        return true
    end
    function self.validate()
        checked = false
        local ok, value = pcall(validate)
        if not ok then
            return nil, tostring(value)
        end
        return value
    end
    local function snapshot()
        if not checked then
            validate()
        end
        reset()
        assert(deps.module('game.dll') == game, 'game.dll changed')
        local players, owner, inv = pointer(game + L.player), pointer(game + L.owner), pointer(game + L.inventory)
        local count = u32(read(players + 0x84, 4), 0)
        assert(count >= 1 and count <= 8, 'No bounded local player list')
        local player, player_at, player_record
        for index = 0, count - 1 do
            local at = pointer(players + 0xe8 + index * 8)
            local record = read(at, 24)
            if owned(record) then
                assert(not player, 'Ambiguous local player ownership')
                player, player_at, player_record = u32(record, 8), at, record
            end
        end
        assert(player and player ~= 0 and player ~= 0xffffffff, 'No local player')
        local player_index = map(players + 0xd0, player, 64)
        assert(player_index and player_index < count, 'Local player index changed')
        local avatar_ref_at = players + 0x3a8 + player_index * 32
        local avatar_ref = u32(read(avatar_ref_at, 4), 0)
        assert(avatar_ref ~= 0 and avatar_ref ~= 0x7fff and avatar_ref ~= 0xffffffff, 'No local avatar')
        local avatar_index = map(owner + L.unit_map, avatar_ref, 1048576)
        assert(avatar_index and avatar_index < 1048576, 'Local avatar entity unavailable')
        local avatar_at = owner + L.records + avatar_index * 24
        local avatar = read(avatar_at, 24)
        assert(
            resource(avatar) == '4d1c334d294dfa97' and owned(avatar) and u32(avatar, 16) == avatar_ref,
            'Local avatar type or ownership changed'
        )
        local avatar_id = u32(avatar, 8)
        assert(avatar_id ~= 0 and avatar_id ~= 0xffffffff, 'Invalid local avatar entity')
        local inventory_index = map(inv + 0x28, avatar_id, 65536)
        local inventory_count = u32(read(inv + 0x14, 4), 0)
        assert(
            inventory_count >= 1 and inventory_count <= 4096 and inventory_index and inventory_index < inventory_count,
            'Inventory bounds changed'
        )
        local inventory_registry = pointer(inv + 0x40)
        assert(
            read(pointer(inventory_registry + inventory_index * 8), 24) == avatar,
            'Inventory avatar identity changed'
        )
        local inventory_data = pointer(inv + 0x50)
        local inventory_at = inventory_data + inventory_index * 48
        local inventory = read(inventory_at, 48)
        local primary = u32(inventory, 0)
        assert(primary ~= 0 and primary ~= 0xffffffff and primary ~= avatar_id, 'No primary inventory candidate')
        local entity_index = map(owner + L.entity_map, primary, 1048576)
        assert(entity_index and entity_index < 1048576, 'Primary entity unavailable')
        local primary_at = owner + L.records + entity_index * 24
        local record = read(primary_at, 24)
        local hash = resource(record)
        assert(
            u32(record, 8) == primary and owned(record) and hash ~= '0000000000000000' and hash ~= '4d1c334d294dfa97',
            'Primary entity identity or ownership changed'
        )
        local ref, native_ref = u32(record, 12), u32(record, 16)
        assert(ref ~= 0 and ref ~= 0xffffffff, 'Invalid primary Unit reference')
        local api = pointer(game + 0x3326308)
        local unit_api = pointer(api + 0x18)
        local getter = pointer(unit_api + 0x90)
        local code = read(getter, 48)
        assert(
            code:sub(1, 9) == unhex('40534883ec204863da')
                and code:byte(10) == 0xe8
                and code:sub(15, 47) == unhex('488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3'),
            'Unknown native Unit getter'
        )
        local resolver = getter + 14 + i32(code, 10)
        code = read(resolver, 116)
        assert(
            code:sub(1, 18) == unhex('48895c24084889742410574883ec20488b35')
                and code:sub(0x26, 0x54)
                    == unhex(
                        '8bc325ffff3f003b8698000000720433dbeb1c8bc8488b86a0000000c1eb16381c0175eb488b8688000000488b1cc8'
                    ),
            'Unknown native Unit resolver'
        )
        local registry = pointer(resolver + 0x16 + i32(code, 0x12))
        local capacity = u32(read(registry + 0x98, 4), 0)
        local index, generation = ref % 0x400000, math.floor(ref / 0x400000) % 256
        assert(capacity >= 1 and capacity <= 0x400000 and index > 0 and index < capacity, 'Native Unit index bounds')
        local array, generations = pointer(registry + 0x88), pointer(registry + 0xa0)
        assert(read(generations + index, 1):byte() == generation, 'Primary Unit generation changed')
        local object = pointer(array + index * 8)
        assert(u32(read(object + 8, 4), 0) == ref, 'Primary Unit object identity changed')
        assert(
            read(primary_at, 24) == record
                and read(avatar_at, 24) == avatar
                and read(player_at, 24) == player_record
                and read(inventory_at, 48) == inventory,
            'Primary ownership changed during snapshot'
        )
        assert(
            u32(read(avatar_ref_at, 4), 0) == avatar_ref
                and pointer(inv + 0x50) == inventory_data
                and pointer(game + L.player) == players
                and pointer(game + L.owner) == owner
                and pointer(game + L.inventory) == inv,
            'Primary managers changed during snapshot'
        )
        assert(
            read(generations + index, 1):byte() == generation
                and pointer(array + index * 8) == object
                and u32(read(object + 8, 4), 0) == ref,
            'Primary Unit recycled during snapshot'
        )
        local slot = u32(inventory, 28)
        local held_offset = ({ [1] = 0, [2] = 4, [3] = 8, [4] = 16, [5] = 16, [6] = 12 })[slot]
        return {
            game_base = game,
            player_entity = player,
            avatar_entity = avatar_id,
            avatar_native_ref = avatar_ref,
            primary_entity = primary,
            primary_record = primary_at,
            primary_resource_hex = hash,
            primary_unit_ref = ref,
            primary_native_ref = native_ref,
            primary_object = object,
            inventory_slot = slot,
            inventory_held_entity = held_offset and u32(inventory, held_offset) or nil,
            provenance = 'inventory_slot_1',
            reads = reads,
            bytes = total,
        }
    end
    function self.snapshot()
        local ok, value = pcall(snapshot)
        if not ok then
            return nil, tostring(value)
        end
        return value
    end
    return self
end
return I
