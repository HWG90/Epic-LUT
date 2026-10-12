-- Pair a material LUT with the Pattern slot on the same exact destination.
-- Resource IDs, list order and gear kind alone never establish a pairing.
local P = { MAX_BINDINGS = 4096 }

function P.is_pattern(document)
    return type(document) == 'table' and document.width == 3 and document.height == 1
end

local function kind(value)
    assert(value == 'armor' or value == 'helmet' or value == 'cape' or value == 'weapon', 'Invalid export gear kind')
    return value
end
local function weapon_identity(value, destination, saved)
    if value.kind ~= 'weapon' then
        return ''
    end
    local resource, slot = value.weapon_resource, value.weapon_slot
    assert(
        type(resource) == 'string' and #resource == 16 and resource:match('^%x+$') and resource ~= string.rep('0', 16),
        'Invalid export weapon resource'
    )
    assert(type(slot) == 'number' and slot % 1 == 0 and slot >= 1 and slot <= 3, 'Invalid export weapon slot')
    local key = saved and destination or value.save_key
    if key then
        key = key:gsub('^p:', '')
        local unit_type, key_slot, mesh, material = key:match('^(%d+):(%d+):(%d+):(%d+)$')
        assert(
            tonumber(unit_type) == 3
                and tonumber(key_slot) == slot
                and tonumber(mesh) <= 63
                and tonumber(material) <= 63,
            'Export weapon slot differs from destination'
        )
    end
    return resource:lower() .. ':' .. slot .. ':'
end

local function document(value)
    assert(
        P.is_pattern(value)
            or (
                type(value) == 'table'
                and value.width == 23
                and type(value.height) == 'number'
                and value.height >= 1
                and value.height <= 64
                and value.height % 1 == 0
            ),
        'Unsupported export LUT dimensions'
    )
    return value
end

local function bounded(values)
    assert(type(values) == 'table' and #values <= P.MAX_BINDINGS, 'Export exceeds 4096 LUT bindings')
    return values
end

local function same_document(a, b)
    return a == b
        or (
            type(a) == 'table'
            and type(b) == 'table'
            and a.width == b.width
            and a.height == b.height
            and a.data ~= nil
            and a.data == b.data
        )
end

local function same_original(a, b)
    return a == b
        or (
            type(a) == 'table'
            and type(b) == 'table'
            and a.resource == b.resource
            and a.patch_source == b.patch_source
            and a.width == b.width
            and a.height == b.height
        )
end

local function live_identity(binding, deps)
    assert(type(binding) == 'table', 'Invalid live export binding')
    local key = deps.key(binding)
    assert(type(key) == 'string' and #key > 0 and not key:find('[%c]'), 'Invalid live export destination')
    local family = kind(deps.kind(binding))
    local descriptor = {
        kind = family,
        save_key = binding.save_key,
        weapon_resource = binding.weapon_resource,
        weapon_slot = binding.weapon_slot,
    }
    return family .. ':' .. weapon_identity(descriptor, key) .. key
end

local function live_alias(a, b)
    return a == b
        or (
            a.original ~= nil
            and a.current ~= nil
            and a.original == b.original
            and a.current == b.current
            and a.slot == b.slot
        )
end

-- Returns Pattern bindings only. The caller resolves their current/original
-- documents and verifies 3x1 snapshots; unedited bindings may have no document.
function P.live(material_bindings, pattern_groups, deps)
    assert(
        type(deps) == 'table' and type(deps.key) == 'function' and type(deps.kind) == 'function',
        'Export pairing dependencies unavailable'
    )
    local destinations, seen, result = {}, {}, {}
    for _, binding in ipairs(bounded(material_bindings)) do
        local identity = live_identity(binding, deps)
        local prior = destinations[identity]
        assert(not prior or live_alias(prior, binding), 'Conflicting material export destination: ' .. identity)
        destinations[identity] = prior or binding
    end
    assert(type(pattern_groups) == 'table', 'Invalid Pattern export groups')
    for _, group in ipairs(pattern_groups) do
        assert(type(group) == 'table' and type(group.bindings) == 'table', 'Invalid Pattern export group')
        for _, binding in ipairs(group.bindings) do
            local identity = live_identity(binding, deps)
            if destinations[identity] then
                local source = binding.texture
                        and binding.current == binding.texture.object
                        and binding.texture.data
                        and binding.texture
                    or binding.document
                assert(not source or P.is_pattern(source), 'Matched Pattern binding is not a 3x1 LUT')
                local prior = seen[identity]
                assert(not prior or live_alias(prior, binding), 'Conflicting Pattern export destination: ' .. identity)
                if not prior then
                    seen[identity] = binding
                    result[#result + 1] = binding
                    assert(#material_bindings + #result <= P.MAX_BINDINGS, 'Export exceeds 4096 LUT bindings')
                end
            end
        end
    end
    assert(#material_bindings + #result <= P.MAX_BINDINGS, 'Export exceeds 4096 LUT bindings')
    return result
end

local function saved_identity(entry)
    assert(type(entry) == 'table', 'Invalid saved export entry')
    kind(entry.kind)
    local pattern = P.is_pattern(document(entry.document))
    local key = entry.key
    assert(type(key) == 'string', 'Invalid saved export destination')
    local prefixed = key:sub(1, 2) == 'p:'
    local destination = prefixed and key:sub(3) or key
    -- Older manifests allow variable-length numeric slot keys; retain them.
    assert(destination:match('^%d[%d:]*$') and prefixed == pattern, 'Invalid saved export destination')
    return entry.kind .. ':' .. weapon_identity(entry, destination, true) .. key
end

-- Returns the selected entry and its stored Pattern entry on the same kind/key.
-- A selected Pattern remains standalone. Patch metadata is optional for DDS.
function P.saved(entries, index)
    bounded(entries)
    assert(type(index) == 'number' and index % 1 == 0 and entries[index], 'Choose a saved preset LUT')
    local seen = {}
    for _, entry in ipairs(entries) do
        local identity = saved_identity(entry)
        local prior = seen[identity]
        assert(
            not prior
                or (same_document(prior.document, entry.document) and same_original(prior.original, entry.original)),
            'Conflicting saved export destination: ' .. identity
        )
        seen[identity] = prior or entry
    end
    local selected = entries[index]
    local result = { selected }
    if not P.is_pattern(selected.document) then
        local paired =
            seen[selected.kind .. ':' .. weapon_identity(selected, selected.key, true) .. 'p:' .. selected.key]
        if paired then
            result[#result + 1] = paired
        end
    end
    return result
end

return P
