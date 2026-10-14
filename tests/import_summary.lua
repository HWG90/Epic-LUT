local ffi = require('ffi')
local summary = dofile('src/editor/import_summary.lua')
local function document(label)
    local data = ffi.new('float[92]')
    data[0], data[1], data[2] = -0.0, 2.5, -3.5
    local original = ffi.new('float[92]')
    ffi.copy(original, data, 368)
    return { data = data, original = original, width = 23, height = 1, source = label }
end
local first, second = document('first'), document('second')
local frame, choices, missing, messages, synced = {}, {}, {}, {}, {}
local values = { resource_format = 1, basic_armor_lut = 1, basic_helmet_lut = 1, palette = 1 }
local controls = { basic_armor_lut = {}, basic_helmet_lut = {}, armory_search = {} }
values.save_name, values.armory_export_name, values.armory_export_format, values.armory_search =
    'DDS', 'Preset', 3, 'Filter'
for _, container in ipairs({ 'armor', 'helmet' }) do
    local prefix = 'basic_' .. container .. '_camo'
    controls[prefix] = { id = prefix }
end
local originals = {
    loaded = false,
    status = 'pending',
    get = function()
        return nil
    end,
}
local modules = {
    basic_enabled = true,
    gear_catalog = {
        kind = function(b)
            return b.kind
        end,
        label = function(kind)
            return kind
        end,
        targets = function()
            return {}
        end,
    },
    resource_ids = {
        describe = function(resource)
            return resource or 'unknown'
        end,
    },
    basic_camo = {
        selection = function()
            return 1
        end,
        available = function(doc)
            return doc ~= nil
        end,
    },
}
local service = summary.new(modules, {
    frame = function()
        return frame
    end,
    ui = function()
        return controls, function(id)
            return values[id]
        end
    end,
    missing_reports = function()
        return missing
    end,
    choices = function(kind)
        return choices[kind] or {}
    end,
    target = function(kind, index)
        return { kind = kind, group = index }
    end,
    resource_id = function(object)
        return tostring(object)
    end,
    matching_plan = function()
        return { matched = 0 }
    end,
    appearance_proof = function()
        return { armor = 'a', cape = 'c' }
    end,
    cape_available = function()
        return false
    end,
    picker_info = function()
        return { busy = false, phase = 'idle' }
    end,
    time = function()
        return 42
    end,
    log = function(text)
        messages[#messages + 1] = text
    end,
    sync_camo = function(control, value, disabled)
        synced[#synced + 1] = { control.id, value, disabled }
    end,
})
local function replace(doc, kind, object)
    local b = { kind = kind, original = object, document = doc }
    frame = {
        groups = { { object = object, bindings = { b } } },
        palettes = { 'source.dds' },
        editor_tables = {},
        source_tables = { ['source.dds'] = doc },
        basic_documents = {},
        basic_state = {
            get = function(_, source)
                return source
            end,
            camo_rows = function()
                return { true }, 1
            end,
        },
        original_luts = originals,
        loaded = doc,
        status = 'ready',
        load_seen = true,
    }
    choices =
        { armor = { { kind = kind, binding = b, group = 1, key = kind .. ':1', label = 'selected', ordinal = 1 } } }
end
replace(first, 'armor', 10)
local before = ffi.string(first.data, 368)
local a = service.info()
assert(a.editor == first and a.raw.basic.armor.document == first and a.tables[1].data == first.data)
assert(a.raw.armor[1].kind == 'armor' and a.raw.armor[1].resource == '10')
assert(a.load_seen and a.palette_ready and not a.dirty and a.time == 42)
assert(
    a.export_name == 'DDS'
        and a.armory_export_name == 'Preset'
        and a.armory_export_format == 3
        and a.armory_query == 'Filter'
)
assert(controls.basic_armor_lut.choices[1] == 'selected' and not controls.basic_armor_lut.disabled)
assert(controls.basic_helmet_lut.choices[1] == 'Waiting for gear...' and controls.basic_helmet_lut.disabled)
assert(synced[1][3] == false and synced[2][3] == true)
assert(ffi.string(first.data, 368) == before, 'View assembly mutated LUT bytes')

-- Refresh/rollback replaces every source record while the service stays alive.
replace(second, 'cape', 20)
second.data[1] = 7
frame.pending, frame.index_job = {}, {}
local b = service.info()
assert(b.editor == second and b.raw.basic.armor.document == second and b.tables[1].data == second.data)
assert(b.raw.armor[1].kind == 'cape' and b.raw.armor[1].resource == '20')
assert(b.raw.armor[1].target.kind == 'cape' and b.dirty and b.busy)
assert(b.phase == 'Comparing imported tables...' and synced[3][3] == true)
assert(a.raw.basic.armor.document == first and a.tables[1].data == first.data, 'Previous frame aliases were rewritten')
assert(ffi.string(first.data, 368) == before)

-- Missing-snapshot diagnostics follow the controller's resettable report set.
frame.loaded, frame.source_tables, frame.basic_documents = nil, {}, {}
frame.groups[1].bindings[1].document = nil
originals.loaded = true
service.info()
service.info()
assert(#messages == 1)
missing = {}
service.info()
assert(#messages == 2)
print(
    'PASS import summary: fresh source/gear frames, exact read-only LUT bytes, dirty/pending state, Camo suppression inputs and resettable diagnostics'
)
