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
assert(packet:match('^[23]x?|') and #packet <= 3600, 'Delta packet failed to fit ten detailed LUTs')
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
assert(dense_packet:match('^3x?|'), 'Dense near-baseline data did not select XOR planes')
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
    transmog_packet:match('^4x?|') and #transmog_packet <= C.MAX_TEXT,
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
-- Small appearances retain the old raw layout. Tagged optional compression
-- never changes that layout and all untagged old versions still read.
assert(codec.encode(identity, entries):match('^[1235]x?|'), 'Small appearance used large-count-only EL4')
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

-- Native formats share exact raw layouts; only an explicit outer x selects
-- XPRESS decoding. Force each raw version without depending on which candidate
-- a given Windows compressor happens to choose as the smallest.
local native = C.compression()
local raw_versions = {}
local capturing = C.new({
    compress = function(raw)
        raw_versions[raw:sub(1, 3)] = raw
        return native.compress(raw, '')
    end,
    decompress = function(bytes, size)
        return native.decompress(bytes, size, '')
    end,
})
assert(capturing.encode(identity, entries))
local large_simple = {}
for n = 1, 129 do
    large_simple[n] = { key = '0:1:' .. math.floor((n - 1) / 4) .. ':' .. (n - 1) % 4, document = doc }
end
assert(capturing.encode(identity, large_simple))
local b64alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64(bytes)
    local out = {}
    for at = 1, #bytes, 3 do
        local a, b, c = bytes:byte(at, at + 2)
        local bits = a * 65536 + (b or 0) * 256 + (c or 0)
        local function digit(n)
            return b64alphabet:sub(n + 1, n + 1)
        end
        out[#out + 1] = digit(math.floor(bits / 262144))
            .. digit(math.floor(bits / 4096) % 64)
            .. (b and digit(math.floor(bits / 64) % 64) or '=')
            .. (c and digit(bits % 64) or '=')
    end
    return table.concat(out)
end
for version = 1, 4 do
    local raw = assert(raw_versions['EL' .. version])
    for _, tag in ipairs(native.formats) do
        local encoded = version .. tag .. '|' .. #raw .. '|' .. b64(native.compress(raw, tag))
        assert(#encoded <= C.MAX_TEXT)
        local result = codec.decode(encoded)
        for _, entry in pairs(result.entries) do
            assert(ffi.string(entry.document.data, 2944) == pixels, 'Tagged native version changed F32 bytes')
        end
        assert(not pcall(codec.decode, encoded .. 'x'), 'Trailing tagged compression data accepted')
        assert(not pcall(codec.decode, encoded:sub(1, -5)), 'Truncated tagged compressed data accepted')
    end
end
for _, invalid in ipairs({ '1h|17|AAAA', '1xx|17|AAAA', '5x|17|AAAA', '4x|18|AAAA', '1x|999999|AAAA' }) do
    assert(not pcall(codec.decode, invalid), 'Unsupported/corrupt/tagged-size packet accepted')
end

-- Optional native probing must fall back MAXIMUM -> STANDARD -> LZNT1 while
-- avoiding oversized allocation and all unvalidated FFI capacities.
local function fake_native(maximum, standard, fail_optional)
    local calls = { compress = 0, decompress = 0, formats = {} }
    local api = {}
    function api.EpicLutWorkspace(format, size, fragment)
        calls.formats[#calls.formats + 1] = format
        if format == 2 then
            size[0] = 32
            fragment[0] = 16
            return 0
        end
        local policy = format == 259 and maximum or standard
        if policy == 'unavailable' then
            return -1
        end
        size[0] = policy == 'large' and 2 * 1024 * 1024 or 64
        fragment[0] = 16
        return 0
    end
    function api.EpicLutCompress(format, bytes, size, out, _, _, final)
        calls.compress = calls.compress + 1
        local kind = format % 256
        if kind == 3 and fail_optional then
            return -1
        end
        local encoded = (kind == 3 and 'X' or 'L') .. bytes:sub(1, size)
        ffi.copy(out, encoded, #encoded)
        final[0] = #encoded
        return 0
    end
    function api.EpicLutDecompress(format, out, size, bytes, count, final)
        calls.decompress = calls.decompress + 1
        local encoded = bytes:sub(1, count)
        if encoded:sub(1, 1) ~= (format == 3 and 'X' or 'L') then
            return -1
        end
        local raw = encoded:sub(2)
        if #raw ~= size then
            return -1
        end
        ffi.copy(out, raw, size)
        final[0] = size
        return 0
    end
    return api, calls
end
local api, calls = fake_native('unavailable', 'ok')
local fallback = C.compression(api)
assert(fallback.xpress_format == 3 and #fallback.formats == 2, 'Unavailable MAXIMUM did not use XPRESS STANDARD')
api, calls = fake_native('large', 'unavailable')
fallback = C.compression(api)
assert(
    not fallback.xpress_format and #fallback.formats == 1,
    'Unavailable/oversized optional workspace did not retain LZNT1'
)
local prior_calls = calls.decompress
for _, size in ipairs({ -1, 0, 0.5, 65537, math.huge, 0 / 0 }) do
    assert(not pcall(fallback.decompress, 'Lx', size), 'Unsafe capacity reached native decompressor')
end
assert(
    not pcall(fallback.decompress, nil, 17) and not pcall(fallback.decompress, '', 17),
    'Invalid compressed input reached FFI'
)
assert(calls.decompress == prior_calls, 'Rejected capacity invoked native decompressor')
prior_calls = calls.compress
assert(
    not pcall(fallback.compress, nil)
        and not pcall(fallback.compress, '')
        and not pcall(fallback.compress, string.rep('x', 65537))
)
assert(calls.compress == prior_calls, 'Rejected raw bytes invoked native compressor')
api, calls = fake_native('ok', 'ok', true)
fallback = C.compression(api)
local failed_optional = C.new(fallback)
local tiny_entries = { { key = 'p:0:1:0:0', document = pattern } }
local legacy_tiny = failed_optional.encode(identity, tiny_entries)
assert(
    legacy_tiny:match('^[12345]|') and failed_optional.decode(legacy_tiny),
    'Optional compression failure blocked valid legacy appearance'
)
api, calls = fake_native('ok', 'ok')
local tagged = C.compression(api)
local x_only = C.new({ formats = { 'x' }, compress = tagged.compress, decompress = tagged.decompress })
local tagged_tiny = x_only.encode(identity, tiny_entries)
assert(tagged_tiny:match('^[12345]x|') and x_only.decode(tagged_tiny), 'Explicit optional compression tag failed')
assert(not pcall(x_only.decode, tagged_tiny:gsub('^([12345])x|', '%1|')), 'Untagged XPRESS was decoded as legacy')
assert(not pcall(x_only.decode, legacy_tiny:gsub('^([12345])|', '%1x|')), 'Legacy bytes were decoded as XPRESS')
for _, bad in ipairs({
    function()
        return nil
    end,
    function()
        return ''
    end,
    function()
        return string.rep('x', C.MAX_RAW + 4097)
    end,
}) do
    local invalid = C.new({
        formats = { '', 'x' },
        compress = function(raw, tag)
            if tag == 'x' then
                return bad()
            end
            return native.compress(raw, '')
        end,
        decompress = native.decompress,
    })
    local accepted, error_text = pcall(invalid.encode, identity, tiny_entries)
    assert(
        not accepted and tostring(error_text):find('Invalid compressed LUT output', 1, true),
        'Invalid optional compressor result escaped its output guard'
    )
end

-- Generated repeated-palette workload with one preserved emissive float per
-- table: LZNT1 cannot match across its4KiB chunks, while XPRESS can. Public,
-- deterministic data only; no saved user files or review-artifact dependencies.
local seed = 20261022
local function random()
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return seed
end
local words = {}
for n = 1, 10 do
    words[n] = 0x3f000000 + random() % 0x800000
end
words[11], words[12] = 0, 0x3f800000
local palette = ffi.new('uint32_t[736]')
for n = 0, 735 do
    palette[n] = words[math.floor(random() / 16777216) % 12 + 1]
end
local generated, generated_entries = {}, {}
for n = 1, 8 do
    local pixels = ffi.new('uint32_t[736]')
    ffi.copy(pixels, palette, 2944)
    pixels[13 * 4] = 0x3f000000 + random() % 0x800000
    local d = { width = 23, height = 8, data = ffi.new('float[736]') }
    ffi.copy(d.data, pixels, 2944)
    generated[n] = d
end
for n = 1, 82 do
    generated_entries[n] =
        { key = '0:1:' .. (n - 1) % 64 .. ':' .. math.floor((n - 1) / 64), document = generated[(n - 1) % 8 + 1] }
end
local old = C.new({
    compress = function(raw)
        return native.compress(raw, '')
    end,
    decompress = function(bytes, size)
        return native.decompress(bytes, size, '')
    end,
})
pcall(old.encode, identity, generated_entries)
assert(
    math.min(old.packet_sizes.full, old.packet_sizes.sparse, old.packet_sizes.xor) > C.MAX_TEXT,
    'Generated regression did not exceed earlier raw-layout lobby budget'
)
local improved = codec.encode(identity, generated_entries)
assert(
    improved:match('^[12345]x?|') and #improved <= C.MAX_TEXT,
    'Repeated exact palette did not fit with tagged XPRESS'
)
local generated_result = codec.decode(improved)
for _, entry in ipairs(generated_entries) do
    assert(
        ffi.string(generated_result.entries[entry.key].document.data, 2944) == ffi.string(entry.document.data, 2944),
        'Improved compression changed preserved-emissive/F32 bytes'
    )
end
print(
    'PASS tagged native XPRESS:legacyEL1-4, exact raw/delta/XOR/compact bytes, workspace/error fallback, strict FFI bounds and generated82-binding palette '
        .. #improved
        .. ' bytes'
)

do
    -- Force EL5 to exercise both index widths even when a short legacy raw
    -- table happens to compress better. Source values remain opaque F32 bits.
    local dictionary_raw
    local dictionary_codec = C.new({
        formats = native.formats,
        compress = function(raw, tag)
            if raw:sub(1, 3) == 'EL5' then
                dictionary_raw = raw
                return native.compress(raw, tag)
            end
            return string.rep('x', 4000)
        end,
        decompress = native.decompress,
    })
    local boundary_raw = {}
    for _, size in ipairs({ 255, 256, 257 }) do
        local values = ffi.new('uint32_t[276]')
        for i = 0, 275 do
            local index = i % size
            values[i] = index == 0 and 0 or index == 1 and 0x80000000 or index == 2 and 0xc0200000 or 0x3f000000 + index
        end
        local d = { width = 23, height = 3, data = ffi.new('float[276]') }
        ffi.copy(d.data, values, 1104)
        local packet = dictionary_codec.encode(identity, { { key = '0:1:0:0', document = d } })
        assert(packet:match('^5x?|'), 'Forced word dictionary did not select EL5')
        boundary_raw[size] = dictionary_raw
        local lo, hi = dictionary_raw:byte(19, 20)
        assert(
            lo + hi * 256 == size and #dictionary_raw == 20 + 2 + size * 4 + 276 * (size <= 256 and 1 or 2) + 3,
            'Dictionary index-width boundary changed'
        )
        local got = dictionary_codec.decode(packet).entries['0:1:0:0'].document
        assert(
            ffi.string(got.data, 1104) == ffi.string(d.data, 1104),
            'Word planes changed HDR/signed-zero/alpha bits at index boundary'
        )
    end
    local mixed = {
        { key = '0:1:0:0', document = doc },
        { key = 'p:0:1:0:0', document = pattern },
    }
    local packet = dictionary_codec.encode(identity, mixed)
    local decoded = dictionary_codec.decode(packet)
    assert(
        ffi.string(decoded.entries['0:1:0:0'].document.data, 2944) == ffi.string(doc.data, 2944)
            and ffi.string(decoded.entries['p:0:1:0:0'].document.data, 48) == ffi.string(pattern.data, 48),
        'Combined Pattern/material dictionary changed full precision bits'
    )
    local function planes(words)
        local result = {}
        for lane = 1, 4 do
            for _, value in ipairs(words) do
                result[#result + 1] = value:sub(lane, lane)
            end
        end
        return table.concat(result)
    end
    local function raw(words, indexes, tail)
        return 'EL5'
            .. kit
            .. string.char(1)
            .. short(1)
            .. short(#words)
            .. string.char(3, 1)
            .. planes(words)
            .. indexes
            .. tail
    end
    local valid_tail = packed_binding(0, 1, 0, 0, 1, true)
    local valid = raw({ word(0) }, string.rep('\0', 12), valid_tail)
    local function reject(value, message)
        local injected = C.new({
            decompress = function()
                return value
            end,
        })
        assert(not pcall(injected.decode, '5|' .. #value .. '|AAAA'), message)
    end
    reject('EL5' .. kit .. string.char(0) .. short(4097) .. short(0), 'EL5 accepted binding4097')
    reject('EL5' .. kit .. string.char(33) .. short(0) .. short(0), 'EL5 accepted document33')
    reject(
        'EL5' .. kit .. string.char(1) .. short(0) .. short(13) .. string.char(3, 1),
        'Dictionary cardinality exceeded reconstructed floats'
    )
    reject(
        'EL5' .. kit .. string.char(1) .. short(0) .. short(0) .. string.char(3, 1),
        'Empty dictionary accepted nonempty data'
    )
    reject('EL5' .. kit .. string.char(1) .. short(0) .. short(1) .. string.char(23, 65), 'EL5 accepted row65')
    reject(
        'EL5' .. kit .. string.char(3) .. short(0) .. short(1) .. string.rep(string.char(23, 64), 3),
        'EL5 exceeded reconstructed64KiB'
    )
    reject(valid:sub(1, 24), 'Truncated dictionary planes accepted')
    reject(valid:sub(1, 37), 'Truncated index stream accepted')
    reject(
        raw({ word(0) }, string.char(1) .. string.rep('\0', 11), valid_tail),
        'Out-of-range one-byte word index accepted'
    )
    local two_byte = boundary_raw[257]
    local high_start = 20 + 2 + 257 * 4 + 276 + 1
    reject(
        two_byte:sub(1, high_start - 1) .. string.char(2) .. two_byte:sub(high_start + 1),
        'Out-of-range high index plane accepted'
    )
    reject(
        raw({ word(0), word(0x7fc00000) }, string.rep('\0', 12), valid_tail),
        'Unused nonfinite dictionary word accepted'
    )
    reject(raw({ word(0x7f800000) }, string.rep('\0', 12), valid_tail), 'Infinite dictionary word accepted')
    reject(
        raw({ ffi.string(ffi.new('float[1]', 1e20), 4) }, string.rep('\0', 12), valid_tail),
        'Dictionary changed existing float magnitude policy'
    )
    reject(valid .. 'x', 'EL5 trailing bytes accepted')
    reject(
        raw({ word(0) }, string.rep('\0', 12), packed_binding(3, 1, 0, 0, 1, true)),
        'EL5 accepted reserved garment type'
    )
    reject(
        raw({ word(0) }, string.rep('\0', 12), packed_binding(0, 1, 0, 0, 1, false)),
        'EL5 Pattern/material binding shape mismatch accepted'
    )
    assert(not pcall(codec.decode, '6x|20|AAAA'), 'Future unknown protocol accepted')
    print(
        'PASS EL5 planar dictionary:255/256/257 index widths, exact combined Pattern/material/HDR/signed-zero bytes, bounded and malformed dictionary rejection'
    )
end

do
    -- Public deterministic multi-table workload: independent repeated material
    -- phrases and exact Pattern values defeat earlier compressed raw layouts.
    -- Park-Miller products remain exact integers in Lua's double range.
    local state = 20261010
    local function next_value()
        state = (state * 48271) % 2147483647
        return state
    end
    local words = {}
    for n = 1, 126 do
        words[n] = 0x3f000000 + next_value() % 0x800000
    end
    words[127], words[128] = 0x80000000, 0x40500000 -- Signed zero and HDR3.25.
    local documents = {}
    for n = 1, 11 do
        local phrase = {}
        for i = 1, 112 do
            phrase[i] = next_value() % 128 + 1
        end
        local bits = ffi.new('uint32_t[736]')
        for i = 0, 735 do
            bits[i] = words[phrase[i % 112 + 1]]
        end
        local document = { width = 23, height = 8, data = ffi.new('float[736]') }
        ffi.copy(document.data, bits, 2944)
        documents[n] = document
    end
    for n = 12, 13 do
        local bits = ffi.new('uint32_t[12]')
        for i = 0, 11 do
            bits[i] = words[next_value() % 128 + 1]
        end
        local document = { width = 3, height = 1, data = ffi.new('float[12]') }
        ffi.copy(document.data, bits, 48)
        documents[n] = document
    end
    local entries = {}
    for i = 0, 123 do
        local pattern = i >= 86
        local index = pattern and (12 + (i - 86) % 2) or (i % 11 + 1)
        entries[#entries + 1] = {
            key = (pattern and 'p:' or '') .. '0:2:' .. math.floor(i / 2) .. ':' .. i % 2,
            document = documents[index],
        }
    end
    local codec = C.new()
    local packet = codec.encode(identity, entries)
    local earlier = math.min(codec.packet_sizes.full, codec.packet_sizes.sparse, codec.packet_sizes.xor)
    assert(
        earlier > C.MAX_TEXT and packet:match('^5x?|') and #packet <= C.MAX_TEXT,
        'Public overbudget appearance did not fit the planar word dictionary'
    )
    local result = codec.decode(packet)
    local count = 0
    for _ in pairs(result.entries) do
        count = count + 1
    end
    assert(count == 124 and #result.documents == 13, 'Dictionary dropped destinations or material/Pattern tables')
    for _, entry in ipairs(entries) do
        local got = result.entries[entry.key].document
        local bytes = entry.document.width * entry.document.height * 16
        assert(
            got.width == entry.document.width
                and got.height == entry.document.height
                and ffi.string(got.data, bytes) == ffi.string(entry.document.data, bytes),
            'Dictionary altered opaque F32/Pattern/HDR/signed-zero bits'
        )
    end
    print(
        'PASS public overbudget combined appearance: '
            .. earlier
            .. ' -> '
            .. #packet
            .. ' bytes,124 exact destinations/13 material and Pattern tables'
    )
end
