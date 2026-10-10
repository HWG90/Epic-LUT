-- Procedural poses on independently owned garment copies. No avatar is spawned,
-- no engine animation graph is entered and no borrowed world is simulated.
local Animation = { MAX_DT = 0.05, MODE = 'garment', CYCLE = 10.3 }
local NAMES = {
    'hips',
    'spine2',
    'chest',
    'neck',
    'head',
    'r_clavicle',
    'l_clavicle',
    'r_shoulder',
    'r_shoulder_twist',
    'r_shoulderarmour',
    'r_elbow',
    'r_hand',
    'r_hand_twist',
    'l_shoulder',
    'l_shoulder_twist',
    'l_shoulderarmour',
    'l_elbow',
    'l_hand',
    'l_hand_twist',
}
for _, side in ipairs({ 'r', 'l' }) do
    for _, finger in ipairs({ 'thumb', 'index', 'middle', 'ring', 'pinky' }) do
        for segment = 1, 3 do
            NAMES[#NAMES + 1] = side .. '_' .. finger .. '_finger' .. segment
        end
    end
end
for i = 1, 8 do
    NAMES[#NAMES + 1] = 'cape' .. i
end
local REQUIRED = {
    Application = { 'worlds' },
    World = { 'units', 'update_unit' },
    Unit = { 'alive', 'num_scene_graph_items', 'has_node', 'node', 'set_local_pose' },
    Matrix4x4 = { 'inverse', 'multiply', 'translation', 'from_quaternion_position' },
    Quaternion = { 'axis_angle' },
    Vector3 = { 'to_elements' },
}
local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end
local function add(a, b)
    return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function sub(a, b)
    return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function scale(a, s)
    return { a[1] * s, a[2] * s, a[3] * s }
end
local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function length(a)
    return math.sqrt(dot(a, a))
end
local function normal(a, fallback)
    local n = length(a)
    if n < 1e-7 then
        assert(fallback, 'Preview animation bone direction is degenerate')
        return fallback
    end
    return scale(a, 1 / n)
end
local function smooth(t)
    return t * t * (3 - 2 * t)
end
local function phase(age)
    if age < 3 then
        return 'standing', age, 0
    elseif age < 4.1 then
        return 'entering', age - 3, smooth((age - 3) / 1.1)
    elseif age < 6.3 then
        return 'saluting', age - 4.1, 1
    elseif age < 7.3 then
        return 'exiting', age - 6.3, 1 - smooth(age - 6.3)
    end
    return 'standing', age - 7.3, 0
end
local function create_authored(E, host, model, manager)
    local C = assert(host.clip_module, 'Authored animation decoder unavailable')
    local dataset = type(host.clips) == 'function' and host.clips() or host.clips
    assert(
        dataset and type(dataset.names) == 'table' and #dataset.names <= 512,
        'Authored animation resources are not ready'
    )
    assert(type(C.sample) == 'function' and type(C.pose) == 'function', 'Authored animation sampler unavailable')
    for name, methods in pairs(REQUIRED) do
        for _, method in ipairs(methods) do
            assert(
                E[name] and type(E[name][method]) == 'function',
                'Authored animation API unavailable: ' .. name .. '.' .. method
            )
        end
    end
    local A, W, U, X, Q = E.Application, E.World, E.Unit, E.Matrix4x4, E.Quaternion
    assert(
        E.Matrix4x4Box
            and model
            and model.world
            and type(model.pieces) == 'table'
            and #model.pieces > 0
            and #model.pieces <= 30,
        'Authored animation model unavailable'
    )
    local world, count = model.world, #model.pieces
    local function live()
        for _, w in ipairs(A.worlds() or {}) do
            if w == world then
                return true
            end
        end
        return false
    end
    assert(live(), 'Authored animation render world disappeared')
    local function box(value)
        return E.Matrix4x4Box(value)
    end
    local function native_pose(m)
        local p, q, scales = C.pose(m)
        local nonunit = false
        for i = 1, 3 do
            assert(
                finite(p[i]) and finite(scales[i]) and scales[i] > 0 and scales[i] <= 128,
                'Unsupported authored garment pose scale'
            )
            nonunit = nonunit or math.abs(scales[i] - 1) >= 0.002
        end
        if q[4] < 0 then
            for i = 1, 4 do
                q[i] = -q[i]
            end
        end
        local sine = math.sqrt(math.max(0, 1 - q[4] * q[4]))
        local axis = { 1, 0, 0 }
        if sine > 1e-7 then
            axis = { q[1] / sine, q[2] / sine, q[3] / sine }
        end
        local rotation =
            Q.axis_angle(E.Vector3(axis[1], axis[2], axis[3]), 2 * math.acos(math.max(-1, math.min(1, q[4]))))
        local value = X.from_quaternion_position(rotation, E.Vector3(p[1], p[2], p[3]))
        if nonunit then
            assert(
                type(X.axis) == 'function' and type(X.set_axis) == 'function',
                'Unsupported authored garment pose scale: matrix axis setter unavailable'
            )
            -- Preserve exact affine rows, including auxiliary attachment scale.
            -- Only this temporary matrix is mutated before any garment write.
            for row = 1, 3 do
                local at = (row - 1) * 4
                X.set_axis(value, row, E.Vector3(m[at + 1], m[at + 2], m[at + 3]))
                local actual = { E.Vector3.to_elements(X.axis(value, row)) }
                for column = 1, 3 do
                    assert(
                        finite(actual[column]) and math.abs(actual[column] - m[at + column]) < 1e-5,
                        'Authored matrix axis constructor differs'
                    )
                end
            end
        end
        return box(value)
    end
    local members = {}
    for _, unit in ipairs(W.units(world) or {}) do
        members[unit] = true
    end
    local maps, reference, total = {}, {}, 0
    local initial = C.sample(dataset, 0)
    for i, piece in ipairs(model.pieces) do
        local unit, n, bind = piece.unit, piece.node_count, piece.animation_bind
        assert(
            unit and unit ~= piece.source and members[unit] and U.alive(unit),
            'Authored garment is not independently owned'
        )
        assert(not piece.source or U.alive(piece.source), 'Equipped source changed; rebuild preview')
        assert(
            finite(n) and n % 1 == 0 and n >= 1 and n <= 512 and U.num_scene_graph_items(unit) == n,
            'Authored garment skeleton changed'
        )
        assert(piece.model_pose and type(piece.model_pose.unbox) == 'function', 'Authored garment basis unavailable')
        local map = {
            piece = piece,
            unit = unit,
            source = piece.source,
            count = n,
            bind = bind,
            basis = piece.model_pose,
            inverse = box(X.inverse(piece.model_pose:unbox())),
            base = {},
            names = {},
            parents = {},
            offsets = {},
        }
        if bind then
            assert(
                bind.node_count == n and type(bind.parents) == 'table' and type(bind.poses) == 'table',
                'Authored garment hierarchy unavailable'
            )
            for node = 1, n do
                assert(
                    bind.poses[node] and type(bind.poses[node].unbox) == 'function',
                    'Authored garment bind pose unavailable'
                )
                map.base[node] = box(X.multiply(bind.poses[node]:unbox(), piece.model_pose:unbox()))
                local parent = bind.parents[node]
                assert(
                    node == 1 or (finite(parent) and parent % 1 == 0 and parent >= 0 and parent <= n and parent ~= node),
                    'Authored garment parent bounds'
                )
                map.parents[node] = node == 1 and 0 or (parent == 0 and 1 or parent)
            end
            for node = 2, n do
                local at, seen = node, {}
                while at ~= 1 do
                    assert(not seen[at], 'Authored garment hierarchy cycle')
                    seen[at], at = true, map.parents[at]
                end
            end
            for _, name in ipairs(dataset.names) do
                if U.has_node(unit, name) then
                    local node = U.node(unit, name)
                    assert(finite(node) and node % 1 == 0 and node >= 1 and node <= n, 'Authored named node bounds')
                    if node > 1 then
                        assert(not map.names[node] and initial[name], 'Authored garment bone mapping differs')
                        native_pose(initial[name]) -- validate math/scale before any pose write
                        map.names[node] = name
                        reference[name] = reference[name] or { map = i, node = node }
                        total = total + 1
                    end
                end
            end
            for node = 2, n do
                if not map.names[node] then
                    local at = map.parents[node]
                    while at ~= 1 and not map.names[at] do
                        at = map.parents[at]
                    end
                    if at ~= 1 then
                        map.offsets[node] = {
                            name = map.names[at],
                            pose = box(X.multiply(map.base[node]:unbox(), X.inverse(map.base[at]:unbox()))),
                        }
                    end
                end
            end
        end
        maps[i] = map
    end
    local anchor_name = reference.boss and 'boss' or (reference.hips and 'hips')
    assert(total > 0 and anchor_name, 'Authored animation needs an owned boss or hips reference')
    local anchor = reference[anchor_name]
    local alignment = box(
        X.multiply(X.inverse(native_pose(initial[anchor_name]):unbox()), maps[anchor.map].base[anchor.node]:unbox())
    )
    local clock = 0
    local session = {
        world = world,
        state = 'ready',
        phase = 'standing',
        age = 0,
        elapsed = 0,
        frames = 0,
        pose_writes = 0,
        salute_available = true,
        mode = 'authored',
        mapped_joints = total,
        anchor = anchor_name,
    }
    function session.stop()
        if session.state ~= 'closed' then
            session.state = 'stopped'
        end
    end
    function session.close()
        session.stop()
        maps = {}
        session.state = 'closed'
        for i = #manager.sessions, 1, -1 do
            if manager.sessions[i] == session then
                table.remove(manager.sessions, i)
            end
        end
        return true
    end
    function session.advance(dt, enabled)
        if enabled == false or session.state ~= 'ready' or not finite(dt) or dt <= 0 then
            return false
        end
        assert(
            session.world == world and model.world == world and #model.pieces == count and live(),
            'Authored render model changed'
        )
        local present = {}
        for _, unit in ipairs(W.units(world) or {}) do
            present[unit] = true
        end
        for i, map in ipairs(maps) do
            local piece = model.pieces[i]
            assert(
                piece == map.piece
                    and piece.unit == map.unit
                    and piece.source == map.source
                    and piece.model_pose == map.basis
                    and piece.animation_bind == map.bind
                    and piece.node_count == map.count
                    and present[map.unit]
                    and U.alive(map.unit)
                    and U.num_scene_graph_items(map.unit) == map.count,
                'Authored garment identity changed'
            )
            assert(not map.source or U.alive(map.source), 'Equipped source changed; rebuild preview')
        end
        clock = clock + math.min(dt, Animation.MAX_DT)
        local sampled, phase, age = C.sample(dataset, clock)
        local common = {}
        for name in pairs(reference) do
            common[name] = box(X.multiply(native_pose(assert(sampled[name])):unbox(), alignment:unbox()))
        end
        -- Authored clips carry all finger rotations. Add only a small separate
        -- cape sway to their resulting poses, without entering cloth simulation.
        for depth = 1, 8 do
            local name = 'cape' .. depth
            if common[name] then
                local p = { E.Vector3.to_elements(X.translation(common[name]:unbox())) }
                local identity = Q.axis_angle(E.Vector3(1, 0, 0), 0)
                local turn =
                    Q.axis_angle(E.Vector3(1, 0, 0), math.sin(clock * 1.8 - depth * 0.42) * (0.006 + depth * 0.0008))
                local delta = box(
                    X.multiply(
                        X.multiply(
                            X.from_quaternion_position(identity, E.Vector3(-p[1], -p[2], -p[3])),
                            X.from_quaternion_position(turn, E.Vector3(0, 0, 0))
                        ),
                        X.from_quaternion_position(identity, E.Vector3(p[1], p[2], p[3]))
                    )
                )
                for later = depth, 8 do
                    local child = 'cape' .. later
                    if common[child] then
                        common[child] = box(X.multiply(common[child]:unbox(), delta:unbox()))
                    end
                end
            end
        end
        local prepared = {}
        for i, map in ipairs(maps) do
            local writes = {}
            for node = 2, map.count do
                local value = map.names[node] and common[map.names[node]]
                if not value and map.offsets[node] then
                    local o = map.offsets[node]
                    value = box(X.multiply(o.pose:unbox(), common[o.name]:unbox()))
                end
                if value then
                    writes[#writes + 1] = { node = node, pose = box(X.multiply(value:unbox(), map.inverse:unbox())) }
                end
            end
            prepared[i] = writes
        end
        local writes = 0
        for i, map in ipairs(maps) do
            for _, write in ipairs(prepared[i]) do
                U.set_local_pose(map.unit, write.node, write.pose:unbox())
                writes = writes + 1
            end
            if #prepared[i] > 0 then
                W.update_unit(world, map.unit)
            end
        end
        session.frames, session.phase, session.age, session.elapsed, session.pose_writes =
            session.frames + 1, phase, age, clock, writes
        if host.log and (session.frames == 1 or phase ~= session.reported_phase) then
            pcall(
                host.log,
                string.format(
                    'preview: authored frame=%d phase=%s elapsed=%.3f writes=%d',
                    session.frames,
                    phase,
                    clock,
                    writes
                )
            )
            session.reported_phase = phase
        end
        return writes > 0
    end
    manager.sessions[#manager.sessions + 1] = session
    if host.log then
        pcall(
            host.log,
            string.format(
                'preview: authored Helldiver clips prepared bones=%d mapped=%d pieces=%d anchor=%s',
                #dataset.names,
                total,
                count,
                anchor_name
            )
        )
    end
    return session
end
function Animation.new(E, host)
    host = host or {}
    local manager = { sessions = {} }
    local A, W, U, X, Q = E.Application, E.World, E.Unit, E.Matrix4x4, E.Quaternion
    local function world_live(world)
        for _, candidate in ipairs(A.worlds() or {}) do
            if candidate == world then
                return true
            end
        end
        return false
    end
    local function boxed(value)
        return E.Matrix4x4Box(value)
    end
    local function position(value)
        local p = { E.Vector3.to_elements(X.translation(value)) }
        assert(#p == 3 and finite(p[1]) and finite(p[2]) and finite(p[3]), 'Preview animation pose is invalid')
        return p
    end
    local function vector(p)
        return E.Vector3(p[1], p[2], p[3])
    end
    local function rotation(axis, angle, pivot)
        local q = Q.axis_angle(vector(axis), angle)
        local identity = Q.axis_angle(vector({ 1, 0, 0 }), 0)
        return boxed(
            X.multiply(
                X.multiply(
                    X.from_quaternion_position(identity, vector(scale(pivot, -1))),
                    X.from_quaternion_position(q, vector({ 0, 0, 0 }))
                ),
                X.from_quaternion_position(identity, vector(pivot))
            )
        )
    end
    local function aim(from, to, amount, pivot)
        local a, b = normal(from), normal(to)
        local d = math.max(-1, math.min(1, dot(a, b)))
        local axis = cross(a, b)
        if length(axis) < 1e-7 then
            if d >= 0 then
                return rotation({ 1, 0, 0 }, 0, pivot)
            end
            axis = cross(a, math.abs(a[3]) < 0.9 and { 0, 0, 1 } or { 0, 1, 0 })
        end
        return rotation(normal(axis), math.acos(d) * amount, pivot)
    end
    local function remove(session)
        for i = #manager.sessions, 1, -1 do
            if manager.sessions[i] == session then
                table.remove(manager.sessions, i)
            end
        end
    end
    function manager.stop()
        for _, session in ipairs(manager.sessions) do
            session.stop()
        end
    end
    function manager.close()
        for i = #manager.sessions, 1, -1 do
            manager.sessions[i].close()
        end
        return true
    end
    function manager.create(render_model)
        assert(#manager.sessions == 0, 'Player Preview animation is already active')
        if host.authored == true then
            return create_authored(E, host, render_model, manager)
        end
        assert(E.Matrix4x4Box, 'Player Preview animation API unavailable: Matrix4x4Box')
        for name, methods in pairs(REQUIRED) do
            for _, method in ipairs(methods) do
                assert(
                    E[name] and type(E[name][method]) == 'function',
                    'Player Preview animation API unavailable: ' .. name .. '.' .. method
                )
            end
        end
        -- The game's constructors can be callable native objects rather than
        -- Lua functions/tables. Exercise only the already used math APIs.
        position(rotation({ 1, 0, 0 }, 0, { 0, 0, 0 }):unbox())
        assert(
            render_model
                and render_model.world
                and type(render_model.pieces) == 'table'
                and #render_model.pieces > 0
                and #render_model.pieces <= 30,
            'Player Preview animation model is incomplete'
        )
        local world, piece_count = render_model.world, #render_model.pieces
        assert(world_live(world), 'Player Preview render world disappeared')
        local members = {}
        for _, unit in ipairs(W.units(world) or {}) do
            members[unit] = true
        end
        local maps, moving, can_salute = {}, 0, false
        for _, piece in ipairs(render_model.pieces) do
            local unit, count, bind = piece.unit, piece.node_count, piece.animation_bind
            assert(
                unit and unit ~= piece.source and members[unit] and U.alive(unit),
                'Preview animation garment is not independently owned'
            )
            assert(not piece.source or U.alive(piece.source), 'Equipped source changed; rebuild preview')
            assert(
                finite(count)
                    and count % 1 == 0
                    and count >= 1
                    and count <= 512
                    and U.num_scene_graph_items(unit) == count,
                'Preview animation garment skeleton changed'
            )
            assert(
                piece.model_pose and type(piece.model_pose.unbox) == 'function',
                'Preview animation garment basis unavailable'
            )
            local map = {
                piece = piece,
                unit = unit,
                source = piece.source,
                count = count,
                pose = piece.model_pose,
                bind = bind,
                inverse = boxed(X.inverse(piece.model_pose:unbox())),
                poses = {},
                parents = {},
                nodes = {},
                trees = {},
            }
            if bind then
                assert(
                    bind.node_count == count and type(bind.parents) == 'table' and type(bind.poses) == 'table',
                    piece.animation_error or 'Preview animation garment hierarchy unavailable'
                )
                for i = 1, count do
                    local base = bind.poses[i]
                    assert(base and type(base.unbox) == 'function', 'Preview animation bind pose unavailable')
                    map.poses[i] = boxed(X.multiply(base:unbox(), piece.model_pose:unbox()))
                    position(map.poses[i]:unbox())
                    local parent = bind.parents[i]
                    assert(
                        i == 1
                            or (finite(parent) and parent % 1 == 0 and parent >= 0 and parent <= count and parent ~= i),
                        'Preview animation parent bounds changed'
                    )
                    -- Additional authored roots are independent trees. Their
                    -- existing rendered copies have already been linked to 1.
                    map.parents[i] = i == 1 and 0 or (parent == 0 and 1 or parent)
                end
                for i = 2, count do
                    local at, visited = i, {}
                    while at ~= 1 do
                        assert(not visited[at], 'Preview animation hierarchy contains a cycle')
                        visited[at], at = true, map.parents[at]
                    end
                end
                local used = {}
                for _, name in ipairs(NAMES) do
                    if U.has_node(unit, name) then
                        local index = U.node(unit, name)
                        assert(
                            finite(index) and index % 1 == 0 and index > 1 and index <= count and not used[index],
                            'Preview animation named node bounds changed'
                        )
                        map.nodes[name], used[index] = index, true
                        local tree = {}
                        for i = 2, count do
                            local at = i
                            while at ~= 1 do
                                if at == index then
                                    tree[#tree + 1] = i
                                    break
                                end
                                at = map.parents[at]
                            end
                        end
                        map.trees[index] = tree
                    end
                end
                local n = map.nodes
                local function descendant(child, parent)
                    for _, candidate in ipairs(map.trees[parent] or {}) do
                        if candidate == child then
                            return true
                        end
                    end
                    return false
                end
            end
            maps[#maps + 1] = map
        end
        -- Clothing is segmented in the real model: a helmet supplies head,
        -- while torso, upper arm, forearm and glove can each expose only part
        -- of the same skeleton. Resolve joint poses across all owned pieces.
        local joints, cape_count = {}, 0
        local function include(map, set, index)
            for _, child in ipairs(map.trees[index] or {}) do
                set[child] = true
            end
        end
        for i, map in ipairs(maps) do
            map.body, map.upper, map.lower, map.capes = {}, {}, {}, {}
            for depth = 1, 8 do
                map.capes[depth] = {}
            end
            for name, index in pairs(map.nodes) do
                if not joints[name] then
                    joints[name] = { map = i, node = index }
                end
                if name ~= 'hips' then
                    include(map, map.body, index)
                end
                local lower = name == 'r_elbow'
                    or name == 'r_hand'
                    or name == 'r_hand_twist'
                    or name:match('^r_.+_finger%d$')
                local upper = lower or name == 'r_shoulder' or name == 'r_shoulder_twist' or name == 'r_shoulderarmour'
                if upper then
                    include(map, map.upper, index)
                end
                if lower then
                    include(map, map.lower, index)
                end
                local cape = tonumber(name:match('^cape(%d)$'))
                if cape then
                    cape_count = cape_count + 1
                    -- A later cape segment can live in a different garment.
                    -- It still receives every earlier joint's rigid transform.
                    for depth = 1, cape do
                        include(map, map.capes[depth], index)
                    end
                end
            end
            if next(map.body) then
                moving = moving + 1
            end
        end
        local function joint(name, poses)
            local ref = assert(joints[name], 'Preview animation joint unavailable: ' .. name)
            local map = maps[ref.map]
            return position(((poses and poses[ref.map][ref.node]) or map.poses[ref.node]):unbox())
        end
        can_salute = joints.head ~= nil and joints.r_shoulder ~= nil and joints.r_elbow ~= nil and joints.r_hand ~= nil
        local upper_length, lower_length
        if can_salute then
            local shoulder, elbow, hand = joint('r_shoulder'), joint('r_elbow'), joint('r_hand')
            upper_length, lower_length = length(sub(elbow, shoulder)), length(sub(hand, elbow))
            assert(upper_length > 1e-4 and lower_length > 1e-4, 'Preview animation arm is degenerate')
            assert(length(sub(joint('head'), shoulder)) > 1e-4, 'Preview animation head is degenerate')
        end
        assert(can_salute or cape_count > 0, 'Player Preview garments have no supported arm or cape chain')
        local joint_count = 0
        for _ in pairs(joints) do
            joint_count = joint_count + 1
        end
        local session = {
            world = world,
            phase = 'standing',
            age = 0,
            state = 'ready',
            salute_available = can_salute,
            animated_pieces = moving,
            mapped_joints = joint_count,
            cape_nodes = cape_count,
            frames = 0,
            pose_writes = 0,
            elapsed = 0,
        }
        local clock = 0
        function session.stop()
            if session.state ~= 'closed' then
                session.state = 'stopped'
            end
        end
        function session.close()
            -- The model owns native garments and their fence. This service owns
            -- only Lua pose boxes, so retirement never writes to a lost world.
            session.stop()
            maps = {}
            session.state, session.error = 'closed', nil
            remove(session)
            return true
        end
        local function frames(amount)
            local poses = {}
            for i = 1, #maps do
                poses[i] = {}
            end
            local spine = joints.chest and 'chest' or (joints.hips and 'hips')
            local up = joints.head and spine and normal(sub(joint('head'), joint(spine)), { 0, 0, 1 }) or { 0, 0, 1 }
            local fallback = math.abs(up[1]) < 0.9 and { 1, 0, 0 } or { 0, 1, 0 }
            local right = joints.r_shoulder and spine and sub(joint('r_shoulder'), joint(spine)) or fallback
            right = normal(sub(right, scale(up, dot(right, up))), normal(cross(fallback, up)))
            local forward = normal(cross(up, right), { 0, 1, 0 })
            local function apply(region, delta, depth)
                for i, map in ipairs(maps) do
                    local selected = depth and map.capes[depth] or map[region]
                    for node = 2, map.count do
                        if selected[node] then
                            poses[i][node] =
                                boxed(X.multiply((poses[i][node] or map.poses[node]):unbox(), delta:unbox()))
                        end
                    end
                end
            end
            if joints.chest then
                apply('body', rotation(right, math.sin(clock * 1.5) * 0.006, joint('chest')))
            end
            if can_salute and amount > 0 then
                local shoulder, elbow, hand, head =
                    joint('r_shoulder', poses), joint('r_elbow', poses), joint('r_hand', poses), joint('head', poses)
                local width = length(sub(shoulder, head))
                local target = add(add(head, scale(right, width * 0.22)), scale(forward, width * 0.35))
                target = sub(target, scale(up, width * 0.09))
                local direction = normal(sub(target, shoulder))
                local reach = math.max(
                    math.abs(upper_length - lower_length) + 1e-5,
                    math.min(upper_length + lower_length - 1e-5, length(sub(target, shoulder)))
                )
                target = add(shoulder, scale(direction, reach))
                local preferred = add(scale(right, 0.8), scale(up, -0.45))
                local plane = sub(preferred, scale(direction, dot(preferred, direction)))
                if length(plane) < 1e-6 then
                    plane = sub(sub(elbow, shoulder), scale(direction, dot(sub(elbow, shoulder), direction)))
                end
                plane = normal(plane, forward)
                local along = (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2 * reach)
                local solved_elbow = add(
                    add(shoulder, scale(direction, along)),
                    scale(plane, math.sqrt(math.max(0, upper_length * upper_length - along * along)))
                )
                apply('upper', aim(sub(elbow, shoulder), sub(solved_elbow, shoulder), amount, shoulder))
                elbow, hand = joint('r_elbow', poses), joint('r_hand', poses)
                apply('lower', aim(sub(hand, elbow), sub(target, elbow), amount, elbow))
            end
            for depth = 1, 8 do
                local name = 'cape' .. depth
                if joints[name] then
                    local angle = math.sin(clock * 1.8 - depth * 0.42) * (0.009 + depth * 0.0012)
                    angle = angle + math.sin(clock * 0.9) * amount * 0.006
                    apply('capes', rotation(right, angle, joint(name, poses)), depth)
                end
            end
            local result = {}
            for i, map in ipairs(maps) do
                local writes = {}
                for node = 2, map.count do
                    if poses[i][node] then
                        writes[#writes + 1] =
                            { node = node, pose = boxed(X.multiply(poses[i][node]:unbox(), map.inverse:unbox())) }
                    end
                end
                result[i] = writes
            end
            return result
        end
        function session.advance(dt, enabled)
            if enabled == false or session.state ~= 'ready' or not finite(dt) or dt <= 0 then
                return false
            end
            assert(
                session.world == world
                    and render_model.world == world
                    and world_live(world)
                    and #render_model.pieces == piece_count,
                'Preview animation render model changed'
            )
            local present = {}
            for _, unit in ipairs(W.units(world) or {}) do
                present[unit] = true
            end
            -- Validate every identity before preparing or writing any pose.
            for i, map in ipairs(maps) do
                local piece = render_model.pieces[i]
                assert(
                    piece == map.piece
                        and piece.unit == map.unit
                        and piece.source == map.source
                        and piece.model_pose == map.pose
                        and piece.animation_bind == map.bind
                        and piece.node_count == map.count
                        and present[map.unit]
                        and U.alive(map.unit)
                        and U.num_scene_graph_items(map.unit) == map.count,
                    'Preview animation garment changed'
                )
                assert(not map.source or U.alive(map.source), 'Equipped source changed; rebuild preview')
            end
            clock = (clock + math.min(dt, Animation.MAX_DT)) % Animation.CYCLE
            local amount
            session.phase, session.age, amount = phase(clock)
            local prepared, changed, writes = frames(amount), false, 0
            for i, map in ipairs(maps) do
                for _, write in ipairs(prepared[i]) do
                    U.set_local_pose(map.unit, write.node, write.pose:unbox())
                    writes = writes + 1
                end
                if #prepared[i] > 0 then
                    W.update_unit(world, map.unit)
                    changed = true
                end
            end
            session.frames, session.pose_writes, session.elapsed = session.frames + 1, writes, clock
            if host.log and (session.frames == 1 or session.reported_phase ~= session.phase) then
                pcall(
                    host.log,
                    string.format(
                        'preview: garment pose frame=%d phase=%s elapsed=%.3f writes=%d salute=%s dt=%.4f',
                        session.frames,
                        session.phase,
                        clock,
                        writes,
                        tostring(can_salute),
                        math.min(dt, Animation.MAX_DT)
                    )
                )
                session.reported_phase = session.phase
            end
            return changed
        end
        manager.sessions[#manager.sessions + 1] = session
        if host.log then
            pcall(
                host.log,
                string.format(
                    'preview: garment poses prepared pieces=%d animated=%d joints=%d salute=%s cape_nodes=%d',
                    piece_count,
                    moving,
                    joint_count,
                    tostring(can_salute),
                    cape_count
                )
            )
        end
        return session
    end
    return manager
end
return Animation
