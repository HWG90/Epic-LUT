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
valid = false
local ok = pcall(bridge.apply, state.target, document)
assert(not ok and applied == 1, 'Stale weapon target reached the runtime writer')
bridge.update(0.2)
assert(invalidated[1] == 1)
assert(bridge.close() and closed)
print('PASS weapon bridge: shared editor routing, exact group/LOD receipts, raw values, apply, stale guard and cleanup')
