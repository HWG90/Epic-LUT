local ffi = require('ffi')
local N = dofile('src/preview/player_preview_native.lua')
local function pack32(value)
    local out = ffi.new('uint32_t[1]', value)
    return ffi.string(out, 4)
end
local function pack64(value)
    local out = ffi.new('uint64_t[1]', value)
    return ffi.string(out, 8)
end
local blocks =
    { [100024] = pack32(1) .. pack32(0) .. pack64(200000), [200000] = pack32(123) .. pack32(0) .. pack64(300000) }
local writes = {}
local shared = false
local commits = 0
local piece = { source = ffi.cast('void *', 4), unit = ffi.cast('void *', 8), kind = 'helmet' }
local engine = {
    LUT_SLOT = 123,
    PATTERN_SLOT = 456,
    unit_materials = function(_, id)
        return {
            { material = (id == 1 or shared) and 100000 or 110000, mesh = 120000, mesh_index = 0, material_index = 0 },
        }
    end,
    bind = function(_, material, slot, object)
        writes[#writes + 1] = { material, slot, object }
    end,
}
local m = {
    engine = engine,
    player_model = {
        new = function(_, host)
            return {
                create = function()
                    local created = { source = piece.source, unit = piece.unit, kind = piece.kind }
                    host.copy_materials(created)
                    return { pieces = { created } }
                end,
                destroy = function() end,
                apply = function(model, palettes)
                    if palettes.helmet then
                        host.apply_palette(model.pieces[1], palettes.helmet)
                    end
                end,
            }
        end,
    },
}
local E = {
    Application = {
        can_get = function()
            return true
        end,
        back_buffer_size = function()
            return 3840, 2160
        end,
        worlds = function()
            return { 'owned' }
        end,
    },
    World = {},
    Unit = {
        alive = function()
            return true
        end,
    },
    Gui = {},
    Renderer = {},
    Viewport = {},
    Matrix4x4 = {},
    Light = {},
}
E.World.create_shading_environment = function()
    return 'environment'
end
E.World.spawn_unit = function()
    return 'light'
end
E.World.update_unit = function() end
E.Unit.light = function()
    return 'light'
end
E.IdString64 = {
    from_hex = function(value)
        return value
    end,
}
E.Vector3 = setmetatable({
    normalize = function(value)
        return value
    end,
}, {
    __call = function(_, x)
        return x
    end,
})
E.Quaternion = {
    look = function()
        return 'rotation'
    end,
}
E.ShadingEnvironment = { update = function() end }
for _, name in ipairs({ 'set_type', 'set_color', 'set_intensity', 'set_casts_shadows', 'set_enabled' }) do
    E.Light[name] = function() end
end
local calls = {}
local a = N.new(E, m, {
    memory = {
        read = function(at, len)
            local value = blocks[tonumber(ffi.cast('uintptr_t', at))]
            assert(value and #value == len)
            return value
        end,
    },
    native = {
        commit = function()
            commits = commits + 1
        end,
        destroy = function()
            calls[#calls + 1] = 'fence destroy queued'
        end,
    },
    log = function() end,
})
local model = a.create_model('owned', { plan = { pieces = { piece } } })
assert(#writes == 1 and writes[1][1] == 110000 and writes[1][2] == 123 and writes[1][3] == 300000 and commits == 1)
a.apply_luts(model, { helmet = true })
assert(#writes == 1 and commits == 1, 'Unchanged palettes generated material commits')
blocks[200000] = pack32(123) .. pack32(0) .. pack64(300004)
a.apply_luts(model, { helmet = true })
assert(#writes == 2 and commits == 2 and writes[2][3] == 300004, 'Changed live LUT was not copied')
shared = true
assert(
    not pcall(a.create_model, 'owned', { plan = { pieces = { piece } } }) and #writes == 2,
    'Shared source material was written'
)
shared = false
blocks[100024] = pack32(65) .. pack32(0) .. pack64(200000)
assert(not pcall(a.apply_luts, model, { helmet = true }) and #writes == 2, 'Unbounded binding count accepted')
E.Renderer.create_resource = function(_, _, width, height)
    assert(width == 3840 and height == 2160, 'Undersized render target can produce a zero jitter divisor')
    return 'portrait'
end
E.Renderer.resource = function(name)
    return name
end
E.Renderer.run_resource_generator = function(name, mapping)
    if name == 'gbuffer_normal_copy' then
        assert(mapping.gbuffer1 == 'output_target' and mapping.gbuffer1_copy == 'portrait')
        calls[#calls + 1] = 'copy output'
    else
        calls[#calls + 1] = 'clear'
    end
end
E.Application.update_render_world = function()
    calls[#calls + 1] = 'world update'
end
E.Application.render_world = function()
    calls[#calls + 1] = 'render'
end
E.ShadingEnvironment.apply = function()
    calls[#calls + 1] = 'lighting apply'
end
m.engine.create_texture = function(_, width, height, data, read_into, buffer)
    assert(width == 1 and height == 1 and data[3] == 1)
    assert(type(read_into) == 'function' and ffi.sizeof(buffer) == 16)
    calls[#calls + 1] = 'fence wait'
    return { handle = 1, data = data }
end
a.create_target()
a.render('owned', { camera = 'camera' }, { viewport = 'viewport' })
assert(a.quiesce() and a.quiesce())
assert(
    table.concat(calls, ',') == 'lighting apply,clear,world update,render,copy output,fence wait,fence destroy queued',
    'Render work was not drained exactly once before release'
)
assert(
    type(dofile('vendor/engine.lua').create_texture) == 'function',
    'Fixture texture function differs from the actual adapter'
)
local position, rotation
E.Vector3 = setmetatable({}, {
    __call = function(_, x, y, z)
        return { x, y, z }
    end,
})
E.Quaternion.look = function(direction, up)
    return { direction = direction, up = up }
end
E.Unit.set_local_position = function(unit, node, p)
    assert(unit == 'camera unit' and node == 1 and p[1] == 0)
end
E.Unit.set_local_rotation = function(unit, node, r)
    assert(unit == 'camera unit' and node == 1)
end
E.Matrix4x4.from_quaternion_position = function(q, p)
    return { q = q, p = p }
end
E.Camera = {
    set_local_pose = function(value, parent, pose)
        assert(value == 'camera' and parent == 'camera unit')
        position = pose.p
        rotation = pose.q
    end,
}
local camera = { unit = 'camera unit', camera = 'camera', world = 'owned', center = { 100, 0, 1 }, distance = 5 }
a.rotate(camera, 90)
assert(math.abs(position[1] - 100) < 0.001 and math.abs(position[2] - 5) < 0.001 and position[3] == 1)
assert(math.abs(rotation.direction[2] + 5) < 0.001 and rotation.up[3] == 1)
a.rotate(camera, 360)
assert(math.abs(position[1] - 100) < 0.001 and math.abs(position[2] - 5) < 0.001)
-- A borrowed initialized context must never be released by our adapter.
local main = ffi.cast('void *', 0x700000)
local ui = ffi.cast('void *', 0x800000)
local ui_manager = 0x900000
local ui_real = 0xa00000
local ui_game = 0xb00000
local ui_blocks = {
    [ui_game + 0x347cd90] = pack64(ui_manager),
    [ui_manager + 0x3c48] = pack64(ui_real),
    [0x800000] = pack64(ui_real),
}
E.Application.worlds = function()
    return { main, ui }
end
E.Application.main_world = function()
    return main
end
E.Application.release_world = function()
    error('Released borrowed game world')
end
local leased = N.new(E, m, {
    game = ui_game,
    use_ui_world = true,
    native = {},
    log = function() end,
    memory = {
        read = function(at, len)
            local b = ui_blocks[tonumber(ffi.cast('uintptr_t', at))]
            assert(b and #b == len)
            return b
        end,
    },
})
assert(leased.create_world() == ui)
leased.destroy_world(ui)
assert(leased.create_world() == ui)
ui_blocks[ui_manager + 0x3c48] = pack64(ui_real + 0x100)
E.Application.destroy_viewport = function()
    error('Destroyed stale game-owned context viewport')
end
E.Renderer.destroy_resource = function()
    error('Freed target still referenced by a retired viewport')
end
leased.destroy_viewport({ world = ui, viewport = 'stale' })
leased.destroy_model({ pieces = {} })
leased.destroy_camera({ world = ui, unit = 'stale' })
leased.destroy_world(ui)
leased.destroy_target('retired portrait')
assert(package.loaded['epic.preview.retired.targets'][1] == 'retired portrait')
blocks[100024] = pack32(1) .. pack32(0) .. pack64(200000)
E.Unit.resource_name = function()
    return 'leg-resource'
end
model.pieces[1].slot = 6
local diagnostic = a.material_masks(model)
assert(#diagnostic == 1 and diagnostic[1].mode == 'original')
local retained_probes = package.loaded['epic.preview.mask.probes.v1']
retained_probes.black = { object = 444444 }
a.set_material_mask(model, 1, 1, 123, 'black')
assert(writes[#writes][1] == 110000 and writes[#writes][3] == 444444, 'Probe wrote outside copied material')
local before = #writes
blocks[200000] = pack32(123) .. pack32(0) .. pack64(300008)
a.apply_luts(model, { helmet = true })
assert(#writes == before, 'Live sync overwrote diagnostic mask')
a.reset_material_masks(model)
assert(writes[#writes][3] == 300008, 'Reset failed to restore current source binding')
assert(a.material_masks(model)[1].mode == 'original')
assert(not pcall(a.set_material_mask, model, 1, 1, 999, 'black'), 'Unknown texture slot accepted')
local own = model.pieces[1].unit
model.pieces[1].unit = model.pieces[1].source
assert(not pcall(a.set_material_mask, model, 1, 1, 123, 'black'), 'Live source unit accepted')
model.pieces[1].unit = own
retained_probes.black = nil
print('PASS native preview material copy, shared source refusal and bounded binding reads')
