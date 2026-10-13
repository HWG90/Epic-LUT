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
local function recovery_fixture()
    local f, invalidations = fixture(), {}
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
    local recovery_bridge = Bridge.new(adapter, {
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
        bind = function()
            error('Runtime fixture owns writes')
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
recovery_bridge.update(0.2)
assert(invalidations[1] and #recovered.writes == writes + 5, 'Bridge did not replay retained respawn bindings')
assert(recovered.runtime.load(1, 1).data[0] == 0.625)
assert(
    not pcall(recovery_bridge.apply, stale_target, recovered.documents[recovered.A]),
    'Old editor was revived after respawn'
)
recovery_bridge.update(0.2)
assert(#recovered.writes == writes + 5, 'Bridge repeatedly reapplied an already recovered draft')

local pending, pending_bridge = recovery_fixture()
writes = #pending.writes
local stock = pending.documents[pending.A]
pending.documents[pending.A] = nil
pending.respawn(1, 101)
pending_bridge.update(0.2)
pending_bridge.update(0.2)
assert(#pending.writes == writes, 'Recovery allocated/wrote before the original cache was ready')
pending.documents[pending.A] = stock
pending_bridge.update(0.2)
assert(#pending.writes == writes + 5 and pending.runtime.load(1, 1).data[0] == 0.625, 'Pending recovery was lost')

local dropped, dropped_bridge = recovery_fixture()
writes = #dropped.writes
dropped.snapshots[1] = nil
dropped_bridge.update(0.2)
dropped_bridge.update(0.2)
assert(dropped.units[100].alive and #dropped.writes == writes, 'Bridge wrote to a still-live dropped weapon')

local different, different_bridge = recovery_fixture()
writes = #different.writes
different.respawn(1, 101, '9988776655443322')
different_bridge.update(0.2)
different_bridge.update(0.2)
assert(#different.writes == writes, 'Respawn draft crossed weapon configuration identities')

local foreign, foreign_bridge = recovery_fixture()
local foreign_binding = foreign.runtime.groups(1)[1].bindings[1]
foreign.textures[foreign_binding.material][foreign_binding.slot] = 0xdead00
writes = #foreign.writes
foreign_bridge.update(0.2)
foreign.respawn(1, 101)
foreign_bridge.update(0.2)
assert(#foreign.writes == writes, 'A foreign writer was overridden by later recovery')

local closed_recovery, closed_bridge = recovery_fixture()
closed_recovery.documents[closed_recovery.A] = nil
closed_recovery.respawn(1, 101)
closed_bridge.update(0.2)
writes = #closed_recovery.writes
assert(closed_bridge.close())
closed_bridge.update(0.2)
assert(#closed_recovery.writes == writes, 'Closed bridge retained a respawn replay job')
print(
    'PASS weapon bridge: editor routing, raw values, stale guard, exact respawn recovery, pending cache retries, drop/configuration/foreign refusal and cleanup'
)
