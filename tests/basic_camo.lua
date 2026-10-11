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
d.read_only = true
assert(not C.available(d) and not pcall(C.apply, d, 3))
d.read_only, d.width = nil, 16
assert(
    not C.available(d) and C.selection(d) == 1 and not pcall(C.apply, d, 3),
    'Cape layout accepted material camo controls'
)
local called
local controls = C.controls(function(kind, value)
    called = { kind, value }
end)
controls[2].on_change(4)
assert(called[1] == 'helmet' and called[2] == 4)
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
    'PASS Basic camo: all64 rows, exact single-field edits, preserved colors/materials/alpha, mixed/off selections, unsupported layouts and neutral actual-mask thumbnails'
)
