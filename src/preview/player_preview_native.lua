-- Native adapter for an owned, frozen visual copy. Optional candidate only.
local Native = {}
-- The game's Armory model uses ui_3d's forward layers. The default viewport
-- includes the gameplay temporal pipeline and writes shared output_target.
Native.VIEWPORT = 'ui_3d'
function Native.new(E, m, host)
    local ffi = require('ffi')
    local A, W, U, G, R, V = E.Application, E.World, E.Unit, E.Gui, E.Renderer, E.Viewport
    local memory, native = host.memory, host.native
    local source_materials = {}
    local transparent_mask
    local function address(value)
        return tonumber(ffi.cast('uintptr_t', value))
    end
    local function token(unit)
        return math.floor(address(unit) / 4)
    end
    local function read(at, n)
        local bytes = memory.read(ffi.cast('const uint8_t *', at), n)
        assert(bytes and #bytes == n, 'Preview material memory unavailable')
        return bytes
    end
    local function u32(bytes, at)
        local a, b, c, d = bytes:byte(at + 1, at + 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end
    local function u64(bytes, at)
        return u32(bytes, at) + u32(bytes, at + 4) * 4294967296
    end
    local function initialized_ui_world()
        local manager = u64(read(host.game + 0x347cd90, 8), 0)
        assert(manager >= 65536, 'UI scene manager is unavailable')
        local real = u64(read(manager + 0x3c48, 8), 0)
        assert(real >= 65536, 'UI render world is unavailable')
        for _, world in ipairs(A.worlds()) do
            if world ~= A.main_world() and u64(read(address(world), 8), 0) == real then
                return world
            end
        end
        error('Initialized UI render world was not found')
    end
    local function bindings(material)
        local header = read(material + 24, 16)
        local count = u32(header, 0)
        local data = u64(header, 8)
        assert(count <= 64 and (count == 0 or data >= 65536), 'Preview material binding bounds')
        local out = {}
        if count > 0 then
            local bytes = read(data, count * 16)
            for i = 0, count - 1 do
                out[#out + 1] = { slot = u32(bytes, i * 16), object = u64(bytes, i * 16 + 8) }
            end
        end
        return out
    end
    local function copy_materials(piece)
        local sources = m.engine.unit_materials(native, token(piece.source))
        local copies = m.engine.unit_materials(native, token(piece.unit))
        assert(#sources == #copies, 'Preview material layout differs')
        piece.materials = {}
        for i, source in ipairs(sources) do
            local dest = copies[i]
            assert(
                source.material ~= dest.material and not source_materials[dest.material],
                'Preview materials are shared; source will not be changed'
            )
            assert(
                source.mesh_index == dest.mesh_index and source.material_index == dest.material_index,
                'Preview material ordering differs'
            )
            local kept = {
                source = source.material,
                material = dest.material,
                mesh = dest.mesh,
                mesh_index = dest.mesh_index,
                material_index = dest.material_index,
                objects = {},
            }
            piece.materials[#piece.materials + 1] = kept
            for _, resource in ipairs(bindings(source.material)) do
                m.engine.bind(native, dest.material, resource.slot, resource.object)
                kept.objects[resource.slot] = resource.object
            end
            native.commit(dest.mesh)
        end
        -- The base garments carry m_gibs as a separate material section within
        -- the same skinned mesh as the pants/jacket. Use the authored shadow-only
        -- transparent material for that slot on the copy (nil produces a pink error surface),
        -- rather than hiding the complete limb or changing its texture masks.
        if
            type(U.set_material) == 'function'
            and E.Mesh
            and type(E.Mesh.has_material) == 'function'
            and type(E.Mesh.material) == 'function'
        then
            local removed = {}
            for _, material in ipairs(piece.materials) do
                local mesh = U.mesh(piece.unit, material.mesh_index + 1)
                if E.Mesh.has_material(mesh, 'm_gibs') then
                    local handle = E.Mesh.material(mesh, 'm_gibs')
                    if handle and address(handle) == material.material then
                        assert(
                            material.material ~= material.source and not source_materials[material.material],
                            'Shared gore material refused'
                        )
                        removed[material.material] = true
                    end
                end
            end
            if next(removed) then
                local transparent = 'content/ui/shared/material/gui_diffuse_map'
                assert(A.can_get('material', transparent), 'Preview transparent material unavailable')
                U.set_material(piece.unit, 'm_gibs', transparent)
                local copies = m.engine.unit_materials(native, token(piece.unit))
                local hidden = 0
                for _, material in ipairs(copies) do
                    local mesh = U.mesh(piece.unit, material.mesh_index + 1)
                    if E.Mesh.has_material(mesh, 'm_gibs') then
                        local handle = E.Mesh.material(mesh, 'm_gibs')
                        if handle and address(handle) == material.material then
                            assert(not source_materials[material.material], 'Shared transparent material refused')
                            m.engine.bind(native, material.material, 0x3aa8b87e, transparent_mask())
                            native.commit(material.mesh)
                            hidden = hidden + 1
                        end
                    end
                end
                assert(hidden > 0, 'Preview transparent gib material did not resolve')
                local kept = {}
                for _, material in ipairs(piece.materials) do
                    if not removed[material.material] then
                        kept[#kept + 1] = material
                    end
                end
                piece.materials = kept
                host.log('preview: transparent owned m_gibs slot resource=' .. tostring(U.resource_name(piece.unit)))
            end
        end
        if
            m.limb_caps
            and (piece.slot == 6 or piece.slot == 7)
            and type(E.Mesh.bounding_volume_components) == 'function'
        then
            local meshes = {}
            for _, source in ipairs(sources) do
                local index = source.mesh_index
                if index then
                    local candidate = meshes[index] or { eligible = true }
                    candidate.eligible = candidate.eligible and m.limb_caps.material(bindings(source.material))
                    meshes[index] = candidate
                end
            end
            for index, candidate in pairs(meshes) do
                if candidate.eligible then
                    local lo, hi = E.Mesh.bounding_volume_components(U.mesh(piece.source, index + 1))
                    local compact = m.limb_caps.compact(lo, hi)
                    host.log(
                        'preview: limb cap candidate slot='
                            .. piece.slot
                            .. ' mesh='
                            .. index
                            .. ' compact='
                            .. tostring(compact)
                            .. ' span='
                            .. math.abs(hi.x - lo.x)
                            .. ','
                            .. math.abs(hi.y - lo.y)
                            .. ','
                            .. math.abs(hi.z - lo.z)
                    )
                    if compact then
                        U.set_mesh_visibility(piece.unit, index + 1, false)
                    end
                end
            end
        end
    end
    local function sync_materials(piece)
        assert(U.alive(piece.source), 'Equipped source changed; rebuild preview')
        local live = {}
        for _, material in ipairs(m.engine.unit_materials(native, token(piece.source))) do
            live[material.material] = true
        end
        -- An equipped unit can survive while its materials are replaced. Check
        -- every cached source before reading pointers or updating the copy.
        for _, material in ipairs(piece.materials) do
            assert(live[material.source], 'Equipped source changed; rebuild preview')
        end
        for _, material in ipairs(piece.materials) do
            local changed = false
            for _, resource in ipairs(bindings(material.source)) do
                if
                    (resource.slot == m.engine.LUT_SLOT or resource.slot == m.engine.PATTERN_SLOT)
                    and material.objects[resource.slot] ~= resource.object
                then
                    m.engine.bind(native, material.material, resource.slot, resource.object)
                    material.objects[resource.slot] = resource.object
                    changed = true
                end
            end
            if changed then
                native.commit(material.mesh)
            end
        end
    end
    local model = m.player_model.new(E, {
        note = host.log,
        copy_materials = copy_materials,
        apply_palette = host.apply_palette or function(piece)
            sync_materials(piece)
        end,
        retain_failed = function(model, why)
            host.failed_model = model
            error(why, 0)
        end,
    })
    local adapter = {}
    local environment
    local ui_constants
    local owned_world
    local panel
    local portrait
    local lights = {}
    local submitted = false
    local target_width, target_height
    local lease_native
    local context_lost = false
    local retired_targets = package.loaded['epic.preview.retired.targets'] or {}
    package.loaded['epic.preview.retired.targets'] = retired_targets
    local function world_live(world)
        for _, candidate in ipairs(A.worlds()) do
            if candidate == world then
                return true
            end
        end
        return false
    end
    local function lease_live(world)
        if not world_live(world) then
            return false
        end
        if not host.use_ui_world then
            return true
        end
        local ok, valid = pcall(function()
            return initialized_ui_world() == world and u64(read(address(world), 8), 0) == lease_native
        end)
        return ok and valid
    end
    local retired = package.loaded['epic.preview.fence.receipts'] or {}
    package.loaded['epic.preview.fence.receipts'] = retired
    function adapter.quiesce()
        if not submitted then
            return true
        end
        host.log('preview: draining submitted render work')
        -- Engine.create inserts a render fence and waits for previously queued
        -- renderer work. Do this in update/cleanup, never in the render callback.
        local data = ffi.new('float[4]', { 0, 0, 0, 1 })
        local function read_into(at, n, buffer)
            return memory.read_into(ffi.cast('const uint8_t *', at), n, buffer)
        end
        local fence, why = m.engine.create_texture(native, 1, 1, data, read_into, ffi.new('uint8_t[16]'))
        assert(fence, why)
        retired[#retired + 1] = fence
        native.destroy(fence.handle)
        -- The next fence has processed the preceding receipt's destruction.
        while #retired > 2 do
            table.remove(retired, 1)
        end
        submitted = false
        host.log('preview: render queue drained')
        return true
    end
    local function prepare_environment(world)
        environment = assert(W.create_shading_environment(world))
        if E.ShadingEnvironment.blend then
            E.ShadingEnvironment.blend(environment, { 'default', 1 })
        end
        local name = E.IdString64.from_hex('15c7f9cccbb13826')
        assert(A.can_get('unit', name), 'Preview light resource unavailable')
        for _, spec in ipairs({ { -2.5, 3, 3.2, 6 }, { 2.8, 3, 1.4, 4 }, { 0, -3, 2.5, 3 } }) do
            local position = E.Vector3(spec[1], spec[2], spec[3])
            local aim = E.Vector3(0, 0, 1)
            local unit = assert(
                W.spawn_unit(
                    world,
                    name,
                    position,
                    E.Quaternion.look(E.Vector3.normalize(aim - position), E.Vector3(0, 0, 1))
                )
            )
            lights[#lights + 1] = unit
            local light = U.light(unit, 1)
            E.Light.set_type(light, 'directional')
            E.Light.set_color(light, E.Vector3(1, 1, 1))
            E.Light.set_intensity(light, spec[4])
            E.Light.set_casts_shadows(light, false)
            E.Light.set_enabled(light, true)
            W.update_unit(world, unit)
        end
        E.ShadingEnvironment.update(environment)
    end
    function adapter.capture(identity)
        if host.game then
            local ok, world = pcall(initialized_ui_world)
            host.log(ok and 'preview: initialized UI render world available' or 'preview: ' .. tostring(world))
        end
        local world = A.main_world()
        local units = W.units(world)
        local function contains_player(list)
            for _, unit in ipairs(list) do
                if token(unit) == identity.unit then
                    return true
                end
            end
            return false
        end
        if not contains_player(units) then
            for _, candidate in ipairs(A.worlds() or {}) do
                if candidate ~= world then
                    local candidates = W.units(candidate)
                    if contains_player(candidates) then
                        world, units = candidate, candidates
                        break
                    end
                end
            end
        end
        local wanted = {}
        local root
        for _, piece in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
            wanted[piece.unit] = { kind = piece.slot == 0 and 'helmet' or 'armor', slot = piece.slot }
        end
        local pieces = {}
        source_materials = {}
        for _, unit in ipairs(units) do
            local id = token(unit)
            if id == identity.unit then
                root = unit
            end
            if wanted[id] then
                pieces[#pieces + 1] = { unit = unit, kind = wanted[id].kind, slot = wanted[id].slot }
                for _, material in ipairs(m.engine.unit_materials(native, id)) do
                    source_materials[material.material] = true
                end
            end
        end
        if not root then
            -- identity.unit is a gameplay entity key, not always a world Unit handle.
            -- Any confirmed equipped garment supplies a common rigid transform origin.
            -- All garment poses are captured relative to that same origin.
            for _, piece in ipairs(pieces) do
                if piece.kind == 'armor' and U.alive(piece.unit) then
                    root = piece.unit
                    break
                end
            end
            if not root and pieces[1] and U.alive(pieces[1].unit) then
                root = pieces[1].unit
            end
            if root then
                host.log('preview: using confirmed equipped garment as transform origin')
            end
        end
        assert(root, 'No equipped garment units were found in the live world')
        local gear = m.avatar.copy(identity)
        gear.plan = model.capture(world, root, pieces)
        local visible, nodes = 0, 0
        for _, piece in ipairs(gear.plan.pieces) do
            nodes = nodes + piece.node_count
            for _, shown in ipairs(piece.visible) do
                if shown then
                    visible = visible + 1
                end
            end
        end
        host.log(
            'preview: source '
                .. #pieces
                .. ' pieces, '
                .. visible
                .. ' visible meshes, '
                .. nodes
                .. ' scene nodes; root '
                .. U.num_scene_graph_items(root)
                .. ' nodes'
        )
        return gear
    end
    function adapter.create_world()
        if host.use_ui_world then
            host.log('preview: lease initialized UI render context')
            owned_world = initialized_ui_world()
            lease_native = u64(read(address(owned_world), 8), 0)
            context_lost = false
        else
            host.log('preview: create owned world')
            owned_world = assert(A.new_world())
        end
        submitted = true
        return owned_world
    end
    function adapter.destroy_world(world)
        host.log('preview: release owned world')
        if context_lost or not world_live(world) then
            host.failed_model = nil
            lights = {}
            environment = nil
            owned_world = nil
            return
        end
        if host.failed_model then
            model.destroy(host.failed_model)
            host.failed_model = nil
        end
        for i = #lights, 1, -1 do
            if U.alive(lights[i]) then
                W.destroy_unit(world, lights[i])
            end
            table.remove(lights, i)
        end
        if environment then
            W.destroy_shading_environment(world, environment)
            environment = nil
        end
        if not host.use_ui_world then
            A.release_world(world)
        end
        owned_world = nil
    end
    function adapter.create_model(world, gear)
        host.log('preview: copy ' .. #gear.plan.pieces .. ' equipped pieces')
        local result = model.create(world, gear.plan)
        if host.use_ui_world then
            result.preview_offset = { 100, 0, 0 }
            for _, piece in ipairs(result.pieces) do
                U.set_local_position(piece.unit, 1, U.local_position(piece.unit, 1) + E.Vector3(100, 0, 0))
                W.update_unit(world, piece.unit)
                piece.preview_pose = E.Matrix4x4Box(U.world_pose(piece.unit, 1))
            end
        end
        local ok, why = pcall(prepare_environment, world)
        if not ok then
            local cleaned, problem = pcall(model.destroy, result)
            if not cleaned then
                host.failed_model = result
                error(problem, 0)
            end
            error(why, 0)
        end
        return result
    end
    -- Retain the transparent gib mask across reloads while queued reads may
    -- outlive the adapter. Reuse earlier retained buffers; never free them here.
    local probe_key = 'epic.preview.mask.probes.v1'
    local probes = package.loaded[probe_key] or {}
    package.loaded[probe_key] = probes
    transparent_mask = function()
        if probes.black then
            return probes.black.object
        end
        local data = ffi.new('float[4]')
        local texture, why = m.engine.create_texture(native, 1, 1, data, function(at, n, buffer)
            return memory.read_into(ffi.cast('const uint8_t *', at), n, buffer)
        end, ffi.new('uint8_t[16]'))
        assert(texture, why)
        probes.black = texture
        return texture.object
    end
    function adapter.destroy_model(value)
        host.log('preview: release copied pieces')
        if not context_lost then
            model.destroy(value)
        end
    end
    function adapter.create_camera(world, copied)
        assert(world_live(world), 'Preview context disappeared')
        host.log('preview: create camera')
        local name = E.IdString64.from_hex('465f4895f3dc98d1')
        assert(A.can_get('unit', name), 'Preview camera resource is not loaded')
        if not host.use_ui_world then
            W.update(world, 0)
        end
        local lo = { math.huge, math.huge, math.huge }
        local hi = { -math.huge, -math.huge, -math.huge }
        for _, piece in ipairs(copied.pieces) do
            local pose, extent = U.box(piece.unit, true)
            local center = { E.Vector3.to_elements(E.Matrix4x4.translation(pose)) }
            local half = { E.Vector3.to_elements(extent) }
            local size = { 0, 0, 0 }
            for i = 1, 3 do
                local axis = { E.Vector3.to_elements(E.Matrix4x4.axis(pose, i)) }
                for j = 1, 3 do
                    size[j] = size[j] + math.abs(axis[j]) * half[i]
                end
            end
            for j = 1, 3 do
                lo[j] = math.min(lo[j], center[j] - size[j])
                hi[j] = math.max(hi[j], center[j] + size[j])
            end
        end
        local center = {}
        for i = 1, 3 do
            center[i] = (lo[i] + hi[i]) / 2
        end
        local distance = math.max((hi[3] - lo[3]) / 2, (hi[1] - lo[1]) / (2 * 0.6)) / math.tan(math.rad(22.5)) * 1.1
            + (hi[2] - lo[2]) / 2
        assert(distance > 0 and distance < 1000, 'Preview model bounds are invalid')
        host.log(
            string.format(
                'preview: camera center %.2f %.2f %.2f distance %.2f',
                center[1],
                center[2],
                center[3],
                distance
            )
        )
        local unit = assert(
            W.spawn_unit(
                world,
                name,
                E.Vector3(center[1], center[2] + distance, center[3]),
                E.Quaternion.look(E.Vector3(0, -1, 0), E.Vector3(0, 0, 1))
            )
        )
        local ok, camera = pcall(function()
            local value = assert(U.camera(unit, 1), 'Preview camera missing')
            E.Camera.set_projection_type(value, E.Camera.PERSPECTIVE)
            E.Camera.set_vertical_fov(value, math.rad(45))
            E.Camera.set_near_range(value, 0.05)
            E.Camera.set_far_range(value, math.max(20, distance * 3))
            W.update_unit(world, unit)
            return value
        end)
        if not ok then
            W.destroy_unit(world, unit)
            error(camera, 0)
        end
        return {
            unit = unit,
            camera = camera,
            world = world,
            center = center,
            distance = distance,
            model = copied,
            preview_revision = 0,
            preview_position = { center[1], center[2] + distance, center[3] },
            preview_fov = 45,
            preview_near = 0.05,
            preview_far = math.max(20, distance * 3),
        }
    end
    function adapter.destroy_camera(camera)
        host.log('preview: release camera')
        if not context_lost and world_live(camera.world) and U.alive(camera.unit) then
            W.destroy_unit(camera.world, camera.unit)
        end
        -- close() drains queued render work before releasing any camera state.
        ui_constants = nil
    end
    function adapter.create_target()
        assert(#retired_targets < 2, 'Preview context retired; restart before opening more previews')
        host.log('preview: create portrait target')
        target_width, target_height = A.back_buffer_size()
        assert(
            target_width > 0 and target_height > 0 and target_width * target_height * 4 <= 256 * 1024 * 1024,
            'Preview render dimensions are invalid'
        )
        -- Retain the verified back-buffer dimensions while changing render
        -- paths. ui_3d has no gameplay TAA; smaller targets can be evaluated
        -- separately after this path has visible in-game confirmation.
        portrait = assert(R.create_resource('render_target', 'R8G8B8A8', target_width, target_height))
        submitted = true
        return portrait
    end
    function adapter.destroy_target(target)
        if context_lost then
            retired_targets[#retired_targets + 1] = target
            host.log('preview: retain target after lost UI lease; restart required')
        else
            host.log('preview: release portrait target')
            R.destroy_resource(target)
        end
        portrait = nil
    end
    function adapter.create_viewport(world, target)
        host.log('preview: create portrait viewport')
        local viewport = assert(A.create_viewport(world, Native.VIEWPORT))
        local ok, why = pcall(function()
            V.set_output_render_target(viewport, target)
            V.set_rect(viewport, 0, 0, 1, 1)
            host.log('preview: Game Default ui_3d viewport; private portrait output')
            -- Publish scene graphs and skinning data before the first render.
            if not host.use_ui_world then
                W.update(world, 0)
            end
        end)
        if not ok then
            A.destroy_viewport(world, viewport)
            error(why, 0)
        end
        return { world = world, viewport = viewport }
    end
    function adapter.destroy_viewport(viewport)
        if not lease_live(viewport.world) then
            context_lost = true
            host.log('preview: UI lease changed; skip stale viewport destruction')
            return
        end
        host.log('preview: release viewport')
        A.destroy_viewport(viewport.world, viewport.viewport)
    end
    function adapter.layout_panel()
        assert(panel and world_live(panel.world), 'Preview panel disappeared')
        for _, item in ipairs(panel.items or {}) do
            G['destroy_' .. item.kind](panel.gui, item.id)
        end
        panel.items = {}
        local c = host.controls or panel
        panel.x, panel.y, panel.w, panel.h = c.x, c.y, c.w, c.h
        local function keep(kind, id)
            panel.items[#panel.items + 1] = { kind = kind, id = id }
        end
        local function rect(x, y, w, h, color)
            keep('rect', G.rect(panel.gui, E.Vector3(x, y, 152), E.Vector2(w, h), color))
        end
        local function text(label, x, y)
            keep(
                'text',
                G.text(
                    panel.gui,
                    label,
                    'core/performance_hud/debug',
                    16,
                    'core/performance_hud/debug',
                    E.Vector3(x, y, 153),
                    E.Color(255, 255, 235, 100)
                )
            )
        end
        rect(panel.x - 2, panel.y - 30, panel.w + 4, panel.h + 60, E.Color(255, 60, 80, 100))
        local stroke = E.Color(255, 119, 185, 205)
        local bx, by, bw, bh = panel.x - 2, panel.y - 30, panel.w + 4, panel.h + 60
        rect(bx, by, 2, bh, stroke)
        rect(bx + bw - 2, by, 2, bh, stroke)
        rect(bx, by, bw, 2, stroke)
        rect(bx, by + bh - 2, bw, 2, stroke)
        local span = math.min(1, (panel.w / panel.h) / (target_width / target_height))
        keep(
            'bitmap',
            G.bitmap_uv(
                panel.gui,
                'content/ui/shared/material/gui_diffuse_map',
                E.Vector2((1 - span) / 2, 0),
                E.Vector2((1 + span) / 2, 1),
                E.Vector3(panel.x, panel.y, 153),
                E.Vector2(panel.w, panel.h),
                E.Color(255, 255, 255, 255)
            )
        )
        text(panel.w >= 300 and 'Player Preview' or 'Preview', panel.x + 8, panel.y + panel.h + 8)
        text('X', panel.x + panel.w - 22, panel.y + panel.h + 8)
        if host.controls and host.controls.can_dock then
            text(host.controls.docked and 'Pop Out' or 'Dock', panel.x + panel.w - 94, panel.y + panel.h + 8)
        end
        text('- Zoom', panel.x + 8, panel.y - 20)
        text('+ Zoom', panel.x + panel.w / 2 + 8, panel.y - 20)
        if not (host.controls and host.controls.docked) then
            text('\\', panel.x + panel.w - 18, panel.y - 20)
        end
        text('Left: pan / Right: rotate', panel.x + 8, panel.y + 8)
    end
    function adapter.zoom(camera, fov)
        assert(lease_live(camera.world) and U.alive(camera.unit), 'Preview context disappeared')
        local value = math.max(12, math.min(65, fov))
        E.Camera.set_vertical_fov(camera.camera, math.rad(value))
        camera.preview_fov = value
        camera.preview_revision = (camera.preview_revision or 0) + 1
    end
    function adapter.rotate(camera, yaw, controls)
        assert(lease_live(camera.world) and U.alive(camera.unit), 'Preview context disappeared')
        assert(
            E.Camera.set_local_pose and E.Matrix4x4.from_quaternion_position,
            'Preview camera transform API unavailable'
        )
        local angle = math.rad(yaw % 360)
        local dx = 0
        local dy = camera.distance
        local c = camera.center
        local shiftx, shifty, shiftz = 0, 0, 0
        if camera.model then
            local X = E.Matrix4x4
            local before = X.from_quaternion_position(
                E.Quaternion.look(E.Vector3(0, 1, 0), E.Vector3(0, 0, 1)),
                E.Vector3(-c[1], -c[2], 0)
            )
            local after =
                X.from_quaternion_position(E.Quaternion.axis_angle(E.Vector3(0, 0, 1), angle), E.Vector3(c[1], c[2], 0))
            for _, piece in ipairs(camera.model.pieces) do
                assert(U.alive(piece.unit) and piece.preview_pose, 'Preview garment disappeared')
                U.set_local_pose(piece.unit, 1, X.multiply(X.multiply(piece.preview_pose:unbox(), before), after))
                -- Frozen garments do not receive an animation update. Refresh
                -- every baked bone explicitly when their parent pose changes.
                for node = 2, U.num_scene_graph_items(piece.unit) do
                    U.set_local_pose(piece.unit, node, U.local_pose(piece.unit, node))
                end
                W.update_unit(camera.world, piece.unit)
            end
        end
        if controls then
            local visible = camera.distance * math.tan(math.rad(controls.fov / 2)) * 2
            local horizontal = math.max(-0.25, math.min(0.25, controls.pan_x)) * visible * 0.6
            shiftx = horizontal
            shiftz = -math.max(-1, math.min(1, controls.pan_y)) * visible
        end
        -- Update the camera component explicitly. The leased world does not
        -- run our simulation, so changing only its parent unit is insufficient.
        U.set_local_position(camera.unit, 1, E.Vector3(0, 0, 0))
        U.set_local_rotation(camera.unit, 1, E.Quaternion.look(E.Vector3(0, 1, 0), E.Vector3(0, 0, 1)))
        local rotation = E.Quaternion.look(E.Vector3(-dx, -dy, 0), E.Vector3(0, 0, 1))
        local position = E.Vector3(c[1] + dx + shiftx, c[2] + dy + shifty, c[3] + shiftz)
        E.Camera.set_local_pose(camera.camera, camera.unit, E.Matrix4x4.from_quaternion_position(rotation, position))
        W.update_unit(camera.world, camera.unit)
        camera.preview_position = { c[1] + dx + shiftx, c[2] + dy + shifty, c[3] + shiftz }
        camera.preview_revision = (camera.preview_revision or 0) + 1
    end
    function adapter.create_panel(target)
        host.log('preview: create floating panel')
        local world = A.main_world()
        for _, candidate in ipairs(A.worlds()) do
            if candidate ~= world and candidate ~= owned_world then
                world = candidate
                break
            end
        end
        local gui = assert(W.create_screen_gui(world, 'scale', 1, 1))
        panel = { gui = gui, world = world, x = 32, y = 150, w = 300, h = 500 }
        local ok, why = pcall(function()
            local material = assert(G.material(gui, 'content/ui/shared/material/gui_diffuse_map'))
            assert(address(material) >= 65536, 'Preview GUI material unavailable')
            E.Material.set_resource(material, 'diffuse_map', target)
            adapter.layout_panel()
        end)
        if not ok then
            W.destroy_gui(world, gui)
            panel = nil
            error(why, 0)
        end
        return panel
    end
    function adapter.destroy_panel(value)
        host.log('preview: release panel')
        if world_live(value.world) then
            W.destroy_gui(value.world, value.gui)
        end
        panel = nil
    end
    function adapter.apply_luts(value, palettes)
        assert(not owned_world or lease_live(owned_world), 'Preview context disappeared')
        return model.apply(value, palettes)
    end
    function adapter.debug_target()
        assert(portrait, 'Preview target is closed')
        R.run_resource_generator('ui_3d_debug', {
            ui_3d_canvas = portrait,
            ui_3d_shadows = R.resource('depth_stencil_buffer'),
        })
    end
    function adapter.render(world, camera, viewport)
        assert(lease_live(world), 'Preview context disappeared')
        assert(environment, 'Preview environment is not prepared')
        local width, height = A.back_buffer_size()
        assert(width == target_width and height == target_height, 'Display resolution changed; reopen the preview')
        if host.game then
            if not ui_constants then
                assert(m.player_preview_ui, 'Game Default UI material adapter unavailable')
                ui_constants = m.player_preview_ui.new(E, memory, host.game, {
                    origin_shift = camera.model and camera.model.preview_offset,
                })
            end
            if ui_constants.needs_update(camera) then
                local materials = {}
                for _, piece in ipairs(assert(camera.model, 'UI preview model unavailable').pieces) do
                    assert(piece.unit ~= piece.source and U.alive(piece.unit), 'UI preview copy unavailable')
                    for _, material in ipairs(piece.materials) do
                        assert(
                            material.material ~= material.source and not source_materials[material.material],
                            'Shared UI preview material refused'
                        )
                        materials[#materials + 1] = { material = material.material, mesh = material.mesh, owned = true }
                    end
                end
                if ui_constants.apply(camera, materials, width, height) then
                    local committed = {}
                    for _, material in ipairs(materials) do
                        if not committed[material.mesh] then
                            native.commit(material.mesh)
                            committed[material.mesh] = true
                        end
                    end
                end
            end
        end
        submitted = true
        E.ShadingEnvironment.apply(environment)
        R.run_resource_generator('resource_clear', { output_rt = portrait })
        if host.submit then
            host.submit(world, camera.camera, viewport.viewport, environment)
        else
            if A.update_render_world then
                A.update_render_world(world)
            end
            A.render_world(world, camera.camera, viewport.viewport, environment)
        end
        -- ui_3d renders to the viewport's output_rt directly. Reading the shared
        -- gameplay output_target here can capture another queued view instead
        -- of the portrait, and reintroduces the full-pipeline flicker path.
    end
    return adapter
end
return Native
