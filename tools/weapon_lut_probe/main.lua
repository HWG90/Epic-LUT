-- Isolated, one-shot live diagnostic. Owns no game object, hook, input or texture.
-- Package the manifest's dependencies from the frozen R6 source snapshot.
local ffi = require('ffi')
local job, completed, rows, directory, runtime
local MAX_ROWS, MAX_UNITS, MAX_MATERIALS = 8192, 131072, 512
local function address(handle)
    local kind = type(handle)
    if kind ~= 'userdata' and kind ~= 'cdata' then
        return nil
    end
    if kind == 'cdata' and not tostring(ffi.typeof(handle)):match('%*%s*>$') then
        return nil
    end
    local ok, value = pcall(function()
        return tonumber(ffi.cast('uintptr_t', handle))
    end)
    return ok and value or nil
end
local function text(value)
    return tostring(value):gsub('[\t\r\n]', ' ')
end
local function add(...)
    assert(#rows < MAX_ROWS, 'Diagnostic row bound exceeded')
    local fields = {}
    for i = 1, select('#', ...) do
        fields[i] = text(select(i, ...))
    end
    rows[#rows + 1] = table.concat(fields, '\t')
end
local function pause()
    coroutine.yield()
end
local function collect(ctx)
    local Primary = mod.require('src/weapons/primary_identity.lua')
    local Engine = mod.require('vendor/engine.lua')
    runtime = mod.require('vendor/bingus_memory.lua').new(mod.require('vendor/bingus_runtime.lua'))
    local function read(at, size)
        return runtime.read(ffi.cast('const uint8_t *', at), size)
    end
    local identity = Primary.new({
        module = function(name)
            local found = runtime.module(name)
            return found and runtime.address(found)
        end,
        read = read,
        verify_build = runtime.verify_build,
    })
    local function initializing(reason)
        for _, message in ipairs({
            'Invalid pointer',
            'Unreadable primary identity memory',
            'No bounded local player list',
            'No local player',
            'No local avatar',
            'Local avatar entity unavailable',
            'Inventory bounds changed',
            'No primary inventory candidate',
            'Primary entity unavailable',
        }) do
            if tostring(reason):find(message, 1, true) then
                return true
            end
        end
        return false
    end
    local began, snapshot, why, waiting = runtime.time(), nil, nil, false
    while not snapshot do
        snapshot, why = identity.snapshot()
        if not snapshot then
            assert(initializing(why), why)
            if not waiting then
                waiting = true
                add('initial_identity', 'waiting', tostring(why))
                ctx.log('Waiting for initial local primary identity; bounded to 60 seconds')
            end
            local retry_at = runtime.time() + 1
            repeat
                pause()
                assert(
                    runtime.time() - began < 60,
                    'Initial primary identity readiness timed out after 60 seconds: ' .. tostring(why)
                )
            until runtime.time() >= retry_at
        end
    end
    if waiting then
        add('initial_identity', 'ready', 'wait_seconds', runtime.time() - began)
    end
    local function current()
        local fresh, reason = identity.snapshot()
        assert(fresh, reason)
        for _, key in ipairs({
            'player_entity',
            'avatar_entity',
            'avatar_native_ref',
            'primary_entity',
            'primary_record',
            'primary_resource_hex',
            'primary_unit_ref',
            'primary_native_ref',
            'primary_object',
        }) do
            assert(fresh[key] == snapshot[key], 'Captured primary identity changed: ' .. key)
        end
    end
    for _, key in ipairs({
        'player_entity',
        'avatar_entity',
        'avatar_native_ref',
        'primary_entity',
        'primary_record',
        'primary_resource_hex',
        'primary_unit_ref',
        'primary_native_ref',
        'primary_object',
        'inventory_slot',
        'inventory_held_entity',
        'provenance',
    }) do
        add('identity', key, snapshot[key])
    end
    pause()
    current()
    local native = assert(Engine.open(runtime, snapshot.game_base, runtime.address(assert(runtime.module()))))
    assert(native.alive(snapshot.primary_unit_ref) ~= 0, 'Primary engine Unit is not alive')
    local E = assert(rawget(_G, 'stingray'), 'Game Lua API namespace unavailable')
    local Application, World, Unit, Mesh = E.Application, E.World, E.Unit, E.Mesh
    assert(
        type(Application) == 'table' and type(World) == 'table' and type(Unit) == 'table' and type(Mesh) == 'table',
        'Game Lua API tables unavailable'
    )
    assert(type(Application.worlds) == 'function' and type(World.units) == 'function', 'Lua World APIs unavailable')
    assert(
        type(Unit.alive) == 'function'
            and type(Unit.resource_name) == 'function'
            and type(Unit.num_meshes) == 'function'
            and type(Unit.mesh) == 'function'
            and type(Mesh.has_material) == 'function'
            and type(Mesh.material) == 'function',
        'Lua Unit/Material APIs unavailable'
    )
    local worlds, seen = {}, {}
    local function append(world)
        if world ~= nil and not seen[world] then
            assert(#worlds < 64, 'World count bound exceeded')
            worlds[#worlds + 1], seen[world] = world, true
        end
    end
    if type(Application.main_world) == 'function' then
        append(Application.main_world())
    end
    local listed = Application.worlds()
    assert(type(listed) == 'table' and #listed <= 64, 'World list bound changed')
    for _, world in ipairs(listed) do
        append(world)
    end
    local handle, owner
    for _, world in ipairs(worlds) do
        local units = World.units(world)
        assert(type(units) == 'table' and #units <= MAX_UNITS, 'World Unit count bound changed')
        for i, unit in ipairs(units) do
            local ptr = address(unit)
            if ptr and math.floor(ptr / 4) == snapshot.primary_unit_ref then
                assert(not handle, 'Ambiguous primary Unit handle across live worlds')
                handle, owner = unit, world
            end
            if i % 256 == 0 then
                pause()
                current()
            end
        end
        pause()
        current()
    end
    assert(handle, 'No genuine Lua Unit handle matches the inventory primary engine reference')
    assert(Unit.alive(handle) == true, 'Primary Lua Unit disappeared')
    add('lua_unit', 'handle', address(handle), 'world', tostring(owner), 'resource_name', Unit.resource_name(handle))
    current()
    local sections = {}
    local names = assert(mod.read('src/gear/binding_names.lua'))
    names = assert(names:match('local sections = {(.-)\n}'), 'Section catalog format changed')
    for hash, name in names:gmatch("%[0x(%x+)%] = '([^']+)'") do
        sections[#sections + 1] = { id = tonumber(hash, 16), name = name }
    end
    assert(#sections > 0 and #sections <= 1024, 'Section catalog bound changed')
    table.sort(sections, function(a, b)
        return a.id < b.id
    end)
    local small, big = ffi.new('uint8_t[16]'), ffi.new('uint8_t[1024]')
    local function read_into(at, size, out)
        return runtime.read_into(ffi.cast('const uint8_t *', at), size, out)
    end
    local count = tonumber(native.meshes(snapshot.primary_unit_ref))
    assert(count >= 1 and count <= 64, 'Primary mesh count bound changed')
    assert(tonumber(Unit.num_meshes(handle)) == count, 'Lua and native mesh counts differ')
    local total, material_luts, pattern_luts = 0, 0, 0
    local captures, mesh_counts, wanted = {}, {}, {}
    for mesh_index = 0, count - 1 do
        current()
        assert(Unit.alive(handle) == true and native.alive(snapshot.primary_unit_ref) ~= 0, 'Primary disappeared')
        local mesh = tonumber(native.mesh(snapshot.primary_unit_ref, mesh_index))
        assert(mesh and mesh % 1 == 0 and mesh >= 65536 and mesh < 2 ^ 47, 'Invalid primary native Mesh pointer')
        local lua_mesh = Unit.mesh(handle, mesh_index + 1)
        assert(address(lua_mesh) == tonumber(mesh), 'Lua and native Mesh handles differ')
        local material_count = tonumber(native.materials(mesh))
        assert(material_count <= 64, 'Primary material count bound changed')
        mesh_counts[mesh_index] = material_count
        for material_index = 0, material_count - 1 do
            current()
            assert(Unit.alive(handle) == true and native.alive(snapshot.primary_unit_ref) ~= 0, 'Primary disappeared')
            assert(address(Unit.mesh(handle, mesh_index + 1)) == tonumber(mesh), 'Primary Mesh changed')
            total = total + 1
            assert(total <= MAX_MATERIALS, 'Primary total material bound exceeded')
            local material = tonumber(native.material(mesh, material_index))
            assert(material and material >= 65536, 'Invalid native Material pointer')
            local matches = {}
            for index, section in ipairs(sections) do
                if Mesh.has_material(lua_mesh, section.name) == true then
                    if address(Mesh.material(lua_mesh, section.name)) == material then
                        matches[#matches + 1] = string.format('%08x:%s', section.id, section.name)
                    end
                end
                if index % 8 == 0 then
                    pause()
                    current()
                    assert(Unit.alive(handle) == true, 'Primary Lua Unit disappeared')
                    assert(address(Unit.mesh(handle, mesh_index + 1)) == tonumber(mesh), 'Primary Mesh changed')
                    assert(tonumber(native.material(mesh, material_index)) == material, 'Primary Material changed')
                end
            end
            local lut = Engine.binding(read_into, material, Engine.LUT_SLOT, small, big)
            local pattern = Engine.binding(read_into, material, Engine.PATTERN_SLOT, small, big)
            captures[#captures + 1] = {
                mesh_index = mesh_index,
                mesh = mesh,
                material_index = material_index,
                material = material,
                lut = lut,
                pattern = pattern,
            }
            if lut and lut ~= 0 then
                wanted[lut] = true
            end
            if pattern and pattern ~= 0 then
                wanted[pattern] = true
            end
            material_luts = material_luts + (lut and lut ~= 0 and 1 or 0)
            pattern_luts = pattern_luts + (pattern and pattern ~= 0 and 1 or 0)
            add(
                'material',
                'mesh_index',
                mesh_index,
                'mesh_pointer',
                tonumber(mesh),
                'material_index',
                material_index,
                'material_pointer',
                material,
                'SectionID:names',
                #matches > 0 and table.concat(matches, ',') or 'unresolved',
                'MaterialLut_slot',
                string.format('%08x', Engine.LUT_SLOT),
                'MaterialLut_object',
                lut or 'unavailable_or_unbound',
                'PatternLut_slot',
                string.format('%08x', Engine.PATTERN_SLOT),
                'PatternLut_object',
                pattern or 'unavailable_or_unbound',
                'dimensions',
                'unavailable: match object to original resource catalog',
                'raw_pixels',
                'unavailable: no proven runtime CPU pixel reader'
            )
            pause()
        end
    end
    current()
    add('summary', 'materials', total, 'MaterialLut_bindings', material_luts, 'PatternLut_bindings', pattern_luts)
    local Match = mod.require('src/weapons/lut_catalog_match.lua')
    local catalog_file = io.open(directory .. '/catalog.txt', 'rb')
    if not catalog_file then
        add('catalog', 'absent', 'Phase 1 complete; exact texture resource aliases not requested')
        return
    end
    local catalog = catalog_file:read(Match.MAX_BYTES + 1)
    assert(catalog_file:close())
    assert(type(catalog) == 'string' and #catalog <= Match.MAX_BYTES, 'Catalog byte bounds')
    if not next(wanted) then
        add('catalog', 'skipped', 'No bound LUT objects to match')
        return
    end
    -- The build-only identity.validate() is not a current weapon receipt check.
    -- Re-resolve the primary, then prove every captured slot still has the same
    -- Lua/native mesh, material and both texture bindings around each chunk.
    local function stable_bindings()
        current()
        assert(Unit.alive(handle) == true and native.alive(snapshot.primary_unit_ref) ~= 0, 'Primary disappeared')
        assert(tonumber(native.meshes(snapshot.primary_unit_ref)) == count, 'Primary mesh count changed')
        assert(tonumber(Unit.num_meshes(handle)) == count, 'Primary Lua mesh count changed')
        for _, captured in ipairs(captures) do
            local mesh = tonumber(native.mesh(snapshot.primary_unit_ref, captured.mesh_index))
            assert(
                mesh == captured.mesh and address(Unit.mesh(handle, captured.mesh_index + 1)) == mesh,
                'Captured primary Mesh changed'
            )
            assert(
                tonumber(native.materials(mesh)) == mesh_counts[captured.mesh_index],
                'Captured primary material count changed'
            )
            assert(
                tonumber(native.material(mesh, captured.material_index)) == captured.material,
                'Captured primary Material changed'
            )
            assert(
                Engine.binding(read_into, captured.material, Engine.LUT_SLOT, small, big) == captured.lut,
                'Captured MaterialLut binding changed'
            )
            assert(
                Engine.binding(read_into, captured.material, Engine.PATTERN_SLOT, small, big) == captured.pattern,
                'Captured PatternLut binding changed'
            )
        end
        return true
    end
    local matcher = Match.new({
        lookup = function(resource)
            return Engine.texture_object(native, resource)
        end,
        validate = stable_bindings,
    }, catalog, wanted)
    local result = matcher.result()
    while not result.complete and not result.refused do
        result = matcher.step(8)
        if not result.complete and not result.refused then
            pause()
        end
    end
    assert(not result.refused, result.reason)
    local objects, required_rows = {}, 0
    for object in pairs(wanted) do
        objects[#objects + 1] = object
        required_rows = required_rows + math.max(1, #(result.matches[object] or {}))
    end
    assert(#rows + required_rows + 2 < MAX_ROWS, 'Exact alias report row bound exceeded')
    table.sort(objects)
    for _, object in ipairs(objects) do
        local aliases = result.matches[object] or {}
        if #aliases == 0 then
            add('texture_resource_unmatched', 'object', object, 'resource', 'unresolved_after_complete_catalog')
        else
            for index, resource in ipairs(aliases) do
                add(
                    'texture_resource_alias',
                    'object',
                    object,
                    'resource',
                    resource,
                    'alias_index',
                    index,
                    'alias_count',
                    #aliases
                )
            end
        end
    end
    add(
        'catalog_summary',
        'state',
        result.state,
        'processed',
        result.processed,
        'total',
        result.total,
        'objects',
        #objects
    )
end
local function save(ctx, state, reason)
    add('result', state, reason or '')
    local suffix = os.date('%Y%m%d-%H%M%S')
        .. '-'
        .. tostring(math.floor((runtime and runtime.time() or os.clock()) * 1000000))
    local path = directory .. '/primary-lut-probe-' .. suffix .. '.tsv'
    local prior = io.open(path, 'rb')
    if prior then
        prior:close()
        error('Diagnostic output already exists; refusing overwrite')
    end
    local file = assert(io.open(path, 'wb'))
    assert(file:write(table.concat(rows, '\n') .. '\n'))
    assert(file:close())
    ctx.log('Primary LUT probe ' .. state .. ': ' .. (reason or path))
    ctx.log('Read-only output: ' .. path)
    job, rows, runtime, completed = nil, nil, nil, true
end
return {
    name = 'Epic LUT R6 primary LUT read-only probe',
    on_enable = function(ctx)
        assert(mod and type(mod.require) == 'function', 'Scoped LLL project API required')
        directory, rows, completed = ctx.dir, {}, false
        job = coroutine.create(function()
            collect(ctx)
        end)
        ctx.log('Read-only primary LUT probe enabled; R5 editor untouched')
    end,
    on_update = function(ctx)
        if completed or not job then
            return
        end
        local cancel = io.open(directory .. '/cancel.txt', 'rb')
        if cancel then
            cancel:close()
            save(ctx, 'cancelled', 'Own cancel sentinel present')
            return
        end
        local now = runtime and runtime.time or os.clock
        local started = now()
        for _ = 1, 8 do
            local ok, why = coroutine.resume(job)
            if not ok then
                save(ctx, 'refused', tostring(why))
                return
            end
            if coroutine.status(job) == 'dead' then
                save(ctx, 'completed')
                return
            end
            if now() - started >= 0.0015 then
                break
            end
        end
    end,
    on_disable = function(ctx)
        job, rows, runtime, completed = nil, nil, nil, true
        ctx.log('Read-only primary LUT probe cleanup acknowledged; no game ownership retained')
        return true
    end,
}
