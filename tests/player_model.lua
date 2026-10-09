local M = dofile('src/preview/player_model.lua')
local units =
    { root = { alive = true, pose = 10 }, armor = { alive = true, pose = 12 }, helmet = { alive = true, pose = 14 } }
local E = { Application = {}, World = {}, Unit = {}, Matrix4x4 = {}, Mesh = {} }
local id = 0
local destroyed = {}
local copies = 0
local failure
local U, W, X = E.Unit, E.World, E.Matrix4x4
U.alive = function(u)
    return units[u] and units[u].alive
end
U.world_pose = function(u, index)
    return units[u].pose + ((index or 1) - 1) * 3
end
X.inverse = function(p)
    return -p
end
X.multiply = function(a, b)
    return a + b
end
E.Matrix4x4Box = function(value)
    return {
        unbox = function()
            return value
        end,
    }
end
U.resource_name = function(u)
    return u
end
E.Application.can_get = function()
    return true
end
U.num_meshes = function()
    return 1
end
U.mesh = function(u)
    return u
end
E.Mesh.visibility = function()
    return true
end
U.num_scene_graph_items = function()
    return 10
end
U.disable_physics = function() end
U.has_animation_state_machine = function()
    return true
end
U.disable_animation_state_machine = function() end
U.scene_graph_link = function(unit, node, parent)
    assert(parent == 1 and node > parent and unit ~= 'armor' and unit ~= 'helmet')
end
U.set_local_pose = function(unit, node, pose)
    assert(pose == (node - 1) * 3, 'World bone pose was not preserved relative to the copy root')
    copies = copies + 1
end
U.set_mesh_visibility = function() end
W.update_unit = function() end
W.spawn_unit = function(_, resource, pose)
    id = id + 1
    local unit = 'copy' .. id
    units[unit] = { alive = true, pose = pose, resource = resource }
    return unit
end
W.destroy_unit = function(_, unit)
    assert(unit ~= 'armor' and unit ~= 'helmet')
    units[unit].alive = false
    destroyed[#destroyed + 1] = unit
end
local applied = {}
local m = M.new(E, {
    copy_materials = function()
        if failure then
            error('shared material')
        end
    end,
    retain_failed = function()
        error('Unexpected failed cleanup')
    end,
    apply_palette = function(piece, palette)
        applied[piece.kind] = palette
    end,
})
local plan = m.capture(
    'main',
    'root',
    { { unit = 'armor', kind = 'armor' }, { unit = 'helmet', kind = 'helmet' }, { unit = 'armor', kind = 'armor' } }
)
assert(
    #plan.pieces == 2 and plan.pieces[1].pose:unbox() == 0 and plan.pieces[2].pose:unbox() == 2,
    'Duplicate piece or normalization against gameplay origin instead of visual origin'
)
local model = m.create('owned', plan)
assert(copies == 18 and #model.pieces == 2)
m.apply(model, { helmet = 'blue' })
assert(applied.helmet == 'blue' and applied.armor == nil)
m.destroy(model)
assert(#destroyed == 2 and units.armor.alive and units.helmet.alive)
failure = true
assert(not pcall(m.create, 'owned', plan))
assert(#destroyed == 3, 'Partial setup leaked garment')
print('PASS independent garment copies, relative pose, exact skeleton, target LUTs and partial cleanup')

local hidden = {}
U.has_visibility_group = function(unit, name)
    return name == 'gore_left_knee' or name == 'gore_right_knee'
end
U.set_visibility = function(unit, name, visible)
    assert(unit ~= 'armor' and unit ~= 'helmet', 'Gore filter changed equipped source')
    assert(visible == false)
    hidden[name] = true
end
local filtered = M.new(E, { copy_materials = function() end, retain_failed = function() end })
local filtered_plan = filtered.capture('world', 'root', { { unit = 'armor', kind = 'armor' } })
local cleaned = filtered.create('world', filtered_plan)
assert(hidden.gore_left_knee and hidden.gore_right_knee, 'Declared knee gore groups were not hidden')
filtered.destroy(cleaned)

local prior_visibility = E.Mesh.visibility
E.Mesh.visibility = function()
    return 0
end
local numeric = M.new(E, { copy_materials = function() end, retain_failed = function() end })
local numeric_plan = numeric.capture('world', 'root', { { unit = 'armor', kind = 'armor' } })
assert(numeric_plan.pieces[1].visible[1] == false, 'Numeric zero made a hidden damage mesh visible')
E.Mesh.visibility = prior_visibility

local old_set_visibility = U.set_mesh_visibility
U.set_mesh_visibility = function(unit, index, value)
    assert(value == false, 'Preview force-enabled a resource-default hidden mesh')
end
local default_model = M.new(E, { copy_materials = function() end, retain_failed = function() end })
local defaults = default_model.capture('world', 'root', { { unit = 'armor', kind = 'armor' } })
local default_copy = default_model.create('world', defaults)
default_model.destroy(default_copy)
U.set_mesh_visibility = old_set_visibility
