-- LZNT1 wire format, implemented from Microsoft [MS-XCA] sections 2.5 and 3.3.
-- https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-xca/cba0fa15-bd62-4eda-8838-8fc7ab406df1
-- Work is demand-driven and bounded to 64 KiB; no native or bit dependency.
local MAX_RAW, MAX_COMPRESSED, MAX_CHAIN = 65536, 69632, 8
local L = { MAX_RAW = MAX_RAW, MAX_COMPRESSED = MAX_COMPRESSED, formats = { '' }, MAX_CHAIN = MAX_CHAIN }
local floor, byte, char, sub = math.floor, string.byte, string.char, string.sub
local function short(value) return char(value % 256, floor(value / 256)) end
local function format_tag(tag)
    assert(tag == nil or tag == '', 'XPRESS shared LUT compression requires a supported host provider')
end
function L.compress(bytes, tag, checkpoint)
    format_tag(tag)
    assert(type(bytes) == 'string' and #bytes > 0 and #bytes <= MAX_RAW, 'Invalid LZNT1 input bounds')
    checkpoint = checkpoint or function() end
    local chunks = {}
    for first = 1, #bytes, 4096 do
        checkpoint()
        local source = sub(bytes, first, first + 4095)
        local next_checkpoint = 256
        local length, heads, previous, parts, produced, at = #source, {}, {}, {}, 0, 1
        local factor, distance_limit = 4096, 16
        local function key(position)
            if position + 2 <= length then
                local a, b, c = byte(source, position, position + 2)
                return a * 65536 + b * 256 + c
            end
        end
        local function retain(position)
            local hash = key(position)
            if hash then previous[position], heads[hash] = heads[hash], position end
        end
        while at <= length do
            local flag_at, flags = #parts + 1, 0
            parts[flag_at] = ''
            for lane = 0, 7 do
                if at > length then break end
                while at - 1 > distance_limit do factor, distance_limit = factor / 2, distance_limit * 2 end
                local maximum = math.min(factor + 2, length - at + 1)
                local hash, best, best_distance = key(at), 0, 0
                local candidate = hash and heads[hash]
                for _ = 1, MAX_CHAIN do
                    if not candidate or at - candidate > distance_limit then break end
                    if best == 0 or byte(source, candidate + best) == byte(source, at + best) then
                        local matched = 3
                        while matched < maximum and byte(source, candidate + matched) == byte(source, at + matched) do
                            matched = matched + 1
                        end
                        if matched > best then best, best_distance = matched, at - candidate end
                        if best == maximum then break end
                    end
                    candidate = previous[candidate]
                end
                if best >= 3 then
                    parts[#parts + 1] = short((best_distance - 1) * factor + best - 3)
                    flags = flags + 2 ^ lane
                    for position = at, at + best - 1 do
                        retain(position)
                        if position >= next_checkpoint then checkpoint(); next_checkpoint = next_checkpoint + 256 end
                    end
                    at = at + best
                    produced = produced + 2
                else
                    parts[#parts + 1] = sub(source, at, at)
                    retain(at)
                    at, produced = at + 1, produced + 1
                end
            end
            parts[flag_at] = char(flags)
            produced = produced + 1
            if at >= next_checkpoint then checkpoint(); next_checkpoint = next_checkpoint + 256 end
            if produced >= length then break end
        end
        if produced < length and at > length then
            local packed = table.concat(parts)
            assert(#packed == produced and #packed <= 4096, 'Invalid LZNT1 chunk result')
            chunks[#chunks + 1] = short(45056 + #packed - 1) .. packed
        else
            chunks[#chunks + 1] = short(12288 + length - 1) .. source
        end
    end
    return table.concat(chunks)
end
function L.decompress(bytes, expected, tag)
    format_tag(tag)
    assert(type(bytes) == 'string' and #bytes >= 3 and #bytes <= MAX_COMPRESSED
        and type(expected) == 'number' and expected >= 1 and expected <= MAX_RAW and expected % 1 == 0,
        'Invalid LZNT1 decompression bounds')
    local at, total, chunks = 1, 0, {}
    while at <= #bytes do
        assert(at + 1 <= #bytes, 'Truncated LZNT1 chunk header')
        local a, b = byte(bytes, at, at + 1)
        local header = a + b * 256
        at = at + 2
        if header == 0 then
            assert(at == #bytes + 1, 'Trailing LZNT1 data')
            break
        end
        assert(floor(header / 4096) % 8 == 3, 'Invalid LZNT1 chunk signature')
        local length = header % 4096 + 1
        local finish = at + length - 1
        assert(finish <= #bytes, 'Truncated LZNT1 chunk')
        local output, count = {}, 0
        if header < 32768 then
            assert(total + length <= expected, 'LZNT1 output exceeds declared size')
            chunks[#chunks + 1] = sub(bytes, at, finish)
            count, at = length, finish + 1
        else
            local factor, distance_limit = 4096, 16
            while at <= finish do
                local flags = byte(bytes, at)
                at = at + 1
                assert(at <= finish, 'Empty LZNT1 flag group')
                for _ = 1, 8 do
                    if at > finish then break end
                    if flags % 2 == 0 then
                        assert(count < 4096 and total + count < expected, 'LZNT1 output exceeds declared size')
                        count = count + 1
                        output[count], at = sub(bytes, at, at), at + 1
                    else
                        assert(at + 1 <= finish, 'Truncated LZNT1 match')
                        while count > distance_limit do factor, distance_limit = factor / 2, distance_limit * 2 end
                        a, b = byte(bytes, at, at + 1)
                        local token = a + b * 256
                        local distance, matched = floor(token / factor) + 1, token % factor + 3
                        assert(distance <= count and count + matched <= 4096 and total + count + matched <= expected,
                            'Invalid LZNT1 match bounds')
                        for _ = 1, matched do count = count + 1; output[count] = output[count - distance] end
                        at = at + 2
                    end
                    flags = floor(flags / 2)
                end
            end
            chunks[#chunks + 1] = table.concat(output)
        end
        total = total + count
        if at <= #bytes and sub(bytes, at, at + 1) ~= '\0\0' then
            assert(count == 4096, 'Short nonfinal LZNT1 chunk')
        end
    end
    assert(total == expected, 'LZNT1 output size differs')
    return table.concat(chunks)
end
return L
