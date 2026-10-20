-- Explicit legacy memory boundary, selected only after verified native startup.
-- Stock projects supply a read_snapshot service and do not load this module.
local M = {}
function M.buffers()
    local ffi = require('ffi')
    return { small = ffi.new('uint8_t[96]'), big = ffi.new('uint8_t[1024]'),
        read_into = function(memory, address, size, out)
            return memory.read_into(ffi.cast('const uint8_t *', address), size, out)
        end }
end
function M.read(memory, address, size)
    assert(type(memory) == 'table' and type(memory.read_into) == 'function', 'Legacy snapshot memory unavailable')
    assert(type(address) == 'number' and address >= 65536 and address < 2 ^ 47 and address % 1 == 0
        and type(size) == 'number' and size >= 1 and size <= 96 and size % 1 == 0,
        'Invalid kit snapshot read')
    local ffi = require('ffi')
    local buffer = ffi.new('uint8_t[?]', size)
    return memory.read_into(ffi.cast('const uint8_t *', address), size, buffer) and ffi.string(buffer, size) or nil
end
return M
