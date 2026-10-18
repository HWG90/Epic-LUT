-- Ask the game's own allocator to clone an unmodified weapon configuration.
-- An empty customization descriptor leaves every gameplay byte unchanged.
local P = {}
local signatures = {
    { 0x7512e0, '48895c240848896c2410488974241848897c242041564883ec408b4208498be83b051e29d3024c8bf2488bd90f848600' },
    { 0x515540, '48895c240848896c24104889742418574883ec208b5a04498bf0448b4a08488bfa4403cb488be9413bd973320f1f4000' },
}
local function u32(bytes, offset)
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    assert(d, 'Short private configuration read')
    return a + b * 256 + c * 65536 + d * 16777216
end
function P.new(deps)
    local function read(address, size)
        assert(type(address) == 'number' and address >= 65536 and address + size < 2 ^ 47)
        local bytes = deps.read(address, size)
        assert(type(bytes) == 'string' and #bytes == size, 'Private weapon configuration unavailable')
        return bytes
    end
    local function pointer(address)
        local bytes = read(address, 8)
        local value = u32(bytes, 0) + u32(bytes, 4) * 4294967296
        assert(value >= 65536 and value < 2 ^ 47, 'Private configuration pointer bounds')
        return value
    end
    local function index(manager, entity)
        local header = read(manager + 0x2b8, 16)
        local capacity, empty = u32(header, 8), u32(header, 12)
        assert(capacity >= 2 and capacity <= 4096, 'Private configuration map bounds')
        local data, found = pointer(manager + 0x2b8), nil
        for row = 0, capacity - 1 do
            local bytes = read(data + row * 8, 8)
            if u32(bytes, 0) == entity and entity ~= empty then
                assert(found == nil, 'Duplicate private configuration identity')
                found = u32(bytes, 4)
                assert(found < 4096, 'Private configuration index bounds')
            end
        end
        return found
    end
    return function(identity, manager, owner_at, owner)
        local game = assert(deps.module('game.dll'))
        for _, signature in ipairs(signatures) do
            local expected = signature[2]:gsub('..', function(pair)
                return string.char(tonumber(pair, 16))
            end)
            assert(read(game + signature[1], #expected) == expected, 'Private weapon allocator signature changed')
        end
        assert(
            pointer(game + 0x3326a38) == manager and read(owner_at, 24) == owner,
            'Weapon configuration owner changed'
        )
        assert(u32(owner, 8) == identity.weapon_entity, 'Private configuration belongs to another weapon')
        if index(manager, identity.weapon_entity) ~= nil then
            return true
        end
        local count = u32(read(manager + 0x2f0, 4), 0)
        local allocated = u32(read(manager + 0x25c, 4), 0)
        assert(count < allocated and allocated <= 4096, 'Private configuration storage is full')
        local storage = pointer(manager + 0x2f8)
        -- This is the same bounded resource table used by the game's getter.
        local database = pointer(pointer(game + 0x346bf98) + 0xf12cf0)
        local original
        for row = 0, 381 do
            local bytes = read(database + row * 16, 16)
            if bytes:sub(1, 8) == owner:sub(1, 8) then
                assert(not original, 'Duplicate stock weapon configuration')
                local stock = u32(bytes, 8)
                assert(stock < 382, 'Stock weapon configuration index bounds')
                original = database + 0x17e0 + stock * 0x1308
            end
        end
        assert(original, 'Exact stock weapon configuration unavailable')
        local baseline = read(original, 0x1308)
        assert(
            pointer(game + 0x3326a38) == manager and read(owner_at, 24) == owner,
            'Weapon changed before private configuration allocation'
        )
        deps.clone(game + 0x7512e0, manager, owner_at)
        assert(
            pointer(game + 0x3326a38) == manager and read(owner_at, 24) == owner,
            'Weapon changed during private configuration allocation'
        )
        assert(pointer(manager + 0x2f8) == storage, 'Private configuration storage moved')
        assert(index(manager, identity.weapon_entity) == count, 'Private configuration allocation readback failed')
        assert(u32(read(manager + 0x2f0, 4), 0) == count + 1, 'Private configuration count changed unexpectedly')
        assert(read(storage + count * 0x1308, 0x1308) == baseline, 'Private clone changed weapon configuration bytes')
        assert(read(original, 0x1308) == baseline, 'Shared stock weapon configuration changed')
        return true
    end
end
return P
