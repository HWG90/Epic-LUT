local ffi = require('ffi')
local B = dofile('src/gear/binding_session.lua')
assert(B.MAX_BYTES == 64 * 1024 * 1024 and B.MAX_TEXTURES == 16384)
local document = { width = 23, height = 1, data = ffi.new('float[92]') }
document.data[0], document.data[3] = -0.25, 2.5
ffi.cast('uint32_t *', document.data)[17] = 0x80000000
local bytes = ffi.string(document.data, 368)
local function records(count)
    local result, placeholder = {}, {}
    for index = 1, count do
        result[index] = placeholder
    end
    return result
end
local function session(retain, creator)
    local b, object, creates, writes = { original = 10, current = 10 }, 10, 0, 0
    local deps = {
        retain = retain,
        present = function(target)
            return target == b
        end,
        binding = function()
            return object
        end,
        key = function()
            return 'material'
        end,
        create_texture = function(w, h, pixels)
            creates = creates + 1
            assert(w == 23 and h == 1 and ffi.string(pixels, 368) == bytes)
            if creator then
                return creator(pixels)
            end
            return { object = 20 }
        end,
        bind = function(_, value)
            object = value
            writes = writes + 1
        end,
    }
    return B.new(deps),
        b,
        function()
            return creates, writes, object
        end,
        function(value)
            object = value
        end
end
-- A running process already beyond either old ceiling gains bounded headroom;
-- retained resources are not discarded or overwritten to accomplish it.
local retain = { records = records(2048), bytes = 8 * 1024 * 1024, cache = {} }
local first_record = retain.records[1]
local store, b, counters = session(retain)
assert(store.apply(document, { b }) == 1)
local creates, writes, object = counters()
assert(creates == 1 and writes == 1 and object == 20)
assert(#retain.records == 2049 and retain.bytes == 8 * 1024 * 1024 + 368 and retain.records[1] == first_record)
assert(ffi.string(retain.records[#retain.records].data, 368) == bytes, 'Retained upload bytes changed')
document.data[0] = 0.75
assert(retain.records[#retain.records].data[0] == -0.25, 'New headroom made old uploads mutable')
document.data[0] = -0.25
assert(store.restore())
assert(
    retain.bytes == 8 * 1024 * 1024 + 368 and #retain.records == 2049,
    'Restore falsely reclaimed retained resources'
)
for _, limits in ipairs({ { count = B.MAX_TEXTURES, bytes = 0 }, { count = 0, bytes = B.MAX_BYTES } }) do
    retain = { records = records(limits.count), bytes = limits.bytes, cache = {} }
    store, b, counters = session(retain)
    local ok, reason = pcall(store.apply, document, { b })
    creates, writes, object = counters()
    assert(
        not ok
            and reason:find('Reload Epic LUT to reclaim eligible textures', 1, true)
            and reason:find('game restart clears all', 1, true)
            and reason:find('Local draft kept', 1, true)
            and reason:find('Restore alone does not clear the budget', 1, true)
    )
    assert(
        reason:find('/16384 textures', 1, true) and reason:find('/64 MiB', 1, true),
        'Budget diagnostics omitted usage/limits'
    )
    assert(creates == 0 and writes == 0 and object == 10, 'Budget cap was checked after native allocation or binding')
    assert(retain.bytes == limits.bytes and #retain.records == limits.count)
    assert(ffi.string(document.data, 368) == bytes, 'Budget rejection changed the local draft')
end
-- Cache reuse remains available even when both creation ceilings are reached.
local cache_key = '23:1:' .. bytes
retain = {
    records = records(B.MAX_TEXTURES),
    bytes = B.MAX_BYTES,
    cache = {
        [cache_key] = { object = 20, width = 23, height = 1, data = document.data },
    },
}
store, b, counters = session(retain)
assert(store.apply(document, { b }) == 1)
creates, writes, object = counters()
assert(
    creates == 0 and writes == 1 and object == 20 and #retain.records == B.MAX_TEXTURES and retain.bytes == B.MAX_BYTES
)
-- Ownership validation still precedes every allocation, including cache hits.
retain = { records = {}, bytes = 0, cache = {} }
local foreign
store, b, counters, foreign = session(retain)
foreign(99)
assert(not pcall(store.apply, document, { b }))
creates, writes, object = counters()
assert(creates == 0 and writes == 0 and object == 99 and #retain.records == 0 and retain.bytes == 0)
-- A native call may have partial effects before it raises. Its immutable source
-- record is conservatively retained rather than freed or retried implicitly.
retain = { records = {}, bytes = 0, cache = {} }
local observed
store, b, counters = session(retain, function(pixels)
    observed = pixels
    error('Native creation partially failed')
end)
assert(not pcall(store.apply, document, { b }))
creates, writes, object = counters()
assert(creates == 1 and writes == 0 and object == 10)
assert(
    retain.bytes == 368 and #retain.records == 1 and retain.records[1].data == observed and next(retain.cache) == nil
)
assert(ffi.string(observed, 368) == bytes and store.restore())
print(
    'PASS texture budget: bounded 64MiB/16384 headroom, immutable retention, diagnostics/preallocation rejection, at-cap cache reuse, foreign ownership and partial-create accounting'
)
