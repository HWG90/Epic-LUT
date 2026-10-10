-- Real three-dimensional affine math, deliberately unequal garment node indices,
-- and temporary native-style matrices which expire at scene updates.
local Animation = dofile('src/preview/player_animation.lua')
local function copy(a)
    local b = {}
    for i, value in ipairs(a) do
        b[i] = value
    end
    return b
end
local function identity()
    return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end
local function multiply(a, b)
    local out = {}
    for r = 0, 3 do
        for c = 0, 3 do
            local value = 0
            for k = 0, 3 do
                value = value + a[r * 4 + k + 1] * b[k * 4 + c + 1]
            end
            out[r * 4 + c + 1] = value
        end
    end
    return out
end
local function inverse(a)
    local rows = {}
    for r = 1, 4 do
        rows[r] = {}
        for c = 1, 4 do
            rows[r][c] = a[(r - 1) * 4 + c]
            rows[r][c + 4] = r == c and 1 or 0
        end
    end
    for c = 1, 4 do
        local at = c
        for r = c + 1, 4 do
            if math.abs(rows[r][c]) > math.abs(rows[at][c]) then
                at = r
            end
        end
        rows[c], rows[at] = rows[at], rows[c]
        local pivot = rows[c][c]
        assert(math.abs(pivot) > 1e-9, 'Singular test pose')
        for k = 1, 8 do
            rows[c][k] = rows[c][k] / pivot
        end
        for r = 1, 4 do
            if r ~= c then
                local ratio = rows[r][c]
                for k = 1, 8 do
                    rows[r][k] = rows[r][k] - ratio * rows[c][k]
                end
            end
        end
    end
    local result = {}
    for r = 1, 4 do
        for c = 1, 4 do
            result[(r - 1) * 4 + c] = rows[r][c + 4]
        end
    end
    return result
end
local function pose(angle, position, axis)
    local p = identity()
    axis = axis or { 0, 0, 1 }
    position = position or { 0, 0, 0 }
    local x, y, z = axis[1], axis[2], axis[3]
    local c, s = math.cos(angle), math.sin(angle)
    local t = 1 - c
    p[1], p[2], p[3] = c + x * x * t, x * y * t + z * s, x * z * t - y * s
    p[5], p[6], p[7] = x * y * t - z * s, c + y * y * t, y * z * t + x * s
    p[9], p[10], p[11] = x * z * t + y * s, y * z * t - x * s, c + z * z * t
    p[13], p[14], p[15] = position[1], position[2], position[3]
    return p
end
local function position(p)
    return { p[13], p[14], p[15] }
end
local function distance(a, b)
    local s = 0
    for i = 1, 3 do
        s = s + (a[i] - b[i]) ^ 2
    end
    return math.sqrt(s)
end
local function near(a, b, tolerance)
    for i = 1, #a do
        assert(math.abs(a[i] - b[i]) < (tolerance or 1e-8), '3D pose differs at ' .. i)
    end
end
local function fixture()
    local f = { writes = {}, updates = 0, lookups = 0 }
    local main = { alive = true, units = {} }
    local render = { alive = true, units = {} }
    f.main, f.render = main, render
    local E = { Application = {}, World = {}, Unit = {}, Matrix4x4 = {}, Quaternion = {} }
    f.E = E
    local U, W, X = E.Unit, E.World, E.Matrix4x4
    local temporaries = {}
    local function temporary(p)
        temporaries[#temporaries + 1] = p
        return p
    end
    function f.recycle()
        for _, p in ipairs(temporaries) do
            for i = 1, #p do
                p[i] = 0 / 0
            end
        end
        temporaries = {}
    end
    X.multiply = function(a, b)
        return temporary(multiply(a, b))
    end
    X.inverse = function(p)
        return temporary(inverse(p))
    end
    X.translation = function(p)
        return { p[13], p[14], p[15] }
    end
    X.from_quaternion_position = function(q, p)
        return temporary(pose(q.angle, p, q.axis))
    end
    E.Quaternion.axis_angle = function(axis, angle)
        return { axis = copy(axis), angle = angle }
    end
    E.Vector3 = setmetatable({
        to_elements = function(p)
            return p[1], p[2], p[3]
        end,
    }, {
        __call = function(_, x, y, z)
            return { x, y, z }
        end,
    })
    E.Matrix4x4Box = function(p)
        local saved = copy(p)
        return {
            unbox = function()
                return temporary(copy(saved))
            end,
        }
    end
    function E.Application.worlds()
        return render.alive and { main, render } or { main }
    end
    function W.units(world)
        assert(world == render and render.alive)
        return render.units
    end
    function W.update_unit(world, unit)
        assert(world == render and not unit.source, 'Borrowed gameplay unit updated')
        f.updates = f.updates + 1
        if f.recycle_between_pieces then
            f.recycle()
        end
    end
    for _, api in ipairs({ 'new_world', 'release_world' }) do
        E.Application[api] = function()
            error('Extra native world touched')
        end
    end
    for _, api in ipairs({ 'spawn_unit', 'destroy_unit', 'update', 'update_animations', 'update_scene' }) do
        W[api] = function()
            error('Native animation/simulation touched')
        end
    end
    for _, api in ipairs({ 'animation_event', 'has_animation_event', 'enable_animation_state_machine' }) do
        U[api] = function()
            error('Native state machine touched')
        end
    end
    function U.alive(unit)
        return unit.alive
    end
    function U.num_scene_graph_items(unit)
        assert(not unit.source)
        return unit.count
    end
    function U.has_node(unit, name)
        assert(not unit.source)
        f.lookups = f.lookups + 1
        return unit.names[name] ~= nil
    end
    function U.node(unit, name)
        assert(not unit.source)
        f.lookups = f.lookups + 1
        return assert(unit.names[name])
    end
    function U.set_local_pose(unit, index, p)
        assert(not unit.source and index > 1 and index <= unit.count, 'Source or portrait root changed')
        local saved = copy(p)
        for _, v in ipairs(saved) do
            assert(v == v, 'Expired native pose used')
        end
        unit.poses[index] = saved
        f.writes[#f.writes + 1] = { unit = unit, index = index, pose = saved }
    end
    local names = {
        hips = 2,
        chest = 3,
        neck = 4,
        head = 5,
        r_shoulder = 6,
        r_elbow = 7,
        r_hand = 8,
        cape1 = 10,
        cape2 = 11,
        cape3 = 12,
    }
    local parents = { 0, 1, 2, 3, 4, 3, 6, 7, 8, 3, 10, 11 }
    local points = {
        { 0, 0, 0 },
        { 0, 0, 1 },
        { 0, 0, 1.4 },
        { 0, 0, 1.65 },
        { 0, 0, 1.82 },
        { 0.3, 0, 1.55 },
        { 0.55, 0, 1.22 },
        { 0.66, 0, 0.91 },
        { 0.70, 0, 0.86 },
        { 0, -0.12, 1.45 },
        { 0, -0.15, 1.1 },
        { 0, -0.18, 0.75 },
    }
    local function piece(basis, remap)
        local source = { alive = true, source = true }
        main.units[#main.units + 1] = source
        local unit = { alive = true, count = 12, names = {}, poses = {}, root = pose(0.6, { 100, 2, 5 }) }
        local bind = { node_count = 12, parents = {}, poses = {} }
        local inv = inverse(basis)
        for i = 1, 12 do
            local index = remap and remap[i] or i
            local parent = parents[i]
            bind.parents[index] = parent == 0 and 0 or (remap and remap[parent] or parent)
            local p = multiply(pose(0, points[i]), inv)
            bind.poses[index] = E.Matrix4x4Box(p)
            unit.poses[index] = copy(p)
        end
        for name, index in pairs(names) do
            unit.names[name] = remap and remap[index] or index
        end
        render.units[#render.units + 1] = unit
        return {
            unit = unit,
            source = source,
            model_pose = E.Matrix4x4Box(basis),
            node_count = 12,
            animation_bind = bind,
        }
    end
    local armor = piece(identity())
    local reversed = { 1, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2 }
    local cape = piece(pose(0.4, { 0.06, 0.04, 0.03 }), reversed)
    f.armor, f.cape = armor, cape
    f.model = { world = render, pieces = { armor, cape } }
    f.manager = Animation.new(E)
    function f.point(piece, name)
        return position(multiply(piece.unit.poses[piece.unit.names[name]], piece.model_pose:unbox()))
    end
    function f.step(session, seconds)
        for _ = 1, math.floor(seconds / 0.05 + 0.5) do
            assert(session.advance(0.05, true))
        end
    end
    return f
end
local f = fixture()
local session = f.manager.create(f.model)
assert(session.salute_available and #f.manager.sessions == 1 and session.world == f.render)
local roots = { copy(f.armor.unit.root), copy(f.cape.unit.root) }
local upper = distance(f.point(f.armor, 'r_shoulder'), f.point(f.armor, 'r_elbow'))
local lower = distance(f.point(f.armor, 'r_elbow'), f.point(f.armor, 'r_hand'))
local cape_length = distance(f.point(f.cape, 'cape1'), f.point(f.cape, 'cape2'))
local initial_tip = f.point(f.cape, 'cape3')
local initial_hand = f.point(f.armor, 'r_hand')
local lookups = f.lookups
f.recycle()
f.recycle_between_pieces = true
assert(session.advance(0.016, true))
assert(f.lookups == lookups, 'Named bone map was rebuilt every frame')
assert(distance(initial_tip, f.point(f.cape, 'cape3')) > 0.0001, 'Cape chain did not move')
for _ = 1, 90 do
    assert(session.advance(0.05, true))
    assert(
        math.abs(distance(f.point(f.armor, 'r_shoulder'), f.point(f.armor, 'r_elbow')) - upper) < 1e-8,
        'Upper arm stretched'
    )
    assert(
        math.abs(distance(f.point(f.armor, 'r_elbow'), f.point(f.armor, 'r_hand')) - lower) < 1e-8,
        'Forearm stretched'
    )
    assert(
        math.abs(distance(f.point(f.cape, 'cape1'), f.point(f.cape, 'cape2')) - cape_length) < 1e-8,
        'Cape bone stretched'
    )
end
assert(session.phase == 'saluting', 'Standing-enter-hold phase schedule failed')
assert(distance(f.point(f.armor, 'r_hand'), f.point(f.armor, 'head')) < 0.2, 'Saluting hand missed the head')
assert(distance(initial_hand, f.point(f.armor, 'r_hand')) > 0.7, 'Arm stayed in its captured static pose')
near(f.point(f.armor, 'r_hand'), f.point(f.cape, 'r_hand'))
near(f.point(f.armor, 'cape3'), f.point(f.cape, 'cape3'))
near(f.armor.unit.root, roots[1])
near(f.cape.unit.root, roots[2])
local writes, updates, age, phase = #f.writes, f.updates, session.age, session.phase
local frozen = copy(f.armor.unit.poses[f.armor.unit.names.r_hand])
f.armor.unit.root = pose(-0.9, { 100, -4, 7 })
assert(
    not session.advance(10, false)
        and #f.writes == writes
        and f.updates == updates
        and session.age == age
        and session.phase == phase,
    'Pause advanced the pose'
)
near(f.armor.unit.poses[f.armor.unit.names.r_hand], frozen)
for _, dt in ipairs({ 0, -1, 0 / 0, math.huge, -math.huge, 'bad' }) do
    assert(not session.advance(dt, true))
end
assert(not session.advance(nil, true) and #f.writes == writes)
assert(session.advance(1000, true) and session.age - age < 0.051, 'Resume caught up a long suspended frame')
local moved_root = copy(f.armor.unit.root)
f.step(session, 3)
assert(session.phase == 'standing', 'Exit did not return to standing')
near(f.armor.unit.root, moved_root)
f.manager.stop()
writes = #f.writes
assert(not session.advance(0.05, true) and #f.writes == writes, 'Stop wrote a pose before quiescence')
f.render.alive = false
assert(
    f.manager.close() and session.close() and #f.manager.sessions == 0 and #f.writes == writes,
    'Pure Lua retirement touched native garments'
)

-- Capability and hierarchy failures reject before any pose or scene write.
for _, fault in ipairs({
    'api',
    'box',
    'vector',
    'basis',
    'cycle',
    'parent',
    'node',
    'owned',
    'source',
    'world',
    'count',
    'empty',
}) do
    local b = fixture()
    if fault == 'api' then
        b.E.Quaternion.axis_angle = nil
    elseif fault == 'box' then
        b.E.Matrix4x4Box = nil
    elseif fault == 'vector' then
        setmetatable(b.E.Vector3, nil)
    elseif fault == 'basis' then
        b.armor.model_pose = nil
    elseif fault == 'cycle' then
        b.armor.animation_bind.parents[6] = 7
    elseif fault == 'parent' then
        b.armor.animation_bind.parents[6] = 999
    elseif fault == 'node' then
        b.armor.unit.names.r_hand = 513
    elseif fault == 'owned' then
        b.armor.unit = b.armor.source
    elseif fault == 'source' then
        b.armor.source.alive = false
    elseif fault == 'world' then
        b.render.alive = false
    elseif fault == 'count' then
        b.armor.unit.count = 999
    else
        b.model.pieces = {}
    end
    assert(not pcall(b.manager.create, b.model), 'Unsupported animation succeeded: ' .. fault)
    assert(#b.writes == 0 and b.updates == 0 and #b.manager.sessions == 0, 'Failed constructor changed native state')
end
for _, fault in ipairs({ 'unit', 'source', 'membership', 'count', 'world', 'bind', 'public' }) do
    local b = fixture()
    local active = b.manager.create(b.model)
    if fault == 'unit' then
        b.armor.unit = b.armor.source
    elseif fault == 'source' then
        b.cape.source.alive = false
    elseif fault == 'membership' then
        b.render.units = { b.cape.unit }
    elseif fault == 'count' then
        b.cape.unit.count = 10
    elseif fault == 'world' then
        b.render.alive = false
    elseif fault == 'bind' then
        b.cape.animation_bind = {}
    else
        active.world = b.main
    end
    assert(not pcall(active.advance, 0.016, true), 'Stale animation identity accepted: ' .. fault)
    assert(#b.writes == 0 and b.updates == 0, 'Preflight changed a garment before finding stale peer')
    assert(active.close() and #b.manager.sessions == 0, 'Stale world blocked pure Lua cleanup')
end
-- Bind snapshots are private, and optional arm/cape names on another piece do
-- not disable a valid armor chain.
local optional = fixture()
optional.cape.unit.names = { head = optional.cape.unit.names.head }
local supported = optional.manager.create(optional.model)
assert(supported.advance(0.016, true) and supported.salute_available)
assert(supported.close())
local partial = fixture()
partial.cape.animation_bind = nil
partial.cape.animation_error = 'Optional mesh hierarchy unavailable'
local available = partial.manager.create(partial.model)
assert(available.advance(0.016, true) and available.salute_available, 'Optional mesh metadata disabled valid armor')
assert(available.close())
local forest = fixture()
forest.armor.animation_bind.parents[3] = 0
local separate_root = forest.manager.create(forest.model)
assert(separate_root.advance(0.016, true), 'Additional authored root disabled valid arm chain')
assert(separate_root.close())
local immutable = fixture()
local copied = immutable.manager.create(immutable.model)
immutable.armor.animation_bind.poses[8] = immutable.E.Matrix4x4Box(pose(0, { 500, 500, 500 }))
immutable.armor.animation_bind.parents[8] = 500
immutable.step(copied, 4.5)
assert(
    distance(immutable.point(immutable.armor, 'r_hand'), immutable.point(immutable.armor, 'head')) < 0.2,
    'Mutable public bind data redirected an owned pose'
)
assert(copied.close())

-- The live equipment model is segmented: head, shoulder, elbow and hand live
-- in different units. No single garment below exposes a complete arm chain.
local split = fixture()
local function segment(definition, basis)
    local source = { alive = true, source = true }
    local unit = { alive = true, count = #definition + 1, names = {}, poses = {}, root = pose(0.6, { 100, 2, 5 }) }
    local bind = { node_count = unit.count, parents = { [1] = 0 }, poses = { split.E.Matrix4x4Box(identity()) } }
    unit.poses[1] = identity()
    local inv = inverse(basis)
    for i, spec in ipairs(definition) do
        local node = i + 1
        unit.names[spec[1]] = node
        bind.parents[node] = spec[3] or 1
        local local_pose = multiply(pose(0, spec[2]), inv)
        bind.poses[node] = split.E.Matrix4x4Box(local_pose)
        unit.poses[node] = copy(local_pose)
    end
    return {
        unit = unit,
        source = source,
        model_pose = split.E.Matrix4x4Box(basis),
        node_count = unit.count,
        animation_bind = bind,
    }
end
split.model.pieces = {
    segment({ { 'chest', { 0, 0, 1.4 } }, { 'r_shoulder', { 0.3, 0, 1.55 }, 2 } }, identity()),
    segment(
        { { 'r_shoulder', { 0.3, 0, 1.55 } }, { 'r_elbow', { 0.55, 0, 1.22 }, 2 } },
        pose(0.3, { 0.05, 0.02, 0.03 })
    ),
    segment(
        { { 'r_elbow', { 0.55, 0, 1.22 } }, { 'r_hand', { 0.66, 0, 0.91 }, 2 } },
        pose(-0.2, { -0.04, 0.02, 0.05 })
    ),
    segment(
        { { 'r_hand', { 0.66, 0, 0.91 } }, { 'r_index_finger1', { 0.70, 0, 0.86 }, 2 } },
        pose(0.5, { 0.04, -0.01, 0.01 })
    ),
    segment({ { 'neck', { 0, 0, 1.65 } }, { 'head', { 0, 0, 1.82 }, 2 } }, pose(-0.4, { 0.01, 0.03, 0.06 })),
    segment(
        { { 'cape1', { 0, -0.12, 1.45 } }, { 'cape2', { 0, -0.15, 1.1 }, 2 }, { 'cape3', { 0, -0.18, 0.75 }, 3 } },
        pose(0.2, { -0.02, 0.03, 0.01 })
    ),
}
split.render.units = {}
local split_roots = {}
for i, piece in ipairs(split.model.pieces) do
    split.render.units[i], split_roots[i] = piece.unit, copy(piece.unit.root)
end
local function shared_point(name)
    for _, piece in ipairs(split.model.pieces) do
        if piece.unit.names[name] then
            return split.point(piece, name)
        end
    end
    error('Missing split joint')
end
local logs = {}
split.manager = Animation.new(split.E, {
    log = function(message)
        logs[#logs + 1] = message
    end,
})
local shared = split.manager.create(split.model)
assert(shared.salute_available and shared.animated_pieces == 6, 'Split garments silently enabled cape-only playback')
assert(logs[1]:find('salute=true', 1, true), 'Prepared diagnostics omitted actual arm support')
local split_upper = distance(shared_point('r_shoulder'), shared_point('r_elbow'))
local split_lower = distance(shared_point('r_elbow'), shared_point('r_hand'))
local split_tip = shared_point('cape3')
split.recycle_between_pieces = true
for _ = 1, 90 do
    assert(shared.advance(0.05, true))
    assert(math.abs(distance(shared_point('r_shoulder'), shared_point('r_elbow')) - split_upper) < 1e-8)
    assert(math.abs(distance(shared_point('r_elbow'), shared_point('r_hand')) - split_lower) < 1e-8)
end
assert(shared.phase == 'saluting' and shared.frames == 90 and shared.pose_writes > 0)
assert(distance(shared_point('r_hand'), shared_point('head')) < 0.2, 'Cross-garment salute missed the head')
near(split.point(split.model.pieces[3], 'r_hand'), split.point(split.model.pieces[4], 'r_hand'))
near(split.point(split.model.pieces[2], 'r_elbow'), split.point(split.model.pieces[3], 'r_elbow'))
assert(distance(split_tip, shared_point('cape3')) > 0.001)
for i, piece in ipairs(split.model.pieces) do
    near(piece.unit.root, split_roots[i])
end
assert(
    logs[2]:find('frame=1', 1, true) and #logs == 4,
    'First-frame/phase diagnostics spammed or did not prove advancement'
)
assert(shared.close())

local cape_only = fixture()
cape_only.armor.unit.names = {}
cape_only.cape.unit.names = { cape1 = 4, cape2 = 3, cape3 = 2 }
local cape_logs = {}
cape_only.manager = Animation.new(cape_only.E, {
    log = function(message)
        cape_logs[#cape_logs + 1] = message
    end,
})
local sway = cape_only.manager.create(cape_only.model)
assert(
    not sway.salute_available and cape_logs[1]:find('salute=false', 1, true),
    'Cape-only motion advertised a supported salute'
)
assert(sway.close())
local authored_fixture = dofile('tests/player_authored_clip.lua')
-- Actual authored playback uses a stable pelvis reference, never the current
-- right arm/hand pose, and maps every authored finger across split garments.
local pelvis = segment({ { 'hips', { 0, 0, 1 } } }, identity())
split.model.pieces[#split.model.pieces + 1] = pelvis
split.render.units[#split.render.units + 1] = pelvis.unit
local authored = Animation.new(split.E, {
    authored = true,
    clip_module = authored_fixture.module,
    clips = function()
        return authored_fixture.set
    end,
})
local actual = authored.create(split.model)
assert(actual.mode == 'authored' and actual.anchor == 'hips' and actual.salute_available)
local fixed_roots = {}
for i, piece in ipairs(split.model.pieces) do
    fixed_roots[i] = copy(piece.unit.root)
end
for _ = 1, 90 do
    assert(actual.advance(0.05, true))
end
local expected = authored_fixture.module.sample(authored_fixture.set, actual.elapsed)
local glove = split.model.pieces[4]
local hand = split.model.pieces[3]
local named_hand = multiply(hand.unit.poses[hand.unit.names.r_hand], hand.model_pose:unbox())
local named_finger = multiply(glove.unit.poses[glove.unit.names.r_index_finger1], glove.model_pose:unbox())
near(named_hand, expected.r_hand, 1e-6)
near(named_finger, expected.r_index_finger1, 1e-6)
assert(actual.phase == 'saluting' and actual.pose_writes > 0, 'Authored phase did not advance')
local held_elapsed = actual.elapsed
for _ = 1, 180 do
    assert(actual.advance(0.05, true))
end
assert(actual.phase == 'saluting' and actual.elapsed > held_elapsed + 8, 'Held pose stopped the driver clock')
near(multiply(hand.unit.poses[hand.unit.names.r_hand], hand.model_pose:unbox()), named_hand, 1e-6)
near(multiply(glove.unit.poses[glove.unit.names.r_index_finger1], glove.model_pose:unbox()), named_finger, 1e-6)
for i, piece in ipairs(split.model.pieces) do
    near(piece.unit.root, fixed_roots[i])
end
local frozen_authored = copy(named_finger)
local authored_writes = #split.writes
assert(not actual.advance(20, false) and #split.writes == authored_writes)
near(multiply(glove.unit.poses[glove.unit.names.r_index_finger1], glove.model_pose:unbox()), frozen_authored)
glove.source.alive = false
assert(
    not pcall(actual.advance, 0.016, true) and #split.writes == authored_writes,
    'Authored stale peer allowed earlier writes'
)
split.render.alive = false
assert(
    actual.close() and #authored.sessions == 0 and #split.writes == authored_writes,
    'Authored cleanup touched a retired world'
)

local absent = fixture()
local not_ready = Animation.new(absent.E, {
    authored = true,
    clip_module = authored_fixture.module,
    clips = function()
        return nil
    end,
})
assert(
    not pcall(not_ready.create, absent.model) and #absent.writes == 0,
    'Authored candidate silently used procedural fallback'
)
local scaled = fixture()
local invalid_pose = {
    sample = function(set, time)
        local samples, stage, age = authored_fixture.module.sample(set, time)
        for row = 0, 2 do
            for col = 1, 3 do
                samples.r_hand[row * 4 + col] = samples.r_hand[row * 4 + col] * 2
            end
        end
        return samples, stage, age
    end,
    pose = authored_fixture.module.pose,
}
local unsupported_scale =
    Animation.new(scaled.E, { authored = true, clip_module = invalid_pose, clips = authored_fixture.set })
assert(
    not pcall(unsupported_scale.create, scaled.model) and #scaled.writes == 0,
    'Unsupported native garment scale was discarded'
)
scaled.E.Matrix4x4.axis = function(m, row)
    local at = (row - 1) * 4
    return { m[at + 1], m[at + 2], m[at + 3] }
end
scaled.E.Matrix4x4.set_axis = function(m, row, v)
    local at = (row - 1) * 4
    for column = 1, 3 do
        m[at + column] = v[column]
    end
end
local exact_scaled = unsupported_scale.create(scaled.model)
assert(exact_scaled.advance(0.05, true))
local scale_expected = invalid_pose.sample(authored_fixture.set, 0.05)
near(
    multiply(scaled.armor.unit.poses[scaled.armor.unit.names.r_hand], scaled.armor.model_pose:unbox()),
    scale_expected.r_hand,
    1e-6
)
assert(exact_scaled.close(), 'Validated affine construction retained native resources')
print(
    'PASS authored segmented retarget: exact hand/finger transforms, stable pelvis alignment, preserved kit bases/portrait roots, pause/stale guards and required-data/scale fallback'
)
print(
    'PASS garment-only animation: real 3D salute endpoints, limb/cape lengths, unequal node maps/bases, root/pan preservation, pause/bounded dt, temporary math lifetime and stale ownership guards'
)
