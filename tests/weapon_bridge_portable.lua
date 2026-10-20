-- Production bridge/controller/runtime/sessions over an explicit discovery host.
-- Native ABI identity/discovery is outside this detached-controller fixture.
local Buffer = require('src.core.float_buffer')
local Bridge = dofile('src/editor/weapon_bridge.lua')
local Runtime = dofile('src/weapons/weapon_runtime.lua')
local Controller = dofile('src/editor/weapon_controller.lua')
local Session = dofile('src/gear/binding_session.lua')
local receipts, live, current, originals, sources = {}, {}, {}, {}, {}
local captures, validations, writes, allocations, native_reads, actor_wakes = 0, {}, 0, 0, 0, 0
local private, next_object = true, 300000
local retain, cohort = { records = {}, cache = {}, bytes = 0 }, {}
local discovery = {}
local function key(binding) return binding.material .. ':' .. binding.slot end
local function equip(slot, generation)
    local prior = receipts[slot]
    if prior then live[prior.unit] = false end
    local unit = slot * 100 + generation
    receipts[slot] = { weapon_slot = slot, unit = unit, weapon_unit_ref = unit,
        weapon_resource64 = string.format('%016x', slot + 1000), unit_resource64 = string.format('%016x', slot + 2000) }
    live[unit] = true
    for index = 0, 1 do
        local material = unit * 100 + index
        current[material .. ':' .. Runtime.MATERIAL] = 100000 + slot
    end
end
for slot = 1, 3 do
    equip(slot, 1)
    local data = Buffer.new(184)
    for i = 0, 183 do data[i] = (i - 37) / 23 end
    data[0], data[3], data[52] = 2 ^ -149, -1 / math.huge, 1000000
    sources[100000 + slot] = { data = data, width = 23, height = 2, resource = string.format('%016x', slot + 3000) }
    originals[slot] = Buffer.bytes(data, 184)
end
function discovery.capture(slot)
    captures = captures + 1
    return receipts[slot], 'slot is empty'
end
function discovery.validate(receipt)
    validations[#validations + 1] = receipt.weapon_slot
    return receipts[receipt.weapon_slot] == receipt and live[receipt.unit] == true
end
function discovery.materials(receipt) assert(discovery.validate(receipt)); return { 0, 1 } end
function discovery.descriptor(receipt, index, slot)
    if slot == Runtime.PATTERN then return nil end
    local material = receipt.unit * 100 + index
    return { kind = 'weapon', weapon_slot = receipt.weapon_slot, weapon_resource = receipt.weapon_resource64,
        unit = receipt.unit, mesh = receipt.unit * 10 + index, material = material,
        mesh_index = index, material_index = 0, slot = slot, original = 100000 + receipt.weapon_slot,
        current = current[material .. ':' .. slot], save_key = '3:' .. receipt.weapon_slot .. ':' .. index .. ':0' }
end
function discovery.present(binding)
    local receipt = receipts[binding.weapon_slot]
    return live[binding.unit] == true and receipt ~= nil and receipt.unit == binding.unit
end
function discovery.dead(binding) return not live[binding.unit] end
function discovery.binding(binding) assert(discovery.present(binding)); return current[key(binding)] end
function discovery.prove_private(targets)
    if not private then return nil, 'Fixture target is not private' end
    for _, binding in ipairs(targets) do assert(discovery.present(binding)) end
    return true
end
function discovery.with_validation_batch(callback) return callback() end
local identity = {
    snapshot = function(slot) return receipts[slot] end,
    snapshot_remote = function() return nil end,
}
local identity_options, discovery_options
local modules = {
    float_buffer = Buffer, weapon_runtime = Runtime, weapon_controller = Controller, binding_session = Session,
    weapon_mapping = dofile('src/editor/weapon_mapping.lua'),
    primary_identity = { new = function(options) identity_options = options; return identity end },
    weapon_discovery = { new = function(_, options) discovery_options = options; return discovery end },
}
local loaded, opened, invalidated, mutations = nil, nil, {}, 0
local memory = {
    verify_build = function() error('Native build verification is outside this fixture') end,
    read = function() native_reads = native_reads + 1; error('Unexpected raw native read') end,
}
local bridge = Bridge.new(modules, {
    memory = function() return memory end, native = function() return {} end, engine = function() return {} end,
    retain = function() return retain end, cohort = function() return cohort end,
    original = function(object) return sources[object] end,
    create_texture = function(width, height, data)
        allocations = allocations + 1; next_object = next_object + 1
        return { object = next_object, width = width, height = height, data = data }
    end,
    bind = function(binding, object)
        assert(discovery.present(binding), 'Write reached a stale equipment instance')
        writes = writes + 1; current[key(binding)] = object
    end,
    load_editor = function(document, target) loaded = { document = document, target = target } end,
    open_editor = function(cell) opened = cell; return true end,
    invalidate = function(slots) invalidated = slots end,
    mutate = function(callback) mutations = mutations + 1; return callback() end,
    actor_changed = function() actor_wakes = actor_wakes + 1 end,
    message = function() end,
})
for _ = 1, 1000 do bridge.update(0.016) end
assert(captures == 0 and writes == 0 and allocations == 0, 'Uninitialized bridge performed idle work')
assert(bridge.load_current() and captures == 3)
assert(identity_options.verify_build == memory.verify_build and type(identity_options.read) == 'function'
    and type(discovery_options.read) == 'function', 'Native verified-reader wiring changed')
local controller = bridge.controller()
local state = controller.state()
assert(state.quick_ready and state.target.weapon_slot == 1 and #state.target.bindings == 2)
assert(controller.open_editor(2, 1) and loaded.document.data ~= sources[100001].data and opened.row == 2)
assert(Buffer.bytes(loaded.document.data, 184) == originals[1])
loaded.document.data[0] = 0.625
assert(bridge.apply(loaded.target, loaded.document) == 2 and mutations == 1 and writes == 2 and allocations == 1)
local assigned = current[key(state.target.bindings[1])]
loaded.document.data[0] = 0.125
local retained = bridge.runtime().capture_state()
assert(#retained.entries == 1 and retained.entries[1].document.data[0] == 0.625,
    'Editing a detached draft changed retained application intent')
assert(1 / retained.entries[1].document.data[3] == -math.huge
    and retained.entries[1].document.data[52] == 1000000)
retained.entries[1].document.data[0] = 0.875
assert(bridge.runtime().capture_state().entries[1].document.data[0] == 0.625, 'Capture aliases retained state')

local cache = Buffer.bytes(bridge.runtime().groups(1)[1].preview_document.data, 184)
bridge.identify(controller.state().target, 2)
assert(bridge.highlighting() and allocations == 2)
local group = bridge.runtime().groups(1)[1]
assert(Buffer.bytes(group.preview_document.data, 184) == cache, 'Identification changed cached preview bytes')
local flashed = current[key(group.bindings[1])]
assert(flashed ~= assigned and group.bindings[1].texture.object == assigned)
local persisted = bridge.runtime().capture_state()
assert(persisted.entries[1].document.data[0] == 0.625
    and persisted.entries[1].document.data[92] ~= 1, 'Temporary magenta entered retained pixels')
bridge.tick_highlight(0.3, true)
assert(current[key(group.bindings[1])] == assigned)
bridge.tick_highlight(0.3, true)
assert(current[key(group.bindings[1])] == flashed)
assert(bridge.stop_highlight() and current[key(group.bindings[1])] == assigned)
assert(Buffer.bytes(sources[100001].data, 184) == originals[1], 'Identification modified source float bytes')

local before_reads, before_writes, before_allocations = #validations, writes, allocations
for _ = 1, 1000 do bridge.update(0.016) end
assert(#validations == before_reads and writes == before_writes and allocations == before_allocations,
    'Unchanged bridge polled or reapplied')
validations = {}
bridge.equipment_changed(1); bridge.equipment_changed(4); bridge.equipment_changed(1)
bridge.update(0); bridge.update(0); bridge.update(0)
assert(#validations == 2 and validations[1] == 1 and validations[2] == 3,
    'Arithmetic slot mask duplicated or changed the requested slots')
bridge.equipment_changed(8); bridge.update(0)
assert(actor_wakes == 1 and #validations == 2, 'Actor-only event scanned weapon slots')
validations = {}
bridge.equipment_changed(31)
for _ = 1, 4 do bridge.update(0) end
assert(#validations == 3 and validations[1] == 1 and validations[2] == 2 and validations[3] == 3
    and actor_wakes == 2, 'Higher mask bits changed the three-slot pass')

local stale_target = controller.state().target
before_writes, before_allocations = writes, allocations
equip(1, 2)
bridge.equipment_changed(1); bridge.update(0)
assert(invalidated[1] == 1 and not bridge.recovery_pending(1) and writes == before_writes + 2
    and allocations == before_allocations, 'Equip event failed to replay cached retained pixels once')
assert(bridge.runtime().load(1, 1).data[0] == 0.625)
assert(not pcall(bridge.apply, stale_target, loaded.document), 'Old equipment descriptor reached application')
private = false
local target = controller.state().target
assert(not pcall(bridge.apply, target, loaded.document) and writes == before_writes + 2
    and allocations == before_allocations, 'Unowned target reached allocation or binding')
private = true
group = bridge.runtime().groups(1)[1]
bridge.identify(target, 1)
current[key(group.bindings[1])] = 999999
assert(bridge.stop_highlight() and current[key(group.bindings[1])] == 999999,
    'Identification restoration overwrote a foreign texture binding')
assert(not bridge.close() and bridge.close(true) and native_reads == 0
    and current[key(group.bindings[1])] == 999999, 'Foreign ownership was cleared instead of retained for quarantine')
print('PASS portable weapon bridge: real controller/runtime/sessions, detached drafts/capture, exact temporary float copies, retained event recovery, slot masks, idle silence and stale/foreign/private guards')
