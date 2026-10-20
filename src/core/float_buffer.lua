-- Zero-based binary32 buffers. Stock Lua 5.1 needs no native or bit library.
-- The older LuaJIT runtime may reuse an already-loaded FFI backend; this module
-- never loads it and the portable path remains independently executable.
local B = { MAX_ELEMENTS = 64 * 64 * 4 }
local floor, abs, huge = math.floor, math.abs, math.huge
-- Only buffers produced by this module can prove an owned portable array.
-- Public table fields or a copied metatable cannot forge its allocation size.
local counts = setmetatable({}, { __mode = 'k' })
local ffi = type(jit) == 'table' and package and package.loaded and package.loaded.ffi
if type(ffi) ~= 'table' or type(ffi.new) ~= 'function' then ffi = nil end
local function finite(value)
    assert(type(value) == 'number' and value == value and abs(value) ~= huge, 'Nonfinite float value')
    return value
end
local function integer(value, maximum, message)
    assert(type(value) == 'number' and value >= 0 and value <= maximum and value % 1 == 0, message)
    return value
end
local function nearest_even(value)
    local base = floor(value)
    local tail = value - base
    if tail > 0.5 or tail == 0.5 and base % 2 == 1 then return base + 1 end
    return base
end
function B.value_to_word(value)
    finite(value)
    local sign = (value < 0 or value == 0 and 1 / value < 0) and 2147483648 or 0
    value = abs(value)
    if value == 0 then return sign end
    if value < 2 ^ -126 then return sign + nearest_even(value / 2 ^ -149) end
    local fraction, exponent = math.frexp(value)
    exponent = exponent - 1
    local significand = nearest_even(fraction * 16777216)
    if significand == 16777216 then significand, exponent = 8388608, exponent + 1 end
    assert(exponent <= 127, 'Float32 value out of range')
    return sign + (exponent + 127) * 8388608 + significand - 8388608
end
function B.word_to_value(word)
    integer(word, 4294967295, 'Invalid float word')
    local sign = word >= 2147483648 and -1 or 1
    local exponent = floor(word / 8388608) % 256
    local fraction = word % 8388608
    assert(exponent ~= 255, 'Nonfinite float value')
    if exponent == 0 then return sign * fraction * 2 ^ -149 end
    return sign * (1 + fraction / 8388608) * 2 ^ (exponent - 127)
end
function B.round(value)
    return B.word_to_value(B.value_to_word(value))
end
function B.count(data)
    if type(data) == 'table' then return counts[data] end
    if ffi and type(data) == 'cdata' and ffi.istype('float[?]', data) then return ffi.sizeof(data) / 4 end
end
local function extent(data, count, offset)
    integer(count, B.MAX_ELEMENTS, 'Invalid float count')
    integer(offset, B.MAX_ELEMENTS, 'Invalid float offset')
    local available = B.count(data)
    assert(not available or offset + count <= available, 'Float buffer bounds exceeded')
end
function B.new(count)
    integer(count, B.MAX_ELEMENTS, 'Invalid float count')
    if ffi then return ffi.new('float[?]', count) end
    local values = {}
    for i = 0, count - 1 do values[i] = 0 end
    local result = setmetatable({}, {
        __index = function(_, index)
            integer(index, count - 1, 'Float buffer index out of bounds')
            return values[index]
        end,
        __newindex = function(_, index, value)
            integer(index, count - 1, 'Float buffer index out of bounds')
            values[index] = B.round(value)
        end,
    })
    counts[result] = count
    return result
end
function B.copy(destination, source, count, destination_offset, source_offset)
    destination_offset, source_offset = destination_offset or 0, source_offset or 0
    extent(destination, count, destination_offset)
    extent(source, count, source_offset)
    if type(source) == 'string' then
        assert(#source >= (source_offset + count) * 4, 'Truncated float buffer')
        if ffi and type(destination) == 'cdata' then
            ffi.copy(destination + destination_offset, source:sub(source_offset * 4 + 1, (source_offset + count) * 4), count * 4)
        else
            for i = 0, count - 1 do
                local at = (source_offset + i) * 4
                local a, b, c, d = source:byte(at + 1, at + 4)
                destination[destination_offset + i] = B.word_to_value(a + b * 256 + c * 65536 + d * 16777216)
            end
        end
    elseif ffi and type(destination) == 'cdata' and type(source) == 'cdata' and destination ~= source then
        ffi.copy(destination + destination_offset, source + source_offset, count * 4)
    elseif destination == source and destination_offset > source_offset then
        for i = count - 1, 0, -1 do destination[destination_offset + i] = tonumber(source[source_offset + i]) end
    else
        for i = 0, count - 1 do destination[destination_offset + i] = tonumber(source[source_offset + i]) end
    end
    return destination
end
function B.bytes(data, count, offset, checkpoint)
    offset = offset or 0
    extent(data, count, offset)
    if ffi and type(data) == 'cdata' then return ffi.string(data + offset, count * 4) end
    local chunks = {}
    for i = 0, count - 1 do
        if checkpoint and i % 128 == 0 then checkpoint() end
        local word = B.value_to_word(tonumber(data[offset + i]))
        chunks[i + 1] = string.char(word % 256, floor(word / 256) % 256,
            floor(word / 65536) % 256, floor(word / 16777216) % 256)
    end
    return table.concat(chunks)
end
function B.from_bytes(bytes, count, offset)
    offset = offset or 0
    integer(count, B.MAX_ELEMENTS, 'Invalid float count')
    integer(offset, 1024 * 1024, 'Invalid byte offset')
    assert(type(bytes) == 'string' and #bytes >= offset + count * 4, 'Truncated float buffer')
    local out = B.new(count)
    if ffi then ffi.copy(out, bytes:sub(offset + 1, offset + count * 4), count * 4)
    else
        for i = 0, count - 1 do
            local a, b, c, d = bytes:byte(offset + i * 4 + 1, offset + i * 4 + 4)
            out[i] = B.word_to_value(a + b * 256 + c * 65536 + d * 16777216)
        end
    end
    return out
end
return B
