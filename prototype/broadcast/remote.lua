-- Experimental roster discovery. Does not alter the upstream local-only adapter.
local R = {}
function R.list(memory, game, avatar)
    local ffi = require('ffi')
    local read = avatar.reader(memory)
    local function word(address)
        local b = assert(read(address, 4), 'Unreadable player record')
        return avatar.u32(b, 0)
    end
    local function pointer(address)
        local b = assert(read(address, 8), 'Unreadable player pointer')
        local p = avatar.u32(b, 0) + avatar.u32(b, 4) * 4294967296
        assert(p >= 65536 and p < 0x800000000000, 'Invalid player pointer')
        return p
    end
    local manager = pointer(game + avatar.PLAYERS)
    local count = word(manager + 132)
    assert(count > 0 and count <= 8, 'Invalid player count')
    local entities, avatars = pointer(game + avatar.ENTITIES), pointer(game + avatar.AVATARS)
    local result = {}
    for i = 0, count - 1 do
        local p = pointer(manager + 232 + 8 * i)
        local b = assert(read(p, 24))
        local id, owned = avatar.u32(b, 8), b[20] % 2 == 1
        local index = assert(avatar.lookup(read, manager + 208, id), 'Player not indexed')
        assert(index < 8)
        local peer = assert(read(manager + 712 + 56 * index, 8))
        local low, high = avatar.u32(peer, 0), avatar.u32(peer, 4)
        local unit = word(manager + 936 + 32 * index)
        local ei = assert(avatar.lookup(read, entities + 0xF22EC8, unit), 'Player avatar unavailable')
        local entity = assert(read(entities + 0xF32F18 + 24 * ei, 24))
        assert(avatar.u32(entity, 0) == 0x294dfa97 and avatar.u32(entity, 4) == 0x4d1c334d,
            'Player entity is not an avatar')
        local ai = assert(avatar.lookup(read, avatars + 248, avatar.u32(entity, 8)))
        assert(ai < word(avatars + 0x6c), 'Avatar index out of bounds')
        result[#result + 1] = {player=id, unit=unit, peer_low=low, peer_high=high, owned=owned,
            units_at=avatars + 5532272 + 440 * ai + 220,
            peer=string.format('%08x%08x', high, low)}
    end
    return result
end
return R
