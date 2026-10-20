local ffi = require('ffi')
local Bridge = dofile('src/editor/weapon_bridge.lua')
local Controller = dofile('src/editor/weapon_controller.lua')
local resource = '5fecab819f96a3e8'
local data = ffi.new('float[?]', 23 * 8 * 4)
data[0], data[1], data[2], data[3] = 2.5, -0.25, 0.5, 1
local document = { data = data, width = 23, height = 8, resource = 'babd338977faa2ff' }
local binding = {
    unit = 100,
    mesh = 200,
    material = 300,
    mesh_index = 4,
    material_index = 0,
    kind = 'weapon',
    weapon_slot = 1,
    weapon_resource = resource,
    original = 65536,
    current = 65536,
    slot = 0x7e662968,
    save_key = '3:1:4:0',
}
local group = { weapon_resource = resource, object = 65536, bindings = { binding }, document = document }
local valid, applied, loaded, opened, invalidated, closed = true, 0, nil, nil, nil, false
local catalog = { available = true, weapon_resource = resource, material = { group }, pattern = {} }
local fake = {
    catalog = function(slot)
        return slot == 1 and catalog or nil
    end,
    groups = function(slot, kind)
        return slot == 1 and kind == 'material' and { group } or {}
    end,
    refresh = function(slot)
        return slot == 1 and catalog or nil
    end,
    load = function(slot, index, kind)
        assert(slot == 1 and index == 1 and kind == 'material')
        return document, group
    end,
    apply = function(doc, slot, index, kind)
        assert(doc.data[0] == 2.5 and slot == 1 and index == 1 and kind == 'material')
        applied = applied + 1
        return 1, { object = 70000 }
    end,
    restore = function()
        closed = true
        return true
    end,
    update = function()
        return valid and {} or { 1 }
    end,
}
local m = {
    primary_identity = {
        new = function()
            return {}
        end,
    },
    weapon_discovery = {
        new = function()
            return {
                present = function()
                    return valid
                end,
                binding = function(b)
                    return b.current
                end,
            }
        end,
    },
    weapon_runtime = {
        new = function()
            return fake
        end,
    },
    binding_session = {},
    weapon_controller = Controller,
}
do
    local wakes = 0
    local actor = Bridge.new(m, { actor_changed = function() wakes = wakes + 1 end })
    actor.equipment_changed(7)
    assert(wakes == 0, 'Weapon-only event woke armor recovery')
    actor.equipment_changed(15)
    assert(wakes == 1, 'Actor replacement did not wake armor recovery')
end
local bridge = Bridge.new(m, {
    memory = function()
        return {
            module = function()
                return 1
            end,
            address = tonumber,
            read = function() end,
            verify_build = function()
                return true
            end,
        }
    end,
    native = function()
        return {}
    end,
    engine = function()
        return {}
    end,
    retain = function()
        return {}
    end,
    cohort = function()
        return {}
    end,
    original = function()
        return document
    end,
    bind = function()
        error('Unexpected native write')
    end,
    create_texture = function()
        error('Unexpected allocation')
    end,
    load_editor = function(doc, target)
        loaded = { doc, target }
    end,
    open_editor = function(cell)
        opened = cell or {}
        return true
    end,
    invalidate = function(slots)
        invalidated = slots
    end,
    message = function() end,
})
assert(bridge.load_current())
local controller = bridge.controller()
local state = controller.state()
assert(state.quick_ready and state.target.group_index == 1 and state.target.object == 65536)
assert(controller.open_editor(8, 1) and loaded[1] == document and opened.row == 8)
assert(controller.edit_rgb(1) and opened.picker and opened.column == 1)
assert(controller.apply() == 1 and applied == 1)
local load = fake.load
local loads = 0
group.document, group.mixed = nil, true
fake.load = function(...)
    loads = loads + 1
    local value = load(...)
    value.mixed = true
    value.binding_documents = { [binding.save_key] = document }
    return value, group
end
local mixed = bridge.snapshot().weapons[1].main[1]
assert(loads == 1 and mixed.document.mixed and mixed.document.binding_documents[binding.save_key])
fake.load = function()
    loads = loads + 1
    error('Weapon disappeared before the next update', 0)
end
local stale = bridge.snapshot().weapons[1].main[1]
assert(
    loads == 2 and stale.document == nil and stale.reason == 'Weapon disappeared before the next update',
    'A mixed/stale group retried an unprotected runtime load during rendering'
)
fake.load, group.document, group.mixed = load, document, nil
document.mixed, document.binding_documents = nil, nil
valid = false
local ok = pcall(bridge.apply, state.target, document)
assert(not ok and applied == 1, 'Stale weapon target reached the runtime writer')
bridge.equipment_changed()
bridge.update(0.2)
assert(invalidated[1] == 1)
assert(bridge.close() and closed)
local restore = fake.restore
fake.restore = function()
    return false
end
assert(not bridge.close() and bridge.close(true), 'Uncertified restoration blocked lifetime quarantine')
fake.restore = function()
    error('Uncertain weapon restore read', 0)
end
assert(not bridge.close() and bridge.close(true), 'Weapon restoration exception escaped cleanup')
fake.restore = restore
local fixture = dofile('tests/weapon_fixture.lua')
local function recovery_fixture(prepare, remap)
    local f, invalidations = fixture(), {}
    if prepare then
        prepare(f)
    end
    local adapter = {
        primary_identity = {
            new = function()
                return f.identity
            end,
        },
        weapon_discovery = {
            new = function()
                return f.discovery
            end,
        },
        weapon_runtime = {
            new = function()
                return f.runtime
            end,
        },
        binding_session = {},
        weapon_controller = Controller,
    }
    local recovery_bridge
    adapter.weapon_mapping = dofile('src/editor/weapon_mapping.lua')
    recovery_bridge = Bridge.new(adapter, {
        memory = function()
            return {}
        end,
        native = function()
            return f.native
        end,
        engine = function()
            return f.E
        end,
        retain = function()
            return f.retain
        end,
        cohort = function()
            return f.cohort
        end,
        original = function(object)
            return f.documents[object]
        end,
        bind = function(binding, object)
            f.writes[#f.writes + 1] = { binding = binding, object = object }
            f.textures[binding.material][binding.slot] = object
        end,
        create_texture = function()
            error('Runtime fixture owns allocations')
        end,
        load_editor = function() end,
        open_editor = function()
            return true
        end,
        invalidate = function(slots)
            for _, slot in ipairs(slots) do
                invalidations[slot] = true
            end
        end,
        message = function() end,
        recover_preset = remap and function(preset, slot)
            local workflow = dofile('src/editor/weapon_workflow.lua').new(adapter, {
                bridge = function() return recovery_bridge end,
            })
            return workflow.plan(preset, {slots = {[slot] = true}}).apply()
        end or nil,
    })
    assert(recovery_bridge.load_current())
    local initial = recovery_bridge.controller().state()
    local saved = f.runtime.load(1, 1)
    saved.data[0] = 0.625
    assert(recovery_bridge.apply(initial.target, saved) == 5)
    return f, recovery_bridge, initial.target, invalidations
end

-- Exercise the production bridge over real discovery, runtime and binding
-- sessions, rather than calling the recovery method directly as its unit test.
local recovered, recovery_bridge, stale_target, invalidations = recovery_fixture()
local writes = #recovered.writes
recovered.respawn(1, 101)
recovery_bridge.equipment_changed()
recovery_bridge.update(0.2)
assert(invalidations[1] and #recovered.writes == writes + 5, 'Bridge did not replay retained respawn bindings')
assert(recovered.runtime.load(1, 1).data[0] == 0.625)
assert(
    not pcall(recovery_bridge.apply, stale_target, recovered.documents[recovered.A]),
    'Old editor was revived after respawn'
)
recovery_bridge.equipment_changed()
recovery_bridge.update(0.2)
assert(#recovered.writes == writes + 5, 'Bridge repeatedly reapplied an already recovered draft')

local pending, pending_bridge = recovery_fixture()
local reset, reset_bridge = recovery_fixture()
local reset_group = reset.runtime.groups(1)[1]
local reset_writes = #reset.writes
local reset_allocations = reset.allocations
local assigned_object = reset_group.bindings[1].current
for _, binding in ipairs(reset_group.bindings) do
    reset.textures[binding.material][binding.slot] = binding.original
end
reset_bridge.equipment_changed()
reset_bridge.update(0.2)
assert(
    #reset.writes == reset_writes + 5 and reset.runtime.load(1, 1).data[0] == 0.625,
    'Reload resetting live material slots to stock lost the retained weapon LUT'
)
reset_bridge.equipment_changed()
reset_bridge.update(0.2)
assert(#reset.writes == reset_writes + 5, 'Stock reset replay repeated each poll')
assert(
    reset.allocations == reset_allocations and reset_group.bindings[1].current == assigned_object,
    'A stock reset recreated the assigned texture instead of rebinding it'
)
assert(
    reset.runtime.catalog(1).available and reset.runtime.groups(1)[1] == reset_group,
    'A stock reset rebuilt the catalog or replaced editor assignments'
)
local replaced, replaced_bridge = recovery_fixture()
local replaced_writes = #replaced.writes
replaced.respawn(1, 101)
replaced.units[100].alive = true
replaced_bridge.equipment_changed()
replaced_bridge.update(0.2)
assert(#replaced.writes == replaced_writes + 5, 'Fresh equipped weapon lost its LUT while the old unit remained alive')
writes = #pending.writes
local stock = pending.documents[pending.A]
pending.documents[pending.A] = nil
pending.respawn(1, 101)
pending_bridge.equipment_changed()
pending_bridge.update(0.2)
pending_bridge.equipment_changed()
pending_bridge.update(0.2)
assert(#pending.writes == writes, 'Recovery allocated/wrote before the original cache was ready')
pending.documents[pending.A] = stock
pending_bridge.equipment_changed()
pending_bridge.update(0.2)
assert(#pending.writes == writes + 5 and pending.runtime.load(1, 1).data[0] == 0.625, 'Pending recovery was lost')

-- Ship units disappear before mission units exist. Exhausting the first
-- event's three-slot pass must retain intent until player_spawned wakes it.
local mission, mission_bridge = recovery_fixture()
local mission_writes = #mission.writes
mission.units[100].alive = false
mission.snapshots[1] = nil
mission_bridge.equipment_changed()
for _ = 1, 5 do mission_bridge.update(0.2) end
assert(#mission.writes == mission_writes and mission_bridge.recovery_pending(1),
    'Scene loading gap discarded the weapon assignment or wrote dead units')
mission.respawn(1, 101, resource)
mission_bridge.equipment_changed() -- forwarded player_spawned lifecycle
for _ = 1, 3 do mission_bridge.update(0.2) end
assert(#mission.writes == mission_writes + 5 and mission.runtime.load(1, 1).data[0] == 0.625,
    'Mission spawn did not replay the retained ship weapon palette')
mission_writes = #mission.writes
for _ = 1, 30 do mission_bridge.update(0.2) end
assert(#mission.writes == mission_writes, 'Stable mission weapon was repeatedly reapplied')

local dropped, dropped_bridge = recovery_fixture()
writes = #dropped.writes
dropped.snapshots[1] = nil
dropped_bridge.equipment_changed()
dropped_bridge.update(0.2)
dropped_bridge.equipment_changed()
dropped_bridge.update(0.2)
assert(dropped.units[100].alive and #dropped.writes == writes, 'Bridge wrote to a still-live dropped weapon')

local different, different_bridge = recovery_fixture()
writes = #different.writes
different.respawn(1, 101, '9988776655443322')
different_bridge.equipment_changed()
different_bridge.update(0.2)
different_bridge.equipment_changed()
different_bridge.update(0.2)
assert(#different.writes == writes, 'Respawn draft crossed weapon configuration identities')

local foreign, foreign_bridge = recovery_fixture()
local foreign_binding = foreign.runtime.groups(1)[1].bindings[1]
foreign.textures[foreign_binding.material][foreign_binding.slot] = 0xdead00
writes = #foreign.writes
foreign_bridge.equipment_changed()
foreign_bridge.update(0.2)
foreign.respawn(1, 101)
foreign_bridge.equipment_changed()
foreign_bridge.update(0.2)
assert(#foreign.writes == writes, 'A foreign writer was overridden by later recovery')

local closed_recovery, closed_bridge = recovery_fixture()
closed_recovery.documents[closed_recovery.A] = nil
closed_recovery.respawn(1, 101)
closed_bridge.equipment_changed()
closed_bridge.update(0.2)
writes = #closed_recovery.writes
assert(closed_bridge.close())
closed_bridge.equipment_changed()
closed_bridge.update(0.2)
assert(#closed_recovery.writes == writes, 'Closed bridge retained a respawn replay job')
local flashed, flashed_bridge = recovery_fixture()
local flash_target = flashed_bridge.controller().state().target
local flash_group = flashed.runtime.groups(1)[1]
local saved_source = ffi.string(flash_group.preview_document.data, 23 * 8 * 16)
local restore_objects = {}
for _, binding in ipairs(flash_group.bindings) do
    restore_objects[binding] = binding.current
end
assert(flashed_bridge.identify(flash_target, 2) == nil)
assert(flashed_bridge.highlighting())
assert(ffi.string(flash_group.preview_document.data, 23 * 8 * 16) == saved_source, 'Flash changed cached preview')
local captured = flashed.runtime.capture_state()
for _, entry in ipairs(captured.entries) do
    assert(entry.document.data[(2 - 1) * 23 * 4] ~= 1, 'Flash entered persisted pixels')
end
local foreign_target = flash_group.bindings[1]
flashed.textures[foreign_target.material][foreign_target.slot] = 0xdead00
assert(flashed_bridge.stop_highlight() and not flashed_bridge.highlighting())
assert(
    flashed.textures[foreign_target.material][foreign_target.slot] == 0xdead00,
    'Flash restoration overwrote foreign binding'
)
for binding, object in pairs(restore_objects) do
    if binding ~= foreign_target then
        assert(flashed.textures[binding.material][binding.slot] == object)
    end
end
local dropped_flash, dropped_flash_bridge = recovery_fixture()
assert(dropped_flash_bridge.identify(dropped_flash_bridge.controller().state().target, 1) == nil)
dropped_flash.snapshots[1] = nil
local flash_writes = #dropped_flash.writes
assert(dropped_flash_bridge.stop_highlight())
assert(#dropped_flash.writes == flash_writes, 'Flash restoration wrote to a dropped weapon')

local scoped, scoped_bridge = recovery_fixture(function(f)
    for _, mesh in ipairs(f.units[100].meshes) do
        f.textures[mesh.materials[2]][0x81d4c49d] = f.P
    end
end)
local scoped_controller = scoped_bridge.controller()
local companion = scoped_controller.state().pattern_target
assert(#companion.bindings == 5 and #companion.group_bindings == 10)
local body = scoped.runtime.load(1, 1, 'pattern', scoped.runtime.groups(1, 'pattern')[1].bindings)
body.data[11] = 0.2
assert(scoped_bridge.apply(companion, body) == 5)
assert(
    scoped_controller.state().pattern_document.data[11] == body.data[11],
    'Body quick swatch lost its scoped Pattern value'
)
scoped_bridge.snapshot()
local draw_checks = 0
scoped.identity_hook = function()
    draw_checks = draw_checks + 1
end
for _ = 1, 10 do
    scoped_bridge.snapshot()
end
scoped.identity_hook = nil
assert(draw_checks == 0, 'Mixed Pattern UI redraw repeated native identity/World discovery')
for _, mesh in ipairs(scoped.units[100].meshes) do
    assert(scoped.textures[mesh.materials[1]][0x81d4c49d] ~= scoped.P)
    assert(scoped.textures[mesh.materials[2]][0x81d4c49d] == scoped.P, 'Body Pattern edit recolored a sibling material')
end
assert(scoped_controller.choose_group(2))
local sibling = scoped_controller.state().pattern_target
assert(
    scoped_controller.state().pattern_document.data[11] ~= body.data[11],
    'Rail quick swatch displayed the sibling body palette'
)
local selected_members = {}
for _, binding in ipairs(scoped.runtime.groups(1, 'pattern')[1].bindings) do
    if binding.material_index == 1 then
        selected_members[#selected_members + 1] = binding
    end
end
local rail_doc = scoped.runtime.load(1, 1, 'pattern', selected_members)
assert(rail_doc.data[11] ~= 0.2 and not rail_doc.mixed, 'Subset load used a sibling uploaded palette')
rail_doc.data[11] = 0.8
assert(scoped_bridge.apply(sibling, rail_doc) == 5)
assert(
    scoped_controller.state().pattern_document.data[11] == rail_doc.data[11],
    'Rail quick swatch lost its scoped Pattern value'
)
local kept = {}
for _, mesh in ipairs(scoped.units[100].meshes) do
    kept[mesh.materials[2]] = scoped.textures[mesh.materials[2]][0x81d4c49d]
end
assert(scoped_bridge.restore(companion))
for _, mesh in ipairs(scoped.units[100].meshes) do
    assert(scoped.textures[mesh.materials[1]][0x81d4c49d] == scoped.P)
    assert(
        scoped.textures[mesh.materials[2]][0x81d4c49d] == kept[mesh.materials[2]],
        'Subset restore cleared a sibling Pattern'
    )
    assert(scoped.textures[mesh.materials[1]][0x7e662968] ~= scoped.A, 'Pattern restore cleared material LUT edits')
end
local invalid = {}
for key, value in pairs(companion) do
    invalid[key] = value
end
invalid.group_bindings = nil
local before_subset_writes = #scoped.writes
assert(
    not pcall(scoped_bridge.apply, invalid, body) and #scoped.writes == before_subset_writes,
    'Uncertified partial group reached native apply'
)
scoped.textures[scoped.units[100].meshes[1].materials[2]][0x81d4c49d] = 0xdead00
assert(
    not pcall(scoped_bridge.apply, companion, body) and #scoped.writes == before_subset_writes,
    'A foreign sibling writer escaped full-group scope validation'
)
assert(
    not pcall(scoped.runtime.load, 1, 1, 'pattern', { selected_members[1], selected_members[1] }),
    'Duplicate subset load was accepted'
)
print(
    'PASS weapon bridge: editor routing, raw values, stale guard, exact respawn recovery, pending cache retries, drop/configuration/foreign refusal and cleanup'
)

do
    local old_groups, old_load = fake.groups, fake.load
    local loads = 0
    fake.groups = function(slot, kind)
        return slot == 1 and kind == 'material' and { group, group } or {}
    end
    fake.load = function(_, index)
        loads = loads + 1
        if index == 1 then error('Original weapon LUT pixels unavailable', 0) end
        return document, group
    end
    local writes = applied
    local ok, why = pcall(bridge.descriptors, nil, { [1] = true })
    assert(not ok and tostring(why):find('still loading', 1, true) and loads == 2,
        'First cold table prevented other weapon source requests')
    assert(applied == writes, 'Cold source preflight applied a partial preset')
    fake.groups, fake.load = old_groups, old_load
end

-- Startup discovery joins one source snapshot batch, including Pattern LUTs,
-- without fetching pixels or touching materials. Repeated reads use catalogs.
do
    local old_catalog, old_groups, old_refresh, old_load = fake.catalog, fake.groups, fake.refresh, fake.load
    local catalogs, captures, writes = {}, 0, applied
    fake.catalog = function(slot) return catalogs[slot] end
    fake.refresh = function(slot)
        captures = captures + 1
        catalogs[slot] = { available = slot < 3 }
        return catalogs[slot].available and catalogs[slot] or nil
    end
    fake.groups = function(slot, kind)
        if slot == 3 then return {} end
        return { { object = kind == 'pattern' and 70001 or 65536 } }
    end
    fake.load = function() error('Startup source discovery loaded pixels synchronously') end
    local objects = bridge.source_objects()
    local count = 0
    for _ in pairs(objects) do count = count + 1 end
    assert(count == 2 and objects[65536] and objects[70001] and captures == 3,
        'Startup omitted an equipped material/Pattern source or failed to deduplicate')
    bridge.source_objects()
    assert(captures == 3 and applied == writes, 'Unchanged startup source census repeated discovery or applied a LUT')
    fake.catalog, fake.groups, fake.refresh, fake.load = old_catalog, old_groups, old_refresh, old_load
end
print('PASS startup weapon source batch: all slots, material/Pattern deduplication, no pixel reads or writes, idle cache')

do
    local f, editor = recovery_fixture()
    local writes = #f.writes
    f.respawn(1, 101)
    f.units[100].alive = true -- native Armory may keep its previous display unit alive
    local descriptors = editor.descriptors(nil, { [1] = true })
    assert(#descriptors > 0 and descriptors[1].bindings[1].unit == 101,
        'Automatic preset mapping retained the native Armory stale weapon')
    assert(#f.writes == writes, 'Preset discovery applied a LUT or changed the previous display weapon')
end
print('PASS native Armory replacement: fresh automatic preset targets without identity polling')

-- Slot intent follows a different equipped weapon, even while Armory keeps the
-- previous display Unit alive. Stable frames must not call the writer again.
do
    local f, editor = recovery_fixture(nil, true)
    local writes = #f.writes
    f.respawn(1, 101, '9988776655443322')
    f.units[100].alive = true
    editor.equipment_changed(1)
    editor.update(0.01)
    assert(#f.writes > writes, 'Native Armory replacement did not auto-map retained slot palette')
    assert(f.runtime.load(1, 1).data[0] == 0.625, 'Replacement weapon lost assigned colors')
    writes = #f.writes
    for n=1,100 do editor.update(0.01) end
    assert(#f.writes == writes, 'Unchanged recovery wrote repeatedly')
end
print('PASS event-driven slot recovery: different weapon, live previous preview unit, shared mapper and idle writer')

do
    local f, editor = recovery_fixture(nil, true)
    f.documents[f.A], f.documents[f.B], f.documents[f.P] = nil, nil, nil
    local writes = #f.writes
    f.respawn(1, 101, '9988776655443322')
    editor.equipment_changed(1)
    editor.update(0.01)
    assert(#f.writes > writes and not editor.recovery_pending(1),
        'Cold archive pixels prevented event-driven slot recovery')
    local group = f.runtime.groups(1, 'material')[1]
    assert(not group.source_document and group.applied_document.data[0] == 0.625,
        'Cold recovery fabricated original pixels or lost the saved palette')
    assert(not pcall(f.runtime.load, 1, 1), 'Pixel-dependent loading silently accepted a missing original')
    writes = #f.writes
    for n=1,100 do editor.update(0.01) end
    assert(#f.writes == writes, 'Cold recovery continued applying after completion')
end
print('PASS cold equip recovery uses verified loaded dimensions, retains originals and goes idle')
do
    local f, editor = recovery_fixture(nil, true)
    f.documents[f.A], f.documents[f.B], f.documents[f.P] = nil, nil, nil
    local writes = #f.writes
    f.respawn(1, 101) -- same weapon resource, new actor, cold original cache
    editor.equipment_changed(15)
    editor.update(0.01)
    assert(#f.writes > writes and not editor.recovery_pending(1),
        'Same-resource respawn discarded retained pixels while the original cache was cold')
    assert(f.runtime.groups(1, 'material')[1].applied_document.data[0] == 0.625)
    writes = #f.writes
    for _=1,100 do editor.update(0.01) end
    assert(#f.writes == writes, 'Respawn recovery did not become idle')
end
print('PASS same-weapon cold respawn: shared slot mapper restores intent without archived pixels or idle writes')

do
    local f, editor = recovery_fixture(nil, true)
    local document = f.runtime.groups(1, 'material')[1].applied_document
    f.documents[f.A], f.documents[f.B], f.documents[f.P] = nil, nil, nil
    f.respawn(1, 101, '9988776655443322')
    local workflow = dofile('src/editor/weapon_workflow.lua').new({
        weapon_mapping = dofile('src/editor/weapon_mapping.lua'),
    }, {bridge=function()return editor end})
    local plan = workflow.plan({entries={{kind='weapon',weapon_slot=1,
        weapon_resource='5fecab819f96a3e8',key='3:1:0:0',document=document}}}, {slots={[1]=true}})
    local writes, allocations = #f.writes, f.allocations
    f.texture_shapes[f.A][2] = 5
    assert(not pcall(plan.apply) and #f.writes == writes and f.allocations == allocations,
        'Changed loaded dimensions escaped the frozen apply receipt')
end
print('PASS cold mapping rechecks native dimensions before any allocation or write')

-- Cleanup validates native identities while restoring bindings. Those reads
-- cannot recreate an engine subscription after it has been stopped.
do
    local on_snapshot, starts, stops, watched = nil, 0, 0, 0
    local adapter = {}
    for k,v in pairs(m) do adapter[k]=v end
    adapter.primary_identity = {new=function(deps) on_snapshot=deps.on_snapshot;return {} end}
    adapter.weapon_events = {new=function()
        starts=starts+1
        return {watch=function() watched=watched+1 end,close=function() stops=stops+1 end}
    end}
    adapter.weapon_runtime = {new=function()
        return {restore=function() on_snapshot({});return true end}
    end}
    local editor=Bridge.new(adapter, {
        memory=function() return {} end,native=function()return {}end,
        engine=function()return {}end,event_cache=function()return 'unused'end,
        retain=function()return {}end,cohort=function()return {}end,
    })
    editor.runtime();on_snapshot({})
    assert(starts==1 and watched==1)
    assert(editor.reset())
    assert(starts==1 and stops==0 and watched==2,
        'Restore Arrowhead shut down equip recovery or replaced its subscription')
    editor.suspend_events();assert(editor.close())
    assert(starts==1 and stops==1 and watched==2,'Restoration rearmed native callbacks during teardown')
    on_snapshot({})
    assert(starts==1 and watched==2,'Retired bridge accepted a later identity receipt')
end
print('PASS native event lifecycle: Restore retains equip recovery, teardown prevents rearming')
