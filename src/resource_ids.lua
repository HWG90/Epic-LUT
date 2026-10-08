-- Exact unsigned 64-bit decimal formatting without FFI/cdata string conversion.
local R = {}
local cache = {}
function R.format(hash, decimal)
    if type(hash) ~= 'string' or #hash ~= 16 or not hash:match('^%x+$') then
        return 'unavailable'
    end
    hash = hash:lower()
    if not decimal then
        return '[0x' .. hash .. ']'
    end
    if cache[hash] then
        return cache[hash]
    end
    local value = '0'
    for i = 1, 16 do
        local carry = tonumber(hash:sub(i, i), 16)
        local digits = {}
        for n = #value, 1, -1 do
            local v = tonumber(value:sub(n, n)) * 16 + carry
            digits[#digits + 1] = tostring(v % 10)
            carry = math.floor(v / 10)
        end
        while carry > 0 do
            digits[#digits + 1] = tostring(carry % 10)
            carry = math.floor(carry / 10)
        end
        local result = {}
        for n = #digits, 1, -1 do
            result[#result + 1] = digits[n]
        end
        value = table.concat(result)
    end
    cache[hash] = '[' .. value .. ']'
    return cache[hash]
end
return R
