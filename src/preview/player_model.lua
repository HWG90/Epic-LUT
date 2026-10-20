-- Independent visual copy of equipped garment units. No avatar/network entity is
-- registered and no player, Armory actor or thumbnail scheduler is modified.
local Model = {}
-- Exact garment mesh names from the maintained binding-name catalog. Caps,
-- shadows, limbs and similarly named meshes are not inferred from these names.
local gore_meshes = { 'g_gore', 'g_gore_LOD1', 'g_gore_LOD2', 'g_gore_LOD3' }
function Model.new(E, host)
    local A, W, U, X = E.Application, E.World, E.Unit, E.Matrix4x4
    local self = {}
    local function hide_gore_meshes(unit, count)
        local hidden, skipped = {}, {}
        if
            type(U.has_mesh) ~= 'function'
            or type(U.mesh) ~= 'function'
            or type(U.set_mesh_visibility) ~= 'function'
        then
            return hidden, 'named mesh APIs unavailable'
        end
        local indexed = {}
        for index = 1, count do
            local ok, mesh = pcall(U.mesh, unit, index)
            if ok then
                indexed[index] = mesh
            end
        end
        local written = {}
        for _, name in ipairs(gore_meshes) do
            local ok, exists = pcall(U.has_mesh, unit, name)
            if not ok then
                skipped[#skipped + 1] = name .. ':name lookup unavailable'
            elseif exists == true or exists == 1 then
                local got, mesh = pcall(U.mesh, unit, name)
                local match, matches = nil, 0
                if got and mesh and mesh ~= 0 then
                    for index = 1, count do
                        if indexed[index] == mesh then
                            match, matches = index, matches + 1
                        end
                    end
                end
                if matches == 1 then
                    if not written[match] then
                        local changed, result = pcall(U.set_mesh_visibility, unit, match, false)
                        if changed and result ~= false then
                            written[match] = true
                            hidden[#hidden + 1] = name
                        else
                            skipped[#skipped + 1] = name .. ':visibility unavailable'
                        end
                    end
                else
                    skipped[#skipped + 1] = name .. (matches == 0 and ':unmapped handle' or ':ambiguous handle')
                end
            end
        end
        return hidden, #skipped > 0 and table.concat(skipped, ',') or nil
    end
    local function capture_animation_bind(unit, spec)
        assert(type(U.scene_graph_parent) == 'function', 'Preview animation hierarchy API unavailable')
        local bind = { parents = { [1] = 0 }, poses = {}, node_count = spec.node_count }
        -- Read the authored graph only from the newly owned unit, before its
        -- nodes are flattened. Source graph links can belong to another unit.
        bind.poses[1] = E.Matrix4x4Box(X.multiply(spec.pose:unbox(), X.inverse(spec.pose:unbox())))
        for i = 2, spec.node_count do
            local parent = U.scene_graph_parent(unit, i)
            if parent == nil then
                parent = 0
            end
            assert(
                type(parent) == 'number'
                    and parent % 1 == 0
                    and parent >= 0
                    and parent <= spec.node_count
                    and parent ~= i,
                'Preview animation parent bounds changed'
            )
            bind.parents[i] = parent
            bind.poses[i] = E.Matrix4x4Box(spec.nodes[i]:unbox())
        end
        for i = 2, spec.node_count do
            local at, visited = i, {}
            while at ~= 1 and at ~= 0 do
                assert(not visited[at], 'Preview animation hierarchy contains a cycle')
                visited[at], at = true, bind.parents[at]
            end
        end
        return bind
    end
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
                local piece = {
                    unit = unit,
                    source = spec.source,
                    kind = spec.kind,
                    slot = spec.slot,
                    model_pose = spec.pose,
                    node_count = spec.node_count,
                }
                model.pieces[#model.pieces + 1] = piece
                assert(unit ~= spec.source, 'Preview reused the source unit')
                U.disable_physics(unit)
                if U.has_animation_state_machine(unit) then
                    U.disable_animation_state_machine(unit)
                end
                assert(U.num_scene_graph_items(unit) == spec.node_count, 'Preview skeleton differs')
                if host.animate == true or host.capture_animation == true then
                    local captured, bind = pcall(capture_animation_bind, unit, spec)
                    if captured then
                        piece.animation_bind = bind
                    else
                        -- An unsupported hierarchy leaves the existing static
                        -- garment usable; the optional driver reports why.
                        piece.animation_error = tostring(bind)
                    end
                end
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
                -- Native material commits can reveal damage meshes. Resolve
                -- catalog names on this owned copy only after those commits.
                local hidden_meshes, reason = hide_gore_meshes(unit, #spec.visible)
                if host.note then
                    host.note(
                        'preview: gore meshes hidden='
                            .. #hidden_meshes
                            .. ' meshes='
                            .. table.concat(hidden_meshes, ',')
                            .. (reason and ' skipped=' .. reason or '')
                    )
                end
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
        local changed = false
        for _, piece in ipairs(model.pieces) do
            assert(U.alive(piece.unit), 'Preview garment disappeared')
            if palettes[piece.kind] then
                changed = host.apply_palette(piece, palettes[piece.kind]) == true or changed
            end
        end
        return changed
    end
    return self
end
return Model
