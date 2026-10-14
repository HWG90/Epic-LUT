local ffi = require('ffi')
local Factory = dofile('tests/weapon_fixture.lua')
local P = dofile('src/presets/binding_provenance.lua')
local M = dofile('src/editor/weapon_mapping.lua')
local S = dofile('src/weapons/weapon_setup.lua')
local DDS = dofile('src/core/dds.lua')
local function fixture()
    local f = Factory()
    f.now, f.notes, f.cold, f.scope_changed = 0, {}, false, false
    for _, unit in pairs(f.units) do
        for index, mesh in ipairs(unit.meshes) do
            mesh.named_id = index + 100
            f.textures[mesh.materials[2]][P.PATTERN] = f.P
        end
    end
    for _, original in pairs(f.documents) do
        original.patch_source = '0123456789abcdef\n'
            .. ('\0'):rep(192)
            .. DDS.encode(original.data, original.width, original.height):sub(1, 148)
    end
    f.sources = {
        capture = function(b, context)
            if f.cold then
                error('pending exact sources', 0)
            end
            local resource = b.weapon_resource or b.weapon_resource64
            local refs = {
                version = 4,
                kind = 'weapon',
                key = context.key,
                weapon_resource = resource,
                weapon_slot = b.weapon_slot,
                texture_slot = b.slot,
                original_texture = context.original.resource,
                section = 101 + b.material_index,
                index_stamp = ('a'):rep(64),
                unit = {
                    resource = resource,
                    archive = '0123456789abcdef',
                    main_sha256 = (f.scope_changed and 'd' or 'b'):rep(64),
                },
                material = {
                    resource = string.format('%016x', 200 + b.material_index),
                    archive = '0123456789abcdef',
                    main_sha256 = ('c'):rep(64),
                },
                mesh_id = f.meshes[b.mesh].named_id,
                material_slot = b.material_index,
                material_texture = context.original.resource,
                unit_override = false,
            }
            return {}, P.validate(refs, 'weapon', context.key, context.original)
        end,
        with_export_batch = function(entries, fn)
            assert(not f.scope_changed, 'effective source changed before apply')
            return fn({
                provenance = function(entry)
                    return entry.binding_provenance
                end,
            })
        end,
    }
    local bridge = {
        runtime = function()
            return f.runtime
        end,
        discovery = function()
            return f.discovery
        end,
    }
    f.service = S.new(
        { binding_provenance = P, weapon_mapping = M, weapon_provenance = { PENDING = 'pending exact sources' } },
        {
            bridge = function()
                return bridge
            end,
            sources = function()
                return f.sources
            end,
            original = function(b)
                return f.documents[b.original]
            end,
            time = function()
                return f.now
            end,
            busy = function()
                return f.busy
            end,
            apply = function(plans)
                return f.runtime.apply_plan(plans)
            end,
            message = function(note)
                f.notes[#f.notes + 1] = note
            end,
        }
    )
    function f.step(count)
        for _ = 1, count or 1 do
            f.now = f.now + 0.11
            f.service.tick()
        end
    end
    function f.finish()
        for _ = 1, 300 do
            if not f.service.pending() then
                return
            end
            f.step()
        end
        error('Startup job did not finish')
    end
    return f
end
local function applied(f)
    f.runtime.refresh(1)
    local body = f.runtime.load(1, 1)
    body.data[0], body.data[3] = 0.375, -1.5
    f.runtime.apply(body, 1, 1)
    local pattern, group = f.runtime.load(1, 1, 'pattern')
    local body_targets, rail_targets = {}, {}
    for _, b in ipairs(group.bindings) do
        local list = b.material_index == 0 and body_targets or rail_targets
        list[#list + 1] = b
    end
    pattern.data[11] = 0.25
    f.runtime.apply_plan({
        { weapon_slot = 1, family = 'pattern', index = 1, document = pattern, targets = body_targets },
    })
    pattern = M.copy(pattern)
    pattern.data[11] = 0.875
    f.runtime.apply_plan({
        { weapon_slot = 1, family = 'pattern', index = 1, document = pattern, targets = rail_targets },
    })
    local entries = f.service.capture()
    assert(#entries == 15, 'Capture lost material or independent Pattern destinations')
    assert(f.runtime.restore())
    return entries
end
local f = fixture()
local entries = applied(f)
local saved_bytes = M.bytes(entries[1].document)
f.service.start({ entries = entries })
assert(not pcall(f.service.capture), 'An unfinished startup job permitted an empty setup overwrite')
entries[1].document.data[0] = 9 -- queued pixels must already be immutable.
f.cold = true
local writes = #f.writes
f.step(5)
assert(f.service.pending() and #f.writes == writes, 'Cold exact-source cache entered the native write path')
f.cold = false
-- Native mesh enumeration changed; named identity remains stable.
local meshes = f.units[100].meshes
meshes[1], meshes[2] = meshes[2], meshes[1]
-- The queued discovery already crossed frames. This mutation should refuse,
-- preserving original bindings instead of guessing an old material ordinal.
f.finish()
assert(#f.writes == writes, 'Stale native mesh enumeration was overwritten')
entries[1].document.data[0] = 0.375
-- A new activation has a fresh immutable discovery/session registry.
f = fixture()
meshes = f.units[100].meshes
meshes[1], meshes[2] = meshes[2], meshes[1]
writes = #f.writes
f.service.start({ entries = entries })
f.finish()
assert(
    #f.writes == writes + 15 and f.notes[#f.notes]:find('15 bindings', 1, true),
    'Resume failed: ' .. table.concat(f.notes, ' / ') .. '; writes=' .. #f.writes .. ' expected=' .. (writes + 15)
)
local allocations = f.allocations
assert(allocations == 3, 'Identical LOD palettes were allocated per binding instead of per variant')
for _, mesh in ipairs(meshes) do
    local material = mesh.materials[1]
    local owned
    for _, b in ipairs(f.runtime.all_owned()) do
        if b.material == material and b.slot == P.LUT then
            owned = b
        end
    end
    assert(owned and M.bytes(owned.texture) == saved_bytes, 'Startup modified preserved DDS channel bits')
    assert(f.textures[mesh.materials[2]][P.LUT] == f.B, 'Startup changed an unsaved rail material')
    for index, mat in ipairs(mesh.materials) do
        local value
        for _, b in ipairs(f.runtime.all_owned()) do
            if b.material == mat and b.slot == P.PATTERN then
                value = b.texture.data[11]
            end
        end
        assert(value == (index == 1 and 0.25 or 0.875), 'Shared Pattern source collapsed different assignments')
    end
end
assert(f.runtime.restore())
local function refusal(change, expected)
    local candidate = fixture()
    local saved = applied(candidate)
    local before = #candidate.writes
    candidate.service.start({ entries = saved })
    change(candidate)
    candidate.finish()
    assert(#candidate.writes == before, expected)
    assert(not pcall(candidate.service.capture), 'Unresolved startup snapshot could be overwritten by a gear-only save')
    candidate.service.cancel(true)
    assert(#candidate.service.capture() == 0, 'Explicit weapon cancellation did not clear retained startup state')
    return candidate
end
refusal(function(candidate)
    candidate.scope_changed = true
end, 'Changed effective Unit graph reached startup writes')
refusal(function(candidate)
    candidate.snapshots[1].weapon_resource64 = 'ffffffffffffffff'
    candidate.units[100].resource = 'ffffffffffffffff'
end, 'Different primary received a saved palette')
refusal(function(candidate)
    candidate.busy = true
end, 'Manual editor activity did not cancel startup')
refusal(function(candidate)
    candidate.service.cancel()
end, 'Restore cancellation retained a write job')
local waiting = fixture()
local absent = applied(waiting)
waiting.snapshots[1] = nil
waiting.service.start({ entries = absent })
waiting.step(4)
assert(waiting.service.pending())
writes = #waiting.writes
waiting.now = 121
waiting.step()
assert(
    not waiting.service.pending() and #waiting.writes == writes,
    'Unavailable weapon did not time out without writes'
)
local foreign = fixture()
local clean = applied(foreign)
foreign.service.start({ entries = clean })
foreign.step(3)
writes = #foreign.writes
local material = foreign.units[100].meshes[1].materials[1]
foreign.textures[material][P.LUT] = 0xdead00
foreign.finish()
assert(#foreign.writes == writes, 'Foreign writer was overwritten during cooperative startup')
local dead = fixture()
dead.runtime.refresh(1)
dead.runtime.apply(dead.runtime.load(1, 1), 1, 1)
dead.units[100].alive = false
assert(not pcall(dead.service.capture), 'Temporarily unavailable owned weapon permitted snapshot deletion')
local cold = fixture()
cold.runtime.refresh(1)
cold.runtime.apply(cold.runtime.load(1, 1), 1, 1)
cold.cold = true
assert(not pcall(cold.service.capture), 'Incomplete startup assignment proof was silently discarded')
local bad = fixture()
local invalid = applied(bad)
invalid[1].binding_provenance = nil
assert(not pcall(bad.service.start, { entries = invalid }), 'Legacy ordinal-only snapshot entered automatic startup')
print(
    'PASS weapon startup: owned immutable snapshots, exact named roles, independent shared Patterns, cooperative cache, source/configuration/stale/foreign/manual/death guards'
)
