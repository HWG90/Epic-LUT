-- Actual LuaJIT FFI against an owned allocation, never a game-memory address.
local ffi = require('ffi')
local Legacy = dofile('src/platform/legacy_memory.lua')
local bytes = string.char(0, 1, 127, 128, 255, 5, 6, 7)
local owned = ffi.new('uint8_t[8]')
ffi.copy(owned, bytes, #bytes)
local address, reads = tonumber(ffi.cast('uintptr_t', owned)), 0
local memory = { read_into = function(pointer, size, out)
    reads = reads + 1
    assert(tonumber(ffi.cast('uintptr_t', pointer)) == address and size == #bytes)
    ffi.copy(out, pointer, size)
    return true
end }
assert(Legacy.read(memory, address, #bytes) == bytes and reads == 1)
local state = Legacy.buffers()
assert(ffi.sizeof(state.small) == 96 and ffi.sizeof(state.big) == 1024)
assert(state.read_into(memory, address, #bytes, state.small) and ffi.string(state.small, #bytes) == bytes)
reads = 1
for _, args in ipairs({ { address + 0.5, 8 }, { address, 0 }, { address, 97 }, { address, 1.5 } }) do
    assert(not pcall(Legacy.read, memory, args[1], args[2]) and reads == 1)
end
memory.read_into = function() return false end
assert(Legacy.read(memory, address, #bytes) == nil)
print('PASS explicit legacy snapshot boundary: exact binary bytes, bounded integer reads and refusal')
