local ffi = require('ffi')
local C = dofile('src/editor/basic_camo.lua')
local d = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4), revision = 7 }
for i = 0, 23 * 64 * 4 - 1 do
    d.data[i] = (i % 113) / 17 - 2
end
for row = 1, 64 do
    d.data[((row - 1) * 23 + 21) * 4] = 9.5
    d.data[((row - 1) * 23 + 21) * 4 + 2] = 1.25
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
-- Colorways apply a complete MYC-style recipe. A single tint edits only RGB.
local colors = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4), revision = 3 }
ffi.copy(colors.data, original, #before)
for row = 1, 64 do
    colors.data[((row - 1) * 23 + 21) * 4 + 3] = 2
end
local color_before = ffi.string(colors.data, #before)
local function expected_colors(source, values, helmet)
    local height = #source / (23 * 16)
    local expected = ffi.new('float[?]', #source / 4)
    ffi.copy(expected, source, #source)
    for color, hex in pairs(values) do
        for row = 1, height do
            if not helmet or row ~= 8 then
                for channel = 0, 2 do
                    expected[((row - 1) * 23 + 15 + color) * 4 + channel] = tonumber(
                        hex:sub(channel * 2 + 1, channel * 2 + 2),
                        16
                    ) / 255
                end
            end
        end
    end
    return ffi.string(expected, #source)
end
local profiles = {
    { mask = { 216.625, -0.98974609375, 2, 3 }, blend = 0.82958984375 },
    { mask = { 216.625, -0.98974609375, 3.5, 1 }, blend = 0 },
    { mask = { 216.625, -1, 1.19921875, 1 }, blend = 0.82958984375 },
    { mask = { 216.625, -0.98974609375, 5, 3 }, blend = 0.82958984375 },
}
local function expected_recipe(source, index, helmet, mask, seed)
    local palette, profile = C.COLORWAYS[index], profiles[index]
    local height = #source / (23 * 16)
    local expected = ffi.new('float[?]', #source / 4)
    ffi.copy(expected, seed and expected_colors(source, palette.colors, helmet) or source, #source)
    for row = 1, height do
        if not helmet or row ~= 8 then
            local offset = (row - 1) * 23 * 4
            for color, alpha in ipairs({ 0.52978515625, 2, -1, 4 }) do
                expected[offset + (15 + color) * 4 + 3] = alpha
            end
            expected[offset + 20 * 4 + 3] = 0.8896484375
            for channel = 0, 2 do
                expected[offset + 21 * 4 + channel] = profile.mask[channel + 1]
            end
            expected[offset + 21 * 4 + 3] = mask or profile.mask[4]
            expected[offset + 22 * 4 + 3] = profile.blend
        end
    end
    return ffi.string(expected, #source)
end
for index, palette in ipairs(C.COLORWAYS) do
    ffi.copy(colors.data, color_before, #color_before)
    local revision = colors.revision
    assert(C.apply(colors, index + 1, 'colorway') == 64 and colors.revision == revision + 1)
    assert(
        ffi.string(colors.data, #color_before) == expected_recipe(color_before, index, false, 2, true),
        'Colorway missed its recipe or changed Base/mode/emission or the authored valid mask'
    )
    assert(C.colorway_selection(colors) == index + 1)
    for color, hex in ipairs(palette.colors) do
        assert(C.color(colors, color) == '#' .. hex, 'Colorway first-row color did not match its label')
    end
end
for _, at in ipairs({
    16 * 4 + 3,
    17 * 4 + 3,
    18 * 4 + 3,
    19 * 4 + 3,
    20 * 4 + 3,
    21 * 4,
    21 * 4 + 1,
    21 * 4 + 2,
    22 * 4 + 3,
}) do
    local previous = colors.data[at]
    colors.data[at] = previous + 0.25
    assert(C.colorway_selection(colors) == 1, 'Matching RGB concealed a different supporting camo scalar')
    colors.data[at] = previous
    assert(C.colorway_selection(colors) == 5)
end
-- Stock zeroed camo controls must become renderable; a numerically valid
-- mask alone is still dormant. Colorway defaults include Desert's zero blend.
local dormant = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
for row = 1, 64 do
    dormant.data[((row - 1) * 23) * 4] = 1.625
    dormant.data[((row - 1) * 23 + 15) * 4 + 3] = -2.75
    dormant.data[((row - 1) * 23 + 22) * 4] = 0.8125
end
local dormant_before = ffi.string(dormant.data, #before)
assert(C.selection(dormant) == 1, 'Zeroed controls were presented as an active mask')
for index in ipairs(C.COLORWAYS) do
    ffi.copy(dormant.data, dormant_before, #before)
    C.apply(dormant, index + 1, 'colorway')
    assert(ffi.string(dormant.data, #before) == expected_recipe(dormant_before, index, false, nil, true))
    assert(C.selection(dormant) == profiles[index].mask[4] + 3 and C.colorway_selection(dormant) == index + 1)
end
ffi.copy(dormant.data, dormant_before, #before)
C.apply(dormant, 8)
assert(
    ffi.string(dormant.data, #before) == expected_recipe(dormant_before, 1, false, 5, true),
    'Pattern did not initialize dormant scalar controls and all-black camo colors'
)
ffi.copy(dormant.data, dormant_before, #before)
for row = 1, 64 do
    local at = ((row - 1) * 23 + 21) * 4
    dormant.data[at], dormant.data[at + 2], dormant.data[at + 3] = 9.5, 1.25, 4
end
local black_ready = ffi.string(dormant.data, #before)
C.apply(dormant, 8)
assert(
    ffi.string(dormant.data, #before) == expected_recipe(black_ready, 1, false, 5, true),
    'All-black camo RGB with active scalar controls did not seed a visible recipe'
)
local active_bytes = ffi.string(dormant.data, #before)
local off = ffi.new('float[?]', 23 * 64 * 4)
ffi.copy(off, active_bytes, #before)
for row = 1, 64 do
    off[((row - 1) * 23 + 21) * 4 + 3] = -1
end
C.apply(dormant, 2)
assert(ffi.string(dormant.data, #before) == ffi.string(off, #before), 'Off changed existing scalar/color controls')
ffi.copy(dormant.data, dormant_before, #before)
for row = 1, 64 do
    dormant.data[((row - 1) * 23 + 16) * 4] = 0.375
end
local nonblack = ffi.string(dormant.data, #before)
C.apply(dormant, 7)
assert(
    ffi.string(dormant.data, #before) == expected_recipe(nonblack, 1, false, 4, false),
    'Dormant initialization overwrote authored nonblack camo RGB'
)
dormant.data[21 * 4 + 2] = math.huge
assert(C.selection(dormant) == 1)
C.apply(dormant, 7)
assert(ffi.string(dormant.data, #before) == expected_recipe(nonblack, 1, false, 4, false))
dormant.data[21 * 4] = 0 / 0
assert(C.selection(dormant) == 1)
C.apply(dormant, 7)
assert(ffi.string(dormant.data, #before) == expected_recipe(nonblack, 1, false, 4, false))
colors.data[21 * 4] = 0
assert(C.colorway_selection(colors) == 1, 'Matching RGB with dormant controls was labeled an active colorway')
colors.data[21 * 4] = C.COLORWAYS[4].mask[1]
colors.data[(23 + 19) * 4] = 0.12345
assert(C.colorway_selection(colors) == 1, 'First-row colorway hid mixed lower rows')
snapshot = ffi.string(colors.data, #before)
assert(C.apply(colors, '#0a80FF', 'color', 1) == 64 and C.color(colors, 1) == '#0A80FF')
assert(ffi.string(colors.data, #before) == expected_colors(snapshot, { [1] = '0A80FF' }))
snapshot = ffi.string(colors.data, #before)
assert(C.apply(colors, { 255, 32, 0 }, 'color', 4) == 64)
assert(ffi.string(colors.data, #before) == expected_colors(snapshot, { [4] = 'FF2000' }))
-- Basic Helmet camo excludes visor region 8, even on a 64-row table. Its
-- pattern is forced Off; tint edits preserve all of its HDR RGB/alpha bytes.
for _, height in ipairs({ 8, 64 }) do
    local helmet = { width = 23, height = height, data = ffi.new('float[?]', 23 * height * 4) }
    local size = 23 * height * 16
    ffi.copy(helmet.data, original, size)
    local expected = ffi.new('float[?]', 23 * height * 4)
    ffi.copy(expected, helmet.data, size)
    for row = 1, height do
        expected[((row - 1) * 23 + 21) * 4 + 3] = row == 8 and -1 or 5
    end
    C.apply(helmet, 8, nil, nil, 'helmet')
    local pattern_bytes = ffi.string(expected, size)
    assert(ffi.string(helmet.data, size) == pattern_bytes, 'Helmet pattern changed a visor field besides camo Off')
    assert(C.selection(helmet, 'helmet') == 8 and C.selection(helmet) == 1)
    C.apply(helmet, 3, 'colorway', nil, 'helmet')
    local colorway_bytes = expected_recipe(pattern_bytes, 2, true, 5, true)
    assert(ffi.string(helmet.data, size) == colorway_bytes, 'Helmet colorway changed visor or other material bytes')
    assert(C.colorway_selection(helmet, 'helmet') == 3 and C.colorway_selection(helmet) == 1)
    C.apply(helmet, '#1100F1', 'color', 4, 'helmet')
    assert(
        ffi.string(helmet.data, size) == expected_colors(colorway_bytes, { [4] = '1100F1' }, true),
        'Helmet tint changed visor alpha/RGB or another tint'
    )
    if height == 64 then
        assert(helmet.data[(8 * 23 + 19) * 4] > 0, 'Region 9 was incorrectly excluded with the visor')
        helmet.data[(8 * 23 + 21) * 4 + 3] = 2
        assert(C.selection(helmet, 'helmet') == 1, 'Helmet selector ignored a non-visor mixed region')
    end
end
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
    'PASS Basic camo: all64 rows, complete camo recipes/dormant activation, authored RGB/scalar preservation, exact single-tint/visor edits, mixed/invalid/unsupported selections, commit callbacks and neutral actual-mask thumbnails'
)
