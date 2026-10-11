-- Resolve saved destinations without changing native mesh or material indices.
-- An extra live mesh can inherit only a unanimous saved family certified by an
-- exact live anchor using the same original resource and LUT dimensions.
local T = { MAX_BINDINGS = 4096, MAX_PAYLOAD_BYTES = 8 * 1024 * 1024, MAX_DOCUMENT_BYTES = 65536 }
local kinds = { armor = true, helmet = true, cape = true }
local function dense(list, name)
    assert(type(list) == 'table' and #list <= T.MAX_BINDINGS, 'Invalid ' .. name .. ' list')
    local count = 0
    for index in pairs(list) do
        count = count + 1
        assert(count <= T.MAX_BINDINGS, name .. ' exceeds binding budget')
        assert(
            type(index) == 'number' and index >= 1 and index <= #list and index % 1 == 0,
            'Invalid ' .. name .. ' list'
        )
    end
    assert(count == #list, 'Invalid ' .. name .. ' list')
end
local function target(key)
    if type(key) ~= 'string' or #key > 128 then
        return
    end
    local pattern = key:sub(1, 2) == 'p:'
    local destination = pattern and key:sub(3) or key
    if not destination:match('^[%d:]+$') then
        return
    end
    return destination, pattern
end
local function family(kind, key, pattern)
    if not kinds[kind] or type(key) ~= 'string' or #key > 128 then
        return
    end
    local unit_type, slot, mesh, material = key:match('^(%d+):(%d+):(%d+):(%d+)$')
    if not unit_type then
        return
    end
    local fields = { unit_type, slot, mesh, material }
    for index, value in ipairs(fields) do
        local number = tonumber(value)
        if #value > 10 or not number or number > 4294967295 then
            return
        end
        fields[index] = tostring(number)
    end
    return kind .. ':' .. (pattern and 'p:' or '') .. fields[1] .. ':' .. fields[2] .. ':' .. fields[4]
end
local function shape(document, pattern)
    return type(document) == 'table'
        and type(document.height) == 'number'
        and (
            pattern and document.width == 3 and document.height == 1
            or not pattern
                and document.width == 23
                and document.height >= 1
                and document.height <= 64
                and document.height % 1 == 0
        )
end
local function resource(original)
    local value = type(original) == 'table' and original.resource
    return type(value) == 'string' and #value == 16 and value:match('^%x+$') and value:lower() or nil
end
function T.new(preset, deps)
    deps = deps or {}
    local encode = assert(deps.document_bytes, 'Saved document bytes callback required')
    assert(type(encode) == 'function', 'Invalid saved document bytes callback')
    local entries = preset and preset.entries or {}
    dense(entries, 'Preset targets')
    local exact, families, encoded, payloads, payload_bytes = {}, {}, {}, {}, 0
    for _, entry in ipairs(entries) do
        assert(type(entry) == 'table' and kinds[entry.kind], 'Invalid preset gear kind')
        local key, pattern = target(entry.key)
        assert(key and shape(entry.document, pattern), 'Invalid saved LUT target or dimensions')
        local identity = entry.kind .. ':' .. entry.key
        assert(not exact[identity], 'Duplicate saved LUT target')
        exact[identity] = entry
        local identity_family = family(entry.kind, key, pattern)
        if identity_family then
            local document = entry.document
            local bytes = encoded[document]
            if bytes == nil then
                local ok, value = pcall(encode, document)
                bytes = ok and type(value) == 'string' and #value > 0 and #value <= T.MAX_DOCUMENT_BYTES and value
                    or false
                encoded[document] = bytes
                if bytes and not payloads[bytes] then
                    payload_bytes = payload_bytes + #bytes
                    assert(payload_bytes <= T.MAX_PAYLOAD_BYTES, 'Saved target payload budget exceeded')
                    payloads[bytes] = true
                end
            end
            local current = families[identity_family]
            if not current then
                current = { document = document, bytes = bytes, compatible = bytes ~= false, anchors = {} }
                families[identity_family] = current
            elseif
                bytes == false
                or bytes ~= current.bytes
                or document.width ~= current.document.width
                or document.height ~= current.document.height
            then
                current.compatible = false
            end
        end
    end
    local self = {}
    local function exact_entry(kind, binding, pattern)
        if not kinds[kind] or type(binding) ~= 'table' then
            return
        end
        local key = binding.save_key
        local destination, prefixed = target(key)
        if not destination or prefixed then
            return
        end
        key = (pattern and 'p:' or '') .. key
        return exact[kind .. ':' .. key] or kind == 'cape' and binding.cape == true and exact['armor:' .. key]
    end
    function self.prepare(live)
        dense(live, 'Live targets')
        for _, current in pairs(families) do
            current.anchors = {}
        end
        for _, item in ipairs(live) do
            assert(type(item) == 'table', 'Invalid live target descriptor')
            local kind, binding, pattern, original = item.kind, item.binding, item.pattern == true, item.original
            local saved = exact_entry(kind, binding, pattern)
            -- Legacy Armor entries remain exact-only for a recognized Cape;
            -- they cannot widen the scope of a Cape topology adaptation.
            if
                saved
                and saved.kind == kind
                and shape(original, pattern)
                and saved.document.width == original.width
                and saved.document.height == original.height
            then
                local identity = family(kind, binding.save_key, pattern)
                local current, hash = identity and families[identity], resource(original)
                if
                    current
                    and current.compatible
                    and hash
                    and (not saved.original or resource(saved.original) == hash)
                then
                    current.anchors[hash .. ':' .. original.width .. ':' .. original.height] = true
                end
            end
        end
        return self
    end
    function self.resolve(kind, binding, pattern, original)
        pattern = pattern == true
        local saved = exact_entry(kind, binding, pattern)
        if saved then
            return saved.document, 'exact'
        end
        local identity = type(binding) == 'table' and family(kind, binding.save_key, pattern)
        if not identity then
            return nil, 'Unsupported saved target topology'
        end
        local current = families[identity]
        if not current or not current.compatible then
            return nil, 'No unanimous saved mesh family'
        end
        if
            not shape(original, pattern)
            or original.width ~= current.document.width
            or original.height ~= current.document.height
        then
            return nil, 'Original LUT dimensions do not match saved mesh family'
        end
        local hash = resource(original)
        if not hash or not current.anchors[hash .. ':' .. original.width .. ':' .. original.height] then
            return nil, 'No exact live anchor for this LUT resource'
        end
        return current.document, 'mesh-family'
    end
    return self
end
return T
