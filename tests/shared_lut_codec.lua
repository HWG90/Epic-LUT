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
