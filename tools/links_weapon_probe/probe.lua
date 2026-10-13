-- Diagnostic-only cooperative adapter; no binds, commits, allocations or input.
-- Exact identity/discovery/vendor modules are prepared verbatim beside this file.
local rows, captures, targets, wanted = {}, {}, {}, {}
local runtime, discovery, Engine
local MAX_ROWS, MAX_REPORT, MAX_SECONDS = 32768, 8388608, 90
local function field(value)
    return tostring(value == nil and '' or value):gsub('[\t\r\n]', ' ')
end
local function add(...)
    assert(#rows < MAX_ROWS, 'Weapon probe row budget exceeded')
    local values = {}
    for i = 1, select('#', ...) do
        values[i] = field(select(i, ...))
    end
    rows[#rows + 1] = table.concat(values, '\t')
end
local function pause()
    coroutine.yield()
end
local function emit(state, why)
    add('result', state, why)
    local report = table.concat(rows, '\n') .. '\n'
    assert(#report <= MAX_REPORT, 'Weapon probe report byte budget exceeded')
    save_file('r6_weapon_probe.tsv', report)
    out('R6 weapon probe', state, why or '', 'r6_weapon_probe.tsv', #targets, 'LUT destinations')
end
local function collect()
    local Primary = use('r6_weapon_probe_primary_identity')
    local Discovery = use('r6_weapon_probe_weapon_discovery')
    Engine = use('r6_weapon_probe_engine')
    local Match = use('r6_weapon_probe_lut_catalog_match')
    runtime = use('r6_weapon_probe_bingus_memory').new(use('r6_weapon_probe_bingus_runtime'))
    local function read_bytes(address, size)
        return runtime.read(ffi.cast('const uint8_t *', address), size)
    end
    local function module_address(name)
        local found = runtime.module(name)
        return found and runtime.address(found)
    end
    local identity = Primary.new({ module = module_address, read = read_bytes, verify_build = runtime.verify_build })
    assert(identity.validate())
    for _, name in ipairs({ 'game.dll', 'helldivers2.exe' }) do
        local base, size, stamp = module(name)
        assert(base and size and stamp, 'Module stamp unavailable: ' .. name)
        add('module', name, string.format('%x', base), size, string.format('%08x', stamp))
    end
    local manifest = assert(load_file('r6_weapon_probe_manifest.json'), 'Prepared source manifest missing')
    assert(#manifest <= 16384, 'Source manifest byte bounds')
    local manifest_digest = assert(load_file('r6_weapon_probe_manifest.sha256'), 'Source manifest digest missing')
    assert(#manifest_digest == 64 and manifest_digest:match('^%x+$'), 'Source manifest digest malformed')
    add('source_manifest', 'r6_weapon_probe_manifest.json', manifest_digest)
    local opened, why = Engine.open(runtime, module_address('game.dll'), module_address())
    assert(opened, why)
    -- The adapter exposed to discovery has only its read/query operations.
    local native = {}
    for _, name in ipairs({ 'alive', 'meshes', 'mesh', 'materials', 'material', 'can_get', 'get' }) do
        native[name] = opened[name]
    end
    local game_api = assert(rawget(_G, 'stingray'), 'Game Lua API namespace unavailable')
    local mesh_name = game_api.Mesh and game_api.Mesh.name
    local has_mesh_name = type(mesh_name) == 'function'
    add('mesh_name_api', has_mesh_name and 'available' or 'unavailable')
    discovery = Discovery.new(game_api, { identity = identity, native = native, read = read_bytes })
    local began = runtime.time()
    local mesh_counts, material_counts, mesh_records = {}, {}, {}
    local function mesh_pointer(handle)
        local kind = type(handle)
        assert(kind == 'userdata' or kind == 'cdata', 'Genuine Lua Mesh handle unavailable')
        if kind == 'cdata' then
            assert(tostring(ffi.typeof(handle)):match('%*%s*>$'), 'Lua Mesh handle is not a pointer')
        end
        return tonumber(ffi.cast('uintptr_t', handle))
    end
    local function mesh_id(handle)
        assert(game_api.Mesh.name == mesh_name, 'Mesh.name API changed during probe')
        local value = mesh_name(handle)
        assert(
            type(value) == 'number' and value % 1 == 0 and value >= -0x80000000 and value <= 0xffffffff,
            'Invalid runtime MeshName ID'
        )
        return value < 0 and value + 0x100000000 or value, value
    end
    for slot = 1, 3 do
        local receipt, reason = discovery.capture(slot)
        if not receipt then
            add('weapon', slot, 'unavailable', reason)
        else
            captures[#captures + 1] = receipt
            local count = tonumber(native.meshes(receipt.unit))
            assert(
                type(count) == 'number'
                    and count % 1 == 0
                    and count >= 0
                    and count <= 64
                    and tonumber(game_api.Unit.num_meshes(receipt.lua_unit)) == count,
                'Lua/native weapon mesh count bounds changed'
            )
            mesh_counts[receipt] = count
            mesh_records[receipt] = {}
            add('weapon', slot, 'ready', receipt.weapon_resource64, receipt.unit_resource64, receipt.unit)
            pause()
            if has_mesh_name then
                for index = 0, mesh_counts[receipt] - 1 do
                    local valid, reason = discovery.validate(receipt)
                    assert(valid, reason)
                    local pointer = tonumber(native.mesh(receipt.unit, index))
                    local handle = game_api.Unit.mesh(receipt.lua_unit, index + 1)
                    assert(mesh_pointer(handle) == pointer, 'Captured weapon mesh pointer changed')
                    local id, raw = mesh_id(handle)
                    valid, reason = discovery.validate(receipt)
                    assert(valid, reason)
                    assert(
                        tonumber(native.meshes(receipt.unit)) == mesh_counts[receipt]
                            and tonumber(game_api.Unit.num_meshes(receipt.lua_unit)) == mesh_counts[receipt],
                        'Weapon mesh count changed during name query'
                    )
                    assert(
                        tonumber(native.mesh(receipt.unit, index)) == pointer
                            and mesh_pointer(game_api.Unit.mesh(receipt.lua_unit, index + 1)) == pointer,
                        'Weapon mesh pointer changed during name query'
                    )
                    mesh_records[receipt][index] = { pointer = pointer, id = id }
                    add('mesh_id', slot, index, pointer, string.format('%08x', id), raw)
                    pause()
                    assert(runtime.time() - began < MAX_SECONDS, 'Weapon probe elapsed budget exceeded')
                end
            end
            local material_rows = discovery.materials(receipt)
            add('material_count', slot, #material_rows)
            for _, row in ipairs(material_rows) do
                material_counts[row.mesh] = tonumber(native.materials(row.mesh))
                for _, family in ipairs({ 'material', 'pattern' }) do
                    local hash = family == 'material' and Discovery.LUT or Discovery.PATTERN
                    local binding = discovery.descriptor(receipt, row, hash)
                    if binding then
                        binding.probe_family = family
                        targets[#targets + 1] = binding
                        wanted[binding.original] = true
                        add(
                            'binding',
                            slot,
                            family,
                            binding.save_key,
                            binding.mesh_index,
                            binding.material_index,
                            string.format('%08x', hash),
                            binding.original,
                            binding.mesh,
                            binding.material
                        )
                    end
                end
                pause()
                assert(runtime.time() - began < MAX_SECONDS, 'Weapon probe elapsed budget exceeded')
            end
            local valid, changed = discovery.validate(receipt)
            assert(valid, changed)
        end
        pause()
    end
    local function validate()
        for _, receipt in ipairs(captures) do
            local valid, reason = discovery.validate(receipt)
            if not valid then
                return false, reason
            end
            if
                tonumber(native.meshes(receipt.unit)) ~= mesh_counts[receipt]
                or tonumber(game_api.Unit.num_meshes(receipt.lua_unit)) ~= mesh_counts[receipt]
            then
                return false, 'Captured weapon mesh count changed'
            end
            if has_mesh_name then
                for index = 0, mesh_counts[receipt] - 1 do
                    local prior = mesh_records[receipt][index]
                    local pointer = tonumber(native.mesh(receipt.unit, index))
                    local handle = game_api.Unit.mesh(receipt.lua_unit, index + 1)
                    if pointer ~= prior.pointer or mesh_pointer(handle) ~= pointer then
                        return false, 'Captured weapon mesh pointer changed'
                    end
                    if mesh_id(handle) ~= prior.id then
                        return false, 'Captured weapon MeshName ID changed'
                    end
                end
            end
        end
        local small, large = ffi.new('uint8_t[16]'), ffi.new('uint8_t[1024]')
        local function read_into(address, size, buffer)
            return runtime.read_into(ffi.cast('const uint8_t *', address), size, buffer)
        end
        for _, binding in ipairs(targets) do
            -- validate() above establishes the exact genuine Unit once for
            -- each receipt; frozen locators are then checked without repeating
            -- its World scan for every texture in the same synchronous chunk.
            local mesh = tonumber(native.mesh(binding.unit, binding.mesh_index))
            local lua_mesh = game_api.Unit.mesh(binding.receipt.lua_unit, binding.mesh_index + 1)
            local lua_pointer = mesh_pointer(lua_mesh)
            if mesh ~= binding.mesh or lua_pointer ~= mesh then
                return false, 'Captured weapon mesh pointer changed'
            end
            if
                tonumber(native.materials(mesh)) ~= material_counts[mesh]
                or tonumber(native.material(mesh, binding.material_index)) ~= binding.material
            then
                return false, 'Captured weapon material pointer or count changed'
            end
            if Engine.binding(read_into, binding.material, binding.slot, small, large) ~= binding.original then
                return false, 'Captured weapon texture binding changed'
            end
        end
        return true
    end
    if next(wanted) == nil then
        local valid, why = validate()
        assert(valid, why)
        return 'complete', 'No bound weapon LUT objects were available'
    end
    local catalog = assert(load_file('r6_weapon_catalog.txt'), 'Prepared texture catalog missing')
    local matcher = Match.new({
        lookup = function(resource)
            return Engine.texture_object(native, resource)
        end,
        validate = validate,
    }, catalog, wanted)
    local result = matcher.result()
    while not result.complete and not result.refused do
        result = matcher.step(8)
        pause()
        assert(runtime.time() - began < MAX_SECONDS, 'Weapon probe elapsed budget exceeded')
    end
    assert(not result.refused, result.reason)
    add('catalog', result.processed, result.total, result.input_count, result.duplicates)
    local objects = {}
    for object in pairs(wanted) do
        objects[#objects + 1] = object
    end
    table.sort(objects)
    for _, object in ipairs(objects) do
        local aliases = result.matches[object] or {}
        table.sort(aliases)
        local count = 0
        for _, binding in ipairs(targets) do
            count = count + (binding.original == object and 1 or 0)
        end
        add(
            'texture_object',
            object,
            'bindings',
            count,
            'aliases',
            #aliases,
            #aliases > 0 and table.concat(aliases, ',') or 'unmatched'
        )
        for _, binding in ipairs(targets) do
            if binding.original == object then
                add(
                    'mapped',
                    binding.weapon_slot,
                    binding.probe_family,
                    binding.save_key,
                    binding.mesh_index,
                    binding.material_index,
                    object,
                    #aliases > 0 and table.concat(aliases, ',') or 'unmatched',
                    'dimensions/pixels require matched original DDS; never guessed',
                    has_mesh_name and string.format('%08x', mesh_records[binding.receipt][binding.mesh_index].id)
                        or 'mesh_id_unavailable'
                )
            end
        end
    end
    return 'complete', 'Read-only weapon identity, bindings and complete catalog aliases captured'
end
local job = coroutine.create(collect)
return function()
    local ok, state, why = coroutine.resume(job)
    if not ok then
        emit('refused', tostring(state))
        return true
    end
    if coroutine.status(job) == 'dead' then
        emit(state or 'complete', why)
        return true
    end
    return false
end
