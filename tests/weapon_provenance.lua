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
        source_mode = 'weapon_effective',
        source_kind = 'packed',
        source_file = archive,
        source_scope = ('d'):rep(64),
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
    f.cache = {
        state = 'idle',
        index_stamp = ('c'):rep(64),
        starts = 0,
        mode = 'weapon_effective',
        scope_sha256 = ('d'):rep(64),
    }
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
        f.scope_checks = (f.scope_checks or 0) + 1
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
        patch_export = dofile('src/presets/patch_export.lua'),
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
                assert(host.mode == 'weapon_effective')
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
    assert(not archive and why:find('No weapon export bindings requested', 1, true))
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
test('effective source graph retains modded geometry and material bytes for scoped weapon export', function()
    local f = setup()
    f.sources.request()
    f.sources.poll()
    local b = f.runtime.groups(1)[1].bindings[1]
    local unit = f.unit_source
    unit.source_kind, unit.source_file = 'loose', unit.archive .. '.patch_34'
    unit.gpu, unit.gpu_sha256 = 'modified weapon geometry', P.digest('modified weapon geometry')
    unit.toc = replace(unit.toc, 64, word(#unit.gpu))
    local material = f.material_sources.aaaaaaaaaaaa0001
    material.source_kind, material.source_file = 'loose', material.archive .. '.patch_34'
    material.main = material.main .. 'unrelated shader bytes must survive'
    material.main_sha256 = P.digest(material.main)
    material.toc = replace(material.toc, 56, word(#material.main))
    local original = f.host.original(b)
    local hydrated, refs = f.sources.capture(b, { original = original })
    assert(hydrated.unit.gpu == unit.gpu and hydrated.material.main == material.main)
    local entry = {
        kind = 'weapon',
        key = refs.key,
        original = original,
        binding_provenance = refs,
        weapon_resource = refs.weapon_resource,
        weapon_slot = refs.weapon_slot,
    }
    assert(f.sources.patch_archive({ entry }) == '9ba626afa44a3aa3')
    entry.weapon_resource = 'ffffffffffffffff'
    assert(not f.sources.patch_archive({ entry }))
    entry.weapon_resource = refs.weapon_resource
    f.scope_changed = true
    assert(not f.sources.patch_archive({ entry }))
    assert(#f.writes == 0)
end)
test('weapon source receipts reject stock-mode reuse source escapes and changed scope', function()
    local f = setup()
    f.sources.request()
    f.sources.poll()
    local b = f.runtime.groups(1)[1].bindings[1]
    local original = f.host.original(b)
    f.unit_source.source_mode = 'stock'
    assert(not pcall(f.sources.capture, b, { original = original }))
    f.unit_source.source_mode = 'weapon_effective'
    f.unit_source.source_kind, f.unit_source.source_file = 'loose', '../invalid.patch_34'
    assert(not pcall(f.sources.capture, b, { original = original }))
    f.unit_source.source_file = f.unit_source.archive .. '.patch_34'
    f.unit_source.source_scope = ('e'):rep(64)
    assert(not pcall(f.sources.capture, b, { original = original }))
    assert(#f.writes == 0)
end)
local function export_entries(f)
    f.sources.request()
    f.sources.poll()
    local entries = {}
    local D = dofile('src/core/dds.lua')
    for _, family in ipairs({ 'material', 'pattern' }) do
        for _, group in ipairs(f.runtime.groups(1, family)) do
            for _, b in ipairs(group.bindings) do
                local original = f.host.original(b)
                local _, refs = f.sources.capture(b, { original = original })
                original.patch_source = '1111111111111111\n'
                    .. string.rep('\0', 192)
                    .. D.encode(original.data, original.width, original.height):sub(1, 148)
                local data = ffi.new('float[?]', original.width * original.height * 4)
                ffi.copy(data, original.data, original.width * original.height * 16)
                data[0] = data[0] + 0.125
                entries[#entries + 1] = {
                    kind = 'weapon',
                    key = refs.key,
                    original = original,
                    document = { width = original.width, height = original.height, data = data },
                    binding_provenance = refs,
                    weapon_resource = refs.weapon_resource,
                    weapon_slot = refs.weapon_slot,
                }
            end
        end
    end
    return entries, D
end
test('pending and failed ready errors retain their exact unprefixed message', function()
    local f = setup()
    local b = f.runtime.groups(1)[1].bindings[1]
    f.sources.request()
    local ok, why = pcall(f.sources.capture, b, { original = f.host.original(b) })
    assert(not ok and why == W.PENDING)
    f.cache.state, f.cache.error = 'failed', W.PENDING
    ok, why = pcall(f.sources.capture, b, { original = f.host.original(b) })
    assert(not ok and why == W.PENDING, tostring(why))
    f.cache.state, f.cache.error, f.cache.status = 'stale', nil, 'Source changed; reload current gear'
    local archive
    archive, why = f.sources.patch_archive({})
    assert(not archive and why == f.cache.status, 'A stale cache was disguised as a pending worker')
end)
test('fifteen bindings share two scope checks and unique Unit Material digest checks in real encoding', function()
    local f = setup()
    local entries, D = export_entries(f)
    local hashes = {}
    f.modules.binding_provenance = setmetatable({
        digest = function(bytes, expected)
            if type(bytes) == 'string' then
                hashes[bytes] = (hashes[bytes] or 0) + 1
            end
            return P.digest(bytes, expected)
        end,
    }, { __index = P })
    f.sources = W.new(f.modules, f.host)
    f.scope_checks = 0
    local export = f.modules.patch_export
    local retained, retained_proof
    local patch = export.encode_set(D, entries, {
        binding_writer = dofile('src/presets/binding_patch_export.lua'),
        unit_layout = L,
        id_available = function()
            return true
        end,
        original_patch = function(entry)
            return export.encode(D, entry.original, entry.original)
        end,
        weapon_patch_archive = function()
            error('Per-binding archive callback bypassed batch')
        end,
        provenance = function()
            error('Per-binding provider bypassed batch')
        end,
        weapon_export_batch = function(values, serialize)
            return f.sources.with_export_batch(values, function(batch)
                retained = batch
                retained_proof = batch.provenance(values[1])
                return serialize(batch)
            end)
        end,
    })
    assert(patch.binding_aware and patch.archive == '9ba626afa44a3aa3' and #patch.main > 0)
    assert(#entries == 15 and f.scope_checks == 2, 'Scope was rehashed for each binding')
    assert(hashes[f.unit_source.main] == 2)
    for _, source in pairs(f.material_sources) do
        assert(hashes[source.main] == 2)
    end
    assert(not pcall(retained.provenance, entries[1]), 'A completed batch retained its proof lease')
    assert(
        not retained_proof.verified and not retained_proof.mesh_verified,
        'A retained DTO kept an expired proof flag'
    )
    local provider = f.sources.provider({ entries = entries })
    provider(entries[1])
    f.scope_changed = true
    assert(not pcall(provider, entries[1]), 'Standalone cached provider skipped changed scope')
end)
test('batch changes errors yields and nested exports refuse and always invalidate callbacks', function()
    for _, mutation in ipairs({ 'scope', 'main', 'toc', 'digest', 'proof', 'error', 'yield', 'nested' }) do
        local f = setup()
        local entries = export_entries(f)
        f.scope_checks = 0
        local held
        local ok, why = pcall(f.sources.with_export_batch, entries, function(batch)
            held = batch
            batch.patch_archive(entries)
            batch.provenance(entries[1])
            if mutation == 'scope' then
                f.scope_changed = true
            elseif mutation == 'main' then
                f.unit_source.main = replace(f.unit_source.main, 0, 'x')
            elseif mutation == 'toc' then
                f.unit_source.toc = replace(f.unit_source.toc, 68, word(32))
            elseif mutation == 'digest' then
                f.unit_source.main_sha256 = ('a'):rep(64)
            elseif mutation == 'proof' then
                entries[1].binding_provenance.mesh_id = 9999
            elseif mutation == 'error' then
                error('Serialization failed', 0)
            elseif mutation == 'yield' then
                coroutine.yield('wait for next frame')
            elseif mutation == 'nested' then
                f.sources.with_export_batch(entries, function()
                    return true
                end)
            end
            return 'invalid bytes'
        end)
        assert(not ok and type(why) == 'string', mutation .. ' was accepted')
        assert(f.scope_checks == 2, mutation .. ' omitted the final scope check')
        assert(not pcall(held.provenance, entries[1]), mutation .. ' retained its batch callback')
    end
end)
test('post-serialization scope failure prevents filesystem staging in the real patch saver', function()
    local f = setup()
    local entries, D = export_entries(f)
    local staged = 0
    local export = f.modules.patch_export
    local saver = export.new('C:/fixture/export', {
        dds = D,
        available_name = function(name)
            return name
        end,
        directory_exists = function()
            return false
        end,
        mkdir_new = function()
            staged = staged + 1
            error('Invalid batch reached staging')
        end,
        binding_writer = dofile('src/presets/binding_patch_export.lua'),
        unit_layout = L,
        id_available = function()
            return true
        end,
        original_patch = function(entry)
            return export.encode(D, entry.original, entry.original)
        end,
        weapon_export_batch = function(values, serialize)
            return f.sources.with_export_batch(values, function(batch)
                local patch = serialize(batch)
                f.scope_changed = true
                return patch
            end)
        end,
    })
    assert(not pcall(saver.save, 'Scoped Weapon', entries) and staged == 0)
end)
print('PASS weapon provenance: ' .. cases .. ' focused contracts')
