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

-- Hierarchy capture is opt-in, reads only an owned copy before flattening,
-- and keeps independent pose boxes. Unsupported metadata preserves static use.
local prior_spawn, prior_link = W.spawn_unit, U.scene_graph_link
local hierarchy_reads, cycle = 0, false
W.spawn_unit = function(world, resource, pose)
    local unit = prior_spawn(world, resource, pose)
    units[unit].parents = {}
    for i = 2, 10 do
        units[unit].parents[i] = i - 1
    end
    if cycle then
        units[unit].parents[2], units[unit].parents[3] = 3, 2
    end
    return unit
end
U.scene_graph_parent = function(unit, index)
    assert(unit ~= 'armor' and unit ~= 'helmet', 'Borrowed source hierarchy queried')
    assert(not units[unit].flattened, 'Authored hierarchy was captured after flattening')
    hierarchy_reads = hierarchy_reads + 1
    return units[unit].parents[index]
end
U.scene_graph_link = function(unit, node, parent)
    prior_link(unit, node, parent)
    units[unit].flattened = true
    units[unit].parents[node] = parent
end
local static = M.new(E, { copy_materials = function() end, retain_failed = function() end })
local static_plan = static.capture('world', 'root', { { unit = 'armor', kind = 'armor' } })
local still = static.create('world', static_plan)
assert(hierarchy_reads == 0 and still.pieces[1].animation_bind == nil, 'Static preview acquired new animation APIs')
static.destroy(still)
local animated = M.new(E, { animate = true, copy_materials = function() end, retain_failed = function() end })
local posed = animated.create('world', static_plan)
local piece = posed.pieces[1]
assert(hierarchy_reads == 9 and piece.animation_bind.parents[5] == 4 and units[piece.unit].parents[5] == 1)
assert(piece.animation_bind.poses[5] ~= static_plan.pieces[1].nodes[5], 'Animation retained a mutable plan pose box')
assert(piece.animation_bind.poses[5]:unbox() == 12 and piece.animation_bind.poses[1]:unbox() == 0)
static_plan.pieces[1].nodes[5] = E.Matrix4x4Box(999)
assert(piece.animation_bind.poses[5]:unbox() == 12, 'Public source plan changed immutable animation basis')
animated.destroy(posed)
static_plan.pieces[1].nodes[5] = E.Matrix4x4Box(12)
local parent_api = U.scene_graph_parent
U.scene_graph_parent = nil
local unavailable = animated.create('world', static_plan)
assert(
    unavailable.pieces[1].animation_bind == nil
        and unavailable.pieces[1].animation_error:find('API unavailable', 1, true)
)
animated.destroy(unavailable)
U.scene_graph_parent = function(unit, index)
    if index == 3 then
        return nil
    end
    return parent_api(unit, index)
end
local forest = animated.create('world', static_plan)
assert(forest.pieces[1].animation_bind.parents[3] == 0, 'Authored root node was rejected or given a guessed parent')
animated.destroy(forest)
U.scene_graph_parent, cycle = parent_api, true
local cyclic = animated.create('world', static_plan)
assert(cyclic.pieces[1].animation_bind == nil and cyclic.pieces[1].animation_error:find('cycle', 1, true))
animated.destroy(cyclic)
-- One static adapter can request hierarchy capture for a fenced pose rebuild,
-- then return to its original path. Capture always precedes copied-node links.
U.scene_graph_parent, cycle = parent_api, false
local capture_host = { capture_animation = false, copy_materials = function() end, retain_failed = function() end }
local selectable = M.new(E, capture_host)
local before_capture = hierarchy_reads
local idle_copy = selectable.create('world', static_plan)
assert(hierarchy_reads == before_capture and not idle_copy.pieces[1].animation_bind)
selectable.destroy(idle_copy)
capture_host.capture_animation = true
local selected_copy = selectable.create('world', static_plan)
assert(hierarchy_reads == before_capture + 9 and selected_copy.pieces[1].animation_bind)
selectable.destroy(selected_copy)
capture_host.capture_animation = false
local idle_again = selectable.create('world', static_plan)
assert(hierarchy_reads == before_capture + 9 and not idle_again.pieces[1].animation_bind)
selectable.destroy(idle_again)
print('PASS gated owned hierarchy capture, immutable bind poses and static fallback for missing/cyclic animation data')

-- Exact named gore meshes are suppressed after native material copies, using
-- verified indexed handles only. Other geometry and borrowed sources survive.
do
    local ffi = require('ffi')
    local Names = dofile('src/gear/binding_names.lua')
    for hash, name in pairs({
        [0xfb311215] = 'g_gore',
        [0xf2a082c1] = 'g_gore_LOD1',
        [0x4dcf0af2] = 'g_gore_LOD2',
        [0x2647a6f7] = 'g_gore_LOD3',
    }) do
        assert(Names.mesh(hash) == name, 'Preview gore filter no longer agrees with the mesh-name catalog')
    end
    local old_mesh, old_count, old_has, old_set = U.mesh, U.num_meshes, U.has_mesh, U.set_mesh_visibility
    local old_spawn, old_visibility = W.spawn_unit, E.Mesh.visibility
    local names = {
        'g_clothes',
        'g_gore',
        'g_gore_LOD1',
        'g_gore_LOD2',
        'g_gore_LOD3',
        'g_cap',
        'g_left_arm',
        'g_gore_unknown',
        'g_gore_shadow',
    }
    local handles, source_visibility, events, notes = {}, {}, {}, {}
    local mode, named_error, unmapped, ambiguous, setter_error
    local function unit_handles(unit)
        if not handles[unit] then
            handles[unit] = {}
            local seed = unit == 'armor' and 1 or tonumber(unit:match('%d+$')) + 10
            for index = 1, #names do
                local number = seed * 100 + index
                handles[unit][index] = mode == 'numeric' and number
                    or mode == 'pointer' and ffi.cast('void *', number)
                    or unit .. ':' .. index
            end
            if ambiguous then
                handles[unit][3] = handles[unit][2]
            end
        end
        return handles[unit]
    end
    U.num_meshes = function()
        return #names
    end
    U.has_mesh = function(unit, name)
        assert(unit ~= 'armor' and unit ~= 'helmet', 'Named gore filter queried the borrowed garment')
        for _, expected in ipairs(names) do
            if expected == name then
                return true
            end
        end
        return false
    end
    local has_mesh = U.has_mesh
    U.mesh = function(unit, index)
        local h = unit_handles(unit)
        if type(index) == 'number' then
            return h[index]
        end
        assert(unit ~= 'armor' and unit ~= 'helmet', 'Named gore filter resolved a borrowed mesh')
        if named_error then
            error('Named mesh overload unavailable')
        end
        for at, name in ipairs(names) do
            if index == name then
                if unmapped then
                    return at -- An index is not the actual Mesh handle.
                end
                if mode == 'pointer' then
                    return ffi.cast('void *', h[at]) -- Equal native handle, fresh Lua cdata object.
                end
                return h[at]
            end
        end
    end
    E.Mesh.visibility = function(mesh)
        return source_visibility[mesh]
    end
    U.set_mesh_visibility = function(unit, index, value)
        assert(unit ~= 'armor' and unit ~= 'helmet' and value == false, 'Gore filter modified source visibility')
        if setter_error and index ~= 6 then
            error('Visibility setter unavailable')
        end
        events[#events + 1] = index
        units[unit].visible[index] = false
    end
    W.spawn_unit = function(world, resource, pose)
        local unit = old_spawn(world, resource, pose)
        units[unit].visible = {}
        for index = 1, #names do
            units[unit].visible[index] = index ~= 6
        end
        unit_handles(unit)
        return unit
    end
    local model_service = M.new(E, {
        copy_materials = function(piece)
            assert(units[piece.unit].visible[6] == false, 'Source-hidden cap was lost before material setup')
            events[#events + 1] = 'materials'
            for index = 2, 5 do
                units[piece.unit].visible[index] = true -- Simulate a native material commit revealing gore.
            end
        end,
        retain_failed = function()
            error('Unexpected gore cleanup failure')
        end,
        note = function(text)
            notes[#notes + 1] = text
        end,
    })
    local function create()
        handles, source_visibility, events, notes = {}, {}, {}, {}
        local source = unit_handles('armor')
        for index, mesh in ipairs(source) do
            source_visibility[mesh] = index ~= 6
        end
        local captured = model_service.capture('world', 'root', { { unit = 'armor', kind = 'armor' } })
        assert(captured.pieces[1].visible[6] == false)
        return model_service.create('world', captured)
    end
    local function check_other_geometry(copy)
        for _, index in ipairs({ 1, 7, 8, 9 }) do
            assert(units[copy].visible[index] == true, 'Gore filter hid clothes, limbs, unknown or shadow meshes')
        end
        assert(units[copy].visible[6] == false, 'Gore filter force-enabled a source-hidden cap')
        assert(units.armor.alive and units.helmet.alive, 'Gore filter damaged the borrowed garments')
    end
    for _, handle_type in ipairs({ 'string', 'numeric', 'pointer' }) do
        mode = handle_type
        local owned = create()
        local copy = owned.pieces[1].unit
        assert(
            table.concat(events, ',') == '6,materials,2,3,4,5',
            'Gore writes preceded material copying or used names as indexes'
        )
        for index = 2, 5 do
            assert(units[copy].visible[index] == false, 'Exact catalog gore mesh remained visible')
        end
        check_other_geometry(copy)
        assert(notes[#notes]:find('gore meshes hidden=4', 1, true), 'Named gore diagnostic lost its verified count')
        model_service.destroy(owned)
    end
    mode = 'string'
    for _, unavailable in ipairs({ 'missing', 'has-error', 'named-error', 'unmapped', 'setter-error' }) do
        if unavailable == 'missing' then
            U.has_mesh = nil
        elseif unavailable == 'has-error' then
            U.has_mesh = function()
                error('Named mesh availability unavailable')
            end
        else
            U.has_mesh = has_mesh
        end
        named_error, unmapped, setter_error =
            unavailable == 'named-error', unavailable == 'unmapped', unavailable == 'setter-error'
        local owned = create()
        local copy = owned.pieces[1].unit
        assert(table.concat(events, ',') == '6,materials', 'Unavailable/unmapped optional gore API hid a guessed index')
        check_other_geometry(copy)
        assert(notes[#notes]:find('gore meshes hidden=0', 1, true), 'Skipped gore filter reported an unverified hide')
        model_service.destroy(owned)
    end
    U.has_mesh, named_error, unmapped, setter_error, ambiguous = has_mesh, nil, nil, nil, true
    local owned = create()
    assert(table.concat(events, ',') == '6,materials,4,5', 'Ambiguous indexed handles selected a guessed gore mesh')
    check_other_geometry(owned.pieces[1].unit)
    assert(notes[#notes]:find('ambiguous handle', 1, true), 'Ambiguous gore handles lost their diagnostic')
    model_service.destroy(owned)
    U.mesh, U.num_meshes, U.has_mesh, U.set_mesh_visibility = old_mesh, old_count, old_has, old_set
    W.spawn_unit, E.Mesh.visibility = old_spawn, old_visibility
end
print(
    'PASS exact copied gore mesh suppression after materials, handle proofs, cap/limb preservation and optional API fallback'
)
