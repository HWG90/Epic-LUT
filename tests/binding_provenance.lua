local P = dofile('src/presets/binding_provenance.lua')
local ffi = require('ffi')
local L = dofile('src/presets/binding_unit_layout.lua')
local Units = dofile('src/gear/unit_identity.lua')
local Materials = dofile('src/gear/material_identity.lua')
assert(P.digest('') == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
assert(P.digest('abc') == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function hash(h)
    local out = ''
    for i = 15, 1, -2 do
        out = out .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return out
end
local function replace(data, at, value)
    return data:sub(1, at) .. value .. data:sub(at + #value + 1)
end
local function record(resource, kind, main)
    local toc = hash(resource)
        .. hash(kind)
        .. string.rep('\0', 40)
        .. word(#main)
        .. word(0)
        .. word(0)
        .. string.rep('\0', 12)
    return {
        resource = resource,
        archive = '1234567890abcdef',
        main = main,
        gpu = '',
        stream = '',
        toc = toc,
        main_sha256 = ('a'):rep(64),
        index_stamp = ('b'):rep(64),
    }
end
local unit_id, mat_id, other_mat, tex = '0000000000000111', '0000000000000222', '0000000000000333', 'cf0cc31b981786c9'
local mesh_at, material_at = 140, 276
local mesh = replace(string.rep('\0', 128), 40, word(99))
mesh = replace(mesh, 104, word(2) .. word(128))
mesh = replace(mesh, 120, word(0) .. word(136))
mesh = mesh .. word(0xabc12345) .. word(0x23456789)
local header = replace(string.rep('\0', 128), 44, word(10800438))
header = replace(header, 100, word(128))
header = replace(header, 112, word(material_at))
local unit_main = header
    .. word(1)
    .. word(mesh_at - 128)
    .. word(99)
    .. mesh
    .. word(2)
    .. word(0xabc12345)
    .. word(0x23456789)
    .. hash(mat_id)
    .. hash(other_mat)
local mat_main = replace(string.rep('\0', 136), 64, word(2))
    .. word(P.LUT)
    .. word(P.PATTERN)
    .. hash('1111111111111111')
    .. hash(tex)
local unit = record(unit_id, P.UNIT, unit_main)
local mat = record(mat_id, P.MATERIAL, mat_main)
local other = record(other_mat, P.MATERIAL, mat_main)
local binding = {
    unit = 44,
    mesh = 500000,
    material = 600000,
    current = 700,
    original = 701,
    save_key = '1:6:5:3',
    armor = true,
    slot = P.PATTERN,
}
local context = { kind = 'armor', key = 'p:1:6:5:3', original = { resource = tex } }
local pointer, kit, gets, ready, foreign = 600000, { id = 21, body = 0, archive = '1234567890abcdef' }, 0, 1, false
local unit_handle, mesh_handle = ffi.cast('void *', 44 * 4), ffi.cast('void *', 500000)
local current_identity = { player = 7, unit = 8, avatar = 9, avatar_index = 0, units_at = 65536 }
local resource_calls, manager_calls, stale_mesh, mutate_binding = 0, 0, false, false
local native = {
    can_get = function()
        manager_calls = manager_calls + 1
        error('ResourceManager lookup reached', 0)
    end,
    get = function()
        manager_calls = manager_calls + 1
        error('ResourceManager lookup reached', 0)
    end,
}
local E = {
    Application = {
        worlds = function()
            return { 'world' }
        end,
    },
    World = {
        units = function()
            return { unit_handle }
        end,
    },
    Unit = {
        alive = function(value)
            assert(value == unit_handle and type(value) == 'cdata')
            return true
        end,
        resource_name = function(value)
            assert(value == unit_handle and type(value) == 'cdata', 'Numeric reference reached Unit.resource_name')
            resource_calls = resource_calls + 1
            return '#ID[' .. unit_id .. ']'
        end,
        num_meshes = function(value)
            assert(value == unit_handle)
            return 6
        end,
        has_mesh = function(value, name)
            assert(value == unit_handle)
            return name == 'mesh_jacket'
        end,
        mesh = function(value, index)
            assert(value == unit_handle and (index == 6 or index == 'mesh_jacket'))
            return stale_mesh and ffi.cast('void *', 555555) or mesh_handle
        end,
    },
    Mesh = {
        has_material = function(value, name)
            assert(value == mesh_handle and (name == 'm_jacket' or name == 'm_helmet'))
            return ready == 1
        end,
        material = function(value, name)
            assert(value == mesh_handle and ready == 1)
            gets = gets + 1
            if mutate_binding then
                foreign = true
            end
            local alias = L.parse(unit.main).sections[2].material == mat_id
            return ffi.cast('void *', (name == 'm_jacket' or alias and name == 'm_helmet') and pointer or 900000)
        end,
    },
}
-- Only this fixture constructs synthetic engine handles from numeric tokens.
local units = Units.new(E, {
    avatar = {
        resolve_live = function()
            return current_identity
        end,
        units = function(_, _, preview)
            assert(preview == nil)
            return { { unit = 44, type = 1, slot = 6, preview = false } }
        end,
    },
})
local materials = Materials.new(E, {
    unit_identity = units,
    section_name = function(section)
        return section == 0xabc12345 and 'm_jacket' or 'm_helmet'
    end,
    mesh_name = function(id)
        assert(id == 99)
        return 'mesh_jacket'
    end,
})
local deps = {
    native = native,
    engine = {
        name64 = function(v)
            return v
        end,
        LUT_SLOT = P.LUT,
    },
    unit_source = function(id)
        assert(id == unit_id)
        return unit
    end,
    material_source = function(id)
        return id == mat_id and mat or other
    end,
    unit_resource = units.resource,
    identity = function()
        return current_identity
    end,
    layout = L.parse,
    present = function()
        return true
    end,
    binding = function(b)
        return foreign and 777 or b.current
    end,
    kit_override = function()
        return false, kit
    end,
}
local resolver = P.new(deps)
local denied_calls = resource_calls
local denied = P.new(deps)
local accepted, why = pcall(denied.capture, binding, context)
assert(
    not accepted
        and why:find('identity APIs unavailable', 1, true)
        and resource_calls == denied_calls
        and manager_calls == 0,
    'Default provenance executed native lookups'
)
deps.material_identity = materials
local source, refs = resolver.capture(binding, context)
assert(
    source.verified and source.section == 0xabc12345 and source.material == mat and source.unit == unit,
    'Resolver guessed a serialized section from runtime ordinals'
)
local encoded = P.encode(refs, 'armor', context.key, context.original)
local decoded = P.decode(encoded, 'armor', context.key, context.original)
assert(decoded.section == source.section and decoded.unit.resource == unit_id and decoded.material.resource == mat_id)
assert(
    source.mesh_verified and source.mesh_id == 99 and source.material_slot == 0 and source.material_slot_offset == 268
)
assert(
    decoded.version == 2 and decoded.mesh_id == 99 and decoded.material_slot == 0 and not decoded.material_slot_offset
)
local legacy_refs = {}
for key, value in pairs(refs) do
    legacy_refs[key] = value
end
legacy_refs.version, legacy_refs.mesh_id, legacy_refs.material_slot = 1, nil, nil
local legacy_encoded = P.encode(legacy_refs)
assert(P.decode(legacy_encoded).version == 1 and P.matches(legacy_refs, refs) and not P.matches(refs, legacy_refs))
assert(
    not decoded.verified and not decoded.unit.main and not encoded:find(mat.main, 1, true),
    'Persisted provenance contains game bytes/trusted hydration'
)
local function refused(call, text)
    local ok, why = pcall(call)
    assert(not ok and why:find(text, 1, true), tostring(why))
end
local old_version, old_mesh, old_slot = refs.version, refs.mesh_id, refs.material_slot
refs.version = 1
refused(function()
    P.encode(refs)
end, 'requires provenance version2')
refs.version = 2
refs.mesh_id = nil
refused(function()
    P.encode(refs)
end, 'Invalid MeshName ID')
refs.mesh_id, refs.material_slot = old_mesh, 64
refused(function()
    P.encode(refs)
end, 'exceeds its limit')
refs.version, refs.mesh_id, refs.material_slot = old_version, old_mesh, old_slot
refs.material_slot_offset = 123456
assert(P.encode(refs) == encoded, 'Persisted raw runtime/parser offsets')
refs.material_slot_offset = nil
assert(
    not P.matches(refs, P.validate(setmetatable({ material_slot = 1 }, { __index = refs }))),
    'Stored mesh slot identity changes were accepted'
)
unit = record(unit_id, P.UNIT, replace(unit_main, 16, hash('1111111111111111')))
local partial, partial_refs = resolver.capture(binding, context)
assert(
    not partial.mesh_verified and partial.mesh_id == nil and partial_refs.version == 1,
    'Composite geometry guessed a serialized mesh assignment'
)
unit = record(unit_id, P.UNIT, unit_main)
refused(function()
    P.decode(encoded, 'helmet', context.key, context.original)
end, 'destination differs')
refused(function()
    P.decode(encoded, 'armor', context.key, { resource = '1111111111111111' })
end, 'original texture differs')
refused(function()
    P.decode(encoded:gsub('EPIC%-BINDING\t2', 'EPIC-BINDING\t3'))
end, 'schema')
refused(function()
    P.decode(encoded .. '\n')
end, 'schema')
refused(function()
    P.decode(('x'):rep(P.MAX_BYTES + 1))
end, 'sidecar')
refs.kit_override = true
refused(function()
    P.encode(refs)
end, 'Unsupported')
refs.kit_override = false
pointer = 999999
refused(function()
    resolver.capture(binding, context)
end, 'No verified material slot')
pointer = 600000
ready = 0
local count = gets
refused(function()
    resolver.capture(binding, context)
end, 'No verified material slot')
assert(gets == count)
ready = nil
refused(function()
    resolver.capture(binding, context)
end, 'No verified material slot')
assert(gets == count)
ready = 1
unit = record(unit_id, P.UNIT, replace(unit_main, material_at + 4 + 2 * 4 + 8, hash(mat_id)))
refused(function()
    resolver.capture(binding, context)
end, 'Ambiguous named material pointer proof')
unit = record(unit_id, P.UNIT, unit_main)
mat = record(mat_id, P.MATERIAL, replace(mat_main, 136 + 2 * 4 + 8, hash('1111111111111111')))
refused(function()
    resolver.capture(binding, context)
end, 'Pristine named material texture differs')
mat = record(mat_id, P.MATERIAL, mat_main)
mat = record(mat_id, P.MATERIAL, replace(mat_main, 136 + 4, word(P.LUT)))
refused(function()
    resolver.capture(binding, context)
end, 'repeated material')
mat = record(mat_id, P.MATERIAL, mat_main)
unit = record(unit_id, P.UNIT, replace(unit_main, material_at + 8, word(0xabc12345)))
refused(function()
    resolver.capture(binding, context)
end, 'Ambiguous Unit global SectionID')
unit = record(unit_id, P.UNIT, unit_main)
unit = record(unit_id, P.UNIT, replace(unit_main, material_at, word(65)))
refused(function()
    resolver.capture(binding, context)
end, 'exceeds its limit')
unit = record(unit_id, P.UNIT, unit_main)
local guard = deps.kit_override
deps.kit_override = function()
    return true, kit
end
refused(function()
    resolver.capture(binding, context)
end, 'Active kit texture override')
deps.kit_override = guard
mutate_binding = true
refused(function()
    resolver.capture(binding, context)
end, 'binding changed during capture')
foreign = false
mutate_binding = false
stale_mesh = true
refused(function()
    resolver.capture(binding, context)
end, 'Lua Mesh handle differs')
stale_mesh = false
assert(manager_calls == 0, 'Named capture used a material ResourceManager lookup')
local calls = 0
deps.kit_override = function()
    calls = calls + 1
    return false, { id = calls, body = 0, archive = kit.archive }
end
refused(function()
    resolver.capture(binding, context)
end, 'kit changed')
deps.kit_override = guard
-- Known customization layout with exact-sized, bounded read snapshots.
local addresses = {}
local game, manager, list, kit_at, bodies, pieces = 0x10000000, 0x50000, 0x60000, 0x70000, 0x80000, 0x90000
local function ptr(n)
    return word(n) .. word(0)
end
addresses[game + 0x33264f8] = ptr(manager)
addresses[manager] = ptr(list) .. word(1) .. word(0)
addresses[list] = ptr(kit_at)
local header = string.rep('\0', 64)
header = replace(header, 0, word(21))
header = replace(header, 32, hash(kit.archive))
header = replace(header, 40, word(0))
header = replace(header, 48, ptr(bodies))
header = replace(header, 56, word(1))
addresses[kit_at] = header
local body = word(0) .. word(0) .. ptr(pieces) .. word(1) .. word(0)
addresses[bodies] = body
local piece = hash(unit_id) .. word(6) .. word(1) .. string.rep('\0', 80)
addresses[pieces] = piece
local function read(at, n)
    local data = addresses[at]
    return data and #data >= n and data:sub(1, n) or nil
end
local identity = { armor = 21, helmet = 22, cape = 23, body = 0 }
local override, proof = P.kit_override(read, game, identity, binding, unit_id, P.PATTERN)
assert(override == false and proof.id == 21 and proof.archive == kit.archive)
addresses[pieces] = replace(piece, 32, hash(tex))
assert(P.kit_override(read, game, identity, binding, unit_id, P.PATTERN) == true)
assert(
    P.kit_override(read, game, identity, binding, unit_id, P.LUT) == false,
    'Pattern override leaked into material slot proof'
)
addresses[pieces] = piece
addresses[bodies] = replace(body, 16, word(2))
addresses[pieces + 96] = piece
refused(function()
    P.kit_override(read, game, identity, binding, unit_id, P.PATTERN)
end, 'unique kit piece')
addresses[bodies] = body
addresses[pieces] = replace(piece, 0, hash('0000000000000999'))
refused(function()
    P.kit_override(read, game, identity, binding, unit_id, P.PATTERN)
end, 'unique kit piece')
addresses[pieces] = piece
addresses[manager] = ptr(list) .. word(4097) .. word(0)
refused(function()
    P.kit_override(read, game, identity, binding, unit_id, P.PATTERN)
end, 'count exceeds')
print(
    'PASS binding provenance: real Lua Unit/named material proof with zero ResourceManager calls, fresh named SDK mesh/slot offsets, v1/v2 metadata-only compatibility, composite partial proof and stale/ambiguous refusal'
)
