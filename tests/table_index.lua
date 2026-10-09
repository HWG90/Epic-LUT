local I = dofile('src/imports/table_index.lua')
local reads = {}
local index = I.new({
    max_bytes = 100,
    read = function(path, limit)
        assert(limit == 100)
        reads[#reads + 1] = path
        return path
    end,
    decode = function(bytes)
        if bytes == 'bad' then
            error('malformed DDS')
        end
        return {}, 23, 8
    end,
})
local paths = { 'one', 'two' }
local cache = {}
local job = index.start(paths, cache, { two = 'id' })
paths[2] = 'changed'
assert(coroutine.resume(job) and cache.one and not cache.two, 'Indexer did not yield after one document')
assert(
    coroutine.resume(job) and cache.two.resource == 'id' and not cache.changed,
    'Indexer queue drifted or lost metadata'
)
assert(coroutine.resume(job) and coroutine.status(job) == 'dead')
local cached = index.start({ 'one' }, cache, {})
assert(coroutine.resume(cached) and #reads == 2, 'Cached table was read again')
local failed = index.start({ 'bad' }, cache, {})
assert(not coroutine.resume(failed) and not cache.bad, 'Malformed table poisoned cache')
print(
    'PASS table indexing: bounded reads, cooperative yielding, immutable queue, resource IDs and cache/failure isolation'
)

local patterns = I.new({
    max_bytes = 100,
    read = function(path)
        return path
    end,
    decode = function()
        return {}, 3, 1
    end,
})
local cache3 = {}
local pattern_job = patterns.start({ 'pattern' }, cache3, { pattern = '1234567890abcdef' })
assert(
    coroutine.resume(pattern_job) and cache3.pattern.width == 3 and cache3.pattern.resource == '1234567890abcdef',
    'Archive Pattern LUT was discarded by indexer'
)
