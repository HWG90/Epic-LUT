-- Cooperative read-only resource matching through injected lookup/identity checks.
-- Keep every exact alias for a bound object; never choose a resource by its order.
local M = { MAX_ITEMS = 16384, MAX_BYTES = 294912, MAX_WANTED = 4096, MAX_STEP = 16 }
local function object(value)
    return type(value) == 'number' and value % 1 == 0 and value >= 65536 and value < 2 ^ 47
end
function M.new(deps, text, wanted)
    local state, reason, ids, targets, matches = 'running', nil, {}, {}, {}
    local processed, input_count, duplicates = 0, 0, 0
    local function refuse(why)
        state, reason, matches = 'refused', tostring(why):sub(1, 512), {}
    end
    local parsed, parse_reason = pcall(function()
        assert(
            type(deps) == 'table' and type(deps.lookup) == 'function' and type(deps.validate) == 'function',
            'Resource matcher dependencies unavailable'
        )
        assert(type(text) == 'string' and #text >= 16 and #text <= M.MAX_BYTES, 'Catalog byte bounds')
        assert(type(wanted) == 'table', 'Wanted texture set unavailable')
        local count = 0
        for value, enabled in pairs(wanted) do
            assert(object(value) and enabled == true, 'Invalid wanted texture object')
            count = count + 1
            assert(count <= M.MAX_WANTED, 'Wanted texture count bounds')
            targets[value], matches[value] = true, {}
        end
        assert(count > 0, 'Wanted texture set is empty')
        -- Accept LF or CRLF and one final newline. Other whitespace is malformed.
        assert(not text:find('\0', 1, true), 'Catalog contains NUL')
        local normalized = text:gsub('\r\n', '\n')
        if normalized:sub(-1) == '\n' then
            normalized = normalized:sub(1, -2)
        end
        local seen = {}
        for line in (normalized .. '\n'):gmatch('(.-)\n') do
            input_count = input_count + 1
            assert(input_count <= M.MAX_ITEMS, 'Catalog item bounds')
            assert(#line == 16 and line:match('^%x+$'), 'Malformed catalog resource ID')
            line = line:lower()
            if not seen[line] then
                ids[#ids + 1], seen[line] = line, true
            else
                duplicates = duplicates + 1
            end
        end
        assert(#ids > 0, 'Catalog is empty')
    end)
    if not parsed then
        refuse(parse_reason)
    end
    local self = {}
    local function result()
        local aliases = {}
        for value, entries in pairs(matches) do
            local copy = {}
            for index, id in ipairs(entries) do
                copy[index] = id
            end
            aliases[value] = copy
        end
        return {
            state = state,
            complete = state == 'complete',
            refused = state == 'refused',
            reason = reason,
            processed = processed,
            total = #ids,
            input_count = input_count,
            duplicates = duplicates,
            matches = aliases,
        }
    end
    function self.result()
        return result()
    end
    function self.step(max_items)
        if state ~= 'running' then
            return result()
        end
        max_items = max_items or 8
        if type(max_items) ~= 'number' or max_items % 1 ~= 0 or max_items < 1 or max_items > M.MAX_STEP then
            refuse('Resource matcher chunk bounds')
            return result()
        end
        local ok, failure = pcall(function()
            local valid, why = deps.validate()
            assert(valid == true, why or 'Weapon identity changed before resource chunk')
            local staged = {}
            local final = math.min(#ids, processed + max_items)
            for index = processed + 1, final do
                local found = deps.lookup(ids[index])
                assert(found == nil or object(found), 'Invalid loaded texture object')
                if found and targets[found] then
                    local list = staged[found] or {}
                    list[#list + 1], staged[found] = ids[index], list
                end
            end
            valid, why = deps.validate()
            assert(valid == true, why or 'Weapon identity changed after resource chunk')
            for value, entries in pairs(staged) do
                local destination = matches[value]
                for _, id in ipairs(entries) do
                    destination[#destination + 1] = id
                end
            end
            processed = final
            if processed == #ids then
                state = 'complete'
            end
        end)
        if not ok then
            refuse(failure)
        end
        return result()
    end
    return self
end
return M
