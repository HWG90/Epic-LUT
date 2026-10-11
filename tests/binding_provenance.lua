local P = dofile('src/presets/binding_provenance.lua')
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
local unit_main = replace(string.rep('\0', 116), 112, word(116))
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
    mesh = 500,
    material = 600,
    current = 700,
    original = 701,
    save_key = '1:6:5:3',
    armor = true,
    slot = P.PATTERN,
}
local context = { kind = 'armor', key = 'p:1:6:5:3', original = { resource = tex } }
local pointer, kit, gets, ready, foreign = 600, { id = 21, body = 0, archive = '1234567890abcdef' }, 0, 1, false
local native = {
    can_get = function()
        return ready
    end,
    get = function(_, name)
        gets = gets + 1
        return name == mat_id and pointer or 900
    end,
}
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
    unit_resource = function()
        return unit_id
    end,
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
local denied_calls = gets
local denied = P.new(deps)
local accepted, why = pcall(denied.capture, binding, context)
assert(
    not accepted and why:find('disabled', 1, true) and gets == denied_calls,
    'Default provenance executed native lookups'
)
deps.material_lookup = function(resource)
    local result = tonumber(native.can_get(P.MATERIAL, resource))
    return result and result ~= 0 and native.get(P.MATERIAL, resource) or nil
end
local source, refs = resolver.capture(binding, context)
assert(
    source.verified and source.section == 0xabc12345 and source.material == mat and source.unit == unit,
    'Resolver guessed a serialized section from runtime ordinals'
)
local encoded = P.encode(refs, 'armor', context.key, context.original)
local decoded = P.decode(encoded, 'armor', context.key, context.original)
assert(decoded.section == source.section and decoded.unit.resource == unit_id and decoded.material.resource == mat_id)
assert(
    not decoded.verified and not decoded.unit.main and not encoded:find(mat.main, 1, true),
    'Persisted provenance contains game bytes/trusted hydration'
)
local function refused(call, text)
    local ok, why = pcall(call)
    assert(not ok and why:find(text, 1, true), tostring(why))
end
refused(function()
    P.decode(encoded, 'helmet', context.key, context.original)
end, 'destination differs')
refused(function()
    P.decode(encoded, 'armor', context.key, { resource = '1111111111111111' })
end, 'original texture differs')
refused(function()
    P.decode(encoded:gsub('EPIC%-BINDING\t1', 'EPIC-BINDING\t2'))
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
pointer = 999
refused(function()
    resolver.capture(binding, context)
end, 'pointer proof')
pointer = 600
ready = 0
local count = gets
refused(function()
    resolver.capture(binding, context)
end, 'pointer proof')
assert(gets == count)
ready = nil
refused(function()
    resolver.capture(binding, context)
end, 'pointer proof')
assert(gets == count)
ready = 1
unit = record(unit_id, P.UNIT, replace(unit_main, 116 + 4 + 2 * 4 + 8, hash(mat_id)))
refused(function()
    resolver.capture(binding, context)
end, 'unique loaded')
unit = record(unit_id, P.UNIT, unit_main)
mat = record(mat_id, P.MATERIAL, replace(mat_main, 136 + 2 * 4 + 8, hash('1111111111111111')))
refused(function()
    resolver.capture(binding, context)
end, 'pointer proof')
mat = record(mat_id, P.MATERIAL, mat_main)
mat = record(mat_id, P.MATERIAL, replace(mat_main, 136 + 4, word(P.LUT)))
refused(function()
    resolver.capture(binding, context)
end, 'repeated material')
mat = record(mat_id, P.MATERIAL, mat_main)
unit = record(unit_id, P.UNIT, replace(unit_main, 120 + 4, word(0xabc12345)))
refused(function()
    resolver.capture(binding, context)
end, 'repeated unit')
unit = record(unit_id, P.UNIT, unit_main)
unit = record(unit_id, P.UNIT, replace(unit_main, 116, word(65)))
refused(function()
    resolver.capture(binding, context)
end, 'bounds')
unit = record(unit_id, P.UNIT, unit_main)
local guard = deps.kit_override
deps.kit_override = function()
    return true, kit
end
refused(function()
    resolver.capture(binding, context)
end, 'Active kit texture override')
deps.kit_override = guard
local get = native.get
native.get = function(...)
    foreign = true
    return get(...)
end
refused(function()
    resolver.capture(binding, context)
end, 'binding changed during capture')
foreign = false
native.get = get
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
    'PASS binding provenance: exact material-pointer/slot/SectionID proof, no ordinal guessing, metadata-only roundtrip, unready/ambiguous/stale rejection and known-kit override bounds'
)
