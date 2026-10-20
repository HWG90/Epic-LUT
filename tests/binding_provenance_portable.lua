-- The Python harness injects a real incremental hashlib SHA256 provider.
assert(_VERSION == 'Lua 5.1' and type(sha256_start) == 'userdata')
local hashes, reads = 0, 0
local function digest(bytes)
    hashes = hashes + 1
    local hash = sha256_start()
    if type(bytes) == 'string' then
        hash.update(bytes)
    else
        while true do
            local chunk = bytes()
            if chunk == nil then break end
            hash.update(chunk)
        end
    end
    return hash.finish()
end
local old_m = m
m = { platform = { digest = digest } }
local P = dofile('src/presets/binding_provenance.lua')
assert(hashes == 0 and reads == 0, 'Loading provenance performed hashing or reader work')
local empty = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
local abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
assert(P.digest('') == empty and P.digest('abc') == abc)
local function chunks(chunk, count)
    return function()
        reads = reads + 1
        if count == 0 then return nil end
        count = count - 1
        return chunk
    end
end
assert(P.digest(chunks('abc', 1), 3) == abc and P.digest(chunks('', 0), 0) == empty)
local function bad(bytes, expected, message)
    local ok, why = pcall(P.digest, bytes, expected)
    assert(not ok and tostring(why):find(message, 1, true), tostring(why))
end
local before = hashes
for _, value in ipairs({ false, true, 1, {}, coroutine.create(function() end) }) do
    bad(value, nil, 'Invalid binding digest payload')
end
bad(string.rep('x', P.MAX_PART + 1), nil, 'Invalid binding digest payload')
for _, expected in ipairs({ -1, 1.5, math.huge, -math.huge, 0 / 0, 9007199254740992, '3', false, {} }) do
    bad(chunks('abc', 1), expected, 'Invalid binding digest expected length')
end
bad('abc', 3, 'Invalid binding digest expected length')
assert(hashes == before, 'Invalid payload or declared length reached SHA256 service')
bad(chunks('abc', 1), 4, 'Binding digest file length differs')
bad(chunks('abc', 1), 2, 'Binding digest file exceeds its limit')
bad(chunks('a', 1), 0, 'Binding digest file exceeds its limit')
bad(chunks('', 1), 0, 'Invalid binding digest chunk')
bad(chunks(string.rep('x', 65537), 1), 65537, 'Invalid binding digest chunk')
bad(function() return false end, nil, 'Invalid binding digest chunk')
bad(function() error('reader failed explicitly', 0) end, nil, 'reader failed explicitly')
local result, step = nil, 0
local job = coroutine.create(function()
    result = P.digest(function()
        step = step + 1
        coroutine.yield('reader checkpoint')
        return step <= 3 and ('abc'):sub(step, step) or nil
    end, 3)
end)
local resumptions = 0
while coroutine.status(job) ~= 'dead' do
    local ok, why = coroutine.resume(job)
    assert(ok, why)
    resumptions = resumptions + 1
end
assert(result == abc and resumptions == 5, 'Staged SHA256 reader did not yield across digest boundary')
local large_chunk, large_count = string.rep('x', 65536), 8193
assert(P.digest(chunks(large_chunk, large_count), #large_chunk * large_count)
    == '8bb025e68d2f9f697f887606ed50d6e29322bb579851d07162ba47979db3313f',
    'Exact-sized stream above default 512 MiB bound changed')
bad(chunks(large_chunk, large_count), nil, 'Binding digest file exceeds its limit')
for _, output in ipairs({ '', string.rep('a', 63), string.rep('A', 64), string.rep('g', 64),
    string.rep('a', 65), false, {}, 1 }) do
    m.platform.digest = function() return output end
    bad('abc', nil, 'Invalid binding SHA256 result')
end
m.platform.digest = function() return nil end
bad('abc', nil, 'Invalid binding SHA256 result')
m.platform.digest = function() return abc end
bad(chunks('abc', 1), 3, 'Binding digest service did not consume the complete reader')
m.platform.digest = function(reader)
    reader()
    return abc
end
bad(chunks('abc', 1), 3, 'Binding digest service did not consume the complete reader')
m.platform.digest = function(reader)
    reader();reader();reader()
    return abc
end
bad(chunks('abc', 1), 3, 'Binding digest reader consumed after completion')
m.platform = {}
bad('abc', nil, 'Portable binding SHA256 service unavailable')
local Cache = dofile('src/presets/binding_source_cache.lua')
local opens, overrides = 0, 0
local function writable(counter)
    return { open = function(_, mode)
        assert(mode == 'wb')
        counter()
        return { write = function() return true end, close = function() return true end }
    end }
end
local model = {
    binding_provenance_script = '61', binding_provenance_reader = '62', original_snapshot_reader = '63',
    file_io = writable(function() opens = opens + 1 end),
    windows = {
        process_id = function() return 123 end,
        verify_interface = function() error('Portable cache queried a raw kernel interface') end,
        game_data = function() return 'C:/fixture game/data' end,
        launch_worker = function()
            return { stop = function() return true end, running = function() return false end, close = function() end }
        end,
    },
}
local host = { paths = { cache = 'C:/fixture cache', directory_exists = function() return true end } }
local cache = Cache.new(model, host)
assert(opens == 0, 'Constructing binding cache performed file work')
assert(cache.start({ { resource = '0000000000000111', archive = '1234567890abcdef' } }) and cache.close())
assert(opens == 6, 'Binding cache bypassed shared file_io service')
host.io = writable(function() overrides = overrides + 1 end)
cache = Cache.new(model, host)
assert(cache.start({ { resource = '0000000000000111', archive = '1234567890abcdef' } }) and cache.close())
assert(opens == 6 and overrides == 6, 'Explicit binding cache IO override was ignored')
m = old_m
print('PASS portable binding SHA256: real hashes, exact bounds, failing readers, output proof checks, no idle work, yieldable readers and shared cache file service')
