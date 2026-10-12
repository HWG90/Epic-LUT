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
        weapon_runtime = function()
            return f.weapon_runtime
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
local function weapon_fixture()
    local scenario = fixture()
    local d = Basic.copier().copy(scenario.document)
    d.kind, d.family, d.weapon_slot, d.weapon_resource, d.weapon_resource64 =
        'weapon', 'material', 1, '5fecab819f96a3e8', '5fecab819f96a3e8'
    d.mixed, d.source_resource = true, '1111111111111111'
    local variant = Basic.clone(d)
    variant.data[0] = 0.125
    d.binding_documents = { ['3:1:0:0'] = d, ['3:1:1:0'] = variant }
    scenario.state.loaded, scenario.state.editor_target =
        d, { kind = 'weapon', weapon_slot = 1, family = 'material', index = 1, weapon_resource = d.weapon_resource }
    scenario.weapon_document = d
    local raw = Basic.copier().copy(d)
    raw.kind, raw.family, raw.weapon_slot, raw.weapon_resource, raw.weapon_resource64, raw.binding_documents, raw.mixed =
        nil, nil, nil, nil, nil, nil, nil
    local current = {
        version = 1,
        entries = {
            {
                weapon_slot = 1,
                weapon_resource = d.weapon_resource,
                weapon_resource64 = d.weapon_resource64,
                family = 'material',
                index = 1,
                source_resource = '1111111111111111',
                document = raw,
                save_keys = { '3:1:0:0', '3:1:1:0' },
            },
        },
    }
    scenario.weapon_receipt = {
        unit = 400,
        lua_unit = 'genuine-weapon-unit',
        world = 'main-world',
        weapon_slot = 1,
        weapon_resource64 = d.weapon_resource,
        weapon_resource = d.weapon_resource,
        unit_resource64 = '2222222222222222',
        remote = false,
        peer_scope = 'local',
    }
    scenario.weapon_binding = {
        unit = 400,
        mesh = 500,
        material = 600,
        slot = 0x7e662968,
        original = 700,
        current = 800,
        save_key = '3:1:0:0',
    }
    scenario.weapon_calls = { captures = 0, restores = 0 }
    scenario.weapon_runtime = {
        capture_state = function()
            scenario.weapon_calls.captures = scenario.weapon_calls.captures + 1
            return current
        end,
        catalog = function(slot)
            assert(slot == 1)
            return {
                available = true,
                receipt = scenario.weapon_receipt,
                material = { { bindings = { scenario.weapon_binding } } },
                pattern = {},
            }
        end,
        restore_state = function(desired)
            scenario.weapon_calls.restores = scenario.weapon_calls.restores + 1
            if scenario.weapon_failure then
                error('atomic weapon restore failed')
            end
            current = desired
            for _, entry in ipairs(current.entries) do
                local document = entry.document
                document.kind, document.family, document.weapon_slot, document.weapon_resource, document.weapon_resource64 =
                    'weapon', entry.family, entry.weapon_slot, entry.weapon_resource, entry.weapon_resource64
            end
            scenario.weapon_binding.current = scenario.weapon_binding.current + 1
            return { { count = 2 } }
        end,
    }
    function scenario.weapon_change()
        current = {
            version = 1,
            entries = {
                {
                    weapon_slot = 1,
                    weapon_resource = d.weapon_resource,
                    weapon_resource64 = d.weapon_resource64,
                    family = 'material',
                    index = 1,
                    source_resource = '1111111111111111',
                    document = Basic.copier().copy(current.entries[1].document),
                    save_keys = { '3:1:0:0', '3:1:1:0' },
                },
            },
        }
        current.entries[1].document.data[0] = 0.875
        scenario.weapon_binding.current = scenario.weapon_binding.current + 1
        return scenario.change()
    end
    function scenario.mutate_weapon_pixels()
        current.entries[1].document.data[0] = 0.333
    end
    return scenario
end
f = weapon_fixture()
before = f.service.capture()
local normal_weapon_clone = Basic.clone(f.weapon_document)
assert(
    normal_weapon_clone.binding_documents['3:1:0:0'] == normal_weapon_clone
        and normal_weapon_clone.weapon_resource == f.weapon_document.weapon_resource
        and normal_weapon_clone.binding_documents['3:1:1:0'].data
            ~= f.weapon_document.binding_documents['3:1:1:0'].data,
    'Normal weapon clones lost metadata or mixed self/variant aliases'
)
assert(
    before.loaded.kind == 'weapon'
        and before.loaded.family == 'material'
        and before.loaded.weapon_slot == 1
        and before.loaded.weapon_resource == '5fecab819f96a3e8'
)
assert(
    before.loaded.binding_documents['3:1:0:0'] == before.loaded
        and before.loaded.binding_documents['3:1:1:0'].data ~= f.weapon_document.binding_documents['3:1:1:0'].data
)
assert(
    before.weapon_state.entries[1].document.data ~= f.weapon_runtime.capture_state().entries[1].document.data
        and before.weapon_signature
        and before.weapon_receipts
)
local frozen_weapon_bytes = ffi.string(before.weapon_state.entries[1].document.data, 23 * 16)
after = f.weapon_change()
assert(before.signature ~= after.signature and before.bytes > 2 * (23 + 3) * 16)
assert(f.service.restore(before, after) and f.weapon_calls.restores == 1 and f.bound[1] == 200)
assert(
    ffi.string(before.weapon_state.entries[1].document.data, 23 * 16) == frozen_weapon_bytes,
    'Weapon runtime mutated an immutable stored history frame'
)
assert(f.committed.loaded.kind == 'weapon' and f.committed.editor_target.weapon_slot == 1)
assert(
    f.service.restore(after, before) and f.weapon_calls.restores == 2 and f.bound[1] == 400,
    'Fresh weapon texture or normalized document metadata prevented Redo'
)
local function reject_weapon(mutator, needle)
    local scenario = weapon_fixture()
    local old, expected = scenario.service.capture(), scenario.weapon_change()
    mutator(scenario, old, expected)
    local ok, reason = pcall(scenario.service.restore, old, expected)
    assert(not ok and tostring(reason):find(needle, 1, true), tostring(reason))
    assert(
        #scenario.writes == 0 and scenario.weapon_calls.restores == 0 and scenario.commits == 0 and not scenario.stops,
        'Stale weapon history reached garment writes or highlight cleanup'
    )
end
reject_weapon(function(s)
    s.mutate_weapon_pixels()
end, 'Weapon bytes or assignments changed')
reject_weapon(function(s)
    s.weapon_receipt.unit = 401
end, 'Weapon receipt changed')
reject_weapon(function(s)
    s.weapon_binding.material = 601
end, 'Weapon receipt changed')
reject_weapon(function(_, old)
    old.weapon_state.entries[1].save_keys[1] = '3:1:7:0'
end, 'Saved weapon history frame changed')
f = weapon_fixture()
before, after = f.service.capture(), f.weapon_change()
f.weapon_failure = true
assert(not pcall(f.service.restore, before, after))
assert(
    #f.writes == 4 and f.bound[1] == 400 and f.bound[2] == 500 and f.b.current == 400 and f.commits == 0,
    'Weapon failure did not roll back successful garment writes'
)
f = weapon_fixture()
before, after = f.service.capture(), f.weapon_change()
f.weapon_failure = true
f.before_write = function(_, slot, object)
    if slot == 1 and object == 400 then
        error('rollback refused')
    end
end
assert(not pcall(f.service.restore, before, after))
assert(
    f.bound[1] == 200
        and f.b.current == 200
        and f.b.previous == 400
        and f.b.texture == before.owned[1].texture
        and f.material.owned[1] == f.b,
    'Mixed failed rollback discarded cleanup ownership'
)
print(
    'PASS weapon session history: immutable F32/editor metadata/mixed aliases, native receipts, normalized Undo/Redo, stale preflight and mixed transaction rollback ownership'
)
