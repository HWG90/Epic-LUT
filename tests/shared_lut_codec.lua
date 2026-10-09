local ffi = require('ffi')
local C = dofile('src/gear/shared_lut_codec.lua')
local codec = C.new()
local data = ffi.new('float[?]', 23 * 8 * 4)
for i = 0, 23 * 8 * 4 - 1 do
    data[i] = i % 17 == 0 and 2.75 or i % 11 == 0 and -0.125 or 0
end
local doc = { data = data, width = 23, height = 8 }
local identity = { body = 123, armor = 456, helmet = 789 }
local entries = { { key = '0:1:2:3', document = doc }, { key = '1:0:0:0', document = doc } }
local text = codec.encode(identity, entries)
assert(#text <= 3600)
local decoded = codec.decode(text)
assert(decoded.body == 123 and decoded.armor == 456 and decoded.helmet == 789)
assert(#decoded.documents == 1, 'Identical tables not deduplicated')
assert(
    ffi.string(decoded.entries['0:1:2:3'].document.data, 23 * 8 * 16) == ffi.string(data, 23 * 8 * 16),
    'Float data changed in sharing'
)
assert(decoded.entries['1:0:0:0'].helmet)
assert(not pcall(codec.decode, text .. 'x'), 'Trailing encoded data accepted')
assert(not pcall(codec.decode, '1|999999|AAAA'), 'Decompression size limit ignored')
assert(not pcall(codec.decode, '9|17|AAAA'), 'Unsupported protocol accepted')
data[4] = 0 / 0
assert(not pcall(codec.encode, identity, entries), 'NaN shared')
data[4] = math.huge
assert(not pcall(codec.encode, identity, entries), 'Infinite value shared')
data[4] = 0
assert(not pcall(codec.encode, identity, { { key = '0:42:0:0', document = doc } }), 'Invalid destination shared')
local overflow = C.new({
    compress = function()
        return string.rep('x', 4000)
    end,
})
assert(not pcall(overflow.encode, identity, entries), 'Oversized packet shared partially')
print(
    'PASS full LUT sharing codec: exact HDR/negative RGBA, deduplication, native compression and bounded malformed rejection'
)

local pattern = { data = ffi.new('float[12]'), width = 3, height = 1 }
pattern.data[0], pattern.data[3], pattern.data[7], pattern.data[11] = 0.5, 2.75, 0.4, -0.2
local mixed = codec.decode(
    codec.encode(identity, { { key = '0:1:2:3', document = doc }, { key = 'p:0:1:2:3', document = pattern } })
)
assert(ffi.string(mixed.entries['p:0:1:2:3'].document.data, 48) == ffi.string(pattern.data, 48))
assert(mixed.entries['p:0:1:2:3'].pattern and not mixed.entries['0:1:2:3'].pattern)

-- Ten detailed tables exceed the old packet limit; sparse exact changes fit without quantization.
local originals, many = {}, {}
for n = 1, 10 do
    local base = { width = 23, height = 8, data = ffi.new('float[736]'), resource = string.format('%016x', n) }
    local edited = { width = 23, height = 8, data = ffi.new('float[736]') }
    for i = 0, 735 do
        base.data[i] = math.sin(i * 17 + n * 31) * 4 + i / 1000
    end
    ffi.copy(edited.data, base.data, 2944)
    edited.data[n * 4] = 2.75
    edited.data[n * 4 + 1] = -0.125
    edited.data[n * 4 + 3] = 0.375
    originals[base.resource] = base
    many[#many + 1] = { key = '0:1:' .. n .. ':0', document = edited, original = base }
end
local small = C.new(nil, function(resource)
    return originals[resource]
end)
local packet = small.encode(identity, many)
assert(packet:match('^[23]|') and #packet <= 3600, 'Delta packet failed to fit ten detailed LUTs')
local restored = small.decode(packet)
for _, entry in ipairs(many) do
    assert(
        ffi.string(restored.entries[entry.key].document.data, 2944) == ffi.string(entry.document.data, 2944),
        'Delta changed full-precision RGBA/material bytes'
    )
end
local full = {}
for i, entry in ipairs(many) do
    full[i] = { key = entry.key, document = entry.document }
end
assert(not pcall(codec.encode, identity, full), 'Detailed fixture unexpectedly fits full-table packet')
assert(not pcall(codec.decode, packet), 'Delta without original baseline accepted')
local first = originals['0000000000000001']
local keep = first.data[0]
first.data[0] = keep + 1
assert(not pcall(small.decode, packet), 'Changed receiver baseline accepted')
first.data[0] = keep
assert(small.decode(packet))
print(
    'PASS lossless delta sharing: ten detailed LUTs fit in '
        .. #packet
        .. ' bytes, exact reconstruction and baseline guard'
)

local base_pattern = { width = 3, height = 1, data = ffi.new('float[12]'), resource = '1234567890abcdef' }
for i = 0, 11 do
    base_pattern.data[i] = i * 0.25
end
local changed_pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
ffi.copy(changed_pattern.data, base_pattern.data, 48)
changed_pattern.data[7] = -0.25
originals[base_pattern.resource] = base_pattern
many[#many + 1] = { key = 'p:0:1:0:0', document = changed_pattern, original = base_pattern }
local both = small.decode(small.encode(identity, many))
assert(
    ffi.string(both.entries['p:0:1:0:0'].document.data, 48) == ffi.string(changed_pattern.data, 48),
    'Pattern delta changed unknown or alpha values'
)

-- Dense small changes benefit from XOR byte planes while retaining negative/HDR/alpha bits.
local dense_base = { width = 23, height = 8, data = ffi.new('float[736]'), resource = '0123456789abcdef' }
local dense_edit = { width = 23, height = 8, data = ffi.new('float[736]') }
for i = 0, 735 do
    dense_base.data[i] = math.sin(i * 19) * 8
    dense_edit.data[i] = dense_base.data[i] + 0.00001
end
-- Preserve signed zero through reconstruction too.
dense_base.data[1] = 0
dense_edit.data[1] = -1 / math.huge
originals[dense_base.resource] = dense_base
local dense_entries = { { key = '0:1:0:0', document = dense_edit, original = dense_base } }
local dense_packet = small.encode(identity, dense_entries)
assert(dense_packet:sub(1, 2) == '3|', 'Dense near-baseline data did not select XOR planes')
local dense_result = small.decode(dense_packet)
assert(
    ffi.string(dense_result.entries['0:1:0:0'].document.data, 2944) == ffi.string(dense_edit.data, 2944),
    'XOR planes lost IEEE-754 bits'
)
local packed_full_size = small.packet_sizes.full
assert(#dense_packet < packed_full_size, 'XOR planes did not reduce dense edited packet')
print(
    'PASS XOR byte-plane sharing: '
        .. packed_full_size
        .. ' -> '
        .. #dense_packet
        .. ' bytes, exact HDR/negative/alpha/signed-zero reconstruction'
)

assert(
    #dense_packet == math.min(small.packet_sizes.full, small.packet_sizes.sparse, small.packet_sizes.xor),
    'Codec failed to choose smallest encoded packet'
)
assert(not pcall(codec.decode, dense_packet), 'XOR packet accepted without receiver baseline')
local saved_dense = dense_base.data[0]
dense_base.data[0] = saved_dense + 1
assert(not pcall(small.decode, dense_packet), 'XOR packet accepted mismatched baseline')
dense_base.data[0] = saved_dense
assert(small.decode(dense_packet))

local tall_base = { width = 23, height = 32, data = ffi.new('float[?]', 23 * 32 * 4), resource = 'fedcba9876543210' }
local tall_edit = { width = 23, height = 32, data = ffi.new('float[?]', 23 * 32 * 4) }
for i = 0, 23 * 32 * 4 - 1 do
    tall_base.data[i] = (i % 23) * 0.125
end
ffi.copy(tall_edit.data, tall_base.data, 23 * 32 * 16)
tall_edit.data[31 * 23 * 4 + 3] = 0.375
originals[tall_base.resource] = tall_base
local tall_packet = small.encode(identity, { { key = '0:1:0:0', document = tall_edit, original = tall_base } })
local tall_decoded = small.decode(tall_packet).entries['0:1:0:0'].document
assert(
    tall_decoded.height == 32
        and ffi.string(tall_decoded.data, 23 * 32 * 16) == ffi.string(tall_edit.data, 23 * 32 * 16),
    'Sharing truncated custom rows'
)
