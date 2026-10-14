local ffi = require('ffi')
local DDS = dofile('src/core/dds.lua')
local T = dofile('src/presets/outfit_targets.lua')
local function document(width, height, value)
    local data = ffi.new('float[?]', width * height * 4)
    for index = 0, width * height * 4 - 1 do
        data[index] = (value or 0.1) + index / 4096
    end
    -- DDS identity includes alpha, HDR and unknown shader columns.
    data[3] = -0.25
    data[width * height * 4 - 1] = 3.75
    return { data = data, width = width, height = height }
end
local function encode(d)
    return DDS.encode(d.data, d.width, d.height)
end
local function binding(kind, mesh, material, slot, unit_type)
    return {
        [kind] = true,
        save_key = (unit_type or 1) .. ':' .. (slot or 1) .. ':' .. mesh .. ':' .. (material or 0),
        mesh = mesh,
    }
end
local function original(resource, width, height)
    return { resource = resource or '0123456789abcdef', width = width or 23, height = height or 8 }
end
local function preset(kind, pattern)
    local result = { entries = {} }
    for mesh = 0, 3 do
        result.entries[#result.entries + 1] = {
            kind = kind,
            key = (pattern and 'p:' or '') .. binding(kind, mesh).save_key,
            document = document(pattern and 3 or 23, pattern and 1 or 8),
        }
    end
    return result
end
local function live(kind, pattern, hash, width, height)
    local result = {}
    for mesh = 1, 4 do
        result[#result + 1] = {
            kind = kind,
            binding = binding(kind, mesh),
            pattern = pattern == true,
            original = original(hash, width or (pattern and 3 or 23), height or (pattern and 1 or 8)),
        }
    end
    return result
end
local function resolver(saved, live)
    local result = T.new(saved, { document_bytes = encode })
    if live then
        result.prepare(live)
    end
    return result
end
-- Real V1 topology: saved meshes0..3, current native meshes1..4. Preserve the
-- three exact destinations and adapt only the unmatched fourth mesh.
local v1 = preset('armor')
local current = live('armor')
local r = resolver(v1, current)
for index, item in ipairs(current) do
    local d, mode = r.resolve(item.kind, item.binding, item.pattern, item.original)
    assert(d and encode(d) == encode(v1.entries[1].document), 'V1 uniform family failed byte-exact adaptation')
    assert(mode == (index < 4 and 'exact' or 'mesh-family'), 'V1 native indices were shifted globally')
    if index < 4 then
        assert(d == v1.entries[index + 1].document, 'An exact native mesh destination lost document priority')
    end
    assert(
        item.binding.mesh == index and item.binding.save_key == '1:1:' .. index .. ':0',
        'Resolver changed native mesh identity'
    )
end
-- Exact legacy three-part keys remain readable, but never certify topology.
local legacy = { entries = { { kind = 'armor', key = '1:1:0', document = document(23, 8) } } }
local lr = resolver(legacy)
assert(lr.resolve('armor', { save_key = '1:1:0' }) == legacy.entries[1].document)
lr.prepare({ { kind = 'armor', binding = { save_key = '1:1:0' }, original = original() } })
assert(
    not lr.resolve('armor', binding('armor', 4), false, original()),
    'Legacy three-part target authorized adaptation'
)
-- Shape/resource provenance is required for adaptation, never inferred from
-- another live object, another material, another slot or another gear kind.
local extra = binding('armor', 4)
assert(not r.resolve('armor', extra, false, original('ffffffffffffffff')), 'Cross-resource adaptation succeeded')
assert(not r.resolve('armor', extra, false, { width = 23, height = 8 }), 'Missing original resource was guessed')
assert(not r.resolve('armor', extra, false, original(nil, 23, 64)), 'Original height mismatch was accepted')
assert(not r.resolve('armor', extra, false, original(nil, 3, 1)), 'Pattern/material dimensions were mixed')
assert(not r.resolve('helmet', binding('helmet', 4), false, original()), 'Armor family leaked into Helmet')
assert(not r.resolve('cape', binding('cape', 4), false, original()), 'Armor family leaked into Cape')
assert(not r.resolve('armor', binding('armor', 4, 1), false, original()), 'Material identity was broadened')
assert(not r.resolve('armor', binding('armor', 4, nil, 2), false, original()), 'Unit slot identity was broadened')
assert(not r.resolve('armor', binding('armor', 4, nil, nil, 2), false, original()), 'Unit type identity was broadened')
assert(not r.resolve('armor', { save_key = '1:1:4' }, false, original()), 'Three-part live key adapted')
assert(not r.resolve('armor', { save_key = '1:1:4294967296:0' }, false, original()), 'Oversized topology index adapted')
r.prepare({ { kind = 'armor', binding = extra, original = original() } })
assert(not r.resolve('armor', extra, false, original()), 'Unmatched live mesh was used as its own anchor')
r.prepare(current)
assert(r.resolve('armor', extra, false, original()), 'Valid anchors did not recover after prepare reset')
r.prepare({})
assert(not r.resolve('armor', extra, false, original()), 'Old live anchors survived a new prepare call')
-- A changed saved row or float bit blocks the entire fallback family, while
-- the exact documents still apply through their original destinations.
local conflict = preset('armor')
conflict.entries[4].document.data[3] = -0.5
local cr = resolver(conflict, current)
assert(cr.resolve('armor', current[1].binding, false, current[1].original) == conflict.entries[2].document)
assert(not cr.resolve('armor', extra, false, original()), 'Conflicting alpha bytes were silently unified')
local conflict_height = preset('armor')
conflict_height.entries[4].document = document(23, 64)
assert(
    not resolver(conflict_height, current).resolve('armor', extra, false, original()),
    'Conflicting saved dimensions were silently unified'
)
-- A first exact binding with another live resource does not certify the extra
-- mesh. Once a compatible resource anchor exists, it can certify only itself.
local mixed_current = live('armor')
for index = 1, 3 do
    mixed_current[index].original = original('ffffffffffffffff')
end
local mr = resolver(v1, mixed_current)
assert(
    not mr.resolve('armor', extra, false, mixed_current[4].original),
    'Wrong-resource exact anchor certified fallback'
)
mixed_current[2].original = original()
mr.prepare(mixed_current)
assert(mr.resolve('armor', extra, false, mixed_current[4].original), 'Same-resource exact anchor was ignored')
for index = 1, 3 do
    mixed_current[index].original = original(nil, 23, 64)
end
mr.prepare(mixed_current)
assert(not mr.resolve('armor', extra, false, original()), 'Wrong-shape exact anchor certified fallback')
-- Optional saved V2 resource metadata is also part of anchor compatibility.
local metadata = preset('armor')
for _, entry in ipairs(metadata.entries) do
    entry.original = original('ffffffffffffffff')
end
assert(
    not resolver(metadata, current).resolve('armor', extra, false, original()),
    'Saved original resource mismatch authorized adaptation'
)
-- Pattern meshes use a separate, byte-identical 3x1 family.
local pp, pl = preset('helmet', true), live('helmet', true)
local pr = resolver(pp, pl)
local pd, pm = pr.resolve('helmet', pl[4].binding, true, pl[4].original)
assert(pd and pm == 'mesh-family' and pd.width == 3 and pd.height == 1 and encode(pd) == encode(pp.entries[1].document))
assert(not pr.resolve('helmet', pl[4].binding, false, original()), 'Pattern family authorized a material LUT')
-- A typed Cape exact document has priority. Early Armor-labelled Cape presets
-- remain exact-only and cannot expand into another Cape mesh.
local old_cape, new_cape = document(23, 8, 0.2), document(23, 8, 0.8)
local cb = binding('cape', 1)
local cp = {
    entries = {
        { kind = 'armor', key = cb.save_key, document = old_cape },
        { kind = 'cape', key = cb.save_key, document = new_cape },
    },
}
assert(resolver(cp).resolve('cape', cb, false) == new_cape, 'Typed Cape exact document lost priority to legacy Armor')
cp.entries[2] = nil
local old = resolver(cp, { { kind = 'cape', binding = cb, original = original() } })
assert(old.resolve('cape', cb, false) == old_cape, 'Legacy Cape exact entry no longer applies')
assert(not old.resolve('cape', binding('cape', 4), false, original()), 'Legacy Armor entry authorized Cape adaptation')
-- A missing/failing byte encoder leaves exact application intact and refuses
-- fallback. Encodings are cached once per document identity.
local calls = 0
local alias = document(23, 8)
local aliases = preset('armor')
for _, entry in ipairs(aliases.entries) do
    entry.document = alias
end
local ar = T.new(aliases, {
    document_bytes = function(d)
        calls = calls + 1
        return encode(d)
    end,
})
ar.prepare(current)
assert(calls == 1 and ar.resolve('armor', extra, false, original()), 'Aliased saved DDS was encoded repeatedly')
local er = T.new(v1, {
    document_bytes = function()
        error('unavailable')
    end,
})
er.prepare(current)
assert(er.resolve('armor', current[1].binding, false) == v1.entries[2].document)
assert(not er.resolve('armor', extra, false, original()), 'Unproved DDS bytes authorized adaptation')
local too_many = {}
for index = 1, T.MAX_BINDINGS + 1 do
    too_many[index] = v1.entries[1]
end
assert(not pcall(T.new, { entries = too_many }, { document_bytes = encode }), 'Unbounded preset targets accepted')
assert(not pcall(r.prepare, too_many), 'Unbounded live target list accepted')
assert(
    not pcall(T.new, { entries = { [1] = v1.entries[1], [3] = v1.entries[2] } }, { document_bytes = encode }),
    'Sparse preset list bypassed validation'
)
assert(
    not pcall(T.new, { entries = { v1.entries[1], v1.entries[1] } }, { document_bytes = encode }),
    'Duplicate exact saved destination accepted'
)
print(
    'PASS outfit targets: exact destination priority, byte-identical V1 extra-mesh adaptation, same-resource/shape live anchors, family conflicts, Pattern/Cape isolation and bounded inputs'
)
-- Weapon destinations cannot inherit a table from another configuration, even
-- when its slot, mesh topology and original LUT resource happen to be identical.
local weapon_resource = '5fecab819f96a3e8'
local function weapon_binding(mesh, slot, resource)
    return {
        save_key = '3:' .. (slot or 1) .. ':' .. mesh .. ':0',
        weapon_slot = slot or 1,
        weapon_resource = resource or weapon_resource,
    }
end
local weapon_doc = document(23, 8)
ffi.cast('uint32_t *', weapon_doc.data)[1] = 0x80000000
local weapon_pattern = document(3, 1)
local weapons = { entries = {} }
for mesh = 0, 3 do
    for _, is_pattern in ipairs({ false, true }) do
        weapons.entries[#weapons.entries + 1] = {
            kind = 'weapon',
            key = (is_pattern and 'p:' or '') .. '3:1:' .. mesh .. ':0',
            weapon_slot = 1,
            weapon_resource = weapon_resource,
            document = is_pattern and weapon_pattern or weapon_doc,
        }
    end
end
weapons.entries[#weapons.entries + 1] = v1.entries[1]
local weapon_live = {}
for mesh = 1, 4 do
    weapon_live[#weapon_live + 1] = { kind = 'weapon', binding = weapon_binding(mesh), original = original() }
    weapon_live[#weapon_live + 1] =
        { kind = 'weapon', binding = weapon_binding(mesh), pattern = true, original = original(nil, 3, 1) }
end
local wr = resolver(weapons, weapon_live)
assert(wr.weapon_resources[1] == weapon_resource)
for _, item in ipairs(weapon_live) do
    local got, mode = wr.resolve('weapon', item.binding, item.pattern, item.original)
    local expected = item.pattern and weapon_pattern or weapon_doc
    assert(got and encode(got) == encode(expected))
    assert(mode == (item.binding.save_key:find(':4:', 1, true) and 'mesh-family' or 'exact'))
end
for _, mesh in ipairs({ 1, 4 }) do
    assert(
        not wr.resolve('weapon', weapon_binding(mesh, 1, 'ffffffffffffffff'), false, original()),
        'Mismatched weapon received an exact or adapted table'
    )
    assert(not wr.resolve('weapon', weapon_binding(mesh, 2), false, original()), 'Primary table leaked into secondary')
    assert(
        not wr.resolve('weapon', { save_key = '3:1:' .. mesh .. ':0' }, false, original()),
        'Weapon identity was guessed'
    )
end
assert(not wr.resolve('weapon', weapon_binding(4), false, original('ffffffffffffffff')))
wr.prepare({ { kind = 'weapon', binding = weapon_binding(1, 1, 'ffffffffffffffff'), original = original() } })
assert(not wr.resolve('weapon', weapon_binding(4), false, original()), 'Wrong weapon certified an LOD anchor')
assert(wr.resolve('armor', { save_key = v1.entries[1].key }) == v1.entries[1].document)
for _, bad in ipairs({ 'bad', string.rep('0', 16), '5fecab819f96a3eg' }) do
    local entry = { kind = 'weapon', key = '3:1:0:0', weapon_resource = bad, document = weapon_doc }
    assert(not pcall(resolver, { entries = { entry } }), 'Malformed weapon identity accepted')
end
local multi = resolver({
    entries = {
        weapons.entries[1],
        { kind = 'weapon', key = weapons.entries[1].key, weapon_resource = 'ffffffffffffffff', document = weapon_doc },
    },
})
assert(multi.resolve('weapon', weapon_binding(0, 1, 'ffffffffffffffff'), false) == weapon_doc)
assert(multi.resolve('weapon', weapon_binding(0), false) == weapons.entries[1].document)
print(
    'PASS weapon outfit targets: exact configuration and slot guards, same-weapon LOD anchors, Pattern isolation and exact signed-zero aliases'
)
