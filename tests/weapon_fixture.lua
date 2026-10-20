local ffi = require('ffi')
local Discovery = dofile('src/weapons/weapon_discovery.lua')
local Runtime = dofile('src/weapons/weapon_runtime.lua')
local Sessions = dofile('src/gear/binding_session.lua')
local function u32(value)
    local bytes = {}
    for index = 1, 4 do
        bytes[index] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(bytes)
end
local function pointer(value)
    return u32(value) .. u32(0)
end
local function handle(ref)
    return ffi.cast('void *', ref * 4 + 1)
end
local function unit_ref(value)
    return math.floor(tonumber(ffi.cast('uintptr_t', value)) / 4)
end
local function snapshot(slot, ref, resource)
    return {
        game_base = 0x100000,
        player_entity = 9,
        avatar_entity = 10,
        avatar_native_ref = 77,
        weapon_slot = slot,
        weapon_entity = 1000 + ref,
        weapon_record = 0x200000 + ref * 24,
        weapon_resource64 = resource,
        weapon_unit_ref = ref,
        weapon_native_ref = ref + 500,
        weapon_object = 0x400000 + ref * 128,
    }
end
return function(source_lease)
    local state = {
        units = {},
        meshes = {},
        textures = {},
        snapshots = {},
        worlds = { 'main' },
        world_units = { main = {} },
        reads = 0,
        writes = {},
        allocations = 0,
        next_texture = 0x70000000,
    }
    local A, B, P = 0x500000, 0x600000, 0x700000
    state.A, state.B, state.P = A, B, P
    local function make_unit(ref, mesh_count, resource)
        local model = { alive = true, handle = handle(ref), resource = resource, meshes = {} }
        state.units[ref] = model
        state.world_units.main[#state.world_units.main + 1] = model.handle
        for mesh_index = 0, mesh_count - 1 do
            local mesh = { pointer = 0x300000 + ref * 0x1000 + mesh_index * 0x100, materials = {} }
            for material_index = 0, 1 do
                local value = 0x900000 + ref * 0x10000 + mesh_index * 0x1000 + material_index * 0x100
                mesh.materials[material_index + 1] = value
                state.textures[value] = { [Discovery.LUT] = material_index == 0 and A or B }
                if material_index == 0 then
                    state.textures[value][Discovery.PATTERN] = P
                end
            end
            model.meshes[mesh_index + 1] = mesh
            state.meshes[mesh.pointer] = mesh
        end
        return model
    end
    state.make_unit = make_unit
    make_unit(100, 5, '5fecab819f96a3e8')
    make_unit(200, 2, '1234567812345678')
    make_unit(300, 1, 'fedcba98fedcba98')
    state.snapshots[1] = snapshot(1, 100, '5fecab819f96a3e8')
    state.snapshots[2] = snapshot(2, 200, '1234567812345678')
    state.identity = {
        snapshot = function(slot)
            if state.identity_hook then
                state.identity_hook(slot)
            end
            local saved = state.snapshots[slot]
            if not saved then
                return nil, 'Weapon inventory slot is empty'
            end
            local copied = {}
            for key, value in pairs(saved) do
                copied[key] = value
            end
            return copied
        end,
    }
    local E = {
        Application = {
            worlds = function()
                return state.worlds
            end,
            main_world = function()
                return 'main'
            end,
        },
        World = {
            units = function(world)
                return state.world_units[world] or {}
            end,
        },
        Unit = {
            alive = function(value)
                local model = state.units[unit_ref(value)]
                return model and model.alive == true or false
            end,
            resource_name = function(value)
                return '#ID[' .. state.units[unit_ref(value)].resource .. ']'
            end,
            num_meshes = function(value)
                return #state.units[unit_ref(value)].meshes
            end,
            mesh = function(value, index)
                return ffi.cast('void *', state.units[unit_ref(value)].meshes[index].pointer)
            end,
        },
    }
    local native = {
        alive = function(ref)
            local model = state.units[tonumber(ref)]
            return model and model.alive and 1 or 0
        end,
        meshes = function(ref)
            return #state.units[tonumber(ref)].meshes
        end,
        mesh = function(ref, index)
            return state.units[tonumber(ref)].meshes[tonumber(index) + 1].pointer
        end,
        materials = function(mesh)
            return #state.meshes[tonumber(mesh)].materials
        end,
        material = function(mesh, index)
            return state.meshes[tonumber(mesh)].materials[tonumber(index) + 1]
        end,
    }
    local function read(address, size)
        state.reads = state.reads + 1
        for object, shape in pairs(state.texture_shapes or {}) do
            if address == object and size == 36 then
                return u32(1) .. u32(0) .. u32(0x13) .. u32(0) .. u32(0)
                    .. u32(shape[1]) .. u32(shape[2]) .. u32(1) .. u32(1)
            end
        end
        for material, slots in pairs(state.textures) do
            local keys = {}
            for slot in pairs(slots) do
                keys[#keys + 1] = slot
            end
            table.sort(keys)
            if address == material + 24 and size == 16 then
                return u32(#keys) .. u32(0) .. pointer(material + 0x10000000)
            end
            if address == material + 0x10000000 and size == #keys * 16 then
                local out = {}
                for _, slot in ipairs(keys) do
                    out[#out + 1] = u32(slot) .. u32(0) .. pointer(slots[slot])
                end
                return table.concat(out)
            end
        end
        return nil
    end
    state.E, state.native, state.read = E, native, read
    state.discovery_deps = { identity = state.identity, native = native, read = read }
    state.discovery = Discovery.new(E, state.discovery_deps)
    local documents = {}
    state.texture_shapes = {}
    for object, spec in pairs({
        [A] = { 23, 8, 'babd338977faa2ff' },
        [B] = { 23, 8, 'd1c943c12a564150' },
        [P] = { 3, 1, 'cf0cc31b981786c9' },
    }) do
        local data = ffi.new('float[?]', spec[1] * spec[2] * 4)
        for index = 0, spec[1] * spec[2] * 4 - 1 do
            data[index] = index % 9 / 8
        end
        data[0], data[2], data[3] = -3.25, 42.5, 0.125
        ffi.cast('uint32_t *', data)[1] = 0x80000000
        documents[object] = { data = data, width = spec[1], height = spec[2], resource = spec[3] }
        state.texture_shapes[object] = { spec[1], spec[2] }
    end
    state.documents = documents
    state.retain, state.cohort = { records = {}, cache = {}, bytes = 0 }, { sessions = {} }
    state.runtime = Runtime.new({
        discovery = state.discovery,
        source_lease = source_lease,
        binding_session = Sessions,
        retain = state.retain,
        cohort = state.cohort,
        document = function(object)
            return documents[object]
        end,
        create_texture = function(w, h, data)
            state.allocations = state.allocations + 1
            if state.create_hook then
                state.create_hook()
            end
            local object = state.next_texture
            state.next_texture = state.next_texture + 0x1000
            return { object = object, data = data, width = w, height = h }
        end,
        bind = function(b, object)
            state.writes[#state.writes + 1] = { binding = b, object = object }
            state.textures[b.material][b.slot] = object
            if state.fail_write and #state.writes == state.fail_write then
                error('native bind rejected after write')
            end
        end,
    })
    function state.respawn(slot, ref, resource)
        local prior = state.snapshots[slot]
        if prior then
            state.units[prior.weapon_unit_ref].alive = false
        end
        make_unit(ref, 5, resource or (prior and prior.weapon_resource64) or '5fecab819f96a3e8')
        state.snapshots[slot] = snapshot(slot, ref, resource or prior.weapon_resource64)
    end
    return state
end
