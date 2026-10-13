-- Offline Link's script-envelope fixture over the real cooperative matcher.
local ffi = require('ffi')
local Match = dofile('src/weapons/lut_catalog_match.lua')
local function fixture(change, options)
    options = options or {}
    local logs, written, captures, lookups = {}, {}, {}, 0
    local changed, native_calls, name_changed, pointer_changed = false, 0, false, false
    local bindings = {
        {
            weapon_slot = 1,
            save_key = '3:1:4:0',
            mesh_index = 4,
            material_index = 0,
            original = 0x70000,
            mesh = 0x50000,
            material = 0x60000,
            family = 'material',
        },
        {
            weapon_slot = 1,
            save_key = '3:1:4:0',
            mesh_index = 4,
            material_index = 0,
            original = 0x80000,
            mesh = 0x50000,
            material = 0x60000,
            family = 'pattern',
        },
        {
            weapon_slot = 2,
            save_key = '3:2:2:0',
            mesh_index = 2,
            material_index = 0,
            original = 0x70000,
            mesh = 0x51000,
            material = 0x61000,
            family = 'material',
        },
    }
    local native = {
        alive = function()
            return 1
        end,
        meshes = function()
            native_calls = native_calls + 1
            return 5
        end,
        mesh = function(unit)
            return unit == 101 and 0x50000 or 0x51000
        end,
        materials = function()
            return 1
        end,
        material = function(mesh)
            return mesh == 0x50000 and 0x60000 or 0x61000
        end,
        can_get = function()
            return 1
        end,
        get = function()
            return 0x70000
        end,
    }
    for _, name in ipairs({ 'bind', 'commit', 'set_resource', 'create', 'update', 'destroy' }) do
        native[name] = function()
            error('Unexpected native write or allocation: ' .. name)
        end
    end
    local runtime = {
        read = function(_, n)
            return string.rep('\0', n)
        end,
        module = function(name)
            return name == 'game.dll' and 0x100000 or 0x200000
        end,
        address = function(value)
            return value
        end,
        verify_build = function()
            return true
        end,
        read_into = function()
            return true
        end,
        time = function()
            return 123.5
        end,
    }
    local Discovery = { LUT = 0x7e662968, PATTERN = 0x81d4c49d }
    function Discovery.new(_, deps)
        assert(deps.identity and deps.read and deps.native)
        assert(not deps.native.commit and not deps.native.create and not deps.native.set_resource)
        return {
            capture = function(slot)
                captures[#captures + 1] = slot
                if slot == 3 then
                    return nil, 'Weapon inventory slot is empty'
                end
                return {
                    weapon_slot = slot,
                    weapon_resource64 = string.rep(tostring(slot), 16),
                    unit_resource64 = string.rep(tostring(slot), 16),
                    unit = 100 + slot,
                    lua_unit = slot,
                }
            end,
            materials = function(receipt)
                return {
                    {
                        mesh_index = receipt.weapon_slot == 1 and 4 or 2,
                        material_index = 0,
                        mesh = receipt.weapon_slot == 1 and 0x50000 or 0x51000,
                    },
                }
            end,
            descriptor = function(receipt, _, hash)
                for _, binding in ipairs(bindings) do
                    local expected = binding.family == 'material' and Discovery.LUT or Discovery.PATTERN
                    if binding.weapon_slot == receipt.weapon_slot and expected == hash then
                        binding.receipt, binding.unit, binding.slot = receipt, receipt.unit, hash
                        return binding
                    end
                end
            end,
            validate = function()
                return not changed, changed and 'Identity changed'
            end,
            present = function()
                return not changed, changed and 'Binding changed'
            end,
            binding = function(binding)
                return binding.original
            end,
        }
    end
    local catalog_rows = {}
    for id = 1, 19 do
        catalog_rows[#catalog_rows + 1] = string.format('%016x', id)
    end
    local libraries = {
        r6_weapon_probe_primary_identity = {
            new = function()
                return {
                    validate = function()
                        return true
                    end,
                }
            end,
        },
        r6_weapon_probe_weapon_discovery = Discovery,
        r6_weapon_probe_engine = {
            open = function()
                return native
            end,
            binding = function(_, material, slot)
                for _, binding in ipairs(bindings) do
                    if binding.material == material and binding.slot == slot then
                        return binding.original
                    end
                end
            end,
            texture_object = function(adapter, resource)
                assert(adapter.alive and not adapter.create)
                lookups = lookups + 1
                if change and lookups == 1 then
                    changed = true
                end
                if options.change_name and lookups == 1 then
                    name_changed = true
                end
                local id = tonumber(resource, 16)
                if id == 1 or id == 2 then
                    return 0x70000
                end
                if id == 3 then
                    return 0x80000
                end
            end,
        },
        r6_weapon_probe_bingus_memory = {
            new = function()
                return runtime
            end,
        },
        r6_weapon_probe_bingus_runtime = {},
        r6_weapon_probe_lut_catalog_match = Match,
    }
    local env = setmetatable({
        ffi = ffi,
        stingray = {
            Unit = {
                num_meshes = function()
                    return 5
                end,
                mesh = function(slot)
                    local pointer = slot == 1 and 0x50000 or 0x51000
                    return ffi.cast('void *', pointer + (pointer_changed and 0x100 or 0))
                end,
            },
        },
        use = function(name)
            return assert(libraries[name], name)
        end,
        module = function(name)
            return name == 'game.dll' and 0x100000 or 0x200000, 0x4744000, 0x6ab3b43f
        end,
        load_file = function(name)
            if name == 'r6_weapon_catalog.txt' then
                return table.concat(catalog_rows, '\n') .. '\n'
            end
            if name == 'r6_weapon_probe_manifest.json' then
                return '{"readonly":true}'
            end
            if name == 'r6_weapon_probe_manifest.sha256' then
                return string.rep('a', 64)
            end
        end,
        save_file = function(name, text)
            written[name] = text
        end,
        out = function(...)
            logs[#logs + 1] = { ... }
        end,
    }, { __index = _G })
    if options.mesh_name then
        env.stingray.Mesh = {
            name = function(handle)
                assert(type(handle) == 'cdata', 'Mesh.name received a fabricated numeric handle')
                assert(
                    tonumber(ffi.cast('uintptr_t', handle)) == 0x50000
                        or tonumber(ffi.cast('uintptr_t', handle)) == 0x51000
                )
                if options.change_pointer then
                    pointer_changed = true
                end
                if options.change_identity then
                    changed = true
                end
                if options.invalid_name_enabled then
                    return options.invalid_name
                end
                local value = options.name_value == nil and -1 or options.name_value
                return value + (name_changed and 1 or 0)
            end,
        }
    end
    env._G = env
    local chunk = assert(loadfile('tools/links_weapon_probe/probe.lua'))
    setfenv(chunk, env)
    local step = chunk()
    local frames = 0
    repeat
        frames = frames + 1
        assert(frames <= 100)
    until step()
    return assert(written['r6_weapon_probe.tsv']), captures, lookups, frames, native_calls
end
local report, captured, lookups, frames, calls = fixture(false)
assert(table.concat(captured, ',') == '1,2,3', report)
assert(lookups == 19 and frames >= 8 and calls > 0)
assert(report:find('result\tcomplete', 1, true))
assert(report:find('weapon\t3\tunavailable\tWeapon inventory slot is empty', 1, true))
assert(report:find('mapped\t1\tmaterial\t3:1:4:0', 1, true))
assert(report:find('mapped\t1\tpattern\t3:1:4:0', 1, true))
assert(report:find('texture_object\t458752\tbindings\t2\taliases\t2\t0000000000000001,0000000000000002', 1, true))
local refused, _, refused_lookups = fixture(true)
assert(refused:find('result\trefused', 1, true))
assert(not refused:find('mapped\t', 1, true))
assert(refused_lookups == 8)
assert(report:find('mesh_name_api\tunavailable', 1, true))
assert(report:find('mesh_id_unavailable', 1, true))
local named = fixture(false, { mesh_name = true })
assert(named:find('result\tcomplete', 1, true), named)
assert(named:find('mesh_name_api\tavailable', 1, true))
assert(named:find('mesh_id\t1\t4\t327680\tffffffff\t-1', 1, true))
assert(named:find('never guessed\tffffffff', 1, true), 'Mapped destination omitted its verified MeshName ID')
local minimum = fixture(false, { mesh_name = true, name_value = -0x80000000 })
assert(minimum:find('mesh_id\t1\t4\t327680\t80000000\t-2147483648', 1, true))
local maximum = fixture(false, { mesh_name = true, name_value = 0xffffffff })
assert(maximum:find('mesh_id\t1\t4\t327680\tffffffff\t4294967295', 1, true))
for _, case in ipairs({
    {},
    { value = false },
    { value = 'bad' },
    { value = 0 / 0 },
    { value = math.huge },
    { value = 0.5 },
    { value = -0x80000001 },
    { value = 0x100000000 },
}) do
    local invalid = fixture(false, { mesh_name = true, invalid_name_enabled = true, invalid_name = case.value })
    assert(invalid:find('result\trefused\t', 1, true), invalid)
    assert(invalid:find('Invalid runtime MeshName ID', 1, true), invalid)
    assert(not invalid:find('mapped\t', 1, true))
end
for _, option in ipairs({ 'change_name', 'change_pointer', 'change_identity' }) do
    local settings = { mesh_name = true }
    settings[option] = true
    local unstable = fixture(false, settings)
    assert(unstable:find('result\trefused\t', 1, true), unstable)
    assert(not unstable:find('mapped\t', 1, true))
end
print(
    'PASS Links weapon probe: all slots, complete aliases, query-only native adapter, optional signed MeshName IDs, invalid/stale hash and identity/pointer refusal'
)
