-- Service-level session lifetime contracts. Native ownership and full Pattern
-- pairing are additionally covered by cape_editor's integrated mapping cases.
local Mapping = dofile('src/editor/import_mapping.lua')
local function document(value)
    return { width = 23, height = 8, data = value }
end
local state = {
    palettes = { 'lut001.dds', 'lut000.dds' },
    documents = {},
    menu = {},
    proofs = { armor = 'armor-kit', helmet = 'helmet-kit', cape = 'cape-kit' },
    originals = {},
    groups = {},
    writes = 0,
    records = 0,
    next_texture = 100,
}
for index = 1, 3 do
    local b = {
        kind = index == 3 and 'helmet' or 'armor',
        unit = 1,
        mesh = index,
        material = index,
        slot = 1,
        original = index,
        current = index,
        save_key = 'target-' .. index,
    }
    state.groups[index] = { object = index, bindings = { b } }
    state.originals[index] = { resource = 'resource-' .. index, width = 23, height = 8 }
end
local function key(b)
    return b.unit .. ':' .. b.mesh .. ':' .. b.material
end
local function capture()
    local values = {}
    for _, group in ipairs(state.groups) do
        for _, b in ipairs(group.bindings) do
            values[b.material] = { current = b.current, document = b.document }
        end
    end
    return values
end
local function rollback(values)
    for _, group in ipairs(state.groups) do
        for _, b in ipairs(group.bindings) do
            b.current, b.document = values[b.material].current, values[b.material].document
        end
    end
    -- The real history restoration replaces these lists and source documents.
    state.palettes = { 'lut001.dds', 'lut000.dds' }
    state.documents = { ['lut000.dds'] = document('zero'), ['lut001.dds'] = document('one') }
    return true
end
local service = Mapping.new({
    slots = { material = 1, pattern = 2 },
    gear_catalog = {
        kind = function(b)
            return b.kind
        end,
        label = function(kind)
            return kind == 'armor' and 'Armor' or 'Helmet'
        end,
    },
    menu = function()
        return state.menu
    end,
    pixels = function(d)
        return d and d.data
    end,
    message = function(text)
        return text
    end,
    imports = {
        palettes = function()
            return state.palettes
        end,
        document = function(path)
            return state.documents[path]
        end,
        resource = function(_, d)
            return d and d.resource
        end,
        pending = function()
            return state.pending
        end,
        indexing = function()
            return state.indexing
        end,
        selected = function()
            return 1
        end,
        defer = function(kind, catalog)
            state.deferred, state.indexing = { kind = kind, catalog = catalog }, true
        end,
    },
    gear = {
        proof = function()
            return state.proofs
        end,
        refresh = function() end,
        choices = function(container)
            local result = {}
            for index, group in ipairs(state.groups) do
                local kind = group.bindings[1].kind
                if kind == container then
                    result[#result + 1] =
                        { kind = kind, key = kind .. ':' .. index, group = index, ordinal = #result + 1 }
                end
            end
            return result
        end,
        target = function(kind, index)
            local group, binding_keys = state.groups[index], {}
            for _, b in ipairs(group.bindings) do
                binding_keys[key(b) .. ':1'] = b.save_key
            end
            return { kind = kind, object = group.object, binding_keys = binding_keys }
        end,
        groups = function()
            return state.groups
        end,
        original = function(object)
            return state.originals[object]
        end,
        originals_ready = function()
            return true
        end,
        present = function()
            return true
        end,
        binding = function(b)
            return b.current
        end,
        material_key = key,
    },
    patterns = {
        stop_flash = function()
            return true
        end,
        scan = function() end,
        groups = function()
            return {}
        end,
        apply = function()
            error('Unrelated Pattern must stay untouched')
        end,
    },
    application = {
        stop_identification = function()
            return true
        end,
        preserve_emissives = function()
            return false
        end,
        set_default = function() end,
        remember_appearance = function() end,
        remember_document = function() end,
        with_proofs = function(proof, cape, action)
            assert(proof == state.proofs and cape == nil)
            state.active_proof = proof
            local ok, value = pcall(action)
            state.active_proof = nil
            return ok, value
        end,
        apply = function(d, targets)
            state.writes = state.writes + 1
            if state.fail and state.writes == state.fail then
                error('simulated partial failure', 0)
            end
            for _, b in ipairs(targets) do
                state.next_texture = state.next_texture + 1
                b.current, b.document = state.next_texture, d
            end
            return #targets
        end,
        finish = function() end,
    },
    history = {
        capture = capture,
        current = capture,
        restore = rollback,
        record = function()
            state.records = state.records + 1
        end,
    },
})

assert(service.open('gear'):find('Reading imported LUTs', 1, true))
assert(state.deferred.kind == 'gear' and state.deferred.catalog == state.palettes and not state.menu.lut_apply_dialog)
state.documents = { ['lut000.dds'] = document('zero'), ['lut001.dds'] = document('one') }
state.indexing = nil
service.open('gear', true)
local dialog = assert(state.menu.lut_apply_dialog)
local armor_items = dialog.columns[2].items
assert(#armor_items == 2 and #dialog.columns[3].items == 1 and not dialog.columns[4].enabled)
state.fail = 2
local ok, why = pcall(dialog.on_auto_map, { armor = true, helmet = false, cape = false })
assert(not ok and why:find('simulated partial failure', 1, true))
assert(state.records == 0 and not state.active_proof and state.groups[1].bindings[1].current == 1)
assert(not armor_items[1].mapped_source, 'Failed transaction published a mapping receipt')
state.fail = nil
assert(dialog.on_auto_map({ armor = true, helmet = false, cape = false }))
assert(state.records == 1 and not state.active_proof)
assert(state.groups[1].bindings[1].document == state.documents['lut000.dds'])
assert(state.groups[2].bindings[1].document == state.documents['lut001.dds'])
assert(state.groups[3].bindings[1].current == 3, 'Unselected gear was changed')
assert(armor_items[1].mapped_source == 'source:lut000.dds' and armor_items[2].mapped_source == 'source:lut001.dds')

local writes = state.writes
state.documents['lut000.dds'] = document('zero')
ok, why = pcall(dialog.on_map, 'source:lut000.dds', armor_items[1].id)
assert(not ok and why:find('Imported LUT data changed', 1, true) and state.writes == writes)
service.open('armor')
dialog = assert(state.menu.lut_apply_dialog)
state.menu = {}
ok, why = pcall(dialog.on_auto_map)
assert(not ok and why:find('Imported palette changed', 1, true) and state.writes == writes)
assert(service.open('helmet') and state.menu.lut_apply_dialog.columns[2].items[1].enabled)
print('PASS import_mapping: deferred indexing, dynamic sessions, atomic rollback, source rebasing and stale receipts')
