local ffi = require('ffi')
local C = dofile('src/catalog.lua')
local width, height = 23, 8
local size = width * height * 16
local values = ffi.new('float[?]', width * height * 4)
for i = 0, width * height * 4 - 1 do
    values[i] = (i % 17 - 8) * 0.125
end
local bytes = ffi.cast('uint8_t *', values)
local function split(_, count, out, offset)
    assert(ffi.istype('uint8_t *', out), 'Archive destination must have byte-sized pointer arithmetic')
    local first = math.min(37, count)
    ffi.copy(out + offset, bytes, first)
    ffi.copy(out + offset + first, bytes + first, count - first)
end
local decoded = C.read_rgba32f(split, width, height)
assert(ffi.string(decoded, size) == ffi.string(values, size), 'Split RGBA32F payload changed')
-- Demonstrate the former float-pointer call overruns a payload-sized region safely inside a larger canary allocation.
local guarded = ffi.new('uint8_t[?]', size * 4 + 128)
ffi.fill(guarded, size * 4 + 128, 0xa5)
local wrong = ffi.cast('float *', guarded)
local first = 1024
ffi.copy(wrong, bytes, first)
ffi.copy(wrong + first, bytes + first, size - first)
assert(guarded[size] ~= 0xa5 or guarded[first * 4] ~= 0xa5, 'Former byte-offset error was not reproduced')
local safe = ffi.cast('uint8_t *', guarded)
ffi.fill(guarded, size * 4 + 128, 0xa5)
split(0, size, safe, 0)
for i = size, size * 4 + 127 do
    assert(guarded[i] == 0xa5, 'Byte-addressed split write changed guard region')
end
print(
    'PASS: former float-pointer split-read overrun reproduced inside canary storage; RGBA32F reader now uses byte arithmetic and preserves exact payload/bounds'
)
