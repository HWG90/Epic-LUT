local ffi = require('ffi')
local C = dofile('src/editor/basic_camo.lua')
local d = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4), revision = 7 }
for i = 0, 23 * 64 * 4 - 1 do
    d.data[i] = (i % 113) / 17 - 2
end
local before = ffi.string(d.data, 23 * 64 * 16)
assert(C.available(d) and C.selection(d) == 1)
assert(C.apply(d, 8) == 64 and d.revision == 8 and C.selection(d) == 8)
local original = ffi.new('float[?]', 23 * 64 * 4)
ffi.copy(original, before, #before)
for row = 1, 64 do
    for column = 1, 23 do
        for channel = 1, 4 do
            local at = ((row - 1) * 23 + column - 1) * 4 + channel - 1
            assert(
                d.data[at] == (column == 22 and channel == 4 and 5 or original[at]),
                'Camo selection altered another field'
            )
        end
    end
end
assert(C.apply(d, 2) == 64 and C.selection(d) == 2)
d.data[21 * 4 + 3] = 0
assert(C.selection(d) == 1, 'Mixed row patterns were labeled as a single pattern')
local snapshot = ffi.string(d.data, 23 * 64 * 16)
for _, value in ipairs({ 0, 1, 9, 3.5, '3' }) do
    assert(not pcall(C.apply, d, value))
    assert(ffi.string(d.data, #snapshot) == snapshot, 'Invalid selection partially edited rows')
end
-- Colorways and individual tints change only RGB in C1-C4, including all
-- 64 rows. Arbitrary HDR/negative alpha and every other field stay byte-exact.
local colors = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4), revision = 3 }
ffi.copy(colors.data, original, #before)
local color_before = ffi.string(colors.data, #before)
local function expected_colors(source, values)
    local expected = ffi.new('float[?]', 23 * 64 * 4)
    ffi.copy(expected, source, #source)
    for color, hex in pairs(values) do
        for row = 1, 64 do
            for channel = 0, 2 do
                expected[((row - 1) * 23 + 15 + color) * 4 + channel] = tonumber(
                    hex:sub(channel * 2 + 1, channel * 2 + 2),
                    16
                ) / 255
            end
        end
    end
    return ffi.string(expected, #source)
end
for index, palette in ipairs(C.COLORWAYS) do
    ffi.copy(colors.data, color_before, #color_before)
    local revision = colors.revision
    assert(C.apply(colors, index + 1, 'colorway') == 64 and colors.revision == revision + 1)
    assert(
        ffi.string(colors.data, #color_before) == expected_colors(color_before, palette.colors),
        'Colorway changed alpha, pattern, scale or other material fields'
    )
    assert(C.colorway_selection(colors) == index + 1)
    for color, hex in ipairs(palette.colors) do
        assert(C.color(colors, color) == '#' .. hex, 'Colorway first-row color did not match its label')
    end
end
colors.data[(23 + 19) * 4] = 0.12345
assert(C.colorway_selection(colors) == 1, 'First-row colorway hid mixed lower rows')
snapshot = ffi.string(colors.data, #before)
assert(C.apply(colors, '#0a80FF', 'color', 1) == 64 and C.color(colors, 1) == '#0A80FF')
assert(ffi.string(colors.data, #before) == expected_colors(snapshot, { [1] = '0A80FF' }))
snapshot = ffi.string(colors.data, #before)
assert(C.apply(colors, { 255, 32, 0 }, 'color', 4) == 64)
assert(ffi.string(colors.data, #before) == expected_colors(snapshot, { [4] = 'FF2000' }))
local revision = colors.revision
snapshot = ffi.string(colors.data, #before)
for _, args in ipairs({
    { 1, 'colorway' },
    { 6, 'colorway' },
    { 2.5, 'colorway' },
    { '#BAD', 'color', 1 },
    { 'GGFFFF', 'color', 1 },
    { { 256, 0, 0 }, 'color', 1 },
    { { 1.5, 0, 0 }, 'color', 1 },
    { { 0, 0 }, 'color', 1 },
    { 'FFFFFF', 'color', 0 },
    { 'FFFFFF', 'color', 5 },
    { 'FFFFFF', 'color', '1' },
    { 2, 'unknown' },
}) do
    assert(not pcall(C.apply, colors, unpack(args)), 'Invalid color selection was accepted')
    assert(
        ffi.string(colors.data, #before) == snapshot and colors.revision == revision,
        'Invalid color selection partially changed the table/revision'
    )
end
colors.read_only = true
assert(not pcall(C.apply, colors, 2, 'colorway'))
colors.read_only, colors.stale = nil, true
assert(C.colorway_selection(colors) == 1 and not pcall(C.apply, colors, 'FFFFFF', 'color', 1))
colors.stale, colors.width = nil, 16
assert(C.color(colors, 1) == '#000000' and not pcall(C.apply, colors, 2, 'colorway'))
assert(ffi.string(colors.data, #before) == snapshot)
d.read_only = true
assert(not C.available(d) and not pcall(C.apply, d, 3))
d.read_only, d.width = nil, 16
assert(
    not C.available(d) and C.selection(d) == 1 and not pcall(C.apply, d, 3),
    'Cape layout accepted material camo controls'
)
local called
local controls = C.controls(function(kind, value, mode, index)
    called = { kind, value, mode, index }
    return true
end)
controls[2].on_change(4)
assert(called[1] == 'helmet' and called[2] == 4)
local by_id = {}
for _, control in ipairs(controls) do
    by_id[control.id] = control
end
by_id.basic_armor_camo_colorway.on_change(3)
assert(called[1] == 'armor' and called[2] == 3 and called[3] == 'colorway')
by_id.basic_helmet_camo_color_4.on_change('#FF2000')
assert(called[1] == 'helmet' and called[3] == 'color' and called[4] == 4)
called = nil
assert(by_id.basic_armor_camo_color_1.picker_commit('#FF2000') == true)
assert(called and called[1] == 'armor' and called[3] == 'color' and called[4] == 1)
local thumbnails = C.thumbnails({
    width = 1,
    height = 1,
    layers = {
        string.char(255, 0, 0, 255),
        string.char(0, 255, 0, 255),
        string.char(0, 0, 255, 255),
        string.char(0, 0, 0, 255),
        string.char(255, 255, 255, 255),
        string.char(255, 0, 0, 255),
    },
})
assert(not thumbnails[1] and not thumbnails[2] and thumbnails[8])
assert(not C.thumbnails({ width = 16, height = 16, layers = { 'bad' } }))
assert(thumbnails[3].colors[1][1] ~= thumbnails[4].colors[1][1], 'Mask regions disappeared in neutral thumbnails')
print(
    'PASS Basic camo: all64 rows, exact pattern/colorway/single-tint edits, HDR alpha/material preservation, mixed/invalid/unsupported selections, commit callbacks and neutral actual-mask thumbnails'
)
