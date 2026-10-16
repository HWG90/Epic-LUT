-- Actual byte-backed Engine.binding parity; no game/native calls.
local ffi = require('ffi')
local Engine = dofile('vendor/engine.lua')
local blocks, reads, failures = {}, {}, {}
local function number(bytes, offset, value, size)
    for i = 0, size - 1 do bytes[offset + i] = value % 256; value = math.floor(value / 256) end
end
local function material(address, rows, count, array)
    array = array or address + 0x10000
    local header = ffi.new('uint8_t[16]')
    number(header, 0, count or #rows, 4); number(header, 8, array, 8)
    blocks[address + 24] = { data = header, size = 16 }
    local bytes = ffi.new('uint8_t[1024]')
    for i, row in ipairs(rows) do number(bytes, (i - 1) * 16, row[1], 4); number(bytes, (i - 1) * 16 + 8, row[2], 8) end
    blocks[array] = { data = bytes, size = #rows * 16 }
    return header, bytes, array
end
local function read(address, size, target)
    reads[#reads + 1] = { address, size }
    local source, fault = blocks[address], failures[address]
    if fault == 'throw' then error('slot-read-sentinel', 0) end
    if not source or size > source.size then return false end
    ffi.copy(target, source.data, fault == 'partial' and math.max(0, size - 1) or size)
    return not fault
end
local small, big = ffi.new('uint8_t[96]'), ffi.new('uint8_t[1024]')
local function fresh(address, slot) return Engine.binding(read, address, slot, small, big) end
local rows = { { 0, 0 }, { Engine.LUT_SLOT, 0 }, { Engine.LUT_SLOT, 123 }, { Engine.PATTERN_SLOT, 0x123456789abc },
    { Engine.CAPE_LUT_SLOT, 456 }, { 0xffffffff, 0xffffffffffff } }
local header, entries, array = material(0x20000, rows)
local snapshot = Engine.binding_snapshot(read)
for _, slot in ipairs({ 0, Engine.LUT_SLOT, Engine.PATTERN_SLOT, Engine.CAPE_LUT_SLOT, 0xffffffff, 42 }) do
    assert(snapshot(0x20000, slot) == fresh(0x20000, slot), 'Snapshot diverged from first-match/zero/absent/high-pointer semantics')
end
local before = #reads
assert(snapshot(0x20000, 42) == nil and snapshot(0x20000, Engine.LUT_SLOT) == 0 and #reads == before,
    'A successful copied table must answer present and absent slots without another native read')
number(entries, 8, 789, 8)
assert(snapshot(0x20000, 0) == 0 and fresh(0x20000, 0) == 789, 'Snapshot or default binding leaked the wrong read lifetime')
assert(Engine.binding_snapshot(read)(0x20000, 0) == 789, 'A new operation reused an old slot table')
-- Every malformed/failed load is retried, including within the same operation.
for _, fault in ipairs({ 'false', 'partial', 'throw' }) do
    local _, _, address = material(0x30000, { { Engine.LUT_SLOT, 100 } })
    for _, stage in ipairs({ 0x30000 + 24, address }) do
        local observe = Engine.binding_snapshot(read)
        failures[stage] = fault
        local ok, value = pcall(observe, 0x30000, Engine.LUT_SLOT)
        assert(fault == 'throw' and not ok and value == 'slot-read-sentinel' or fault ~= 'throw' and ok and value == nil)
        failures[stage] = nil
        before = #reads
        assert(observe(0x30000, Engine.LUT_SLOT) == 100 and #reads == before + 2, 'Failed table became a valid cached result')
    end
end
for _, count in ipairs({ 0, 65, 0xffffffff }) do
    local h = material(0x40000, { { Engine.LUT_SLOT, 100 } }, count)
    local observe = Engine.binding_snapshot(read); before = #reads
    assert(observe(0x40000, Engine.LUT_SLOT) == nil and #reads == before + 1, 'Invalid count reached the slot array')
    number(h, 0, 1, 4)
    assert(observe(0x40000, Engine.LUT_SLOT) == 100, 'Invalid count was cached')
end
local h = material(0x50000, { { Engine.LUT_SLOT, 100 } }, nil, 0xffff)
snapshot = Engine.binding_snapshot(read); before = #reads
assert(snapshot(0x50000, Engine.LUT_SLOT) == nil and #reads == before + 1, 'Low invalid array was read')
local _, _, good = material(0x50000, { { Engine.LUT_SLOT, 100 } }, nil, 0x10000)
assert(good == 0x10000 and snapshot(0x50000, Engine.LUT_SLOT) == 100, 'Valid lower-bound array was rejected or old failure persisted')
local all = {}; for i = 0, 63 do all[#all + 1] = { i, i * 1000 } end
material(0x60000, all)
snapshot = Engine.binding_snapshot(read); before = #reads
for i = 0, 63 do assert(snapshot(0x60000, i) == i * 1000) end
assert(#reads == before + 2 and reads[#reads][2] == 1024, 'Maximum valid slot table exceeded its bounded single copy')
print('PASS binding snapshot: byte-backed first-match/zero/high pointers,64 slots, failed/partial/throw retry, operation expiry and fresh default reads')
