-- ui_store-compatible settings through the public modular LLL mod.config/set API.
-- No native paths are opened or migrated implicitly. Saves replace only one ID.
local KEY, VERSION = 'epic_lut_ui', 1
local MAX_STORES, MAX_VALUES, MAX_BYTES = 32, 4096, 524288
local S = { KEY = KEY, VERSION = VERSION }
local function stable(value)
    return type(value) == 'string' and #value >= 1 and #value <= 80 and value:match('^[%w_-]+$')
end
local function scalar(value)
    local kind = type(value)
    return kind == 'boolean'
        or (kind == 'number' and value == value and math.abs(value) <= 3.4028234663852886e38)
        or (kind == 'string' and (#value <= 48 and value:match('^[%w _-]*$')
            or value:match('^#%x%x%x%x%x%x$')))
end
local function values(source, budget)
    assert(type(source) == 'table' and getmetatable(source) == nil, 'Invalid loader settings values')
    local out = {}
    for key, value in pairs(source) do
        assert(stable(key) and scalar(value), 'Invalid loader settings value')
        budget.count = budget.count + 1
        budget.bytes = budget.bytes + #key + (type(value) == 'string' and #value or 32)
        assert(budget.count <= MAX_VALUES and budget.bytes <= MAX_BYTES, 'Loader settings budget exceeded')
        out[key] = value
    end
    return out
end
local function snapshot(host)
    assert(type(host.config) == 'table', 'Public loader config unavailable')
    local state = host.config[KEY]
    local result, budget = { version = VERSION, stores = {} }, { count = 0, bytes = 0 }
    if state == nil then return result, budget, 0 end
    assert(type(state) == 'table' and getmetatable(state) == nil and state.version == VERSION
        and type(state.stores) == 'table' and getmetatable(state.stores) == nil,
        'Unsupported or damaged Epic LUT loader settings schema')
    for field in pairs(state) do
        assert(field == 'version' or field == 'stores', 'Unknown Epic LUT loader settings schema field')
    end
    local count = 0
    for id, stored in pairs(state.stores) do
        count = count + 1
        assert(stable(id) and count <= MAX_STORES, 'Invalid loader settings store ID/count')
        budget.bytes = budget.bytes + #id
        result.stores[id] = values(stored, budget)
    end
    return result, budget, count
end
local function equal(a, b)
    if not a then return false end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end
local function parse_legacy(bytes)
    assert(type(bytes) == 'string' and #bytes <= 65536, 'Legacy settings bytes unavailable or too large')
    if bytes:sub(1, 3) == '\239\187\191' then bytes = bytes:sub(4) end
    local result = {}
    for line in (bytes .. '\n'):gmatch('([^\n]*)\n') do
        line = line:gsub('\r$', '')
        if line ~= '' then
            local key, text = line:match('^([%w_-]+)=([^\r\n]+)$')
            assert(stable(key) and result[key] == nil, 'Ambiguous or malformed legacy settings line')
            local value
            if text == 'true' then value = true
            elseif text == 'false' then value = false
            elseif text:match('^#%x%x%x%x%x%x$') then value = text:upper()
            elseif text:sub(1, 1) == '@' then value = text:sub(2)
            else value = tonumber(text) end
            assert(scalar(value), 'Unsupported legacy settings value; original bytes retained')
            result[key] = value
        end
    end
    return result
end
function S.new(host)
    assert(type(host) == 'table' and type(host.set) == 'function', 'Public modular loader settings API required')
    snapshot(host) -- Reject damaged/future data before any UI can overwrite it.
    local self = { source = 'loader-config', namespace = KEY, legacy_migration = 'explicit only' }
    function self.load(id)
        assert(stable(id), 'Invalid stable settings ID')
        return snapshot(host).stores[id] or {}
    end
    local function save(id, replacement, imported)
        assert(stable(id), 'Invalid stable settings ID')
        local next_state, budget, store_count = snapshot(host)
        if imported then assert(next_state.stores[id] == nil, 'Loader settings already exist; legacy import refused') end
        local incoming = { count = 0, bytes = 0 }
        replacement = values(replacement, incoming)
        if equal(next_state.stores[id], replacement) then return true end
        local previous = next_state.stores[id]
        if previous then
            for key, value in pairs(previous) do
                budget.count = budget.count - 1
                budget.bytes = budget.bytes - #key - (type(value) == 'string' and #value or 32)
            end
        else
            assert(store_count < MAX_STORES, 'Loader settings store count exceeded')
            budget.bytes = budget.bytes + #id
        end
        assert(budget.count + incoming.count <= MAX_VALUES and budget.bytes + incoming.bytes <= MAX_BYTES,
            'Loader settings budget exceeded')
        next_state.stores[id] = replacement
        local ok, why = host.set(KEY, next_state)
        if ok ~= true then return false, why or 'Loader settings save failed' end
        return true
    end
    function self.save(id, replacement)
        local called, ok, why = pcall(save, id, replacement)
        if not called then return false, tostring(ok) end
        return ok, why
    end
    function self.import_legacy(id, bytes_or_reader)
        -- Callers explicitly supply bytes or their own bounded read callback.
        -- This function never guesses a legacy folder, reads files or deletes data.
        local called, ok, why = pcall(function()
            assert(stable(id), 'Invalid stable settings ID')
            assert(snapshot(host).stores[id] == nil, 'Loader settings already exist; legacy import refused')
            local bytes, reason = bytes_or_reader
            if type(bytes_or_reader) == 'function' then bytes, reason = bytes_or_reader(id) end
            assert(type(bytes) == 'string', reason or 'Explicit legacy settings bytes required')
            return save(id, parse_legacy(bytes), true)
        end)
        if not called then return false, tostring(ok) end
        return ok, why
    end
    return self
end
return S
