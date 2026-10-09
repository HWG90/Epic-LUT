local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local S = dofile('src/core/semantics.lua')
local P = dofile('src/core/palette.lua')
local Doc = dofile('src/legacy/document.lua')
local n = 23 * 8 * 4
local original = ffi.new('float[?]', n)
for i = 0, n - 1 do
    original[i] = (i % 101 - 40) / 17
end
original[0] = 500000
original[3] = 2
original[13 * 4] = 8.5
original[13 * 4 + 1] = 100000000
original[13 * 4 + 2] = -12.5
original[13 * 4 + 3] = 0.46
local bytes = D.encode(original, 23, 8)
local decoded, w, h = D.decode(bytes, 23, 8)
assert(
    w == 23 and h == 8 and ffi.string(original, n * 4) == ffi.string(decoded, n * 4),
    'Float DDS round trip changed HDR/negative values'
)
local function header_word(raw, offset, value)
    return raw:sub(1, offset)
        .. string.char(
            value % 256,
            math.floor(value / 256) % 256,
            math.floor(value / 65536) % 256,
            math.floor(value / 16777216) % 256
        )
        .. raw:sub(offset + 5)
end
local mipmapped = header_word(header_word(bytes, 24, 1), 28, 2) .. string.rep('\0', 11 * 4 * 16)
assert(
    ffi.string(D.decode(mipmapped), n * 4) == ffi.string(original, n * 4),
    'Mipmapped DDS changed the full-resolution LUT'
)
assert(not pcall(D.decode, mipmapped:sub(1, -2)), 'Truncated mip chain accepted')
assert(not pcall(D.decode, header_word(mipmapped, 28, 99)), 'Impossible mip count accepted')
assert(not pcall(D.decode, header_word(mipmapped, 8, 0x80100f)), 'Volume texture accepted')
assert(not pcall(D.decode, header_word(mipmapped, 112, 512)), 'Cube texture accepted')
local recolor = P.copy(original, 23, 8, { [0] = '#FF0080' }, function(count)
    return ffi.new('float[?]', count)
end, ffi.copy)
for i = 3, n - 1 do
    assert(recolor[i] == original[i], 'Base recolor changed an untouched value')
end
local changed = ffi.new('float[?]', n)
for i = 0, n - 1 do
    changed[i] = -123
end
local protected = S.protect(original, changed, 23, 8)
for row = 1, 8 do
    for col = 1, 23 do
        for ch = 1, 4 do
            local i = S.index(row, col, ch, 23, 8)
            assert(
                protected[i] == (S.safe_cell(col, ch) and changed[i] or original[i]),
                'Effect protection changed wrong channel'
            )
        end
    end
end
assert(
    protected[3] == 2
        and protected[13 * 4] == 8.5
        and protected[13 * 4 + 1] == 100000000
        and protected[13 * 4 + 2] == -12.5
)
assert(not pcall(D.decode, bytes:sub(1, -2), 23, 8))
assert(not pcall(D.decode, bytes, 23, 5))
local bad = ffi.new('float[?]', n)
ffi.copy(bad, original, n * 4)
bad[9] = 0 / 0
assert(not pcall(D.encode, bad, 23, 8))
local model = Doc.new(D)
local lut = { name = '0123456789abcdef', width = 23, height = 8, values = original }
model.attach({ luts = { lut } }, 'tests/presets', {})
model.edit(lut.name, { [4] = 0.25 })
assert(model.documents[lut.name].data[4] == 0.25)
model.undo()
assert(model.documents[lut.name].data[4] == original[4])
model.redo()
assert(model.documents[lut.name].data[4] == 0.25)
model.row_copy(lut.name, 1)
model.row_paste(lut.name, 2)
for i = 0, 23 * 4 - 1 do
    assert(model.documents[lut.name].data[23 * 4 + i] == model.documents[lut.name].data[i])
end
local Presets = dofile('src/legacy/presets.lua')
local catalog = { identity = { target_kind = 'helmet', target_id = 234, armor = 123, body = 0 }, luts = { lut } }
local get = {
    get = function(id)
        if id:match('_color$') then
            return '#112233'
        else
            return true
        end
    end,
}
local preset = Presets.encode(catalog, get, model)
local values, docs = Presets.decode(preset, catalog)
assert(
    ffi.string(docs[lut.name], n * 4) == ffi.string(model.documents[lut.name].data, n * 4),
    'Full preset changed HDR/emissive floats'
)
local armor_catalog = { identity = { target_kind = 'armor', target_id = 234, body = 0 }, luts = { lut } }
assert(not pcall(Presets.decode, preset, armor_catalog), 'Helmet preset accepted on armor')
assert(
    not pcall(Presets.decode, preset:gsub('float\t0123456789abcdef\t1\t1[^\n]*\n', ''), catalog),
    'Missing float cell accepted'
)
assert(values.enabled and values.preserve_effects)
print(
    'PASS: full-float HDR/negative DDS round trip, untouched emissive/mode preservation, default effect protection, malformed rejection, undo/redo and row copy/paste'
)

local custom = ffi.new('float[?]', 23 * 64 * 4)
for i = 0, 23 * 64 * 4 - 1 do
    custom[i] = (i % 107 - 50) / 13
end
ffi.cast('uint32_t *', custom)[63 * 23 * 4 + 3] = 0x80000000
local custom_bytes = D.encode(custom, 23, 64)
local custom_back, custom_w, custom_h = D.decode(custom_bytes)
assert(custom_w == 23 and custom_h == 64 and ffi.string(custom_back, 23 * 64 * 16) == ffi.string(custom, 23 * 64 * 16))
local recolored = P.copy(custom, 23, 64, { [63] = '#123456' }, function(count)
    return ffi.new('float[?]', count)
end, ffi.copy)
assert(ffi.string(recolored, 63 * 23 * 16) == ffi.string(custom, 63 * 23 * 16), 'Last-row recolor changed earlier rows')
assert(
    ffi.string(recolored + 63 * 23 * 4 + 3, (23 * 4 - 3) * 4) == ffi.string(custom + 63 * 23 * 4 + 3, (23 * 4 - 3) * 4)
)
local too_tall = ffi.new('float[?]', 23 * 65 * 4)
assert(not pcall(D.encode, too_tall, 23, 65), 'DDS encoder accepted row 65')
assert(not pcall(D.decode, header_word(custom_bytes, 12, 65)), 'DDS decoder accepted row 65')
assert(not pcall(P.copy, too_tall, 23, 65, {}, function(count)
    return ffi.new('float[?]', count)
end, ffi.copy), 'Palette accepted row 65')
assert(not pcall(P.copy, custom, 23, 64, { [64] = '#123456' }, function(count)
    return ffi.new('float[?]', count)
end, ffi.copy), 'Palette accepted a row beyond its document')
print('PASS 64-row LUT: exact DDS/signed-zero round trip, last-row RGB isolation and row-65 rejection')
