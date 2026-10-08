local ffi = require('ffi')
local Sync = dofile('vendor/lobby_sync.lua')
local callbacks, posted = {}, nil
local function lookup(name, ctype)
    local fn
    if name == 'PFLobbyPostUpdate' then
        fn = function(handle, user, _, update)
            assert(handle == 0x9000000000000001ULL, '64-bit lobby handle lost precision')
            posted = ffi.cast('const EpicLobbyMemberUpdate *', update)
            return 0
        end
    elseif name == 'PFLobbyGetMembers' then fn = function() return 0 end
    else
        fn = function(_, _, key, out)
            local index = tonumber(ffi.string(key):match('eplut([0-3])'))
            out[0] = posted.values[index]
            return 0
        end
    end
    local cb = ffi.cast(ctype, fn); callbacks[#callbacks + 1] = cb; return cb
end
local api = assert(Sync.natives(lookup))
local user = ffi.new('EpicLobbyEntityKey[1]')
local packet = string.rep('abc/+', 500)
assert(api.post(0x9000000000000001ULL, ffi.cast('uintptr_t', user), packet) == 0)
collectgarbage('collect'); collectgarbage('collect')
assert(posted.count == 4 and ffi.string(posted.keys[0]) == 'eplut0')
local function read_text(address) return ffi.string(ffi.cast('const char *', address)) end
assert(api.property_text(0x9000000000000001ULL, ffi.cast('uintptr_t', user), read_text) == packet, 'Chunked packet changed')
assert(not pcall(api.post, 0x9000000000000001ULL, ffi.cast('uintptr_t', user), string.rep('x',3601)))
assert(api.post(0x9000000000000001ULL, ffi.cast('uintptr_t', user), nil) == 0)
assert(posted.values[0] == nil and posted.values[3] == nil, 'Clear did not remove every chunk')

local blocks = {}
local function put(address, bytes) blocks[address] = bytes end
local function u32(address, n) put(address, ffi.string(ffi.new('uint32_t[1]', n),4)) end
local function u64(address, n) put(address, ffi.string(ffi.new('uint64_t[1]', n),8)) end
local function str(address, text) put(address, text .. string.rep('\0', 1001 - #text)) end
local game, context, engine, pl = 0x100000, 0x200000, 0x300000, 0x400000
u64(game + Sync.CONTEXT, context); u64(context + Sync.LOBBY, engine); u64(engine + Sync.PLAYFAB, pl)
u32(pl + Sync.PL_STATE, 3); u64(pl + Sync.PL_HANDLE, 0x9000000000000001ULL)
u64(pl + Sync.PL_USER, 0x500000); str(0x500000, '123')
local key_at = 0x600000
u64(key_at, 0x700000); u64(key_at + 8, 0x710000)
str(0x700000, '123'); str(0x710000, 'title_player_account')
local memory = {read_into = function(pointer, size, buffer)
    local address = tonumber(ffi.cast('uintptr_t', pointer))
    for start, bytes in pairs(blocks) do
        if address >= start and address + size <= start + #bytes then
            ffi.copy(buffer, bytes:sub(address - start + 1, address - start + size), size); return true
        end
    end
    return false
end}
local posts, found_own = 0, true
local session = Sync.session({memory = memory, game = game, note = function() end,
    natives = function() return {
        members = function() return found_own and 1 or 0, key_at end,
        property = function() return nil end,
        post = function(handle, own, text)
            assert(handle == 0x9000000000000001ULL and own == key_at, 'Post did not use PlayFab member identity')
            posts = posts + 1; return 0
        end,
    } end})
session.poll(0, packet); session.poll(300, packet); session.poll(599, packet)
assert(posts == 0, 'Posted before lobby was stable for ten seconds')
session.poll(600, packet)
assert(posts == 1)
session.poll(720, packet)
assert(posts == 1, 'Unchanged packet reposted')
found_own = false
session.poll(1200, 'new'); session.poll(1800, 'new')
assert(posts == 1, 'Posted without safe local member identity')
found_own = true
assert(session.clear() and posts == 2)
print('PASS lobby transport: exact uint64 handles, retained immutable buffers, bounded chunks, clear, stable lobby and safe member identity')
