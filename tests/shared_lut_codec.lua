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

local tall_base = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4), resource = 'fedcba9876546410' }
local tall_edit = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
for i = 0, 23 * 64 * 4 - 1 do
    tall_base.data[i] = (i % 23) * 0.125
end
ffi.copy(tall_edit.data, tall_base.data, 23 * 64 * 16)
tall_edit.data[63 * 23 * 4 + 3] = 0.375
originals[tall_base.resource] = tall_base
local tall_packet = small.encode(identity, { { key = '0:1:0:0', document = tall_edit, original = tall_base } })
local tall_decoded = small.decode(tall_packet).entries['0:1:0:0'].document
assert(
    tall_decoded.height == 64
        and ffi.string(tall_decoded.data, 23 * 64 * 16) == ffi.string(tall_edit.data, 23 * 64 * 16),
    'Sharing truncated custom rows'
)
assert(
    C.MAX_TEXT == 3600 and C.MAX_RAW == 65536 and #tall_packet <= C.MAX_TEXT,
    'Custom rows widened lobby byte budgets'
)
local too_tall = { width = 23, height = 65, data = ffi.new('float[?]', 23 * 65 * 4) }
assert(not pcall(small.encode, identity, { { key = '0:1:0:0', document = too_tall } }), 'Sharing accepted row 65')
local malformed = C.new({
    decompress = function()
        return 'EL1' .. string.rep('\0', 12) .. string.char(1, 0, 23, 65)
    end,
})
assert(not pcall(malformed.decode, '1|19|AAAA'), 'Shared decoder accepted row 65')

-- Transmog multiplies destinations, not unique palettes. EL4 preserves each
-- canonical key while storing the ten exact documents only once.
local transmog = {}
many[1].document.data[3] = -1 / math.huge
for n = 1, 172 do
    local template = many[(n - 1) % 10 + 1]
    local at = n <= 8 and n - 1 or n - 9
    local key = '0:' .. (n <= 8 and 0 or 1) .. ':' .. math.floor(at / 4) .. ':' .. at % 4
    transmog[#transmog + 1] = { key = key, document = template.document, original = template.original }
end
local transmog_packet = small.encode(identity, transmog)
assert(
    transmog_packet:sub(1, 2) == '4|' and #transmog_packet <= C.MAX_TEXT,
    '172 destination packet did not use compact EL4'
)
local transmog_result = small.decode(transmog_packet)
assert(#transmog_result.documents == 10, 'Transmog repeated exact documents')
local count = 0
for _ in pairs(transmog_result.entries) do
    count = count + 1
end
assert(count == 172, 'EL4 dropped Transmog destinations')
for _, entry in ipairs(transmog) do
    assert(
        ffi.string(transmog_result.entries[entry.key].document.data, 2944) == ffi.string(entry.document.data, 2944),
        'EL4 changed exact F32/alpha/signed-zero bytes'
    )
end
transmog[#transmog + 1] = { key = 'p:0:1:0:0', document = changed_pattern, original = base_pattern }
local with_pattern = small.decode(small.encode(identity, transmog))
assert(
    ffi.string(with_pattern.entries['p:0:1:0:0'].document.data, 48) == ffi.string(changed_pattern.data, 48),
    'EL4 Pattern representation changed bytes'
)
assert(not transmog_packet:match('^([123])|'), 'EL4 incorrectly advertised compatibility with old decoders')
-- Small appearances continue using the old wire format. Their exact native
-- compressor outputs above remain unchanged and all old versions still read.
assert(codec.encode(identity, entries):match('^[123]|'), 'Small appearance unnecessarily switched protocols')
local function word(value)
    return ffi.string(ffi.new('uint32_t[1]', value), 4)
end
local kit = word(identity.body) .. word(identity.armor) .. word(identity.helmet)
local pixels = ffi.string(doc.data, 2944)
local legacy_tail = string.char(0, 1, 2, 3, 1)
for version = 1, 3 do
    local raw = 'EL'
        .. version
        .. kit
        .. string.char(1, 1)
        .. (version == 1 and '' or string.char(0))
        .. string.char(23, 8)
        .. pixels
        .. legacy_tail
    local fixture = C.new({
        decompress = function()
            return raw
        end,
    })
    assert(
        ffi.string(fixture.decode(version .. '|' .. #raw .. '|AAAA').entries['0:1:2:3'].document.data, 2944) == pixels,
        'Legacy packet stopped decoding'
    )
end

-- Exercise the count representation independently of compression capacity.
-- 4,096 is a destination bound, not a promise that every appearance fits3,600.
local stored, next_token = {}, 0
local serialization = C.new({
    compress = function(raw)
        next_token = next_token + 1
        local token = word(next_token)
        stored[token] = raw
        return token
    end,
    decompress = function(token, size)
        local raw = assert(stored[token])
        assert(#raw == size)
        return raw
    end,
})
local maximum = {}
for mesh = 0, 63 do
    for material = 0, 63 do
        maximum[#maximum + 1] = { key = '0:1:' .. mesh .. ':' .. material, document = doc }
    end
end
local maximum_result = serialization.decode(serialization.encode(identity, maximum))
count = 0
for key, entry in pairs(maximum_result.entries) do
    count = count + 1
    assert(
        key:match('^0:1:') and ffi.string(entry.document.data, 2944) == pixels,
        'Maximum-count compact destination/data changed'
    )
end
assert(count == 4096 and #maximum_result.documents == 1, 'EL4 count limit truncated bindings or repeated documents')
local indexed, all_indexes = {}, {}
for n = 1, 31 do
    indexed[n] = { width = 23, height = 1, data = ffi.new('float[92]') }
    indexed[n].data[0] = n
end
for n = 1, 129 do
    all_indexes[#all_indexes + 1] =
        { key = '0:1:' .. math.floor((n - 1) / 4) .. ':' .. (n - 1) % 4, document = indexed[(n - 1) % 31 + 1] }
end
all_indexes[#all_indexes + 1] = { key = 'p:2:9:63:63', document = changed_pattern }
local indexed_result = serialization.decode(serialization.encode(identity, all_indexes))
assert(
    #indexed_result.documents == 32
        and indexed_result.entries['p:2:9:63:63'].document == indexed_result.documents[32]
        and ffi.string(indexed_result.documents[32].data, 48) == ffi.string(changed_pattern.data, 48),
    'Five-bit index32 or maximum destination fields changed'
)
maximum[#maximum + 1] = { key = '1:0:0:0', document = doc }
local ok, why = pcall(serialization.encode, identity, maximum)
assert(not ok and tostring(why):find('4096', 1, true), '4,097 destinations did not fail accurately before publication')
assert(
    C.MAX_DOCS == 32 and C.MAX_RAW == 65536 and C.MAX_TEXT == 3600,
    'Binding expansion changed table or byte budgets'
)

local aliases = { { key = '0:1:0:0', document = doc }, { key = '00:01:00:00', document = doc } }
local alias_result = codec.decode(codec.encode(identity, aliases))
count = 0
for _ in pairs(alias_result.entries) do
    count = count + 1
end
assert(count == 1, 'Canonical duplicate destination was not deduplicated')
local different = { width = 23, height = 8, data = ffi.new('float[736]') }
ffi.copy(different.data, doc.data, 2944)
different.data[0] = different.data[0] + 1
aliases[2].document = different
ok, why = pcall(codec.encode, identity, aliases)
assert(
    not ok and tostring(why):find('Conflicting shared destination', 1, true),
    'Conflicting duplicate destination was silently dropped'
)

local function short(value)
    return string.char(value % 256, math.floor(value / 256))
end
local function packed_binding(t, slot, mesh, material, index, pattern)
    local value = index - 1 + material * 32 + mesh * 2048 + slot * 131072 + (t + (pattern and 4 or 0)) * 2097152
    return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536))
end
local function rejects(raw, reason)
    local fixture = C.new({
        decompress = function()
            return raw
        end,
    })
    assert(not pcall(fixture.decode, '4|' .. #raw .. '|AAAA'), reason)
end
local function raw_packet(bindings, tail, documents)
    return 'EL4' .. kit .. string.char(documents or 1) .. short(bindings) .. string.char(0, 23, 8) .. pixels .. tail
end
rejects('EL4' .. kit .. string.char(0) .. short(4097), 'Decoder accepted count4,097')
rejects('EL4' .. kit .. string.char(33) .. short(0), 'Decoder accepted33 table slots')
rejects(raw_packet(1, packed_binding(3, 1, 0, 0, 1, false)), 'Reserved garment type accepted')
rejects(raw_packet(1, packed_binding(0, 10, 0, 0, 1, false)), 'Out-of-range slot accepted')
rejects(raw_packet(1, packed_binding(0, 1, 0, 0, 32, false)), 'Missing compact document index accepted')
rejects(raw_packet(1, packed_binding(0, 1, 0, 0, 1, true)), 'Pattern destination accepted material table shape')
local valid_binding = packed_binding(0, 1, 0, 0, 1, false)
rejects(raw_packet(2, valid_binding .. valid_binding), 'Duplicate compact binding accepted')
rejects(raw_packet(2, valid_binding), 'Truncated compact binding accepted')
rejects(raw_packet(1, valid_binding) .. 'x', 'Trailing EL4 bytes accepted')
assert(not pcall(codec.encode, identity, { { key = '3:1:0:0', document = doc } }), 'Reserved garment type packed')
assert(not pcall(codec.encode, identity, { { key = '0:1:64:0', document = doc } }), 'Mesh64 packed')
assert(not pcall(codec.encode, identity, { { key = '0:1:0:64', document = doc } }), 'Material64 packed')
assert(
    not pcall(codec.encode, identity, { { key = 'p:0:1:0:0', document = doc } }),
    'Pattern/material shape mismatch packed'
)

-- Packet size errors identify the real lobby budget and preserve source data;
-- this represents a detailed appearance whose lossless compression cannot fit.
local over_budget = C.new({
    compress = function()
        return string.rep('x', 5113)
    end,
})
local oversized_entries = {}
for _, entry in ipairs(transmog) do
    oversized_entries[#oversized_entries + 1] = { key = entry.key, document = entry.document }
end
local before = ffi.string(doc.data, 2944)
ok, why = pcall(over_budget.encode, identity, oversized_entries)
assert(
    not ok
        and tostring(why):find('6828', 1, true)
        and tostring(why):find('3600', 1, true)
        and tostring(why):find('local edits are kept', 1, true),
    'Oversized appearance did not report its encoded size and budget'
)
assert(ffi.string(doc.data, 2944) == before, 'Oversize rejection altered local colors')
print(
    'PASS compact EL4:172/173 exact Transmog bindings, Pattern/HDR/signed-zero data,4,096 count representation, legacy compatibility and strict malformed/budget rejection'
)
