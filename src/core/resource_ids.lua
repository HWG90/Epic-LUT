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
function R.describe(hash, decimal, catalog)
    local formatted = R.format(hash, decimal)
    local name = catalog and catalog.resource_name(hash)
    return name and (name .. ' ' .. formatted) or formatted
end
-- Local display names share the existing bounded, transactional settings store.
function R.labels(storage)
    local self, names = {}, {}
    local function valid_hash(hash)
        return type(hash) == 'string' and #hash == 16 and hash:match('^%x+$')
    end
    local function valid_name(name)
        return type(name) == 'string' and #name > 0 and #name <= 48 and name:match('^[%w _-]+$')
    end
    local count = 0
    for hash, name in pairs(storage.load('epic_lut_labels')) do
        if valid_hash(hash) and valid_name(name) and count < 512 then
            hash, name = hash:lower(), name:match('^%s*(.-)%s*$')
            if name ~= '' then
                if not names[hash] then
                    count = count + 1
                end
                names[hash] = name
            end
        end
    end
    function self.get(hash)
        return valid_hash(hash) and names[hash:lower()] or nil
    end
    function self.set(hash, name)
        assert(valid_hash(hash), 'Load a LUT with a known texture ID first')
        assert(type(name) == 'string', 'Enter a LUT name')
        hash, name = hash:lower(), name:match('^%s*(.-)%s*$')
        assert(name == '' or valid_name(name), 'Use up to 48 letters, numbers, spaces, _ or -')
        if names[hash] == (name ~= '' and name or nil) then
            return true
        end
        assert(names[hash] or name == '' or count < 512, 'Local LUT name limit reached')
        local next_names = {}
        for key, value in pairs(names) do
            next_names[key] = value
        end
        next_names[hash] = name ~= '' and name or nil
        local ok, why = storage.save('epic_lut_labels', next_names)
        assert(ok, why or 'Could not save LUT name')
        if not names[hash] and name ~= '' then
            count = count + 1
        elseif names[hash] and name == '' then
            count = count - 1
        end
        names = next_names
        return true
    end
    return self
end
return R
