local ffi = require('ffi')
local History = dofile('src/editor/session_history.lua')
local Basic = dofile('src/core/basic_state.lua')

local function fixture(empty)
    local f = { writes = {}, commits = 0, proof = 'cape-kit', material = { owned = {} }, pattern = { owned = {} } }
    local function document(width, label)
        local data = ffi.new('float[?]', width * 4)
        for i = 0, width * 4 - 1 do
            data[i] = (i - 7) * 0.375
        end
        ffi.cast('uint32_t *', data)[3] = 0x80000000
        local original = ffi.new('float[?]', width * 4)
        ffi.copy(original, data, width * 16)
        return {
            width = width,
            height = 1,
            data = data,
            original = original,
            source = label,
            resource = 'fedcba9876543210',
            resource_object = 91,
            saved_pixels = 'saved-' .. label,
            revision = 3,
        }
    end
    f.document, f.pattern_document = document(23, 'material.dds'), document(3, 'pattern.dds')
    local function binding(slot, original, object, d)
        return {
            unit = 1,
            mesh = 2,
            material = 3,
            slot = slot,
            original = original,
            current = object,
            document = d,
            texture = { object = object, data = d.data },
            cape = true,
            applied_cape_proof = f.proof,
            resource = 'cape-resource',
            save_key = 'cape-save-key',
        }
    end
    f.b, f.p = binding(1, 100, 200, f.document), binding(2, 101, 300, f.pattern_document)
    f.bound = { [1] = empty and 100 or 200, [2] = empty and 101 or 300 }
    if not empty then
        f.material.owned, f.pattern.owned = { f.b }, { f.p }
    end
    f.state = {
        loaded = f.document,
        basic = { armor = f.document },
        editor_tables = { first = f.document, second = f.pattern_document },
        defaults = { armor = f.b.texture },
        default_proofs = { armor = 'armor-proof' },
        palettes = { 'material.dds', 'pattern.dds' },
        selected = { kind = 'armor', key = 'first' },
        editor_target = { kind = 'cape', group = 1, proof = 'cape-kit' },
        imported = 'material.dds',
        scope = 2,
        palette_index = 2,
        appearance = {
            {
                kind = 'armor',
                pattern = false,
                proof = 'armor-proof',
                save_key = 'armor-key',
                resource = 'resource-armor',
                texture = f.b.texture,
            },
        },
        appearance_pending = { z = { texture = f.p.texture }, a = { texture = f.b.texture } },
        remember_application = true,
    }
    f.service = History.new({
        copier = Basic.copier,
        state = function()
            return f.state
        end,
        material_session = function()
            return f.material
        end,
        pattern_session = function()
            return f.pattern
        end,
        material_slot = 1,
        pattern_slot = 2,
        material_key = function(b)
            return b.unit .. ':' .. b.mesh .. ':' .. b.material
        end,
        appearance_resource = function(b)
            return b.resource
        end,
        stop_identification = function()
            f.stops = (f.stops or 0) + 1
            return not f.highlight_pending
        end,
        appearance_proof = function()
            return { cape = f.proof }
        end,
        present = function(b)
            return not b.missing
        end,
        binding = function(b, slot)
            assert(b.material == 3 and slot == b.slot)
            return f.bound[slot]
        end,
        bind = function(b, slot, object)
            f.writes[#f.writes + 1] = { binding = b, slot = slot, object = object }
            if f.before_write then
                f.before_write(b, slot, object)
            end
            f.bound[slot] = object
            if f.after_write then
                f.after_write(b, slot, object)
            end
        end,
        commit = function(snapshot)
            f.commits = f.commits + 1
            f.committed = snapshot
            f.state = snapshot
            return true
        end,
    })
    function f.change()
        f.b.current, f.p.current = 400, 500
        f.b.texture, f.p.texture = { object = 400 }, { object = 500 }
        f.document.data[0], f.pattern_document.data[0] = 2.5, -1.75
        f.bound[1], f.bound[2] = 400, 500
        return f.service.capture()
    end
    return f
end

local f = fixture()
local before = f.service.capture()
local material_bytes = ffi.string(f.document.data, 23 * 16)
local pattern_bytes = ffi.string(f.pattern_document.data, 3 * 16)
assert(before.bytes == 2 * (23 + 3) * 16, 'Snapshot document aliases consumed duplicate history bytes')
assert(
    before.loaded == before.basic.armor
        and before.loaded == before.editor_tables.first
        and before.loaded == before.owned[1].document
        and before.pattern_owned[1].document == before.editor_tables.second,
    'Snapshot lost shared document aliases across editor/material/Pattern pools'
)
assert(before.loaded ~= f.document and before.loaded.data ~= f.document.data)
assert(ffi.string(before.loaded.data, 23 * 16) == material_bytes)
assert(ffi.string(before.loaded.original, 23 * 16) == material_bytes)
assert(ffi.string(before.pattern_owned[1].document.data, 3 * 16) == pattern_bytes)
assert(before.loaded.resource == f.document.resource and before.loaded.resource_object == 91)
assert(before.loaded.saved_pixels == f.document.saved_pixels and before.loaded.revision == 3)
assert(before.owned[1].binding == f.b and before.owned[1].texture == f.b.texture)
assert(before.pattern_owned[1].binding == f.p and before.pattern_owned[1].texture == f.p.texture)
assert(before.defaults.armor == f.b.texture and before.default_proofs.armor == 'armor-proof')
assert(before.editor_target ~= f.state.editor_target and before.editor_target.kind == 'cape')
assert(before.appearance_pending.a ~= f.state.appearance_pending.a)
assert(before.appearance_pending.a.texture == f.state.appearance_pending.a.texture)
assert(before.signature == table.concat({
    'material.dds',
    material_bytes,
    'material.dds',
    '1:2:3:200',
    '1:2:3:pattern:300',
    'appearance:armor:false:armor-proof:armor-key:resource-armor:200',
    'pending:a:200',
    'pending:z:300',
}, '|'), 'History signature changed its material/Pattern receipts or sorted pending appearances')
local after = f.change()
assert(ffi.string(before.loaded.data, 23 * 16) == material_bytes, 'Later edits mutated a captured history frame')
assert(f.service.restore(before, after))
assert(f.bound[1] == 200 and f.bound[2] == 300 and #f.writes == 2 and f.commits == 1)
assert(f.b.current == 200 and f.p.current == 300 and f.b.previous == nil and f.p.previous == nil)
assert(f.b.texture == before.owned[1].texture and f.p.texture == before.pattern_owned[1].texture)
assert(f.committed ~= before and f.committed.loaded ~= before.loaded)
assert(f.committed.loaded == f.committed.basic.armor and f.committed.loaded == f.b.document)
assert(f.committed.pattern_owned[1].document == f.p.document)
f.committed.loaded.data[0] = 19
assert(ffi.string(before.loaded.data, 23 * 16) == material_bytes, 'Restored editor document mutated stored Undo frame')
assert(f.service.restore(after, before) and f.bound[1] == 400 and f.bound[2] == 500 and f.commits == 2)

-- Empty ownership frames undo to original objects and redo reacquires both pools.
f = fixture(true)
local empty = f.service.capture()
assert(#empty.owned == 0 and #empty.pattern_owned == 0)
f.material.owned, f.pattern.owned = { f.b }, { f.p }
f.bound[1], f.bound[2] = 200, 300
local applied = f.service.capture()
assert(f.service.restore(empty, applied))
assert(f.bound[1] == 100 and f.bound[2] == 101 and #f.material.owned == 0 and #f.pattern.owned == 0)
assert(f.b.current == 100 and f.b.texture == nil and f.p.current == 101 and f.p.texture == nil)
assert(f.service.restore(applied, empty))
assert(f.bound[1] == 200 and f.bound[2] == 300 and f.material.owned[1] == f.b and f.pattern.owned[1] == f.p)

local function reject(mutator, error_text)
    local scenario = fixture()
    local old, current = scenario.service.capture(), scenario.change()
    mutator(scenario)
    local ok, why = pcall(scenario.service.restore, old, current)
    assert(not ok and tostring(why):find(error_text, 1, true), tostring(why))
    assert(
        #scenario.writes == 0 and scenario.commits == 0,
        'Invalid history frame partially wrote gear or committed UI'
    )
end
reject(function(s)
    s.bound[1] = 999
end, 'Gear bindings changed')
reject(function(s)
    s.material.owned = {}
end, 'Gear ownership changed')
reject(function(s)
    s.pattern = nil
end, 'Pattern application unavailable')
reject(function(s)
    s.proof = 'different-cape-kit'
end, 'Cape kit changed')
reject(function(s)
    s.b.resource = 'different-cape-resource'
end, 'Cape resource changed')
reject(function(s)
    s.b.save_key = 'different-cape-save-key'
end, 'Cape resource changed')
reject(function(s)
    s.highlight_pending = true
end, 'Highlight restoration pending')

-- Failures after native mutation roll back both pools in reverse order.
f = fixture()
before, after = f.service.capture(), f.change()
f.after_write = function(_, slot, object)
    if slot == 2 and object == 300 then
        error('forward write failed after mutation')
    end
end
local ok, why = pcall(f.service.restore, before, after)
assert(not ok and tostring(why):find('forward write failed after mutation', 1, true))
assert(#f.writes == 4 and f.writes[3].slot == 2 and f.writes[4].slot == 1)
assert(f.bound[1] == 400 and f.bound[2] == 500 and f.b.current == 400 and f.p.current == 500 and f.commits == 0)

-- A failed rollback retains the exact owned forward-write receipt for cleanup.
f = fixture()
before, after = f.service.capture(), f.change()
f.after_write = function(_, slot, object)
    if slot == 2 and object == 300 then
        error('forward failure')
    end
end
f.before_write = function(_, slot, object)
    if slot == 1 and object == 400 then
        error('rollback rejected before mutation')
    end
end
assert(not pcall(f.service.restore, before, after))
assert(f.bound[1] == 200 and f.bound[2] == 500 and f.commits == 0)
assert(f.b.current == 200 and f.b.previous == 400 and f.b.texture == before.owned[1].texture)
assert(ffi.string(f.b.document.data, 23 * 16) == material_bytes and f.b.applied_cape_proof == 'cape-kit')
assert(#f.material.owned == 1 and f.material.owned[1] == f.b, 'Rollback receipt duplicated or lost owned binding')

-- Redo can reacquire a binding; an incomplete rollback must add its receipt.
f = fixture(true)
empty = f.service.capture()
f.material.owned, f.pattern.owned = { f.b }, { f.p }
f.bound[1], f.bound[2] = 200, 300
applied = f.service.capture()
assert(f.service.restore(empty, applied))
f.writes, f.commits = {}, 0
f.after_write = function(_, slot, object)
    if slot == 2 and object == 300 then
        error('redo forward failure')
    end
end
f.before_write = function(_, slot, object)
    if slot == 1 and object == 100 then
        error('redo rollback rejected')
    end
end
assert(not pcall(f.service.restore, applied, empty))
assert(f.bound[1] == 200 and f.bound[2] == 101 and f.commits == 0)
assert(f.b.current == 200 and f.b.previous == 100 and f.b.texture == applied.owned[1].texture)
assert(f.material.owned[1] == f.b and #f.pattern.owned == 0, 'Reacquired forward write lost its cleanup receipt')

-- A kit swap during the write phase rejects the remaining pool and rolls back.
f = fixture()
before, after = f.service.capture(), f.change()
f.after_write = function(_, slot, object)
    if slot == 1 and object == 200 then
        f.proof = 'swapped-mid-write'
    end
end
ok, why = pcall(f.service.restore, before, after)
assert(not ok and tostring(why):find('Cape kit changed during history restoration', 1, true))
assert(f.bound[1] == 400 and f.bound[2] == 500 and #f.writes == 2 and f.commits == 0)

-- Fresh activation data/sessions are read through getters, with no stale captures.
f = fixture()
f.state = nil
assert(f.service.capture() == nil)
local replacement = fixture()
f.state, f.material, f.pattern = replacement.state, replacement.material, replacement.pattern
f.material.owned[1].current = 600
assert(f.service.capture().owned[1].current == 600)

print(
    'PASS session history: exact aliased RGBA snapshots, stable signatures, material/Pattern undo-redo, Cape/ownership guards, rollback receipts and activation getters'
)
