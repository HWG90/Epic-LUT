-- Serialization test only: tokens below stand in for a separately supplied
-- compressor. They are not production Shared LUT wire compression.
local buffers = require('src.core.float_buffer')
local C = dofile('src/gear/shared_lut_codec.lua')
local portable = C.compression()
assert(type(portable.compress) == 'function' and type(portable.decompress) == 'function')
assert(not pcall(portable.decompress, 'not-XPRESS', 1, 'x'), 'Malformed XPRESS input was accepted')
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256, math.floor(n / 16777216))
end
local identity = { body = 4294967295, armor = 2147483648, helmet = 789 }
local originals = {}
local base = {width = 23, height = 8, data = buffers.new(736), resource = '0123456789abcdef'}
for i = 0, 735 do base.data[i] = math.sin(i * 19) * 8 end
originals[base.resource] = base
local edited = {width = 23, height = 8, data = buffers.new(736)}
buffers.copy(edited.data, base.data, 736)
edited.data[0], edited.data[4], edited.data[9] = 2.75, -0.125, 0.375
buffers.copy(edited.data, word(2147483648), 1, 1)
local pattern = {width = 3, height = 1, data = buffers.new(12)}
pattern.data[0], pattern.data[3], pattern.data[7], pattern.data[11] = 0.5, 2.75, 0.4, -0.2
local entries = {{key = '0:1:2:3', document = edited, original = base},
    {key = '1:0:0:0', document = edited, original = base},
    {key = 'p:0:1:2:3', document = pattern}}
local function exercise(version, selected, selected_identity)
    local stored, sequence, last_raw = {}, 0
    local host = { formats = { '' } }
    host.compress = function(raw, tag)
        assert(tag == '')
        if raw:sub(1, 3) ~= 'EL' .. version then return string.rep('x', 4000) end
        sequence = sequence + 1
        local token = word(sequence)
        stored[token], last_raw = raw, raw
        return token
    end
    host.decompress = function(token, size, tag)
        assert(tag == '')
        local raw = assert(stored[token], 'Unknown serialization token')
        assert(#raw == size)
        return raw
    end
    assert(C.compression(host) == host, 'Explicit compressor host was not accepted')
    local codec = C.new(host, function(resource) return originals[resource] end)
    local packet = codec.encode(selected_identity or identity, selected)
    assert(packet:match('^' .. version .. '|'), 'Requested existing format was not exercised')
    local result = codec.decode(packet)
    for _, entry in ipairs(selected) do
        local decoded = assert(result.entries[entry.key])
        local count = entry.document.width * entry.document.height * 4
        assert(buffers.bytes(decoded.document.data, count) == buffers.bytes(entry.document.data, count),
            'Shared format changed exact float bytes: EL' .. version)
    end
    assert(result.body == identity.body and result.armor == identity.armor and result.helmet == identity.helmet,
        'Unsigned kit identity lost bits')
    assert(not pcall(codec.decode, packet .. 'x'), 'Trailing encoded data accepted')
    if version == '2' or version == '3' then
        local keep = base.data[0]
        base.data[0] = keep + 1
        assert(not pcall(codec.decode, packet), 'Changed receiver baseline was accepted')
        base.data[0] = keep
        assert(codec.decode(packet))
    end
    return last_raw, result
end
for _, version in ipairs({'1', '2', '3', '5', '7'}) do exercise(version, entries) end
local maximum = {}
for mesh = 0, 63 do
    for material = 0, 63 do
        maximum[#maximum + 1] = {key = '0:1:' .. mesh .. ':' .. material, document = edited, original = base}
    end
end
local _, maximum_result = exercise('4', maximum)
local count = 0
for _ in pairs(maximum_result.entries) do count = count + 1 end
assert(count == 4096 and #maximum_result.documents == 1, 'Compact count or deduplication changed')
-- Dictionary index width changes after 256 distinct exact F32 words.
for _, unique in ipairs({255, 256, 257}) do
    local words = {}
    for i = 0, 275 do words[i + 1] = word(1056964608 + i % unique) end
    local d = {width = 23, height = 3, data = buffers.from_bytes(table.concat(words), 276)}
    local raw = exercise('5', {{key = '0:1:0:0', document = d}})
    assert(raw:byte(19) + raw:byte(20) * 256 == unique, 'Wrong dictionary width fixture')
end
-- R6 adds a separate explicit weapon identity representation.
-- R5 does not expose weapon sharing.
assert(not pcall(function() C.new({compress=function() return string.rep('x',4000) end}).encode(identity, entries) end),
    'Oversized compressor output escaped the lobby budget')
print('PASS stock Shared LUT serialization: EL1/2/3/4/5/7, unsigned kit words, exact HDR/signed-zero/Pattern bytes, baseline guard, dictionary widths, 4096 bindings; compressor host remains separate')
