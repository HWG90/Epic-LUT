local ffi = require('ffi')
local fixture = dofile('tests/weapon_fixture.lua')
local P = dofile('src/presets/binding_provenance.lua')
local L = dofile('src/presets/binding_unit_layout.lua')
local Materials = dofile('src/gear/material_identity.lua')
local W = dofile('src/weapons/weapon_provenance.lua')
local function word(value)
    local out = {}
    for index = 1, 4 do
        out[index] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(out)
end
local function hash(value)
    local out = ''
    for index = 15, 1, -2 do
        out = out .. string.char(tonumber(value:sub(index, index + 1), 16))
    end
    return out
end
local function replace(data, at, value)
    return data:sub(1, at) .. value .. data:sub(at + #value + 1)
end
local function record(resource, kind, main, archive)
    local toc = hash(resource)
        .. hash(kind)
        .. string.rep('\0', 40)
        .. word(#main)
        .. word(0)
        .. word(0)
        .. string.rep('\0', 12)
    return {
        resource = resource,
        archive = archive,
        toc = toc,
        main = main,
        gpu = '',
        stream = '',
        main_sha256 = P.digest(main),
        index_stamp = ('c'):rep(64),
    }
end
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
local function setup()
    local f = fixture()
    f.runtime.refresh(1)
    local weapon, rail, body = '5fecab819f96a3e8', 'aaaaaaaaaaaa0002', 'aaaaaaaaaaaa0001'
    local section_body, section_rail = 0x7c4a4a11, 0x06fea65d
    local mesh_table = word(5)
    local mesh_at = 128 + 4 + 5 * 8
    local mesh_records, mesh_hashes, mesh_offsets = {}, {}, {}
    for index = 0, 4 do
        mesh_offsets[#mesh_offsets + 1] = word(mesh_at + index * 136 - 128)
        mesh_hashes[#mesh_hashes + 1] = word(0x100 + index)
        local mesh = replace(string.rep('\0', 128), 40, word(0x100 + index))
        mesh = replace(mesh, 104, word(2) .. word(128))
        mesh = replace(mesh, 120, word(0) .. word(136))
        mesh_records[#mesh_records + 1] = mesh .. word(section_body) .. word(section_rail)
    end
    local material_at = mesh_at + 5 * 136
    local header = replace(string.rep('\0', 128), 44, word(10800438))
    header = replace(header, 100, word(128))
    header = replace(header, 112, word(material_at))
    header = replace(header, 96, word(material_at + 28))
    local main = header
        .. mesh_table
        .. table.concat(mesh_offsets)
        .. table.concat(mesh_hashes)
        .. table.concat(mesh_records)
        .. word(2)
        .. word(section_body)
        .. word(section_rail)
        .. hash(body)
        .. hash(rail)
        .. string.rep('\0', 8)
    local mat_body = replace(string.rep('\0', 136), 64, word(2))
        .. word(P.LUT)
        .. word(P.PATTERN)
        .. hash('babd338977faa2ff')
        .. hash('cf0cc31b981786c9')
    local mat_rail = replace(string.rep('\0', 136), 64, word(1)) .. word(P.LUT) .. hash('d1c943c12a564150')
    f.unit_source = record(weapon, P.UNIT, main, '1111111111111111')
    f.material_sources = {
        [body] = record(body, P.MATERIAL, mat_body, '2222222222222222'),
        [rail] = record(rail, P.MATERIAL, mat_rail, '3333333333333333'),
    }
    local mesh_original = f.E.Unit.mesh
    f.E.Unit.has_mesh = function(handle, name)
        local index = tonumber(name:match('^g_weapon_test_(%d+)$'))
        return index ~= nil and index >= 0 and index < 5
    end
    f.E.Unit.mesh = function(handle, name)
        if type(name) == 'string' then
            return mesh_original(handle, tonumber(name:match('(%d+)$')) + 1)
        end
        return mesh_original(handle, name)
    end
    f.E.Mesh = {
        has_material = function(_, name)
            return name == 'm_weapon' or name == 'm_rail'
        end,
        material = function(mesh, name)
            local index = name == 'm_weapon' and 0 or 1
            return ffi.cast('void *', f.native.material(tonumber(ffi.cast('uintptr_t', mesh)), index))
        end,
    }
    f.cache = { state = 'idle', index_stamp = ('c'):rep(64), starts = 0 }
    f.cache.start = function(requests, force)
        f.cache.requests, f.cache.force = requests, force
        f.cache.starts = f.cache.starts + 1
        if f.cache.state == 'idle' then
            f.cache.state = 'loading'
        end
        return true
    end
    f.cache.tick = function()
        f.cache.state = 'ready'
    end
    f.cache.unit = function(resource)
        return resource == weapon and f.unit_source or nil
    end
    f.cache.material = function(resource)
        return f.material_sources[resource]
    end
    f.cache.id_available = function()
        return true
    end
    f.cache.validate_scope = function()
        return not f.scope_changed, 'Current source scope changed'
    end
    f.cache.close = function()
        f.cache.state = 'closed'
        return true
    end
    local folders = {}
    f.modules = {
        binding_provenance = P,
        binding_unit_layout = L,
        material_identity = Materials,
        binding_names = {
            section = function(value)
                return value == section_body and 'm_weapon' or value == section_rail and 'm_rail' or nil
            end,
            mesh = function(value)
                return value >= 0x100 and value <= 0x104 and 'g_weapon_test_' .. (value - 0x100) or nil
            end,
        },
        binding_source_cache = {
            new = function(_, host)
                assert(host.paths.cache == 'C:/fixture/cache/weapon-provenance')
                f.cache_paths = host.paths
                return f.cache
            end,
        },
    }
    f.host = {
        paths = {
            cache = 'C:/fixture/cache',
            directory_exists = function(path)
                return folders[path] == true
            end,
            mkdir_new = function(path)
                folders[path] = true
            end,
        },
        discovery = function()
            return f.discovery
        end,
        groups = function()
            local out = {}
            for _, family in ipairs({ 'material', 'pattern' }) do
                for _, group in ipairs(f.runtime.groups(1, family)) do
                    for _, b in ipairs(group.bindings) do
                        out[#out + 1] = b
                    end
                end
            end
            return out
        end,
        original = function(b)
            return f.documents[b.original]
        end,
        lua_engine = function()
            return f.E
        end,
        native = f.native,
    }
    f.sources = W.new(f.modules, f.host)
    return f
end
test('weapon source worker paths are isolated and unknown archive is only a lookup hint', function()
    local f = setup()
    assert(f.sources.state() == 'idle')
    assert(f.sources.request() and f.sources.state() == 'loading')
    assert(f.cache_paths.cache == 'C:/fixture/cache/weapon-provenance' and f.host.paths.cache == 'C:/fixture/cache')
    assert(
        #f.cache.requests == 1
            and f.cache.requests[1].resource == '5fecab819f96a3e8'
            and f.cache.requests[1].archive == '0000000000000000'
    )
    assert(f.sources.poll(true) == 'Exact weapon binding sources ready' and f.sources.state() == 'ready')
    local archive, why = f.sources.patch_archive({})
    assert(not archive and why == 'Weapon patch destination has not yet been verified in-game')
end)
test('live named MeshID SectionID and material-slot proof emits exact weapon provenance v4', function()
    local f = setup()
    f.sources.request()
    f.sources.poll()
    for _, family in ipairs({ 'material', 'pattern' }) do
        for _, group in ipairs(f.runtime.groups(1, family)) do
            for _, b in ipairs(group.bindings) do
                local source, refs = f.sources.capture(b, { kind = 'weapon', original = f.host.original(b) })
                assert(source.version == 4 and source.verified and source.mesh_verified and not source.unit_override)
                assert(source.weapon_resource == '5fecab819f96a3e8' and source.mesh_id == 0x100 + b.mesh_index)
                assert(source.material_slot == b.material_index and source.material_slot_offset)
                assert(source.unit.archive == '1111111111111111' and source.material.archive ~= source.unit.archive)
                assert(source.kit == nil and source.kit_override == nil and refs.unit.main == nil)
                local decoded = P.decode(P.encode(refs), 'weapon', refs.key, f.host.original(b))
                assert(P.matches(refs, decoded))
            end
        end
    end
end)
test('saved provider hydrates mixed presets from pristine records without requiring current equipment', function()
    local f = setup()
    f.sources.request()
    f.sources.poll()
    local b = f.runtime.groups(1)[1].bindings[1]
    local original = f.host.original(b)
    local _, refs = f.sources.capture(b, { original = original })
    local entry = {
        kind = 'weapon',
        key = refs.key,
        weapon_slot = 1,
        weapon_resource = '5fecab819f96a3e8',
        original = original,
        binding_provenance = refs,
    }
    local provider = f.sources.provider({ entries = { { kind = 'armor' }, entry } })
    f.snapshots[1] = nil
    local hydrated = provider(entry)
    assert(hydrated.verified and hydrated.unit.main == f.unit_source.main and hydrated.material_slot_offset)
    assert(f.sources.material(refs.material.resource) and f.sources.id_available(P.MATERIAL, 'aaaaaaaaaaaa0099'))
end)
test('missing cache stale live membership and texture mismatch refuse without guessed overrides', function()
    local f = setup()
    local b = f.runtime.groups(1)[1].bindings[1]
    local ok, why = pcall(f.sources.capture, b, { original = f.host.original(b) })
    assert(not ok and tostring(why):find('background cache', 1, true))
    f.sources.poll()
    f.snapshots[1] = nil
    assert(not pcall(f.sources.capture, b, { original = f.host.original(b) }))
    f = setup()
    f.sources.request()
    f.sources.poll()
    b = f.runtime.groups(1)[1].bindings[1]
    ok, why = pcall(f.sources.capture, b, { original = { resource = 'ffffffffffffffff' } })
    assert(not ok and tostring(why):find('serialized Unit override proof required', 1, true))
    assert(#f.writes == 0)
end)
test('provider rejects changed source digests named assignment and loose-patch scope', function()
    local f = setup()
    f.sources.request()
    f.sources.poll()
    local b = f.runtime.groups(1)[1].bindings[1]
    local original = f.host.original(b)
    local _, refs = f.sources.capture(b, { original = original })
    local entry = {
        kind = 'weapon',
        key = refs.key,
        weapon_slot = 1,
        weapon_resource = '5fecab819f96a3e8',
        original = original,
        binding_provenance = refs,
    }
    local provider = f.sources.provider({ entries = { entry } })
    f.scope_changed = true
    assert(not pcall(provider, entry))
    f.scope_changed = false
    refs.mesh_id = refs.mesh_id + 9999
    assert(not pcall(f.sources.provider({ entries = { entry } }), entry), 'Wrong named mesh assignment hydrated')
    refs.mesh_id = refs.mesh_id - 9999
    f.unit_source.main = replace(f.unit_source.main, 0, 'x')
    assert(not pcall(f.sources.provider({ entries = { entry } }), entry), 'Tampered game source bypassed its digest')
end)
print('PASS weapon provenance: ' .. cases .. ' focused contracts')
