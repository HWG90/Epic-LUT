-- Plain XPRESS/LZ77 decoder (MS-XCA2.4.4), not the Huffman variant.
-- https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-xca/34cb9ab9-5ce6-42d7-a518-107c1c7c65e7
-- All work is bounded by the advertised raw size; no native imports or idle work.
local MAX_RAW = 65536
local MAX_PACKED = MAX_RAW + math.ceil(MAX_RAW / 32) * 4 + 4
local X = { MAX_RAW = MAX_RAW, MAX_PACKED = MAX_PACKED }

function X.decompress(bytes, size)
    assert(type(size) == 'number' and size % 1 == 0 and size >= 0 and size <= MAX_RAW,
        'Invalid XPRESS output size')
    assert(type(bytes) == 'string' and #bytes >= 4 and #bytes <= MAX_PACKED,
        'Invalid XPRESS input size')
    local at, count, flags, remaining, nibble = 1, 0, 0, 0, nil
    local out, limit = {}, #bytes
    local function uint(width)
        assert(at + width - 1 <= limit, 'Truncated XPRESS input')
        local value, place = 0, 1
        for index = at, at + width - 1 do
            value, place = value + bytes:byte(index) * place, place * 256
        end
        at = at + width
        return value
    end
    while true do
        if remaining == 0 then
            flags, remaining = uint(4), 32
        end
        local match = flags >= 2147483648
        flags, remaining = (flags % 2147483648) * 2, remaining - 1
        if match then
            if at == limit + 1 then
                assert(count == size, 'XPRESS output size differs from advertised size')
                return table.concat(out)
            end
            local token = uint(2)
            local length, offset = token % 8, math.floor(token / 8) + 1
            if length == 7 then
                if nibble == nil then
                    local value = uint(1)
                    length, nibble = value % 16, math.floor(value / 16)
                else
                    length, nibble = nibble, nil
                end
                if length == 15 then
                    length = uint(1)
                    if length == 255 then
                        length = uint(2)
                        if length == 0 then length = uint(4) end
                        assert(length >= 22, 'Invalid XPRESS extended length')
                        length = length - 22
                    end
                    length = length + 15
                end
                length = length + 7
            end
            length = length + 3
            assert(offset <= count, 'Invalid XPRESS back-reference offset')
            assert(length <= size - count, 'XPRESS match exceeds output size')
            -- Sequential copies intentionally support length greater than offset.
            for _ = 1, length do
                count = count + 1
                out[count] = out[count - offset]
            end
        else
            assert(at <= limit, 'Truncated XPRESS literal')
            assert(count < size, 'XPRESS literal exceeds output size')
            count, out[count + 1] = count + 1, bytes:sub(at, at)
            at = at + 1
        end
    end
end

return X
