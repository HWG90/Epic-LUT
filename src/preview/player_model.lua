-- Independent visual copy of equipped garment units. No avatar/network entity is
-- registered and no player, Armory actor or thumbnail scheduler is modified.
local Model = {}
function Model.new(E, host)
    local A, W, U, X = E.Application, E.World, E.Unit, E.Matrix4x4
    local self = {}
    function self.capture(world, root, pieces)
        assert(U.alive(root), 'Player model disappeared')
        assert(#pieces > 0, 'No equipped garment units')
        -- The gameplay actor and its visual garments use different origins.
        -- Normalize against the shared visual root, not the actor's unit pose.
        local anchor = pieces[1].unit
        for _, piece in ipairs(pieces) do
            if piece.kind == 'armor' then
                anchor = piece.unit
                break
            end
        end
        local inverse = X.inverse(U.world_pose(anchor, 1))
        local plan = { pieces = {} }
        local seen = {}
        for _, piece in ipairs(pieces) do
            local unit = piece.unit
            if not seen[unit] then
                seen[unit] = true
                assert(U.alive(unit), 'Equipped piece disappeared')
                local resource = U.resource_name(unit)
                assert(A.can_get('unit', resource), 'Equipped resource is not loaded')
                local visible, visibility_counts = {}, {}
                for i = 1, U.num_meshes(unit) do
                    local value = E.Mesh.visibility(U.mesh(unit, i))
                    local key = type(value) .. ':' .. tostring(value)
                    visibility_counts[key] = (visibility_counts[key] or 0) + 1
                    assert(
                        type(value) == 'boolean' or value == 0 or value == 1,
                        'Unrecognized preview mesh visibility value'
                    )
                    visible[i] = value == true or value == 1
                end
                if host.note then
                    local summary = {}
                    for key, count in pairs(visibility_counts) do
                        summary[#summary + 1] = key .. '=' .. count
                    end
                    table.sort(summary)
                    host.note(
                        'preview: mesh visibility resource=' .. tostring(resource) .. ' ' .. table.concat(summary, ',')
                    )
                end
                local count = U.num_scene_graph_items(unit)
                assert(count >= 1 and count <= 512, 'Equipped skeleton size is invalid')
                local piece_inverse = X.inverse(U.world_pose(unit, 1))
                local nodes = {}
                for i = 2, count do
                    nodes[i] = E.Matrix4x4Box(X.multiply(U.world_pose(unit, i), piece_inverse))
                end
                plan.pieces[#plan.pieces + 1] = {
                    source = unit,
                    resource = resource,
                    kind = piece.kind,
                    slot = piece.slot,
                    pose = E.Matrix4x4Box(X.multiply(U.world_pose(unit, 1), inverse)),
                    visible = visible,
                    nodes = nodes,
                    node_count = count,
                }
            end
        end
        assert(#plan.pieces > 0, 'No equipped garment units')
        return plan
    end
    function self.create(world, plan)
        local model = { world = world, pieces = {} }
        local ok, err = pcall(function()
            for _, spec in ipairs(plan.pieces) do
                assert(U.alive(spec.source), 'Source changed during preview setup')
                local unit = assert(W.spawn_unit(world, spec.resource, spec.pose:unbox()))
                -- Record ownership before any subsequent setup can fail.
                local piece = { unit = unit, source = spec.source, kind = spec.kind, slot = spec.slot }
                model.pieces[#model.pieces + 1] = piece
                assert(unit ~= spec.source, 'Preview reused the source unit')
                U.disable_physics(unit)
                if U.has_animation_state_machine(unit) then
                    U.disable_animation_state_machine(unit)
                end
                assert(U.num_scene_graph_items(unit) == spec.node_count, 'Preview skeleton differs')
                -- Source bones may be linked to the player's avatar or another
                -- garment. Bake their actual world poses under our own root;
                -- copying local transforms alone retains those dependencies.
                for i = 2, spec.node_count do
                    U.scene_graph_link(unit, i, 1)
                    U.set_local_pose(unit, i, spec.nodes[i]:unbox())
                end
                assert(U.num_meshes(unit) == #spec.visible, 'Preview mesh layout differs')
                for i, visible in ipairs(spec.visible) do
                    -- Mesh.visibility describes the current render context. A true result is not
                    -- permission to override resource-default hidden damage/cap meshes.
                    if visible == false then
                        U.set_mesh_visibility(unit, i, false)
                    end
                end
                local hidden_groups = {}
                if type(U.has_visibility_group) == 'function' and type(U.set_visibility) == 'function' then
                    for _, name in ipairs({
                        'gore',
                        'gibs',
                        'gib',
                        'gore_left_leg',
                        'gore_right_leg',
                        'gore_left_knee',
                        'gore_right_knee',
                        'gore_l',
                        'gore_r',
                    }) do
                        if U.has_visibility_group(unit, name) then
                            U.set_visibility(unit, name, false)
                            hidden_groups[#hidden_groups + 1] = name
                        end
                    end
                end
                if host.note then
                    host.note(
                        'preview: gore groups hidden='
                            .. #hidden_groups
                            .. ' groups='
                            .. table.concat(hidden_groups, ',')
                    )
                end
                W.update_unit(world, unit)
                -- Host copies material bindings only after proving source and
                -- destination materials are distinct instances.
                host.copy_materials(piece)
            end
        end)
        if not ok then
            local cleaned, why = pcall(self.destroy, model)
            if not cleaned then
                host.retain_failed(model, tostring(why))
            end
            error(err, 0)
        end
        return model
    end
    function self.destroy(model)
        for i = #model.pieces, 1, -1 do
            local piece = model.pieces[i]
            if U.alive(piece.unit) then
                W.destroy_unit(model.world, piece.unit)
            end
            table.remove(model.pieces, i)
        end
    end
    function self.apply(model, palettes)
        for _, piece in ipairs(model.pieces) do
            assert(U.alive(piece.unit), 'Preview garment disappeared')
            if palettes[piece.kind] then
                host.apply_palette(piece, palettes[piece.kind])
            end
        end
    end
    return self
end
return Model
