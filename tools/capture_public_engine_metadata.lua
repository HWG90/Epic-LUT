-- One-shot public API metadata only. Never invokes an engine function/metamethod.
-- Returned text is ASCII and independently byte-bounded for loader-config storage.
local M = {}
local namespaces = { 'Renderer', 'RenderBuffer', 'Material', 'Mesh', 'Float32Array', 'Unit' }
local next_raw, get_raw, metatable_raw, equal_raw = next, rawget, getmetatable, rawequal
local MAX_DEPTH, MAX_NODES, MAX_ENTRIES, MAX_NODE_ENTRIES = 2, 128, 4096, 512
-- LLL config decoding is limited to 64 KiB. ASCII JSON escaping can double this
-- text, leaving 16 KiB for capture fields and unrelated loader configuration.
local MAX_BYTES, MAX_NAME, MAX_STRING = 24576, 120, 1024
local docs = { doc=true, __doc=true, documentation=true, description=true, signature=true,
    __signature=true, usage=true, help=true, arguments=true, parameters=true, returns=true,
    overloads=true, name=true, _name=true, __name=true, type=true, __type=true, format=true }
local containers = { __index=true, metadata=true, members=true, methods=true, properties=true,
    constants=true, enums=true, formats=true }
local private = { _g=true, globals=true, registry=true, state=true, data=true, player=true,
    players=true, units=true, world=true, config=true, settings=true, cache=true, private=true }
local function quote(value)
    return '"' .. value:gsub('.', function(byte)
        local code = string.byte(byte)
        if code >= 32 and code <= 126 and code ~= 34 and code ~= 92 then return byte end
        return string.format('\\x%02x', code)
    end) .. '"'
end
local function key_name(key)
    if type(key) == 'string' and #key > 0 and #key <= MAX_NAME and key:match('^[%w_]+$') then return key end
    if type(key) == 'number' and key >= 0 and key <= 64 and key % 1 == 0 then return '[' .. key .. ']' end
end
function M.collect(sr, runtime)
    assert(type(sr) == 'table' and type(runtime) == 'string' and #runtime <= 80, 'Public namespace and Lua version required')
    local lines, seen = {}, {}
    local entries, nodes, bytes, truncated, stopped = 0, 0, 0, false, false
    local function emit(line)
        local size = #line + (#lines > 0 and 1 or 0)
        if size > MAX_BYTES - bytes then truncated, stopped = true, true;return false end
        lines[#lines + 1], bytes = line, bytes + size
        return true
    end
    local function scalar(value, allowed)
        if not allowed then return '' end
        local kind = type(value)
        if kind == 'boolean' then return value and '=true' or '=false' end
        if kind == 'number' and value == value and math.abs(value) ~= math.huge then
            return '=' .. string.format('%.17g', value)
        end
        if kind == 'string' then
            if #value > MAX_STRING then return ' [string limit]' end
            return '=' .. quote(value)
        end
        return ''
    end
    local walk
    walk = function(value, path, depth, documentation)
        if stopped then return end
        if equal_raw(value, sr) or equal_raw(value, _G) then emit(path .. ':table [global scope omitted]');return end
        if seen[value] then emit(path .. ':table ->#' .. seen[value]);return end
        if depth > MAX_DEPTH then emit(path .. ':table [depth limit]');truncated = true;return end
        if nodes >= MAX_NODES then emit(path .. ':table [node limit]');truncated = true;return end
        nodes = nodes + 1;seen[value] = nodes
        if not emit(path .. ':table #' .. nodes) then return end
        local keys, key, scanned = {}, nil, 0
        while not stopped do
            key = next_raw(value, key)
            if key == nil then break end
            if entries >= MAX_ENTRIES then truncated, stopped = true, true;break end
            entries, scanned = entries + 1, scanned + 1
            local label = key_name(key)
            if label then keys[#keys + 1] = { key=key, label=label } end
            if scanned >= MAX_NODE_ENTRIES then
                -- Do not perform an extra engine-table read just to distinguish
                -- an exact boundary from truncation. The bounded result is clear.
                truncated = true;emit(path .. ' [entry limit]')
                break
            end
        end
        table.sort(keys, function(a, b) return a.label < b.label end)
        for index = 1, #keys do
            if stopped then break end
            local item = keys[index]
            local member = get_raw(value, item.key)
            local kind, child_path = type(member), path .. '.' .. item.label
            local named = type(item.key) == 'string'
            local doc = documentation or named and docs[item.key] == true
            local constant = named and item.key:match('^[A-Z][A-Z0-9_]*$') ~= nil
            if named and private[item.key:lower()] then
                emit(child_path .. ':' .. kind .. ' [private scope omitted]')
            elseif kind == 'table' then
                if doc or constant or named and containers[item.key] then
                    walk(member, child_path, depth + 1, doc)
                else emit(child_path .. ':table [non-metadata scope omitted]') end
            else
                emit(child_path .. ':' .. kind .. scalar(member, doc or constant))
            end
        end
        if not stopped then
            local meta = metatable_raw(value)
            if type(meta) == 'table' then walk(meta, path .. '.@metatable', depth + 1, false)
            else emit(path .. '.@metatable:' .. type(meta)) end
        end
    end
    for index = 1, #namespaces do
        if stopped then break end
        local name = namespaces[index]
        local namespace = get_raw(sr, name)
        if type(namespace) == 'table' then walk(namespace, name, 0, false)
        else emit(name .. ':' .. type(namespace)) end
    end
    return { schema=1, runtime=runtime, lookup='raw next/rawget; built-in getmetatable; no calls',
        text=table.concat(lines, '\n'), entries=entries, nodes=nodes, bytes=bytes, truncated=truncated,
        max_depth=MAX_DEPTH, max_entries=MAX_ENTRIES, max_nodes=MAX_NODES, max_bytes=MAX_BYTES }
end
return M
