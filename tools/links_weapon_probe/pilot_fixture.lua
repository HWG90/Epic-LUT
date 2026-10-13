-- Test the pilot envelope through the real production runtime/session/discovery.
local ffi = require('ffi')
local Runtime = dofile('src/weapons/weapon_runtime.lua')
local Session = dofile('src/gear/binding_session.lua')
local Discovery = dofile('src/weapons/weapon_discovery.lua')
local DDS = dofile('src/core/dds.lua')
local Fixture = dofile('tests/weapon_fixture.lua')
local function test(privacy_failure, fail_restore, fail_load)
    local f, clock, report, current = Fixture(), 0, nil, 0x70000000
    local Engine = dofile('vendor/engine.lua')
    local original = DDS.encode(f.documents[f.A].data, 23, 8)
    local native = f.native
    native.can_get = function() return 1 end
    native.get = function() return f.A end
    native.create = function(_, _, _, _, pixels)
        f.allocations = f.allocations + 1
        assert(pixels[0] == 1 and pixels[1] == 0 and pixels[2] == 1)
        assert(pixels[3] == f.documents[f.A].data[3], 'Original Alpha changed')
        return 23
    end
    native.resource = function(handle) assert(handle == 23); return current end
    native.destroy = function() error('Pilot freed retained backing') end
    native.commit = function() end
    native.set_resource = function(material, slot, object)
        if fail_restore and object == f.A then error('Restore refused') end
        f.writes[#f.writes + 1] = { material, slot, object }
        f.textures[material][slot] = object
    end
    Engine.open = function() return native end -- Bounded fake engine port only.
    if privacy_failure then
        f.units[300].meshes[1].materials[1] = f.units[100].meshes[1].materials[1]
    end
    local memory = {
        module = function(name) return name == 'game.dll' and 0x100000 or 0x200000 end,
        address = function(value) return value end,
        time = function() return clock end,
        verify_build = function() return true end,
        read = function(address, size) return f.read(tonumber(ffi.cast('uintptr_t', address)), size) end,
        read_into = function(address, size, buffer)
            local value = tonumber(ffi.cast('uintptr_t', address))
            local bytes = value == current and '\1\0\0\0' or f.read(value, size)
            if not bytes then return false end
            ffi.copy(buffer, bytes, size)
            return true
        end,
    }
    local libraries = {
        r6_weapon_probe_primary_identity = { new = function()
            f.identity.validate = function() return true end
            return f.identity
        end },
        r6_weapon_probe_weapon_discovery = Discovery,
        r6_weapon_probe_weapon_runtime = { new = function(deps)
            local created = Runtime.new(deps)
            if fail_load then created.load = function() error('Original source load rejected') end end
            return created
        end },
        r6_weapon_probe_binding_session = Session, r6_weapon_probe_dds = DDS,
        r6_weapon_probe_engine = Engine, r6_weapon_probe_bingus_runtime = {},
        r6_weapon_probe_bingus_memory = { new = function() return memory end },
    }
    local env = setmetatable({ ffi = ffi, stingray = f.E, package = { loaded = {} },
        use = function(name) return assert(libraries[name], name) end,
        load_file = function(name)
            if name == 'r6_weapon_pilot.cfg' then
                return 'resource=babd338977faa2ff\nweapon=5fecab819f96a3e8\ndds_sha256=' .. string.rep('a', 64) .. '\n'
            end
            if name == 'r6_weapon_pilot_dds.hex' then
                return original:gsub('.', function(value) return string.format('%02x', value:byte()) end)
            end
        end,
        unhex = function(text) return (text:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)) end,
        save_file = function(name, text) assert(name == 'r6_weapon_pilot.tsv'); report = text end,
        out = function() end,
    }, { __index = _G })
    env._G = env
    local chunk = assert(loadfile('tools/links_weapon_probe/pilot.lua'))
    setfenv(chunk, env)
    local step, cleanup = chunk()
    local frames = 0
    repeat frames = frames + 1; clock = clock + 0.5; assert(frames <= 100); until step()
    cleanup()
    local kept = env.package.loaded['epic.links.weapon.pilot.retained.v1'].runs[1]
    assert(report)
    if fail_load then
        assert(f.allocations == 0 and #f.writes == 0)
        assert(report:find('result\trefused_before_apply', 1, true), report)
        assert(not report:find('\nresult\trestored', 1, true), 'Early failure was reported as successful apply/restore')
        assert(report:find('cleanup_result\trestored\t0\t0', 1, true), report)
    elseif privacy_failure then
        assert(f.allocations == 0 and #f.writes == 0, 'Allocation occurred before material privacy proof')
    elseif fail_restore then
        assert(kept.state == 'quarantined' and kept.retain.bytes == 23 * 8 * 16)
        assert(kept.retain.records[1].data ~= nil, 'Failed restoration released native backing')
    else
        assert(report:find('result\trestored', 1, true), report)
        assert(f.allocations == 1 and #f.writes == 10, 'Expected five apply and five restore writes')
        assert(kept.state == 'restored' and kept.retain.records[1].data ~= nil)
        for _, unit in pairs(f.units) do
            for _, mesh in ipairs(unit.meshes) do
                assert(f.textures[mesh.materials[1]][Discovery.LUT] == f.A)
                assert(f.textures[mesh.materials[1]][Discovery.PATTERN] == f.P)
                assert(f.textures[mesh.materials[2]][Discovery.LUT] == f.B)
            end
        end
    end
end
test(false, false)
test(true, false)
test(false, true)
test(false, false, true)
print('PASS Links pilot: production all-LOD apply/restore, unchanged other destinations, privacy refusal before allocation, failed cleanup retains backing')
