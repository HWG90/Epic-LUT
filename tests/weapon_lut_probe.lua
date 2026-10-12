local ffi = require('ffi')
local CatalogMatch = dofile('src/weapons/lut_catalog_match.lua')
local PRIMARY, MESH, MATERIAL, LUT = 123, 0x50000, 0x60000, 0x70000
local function pointer(value)
    return ffi.cast('void *', value)
end
local function fixture(options)
    options = options or {}
    local handle = pointer(PRIMARY * 4)
    local calls = { snapshots = 0, open = 0, materials = 0, material = 0, lua_mesh = 0, bindings = 0, lookups = 0 }
    local logs, files, written, changed = {}, {}, {}, false
    local active_mesh, active_material, active_lut = MESH, MATERIAL, LUT
    local elapsed = 123.5
    local function timer()
        elapsed = elapsed + (options.timer_step or 0)
        return elapsed
    end
    local expected = {
        game_base = 0x100000,
        player_entity = 7,
        avatar_entity = 8,
        avatar_native_ref = 9,
        primary_entity = 10,
        primary_record = 0x30000,
        primary_resource_hex = '5fecab819f96a3e8',
        primary_unit_ref = PRIMARY,
        primary_native_ref = 11,
        primary_object = 0x40000,
        inventory_slot = 1,
        inventory_held_entity = 10,
        provenance = 'inventory_slot_1',
    }
    local Primary = {
        new = function(deps)
            assert(type(deps.module) == 'function' and type(deps.read) == 'function')
            assert(type(deps.verify_build) == 'function')
            return {
                snapshot = function()
                    calls.snapshots = calls.snapshots + 1
                    if
                        options.initial_failure
                        or options.initial_waits and calls.snapshots <= options.initial_waits
                    then
                        return nil, options.initial_failure or 'Invalid pointer'
                    end
                    local result = {}
                    for key, value in pairs(expected) do
                        result[key] = value
                    end
                    if changed or options.change_at and calls.snapshots >= options.change_at then
                        changed = true
                        result.primary_unit_ref = PRIMARY + 1
                    end
                    return result
                end,
                validate = function()
                    error('Build-only validate must not replace live receipt re-resolution')
                end,
            }
        end,
    }
    local native = {
        alive = function(ref)
            assert(ref == PRIMARY and not changed, 'Native alive reached a changed primary')
            return 1
        end,
        meshes = function(ref)
            assert(ref == PRIMARY and not changed)
            return 1
        end,
        mesh = function(ref, index)
            assert(ref == PRIMARY and index == 0 and not changed)
            return options.null_mesh and 0 or active_mesh
        end,
        materials = function(mesh)
            calls.materials = calls.materials + 1
            assert(mesh == active_mesh and not changed, 'Native materials reached a null/stale Mesh')
            return 1
        end,
        material = function(mesh, index)
            calls.material = calls.material + 1
            assert(mesh == active_mesh and index == 0 and not changed, 'Native material reached a stale primary')
            return active_material
        end,
    }
    local Engine = {
        LUT_SLOT = 0x7e662968,
        PATTERN_SLOT = 0x81d4c49d,
        open = function(memory, game, executable)
            calls.open = calls.open + 1
            assert(memory and game == expected.game_base and executable == 0x200000 and not changed)
            return native
        end,
        binding = function(read, material, slot, small, big)
            calls.bindings = calls.bindings + 1
            assert(not changed and material == active_material and ffi.sizeof(small) == 16 and ffi.sizeof(big) == 1024)
            assert(read(material + 24, 16, small))
            if not options.no_lut and slot == 0x7e662968 then
                return active_lut
            end
            if slot == 0x81d4c49d then
                return options.pattern
            end
        end,
        texture_object = function(received, resource)
            calls.lookups = calls.lookups + 1
            assert(received == native and not changed, 'Lookup reached a changed primary')
            if options.fail_lookup_at == calls.lookups then
                error('catalog lookup failed')
            end
            if options.stale_primary then
                changed = true
            end
            if options.stale_mesh then
                active_mesh = MESH + 256
            end
            if options.stale_material then
                active_material = MATERIAL + 256
            end
            if options.stale_lut then
                active_lut = LUT + 256
            end
            return (options.aliases or {})[resource]
        end,
    }
    local memory = {
        read = function()
            return string.rep('\0', 16)
        end,
        read_into = function(_, size, out)
            assert(size == 16)
            ffi.fill(out, size, 0)
            return true
        end,
        address = tonumber,
        module = function(name)
            return name == 'game.dll' and expected.game_base or 0x200000
        end,
        time = timer,
        verify_build = function()
            return true
        end,
    }
    local units = { handle }
    if options.unit_count then
        for i = 2, options.unit_count do
            units[i] = i
        end
    end
    local env = setmetatable({
        Application = {
            main_world = function()
                return 'main'
            end,
            worlds = function()
                return { 'main', 'other' }
            end,
        },
        World = {
            units = function(world)
                return world == 'main' and units or options.ambiguous and { handle } or {}
            end,
        },
        Unit = {
            alive = function(unit)
                assert(unit == handle and type(unit) == 'cdata' and not changed)
                return true
            end,
            resource_name = function(unit)
                assert(unit == handle and not changed)
                return '#ID[abcdef0123456789]'
            end,
            num_meshes = function(unit)
                assert(unit == handle and not changed)
                return 1
            end,
            mesh = function(unit, index)
                calls.lua_mesh = calls.lua_mesh + 1
                assert(unit == handle and index == 1 and not changed)
                return pointer(options.null_mesh and 0 or active_mesh)
            end,
        },
        Mesh = {
            has_material = function(mesh, name)
                assert(mesh == pointer(MESH) and not changed)
                return name == 'm_weapon'
            end,
            material = function(mesh, name)
                assert(mesh == pointer(MESH) and name == 'm_weapon' and not changed)
                return pointer(MATERIAL)
            end,
        },
        os = {
            date = function()
                return '20261011-120000'
            end,
            clock = timer,
        },
    }, { __index = _G })
    env._G = env
    env.stingray = { Application = env.Application, World = env.World, Unit = env.Unit, Mesh = env.Mesh }
    env.Application, env.World, env.Unit, env.Mesh = nil, nil, nil, nil
    env.io = {
        open = function(path, mode)
            if mode == 'rb' then
                if path == 'probe/catalog.txt' and options.catalog then
                    return {
                        read = function(_, size)
                            assert(size == CatalogMatch.MAX_BYTES + 1)
                            return options.catalog:sub(1, size)
                        end,
                        close = function()
                            return true
                        end,
                    }
                end
                if path:match('/cancel.txt$') and options.cancel then
                    return {
                        close = function()
                            return true
                        end,
                    }
                end
                if files[path] then
                    return {
                        close = function()
                            return true
                        end,
                    }
                end
                return nil
            end
            assert(mode == 'wb' and path:match('^probe/primary%-lut%-probe%-') and not files[path])
            local body = ''
            return {
                write = function(_, value)
                    body = body .. value
                    return true
                end,
                close = function()
                    files[path], written[#written + 1] = body, path
                    return true
                end,
            }
        end,
    }
    local catalog = { 'local sections = {', "    [0x7c4a4a11] = 'm_weapon'," }
    for i = 1, 16 do
        catalog[#catalog + 1] = string.format("    [0x%08x] = 'm_unused_%d',", i, i)
    end
    catalog[#catalog + 1] = '}'
    local dependencies = {
        ['src/weapons/primary_identity.lua'] = Primary,
        ['src/weapons/lut_catalog_match.lua'] = CatalogMatch,
        ['vendor/engine.lua'] = Engine,
        ['vendor/bingus_runtime.lua'] = {},
        ['vendor/bingus_memory.lua'] = {
            new = function()
                return memory
            end,
        },
    }
    env.mod = {
        require = function(path)
            return assert(dependencies[path], 'Unexpected probe dependency ' .. path)
        end,
        read = function(path)
            assert(path == 'src/gear/binding_names.lua')
            return table.concat(catalog, '\n')
        end,
    }
    local chunk = assert(loadfile('tools/weapon_lut_probe/main.lua'))
    setfenv(chunk, env)
    local lifecycle = chunk()
    local ctx = {
        dir = 'probe',
        log = function(value)
            logs[#logs + 1] = value
        end,
    }
    lifecycle.on_enable(ctx)
    local self = { calls = calls, logs = logs, files = files, written = written, lifecycle = lifecycle, ctx = ctx }
    function self.finish()
        for _ = 1, 200 do
            lifecycle.on_update(ctx)
            elapsed = elapsed + (options.advance_per_update or 0)
            if #written > 0 then
                break
            end
        end
        assert(#written == 1, 'Probe did not emit exactly one diagnostic output')
        return files[written[1]]
    end
    function self.disable()
        assert(lifecycle.on_disable(ctx) == true)
        assert(logs[#logs]:find('cleanup acknowledged', 1, true))
    end
    return self
end
local success = fixture()
local report = success.finish()
assert(report:find('result\tcompleted', 1, true))
assert(report:find('SectionID:names\t7c4a4a11:m_weapon', 1, true))
assert(report:find('MaterialLut_slot\t7e662968\tMaterialLut_object\t' .. LUT, 1, true))
assert(report:find('PatternLut_object\tunavailable_or_unbound', 1, true))
assert(report:find('dimensions\tunavailable:', 1, true) and report:find('raw_pixels\tunavailable:', 1, true))
local calls_before = success.calls.material
for _ = 1, 20 do
    success.lifecycle.on_update(success.ctx)
end
assert(#success.written == 1 and success.calls.material == calls_before, 'Completed probe resumed native work')
success.disable()
local early_change = fixture({ change_at = 2 })
assert(early_change.finish():find('Captured primary identity changed: primary_unit_ref', 1, true))
assert(early_change.calls.open == 0 and early_change.calls.materials == 0 and early_change.calls.material == 0)
early_change.disable()
local later_change = fixture({ change_at = 9 })
assert(later_change.finish():find('Captured primary identity changed: primary_unit_ref', 1, true))
later_change.disable()
local ambiguous = fixture({ ambiguous = true })
assert(ambiguous.finish():find('Ambiguous primary Unit handle', 1, true))
assert(ambiguous.calls.materials == 0 and ambiguous.calls.material == 0)
ambiguous.disable()
local null = fixture({ null_mesh = true })
assert(null.finish():find('Invalid primary native Mesh pointer', 1, true))
assert(null.calls.materials == 0 and null.calls.material == 0 and null.calls.lua_mesh == 0)
null.disable()
local unavailable = fixture({ no_lut = true })
assert(unavailable.finish():find('MaterialLut_object\tunavailable_or_unbound', 1, true))
unavailable.disable()
local cancel = fixture({ cancel = true })
assert(cancel.finish():find('result\tcancelled', 1, true))
assert(cancel.calls.snapshots == 0 and cancel.calls.open == 0 and cancel.calls.material == 0)
cancel.disable()
local cleanup = fixture()
cleanup.disable()
cleanup.lifecycle.on_update(cleanup.ctx)
assert(#cleanup.written == 0 and cleanup.calls.open == 0 and cleanup.calls.snapshots == 0)
local excessive = fixture({ unit_count = 131073 })
assert(excessive.finish():find('World Unit count bound changed', 1, true))
assert(excessive.calls.materials == 0 and excessive.calls.material == 0)
excessive.disable()
local ID1, ID2, ID3 = '1111111111111111', '2222222222222222', '3333333333333333'
local matching = fixture({
    catalog = ID1 .. '\r\n' .. ID2 .. '\r\n' .. ID1 .. '\r\n' .. ID3 .. '\r\n',
    aliases = { [ID1] = LUT, [ID2] = LUT },
    pattern = LUT + 100,
})
local matching_report = matching.finish()
assert(matching_report:find('result\tcompleted', 1, true))
assert(matching_report:find('resource\t' .. ID1 .. '\talias_index\t1\talias_count\t2', 1, true))
assert(matching_report:find('resource\t' .. ID2 .. '\talias_index\t2\talias_count\t2', 1, true))
assert(matching_report:find('texture_resource_unmatched\tobject\t' .. (LUT + 100), 1, true))
assert(matching_report:find('catalog_summary\tstate\tcomplete\tprocessed\t3\ttotal\t3', 1, true))
assert(matching.calls.lookups == 3, 'Case/ID duplicate produced an extra ResourceManager lookup')
matching.disable()
local failed_lookup = fixture({ catalog = ID1 .. '\n' .. ID2, aliases = { [ID1] = LUT }, fail_lookup_at = 2 })
local failed_report = failed_lookup.finish()
assert(failed_report:find('result\trefused', 1, true) and failed_report:find('catalog lookup failed', 1, true))
assert(not failed_report:find('texture_resource_alias', 1, true), 'Partial failed aliases escaped into output')
failed_lookup.disable()
for option, reason in pairs({
    stale_primary = 'Captured primary identity changed',
    stale_mesh = 'Captured primary Mesh changed',
    stale_material = 'Captured primary Material changed',
    stale_lut = 'Captured MaterialLut binding changed',
}) do
    local opts = { catalog = ID1, aliases = { [ID1] = LUT } }
    opts[option] = true
    local stale = fixture(opts)
    local stale_report = stale.finish()
    assert(stale_report:find('result\trefused', 1, true) and stale_report:find(reason, 1, true), stale_report)
    assert(not stale_report:find('texture_resource_alias', 1, true), 'Stale aliases escaped into output')
    stale.disable()
end
local large = fixture({ catalog = string.rep('0', CatalogMatch.MAX_BYTES + 1) })
assert(large.finish():find('Catalog byte bounds', 1, true))
assert(large.calls.lookups == 0)
large.disable()
local timed = fixture({ timer_step = 0.002, catalog = ID1, aliases = { [ID1] = LUT } })
timed.lifecycle.on_update(timed.ctx)
assert(timed.calls.snapshots == 1 and timed.calls.open == 0, 'Elapsed-time budget did not stop after the first yield')
assert(timed.finish():find('texture_resource_alias', 1, true))
timed.disable()
local readiness = fixture({ initial_waits = 2, advance_per_update = 1 })
readiness.lifecycle.on_update(readiness.ctx)
assert(
    readiness.calls.snapshots == 1 and readiness.calls.open == 0,
    'Initial readiness wait entered native engine calls'
)
local ready_report = readiness.finish()
assert(ready_report:find('initial_identity\tready', 1, true) and ready_report:find('result\tcompleted', 1, true))
local waiting_logs = 0
for _, message in ipairs(readiness.logs) do
    if message:find('Waiting for initial', 1, true) then
        waiting_logs = waiting_logs + 1
    end
end
assert(waiting_logs == 1, 'Readiness waiting log repeated')
readiness.disable()
local timeout = fixture({ initial_failure = 'No local avatar', advance_per_update = 1 })
local timeout_report = timeout.finish()
assert(
    timeout_report:find('result\trefused', 1, true)
        and timeout_report:find('readiness timed out after 60 seconds', 1, true)
)
assert(timeout.calls.open == 0 and timeout.calls.materials == 0 and timeout.calls.material == 0)
timeout.disable()
local unsupported = fixture({ initial_failure = 'Unsupported game PE build' })
assert(unsupported.finish():find('Unsupported game PE build', 1, true))
assert(unsupported.calls.snapshots == 1 and unsupported.calls.open == 0)
for _, message in ipairs(unsupported.logs) do
    assert(not message:find('Waiting for initial', 1, true), 'Unsupported build entered readiness retry')
end
unsupported.disable()
local waiting_options = { initial_failure = 'Invalid pointer' }
local waiting_cancel = fixture(waiting_options)
waiting_cancel.lifecycle.on_update(waiting_cancel.ctx)
assert(waiting_cancel.calls.snapshots == 1 and waiting_cancel.calls.open == 0)
waiting_options.cancel = true
assert(waiting_cancel.finish():find('result\tcancelled', 1, true))
assert(waiting_cancel.calls.open == 0 and waiting_cancel.calls.material == 0)
waiting_cancel.disable()
local waiting_cleanup = fixture({ initial_failure = 'No local player' })
waiting_cleanup.lifecycle.on_update(waiting_cleanup.ctx)
assert(waiting_cleanup.calls.snapshots == 1)
waiting_cleanup.disable()
waiting_cleanup.lifecycle.on_update(waiting_cleanup.ctx)
assert(waiting_cleanup.calls.snapshots == 1 and waiting_cleanup.calls.open == 0 and #waiting_cleanup.written == 0)
print(
    'PASS: read-only primary probe lifecycle, receipt stability, exact slots, pointer guards, cancellation and bounds'
)
