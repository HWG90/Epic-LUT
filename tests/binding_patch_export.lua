local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local P = dofile('src/presets/patch_export.lua')
local B = dofile('src/presets/binding_patch_export.lua')
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function qword(n)
    return word(n) .. word(0)
end
local function hash(value)
    local out = ''
    for i = 15, 1, -2 do
        out = out .. string.char(tonumber(value:sub(i, i + 1), 16))
    end
    return out
end
local function u(bytes, at)
    local a, b, c, d = bytes:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function hex_at(bytes, at)
    local out = ''
    for i = at + 8, at + 1, -1 do
        out = out .. string.format('%02x', bytes:byte(i))
    end
    return out
end
local function replace(bytes, at, value)
    return bytes:sub(1, at) .. value .. bytes:sub(at + #value + 1)
end
local function source(resource, kind, main, gpu, stream)
    gpu, stream = gpu or '', stream or ''
    return {
        resource = resource,
        main = main,
        gpu = gpu,
        stream = stream,
        toc = hash(resource) .. hash(kind) .. string.rep('\0', 24) .. string.rep('\x31', 16) .. word(#main) .. word(
            #stream
        ) .. word(#gpu) .. word(32) .. word(128) .. word(7),
    }
end
local old_texture, old_material, unit_id = 'cf0cc31b981786c9', '1234567890abcdef', 'abcdef0123456789'
local untouched = '0011223344556677'
local material_main = string.rep('\xaa', 176)
material_main = replace(material_main, 64, word(2))
material_main = replace(material_main, 104, word(0))
material_main = replace(material_main, 120, word(0))
material_main = replace(material_main, 136, word(0x81d4c49d) .. word(0x7e662968))
material_main = replace(material_main, 144, hash(old_texture) .. hash(untouched))
local material =
    source(old_material, B.MATERIAL, material_main, 'material-gpu\0unchanged', 'material-stream\0unchanged')
local unit_main = string.rep('\x5a', 240)
unit_main = replace(unit_main, 112, word(160))
unit_main = replace(
    unit_main,
    160,
    word(3) .. word(101) .. word(102) .. word(103) .. hash(old_material) .. hash(old_material) .. hash(old_material)
)
local unit = source(unit_id, B.UNIT, unit_main, 'unit-geometry-gpu\0unchanged', 'unit-geometry-stream\0unchanged')
local function doc(width, height, seed)
    local data = ffi.new('float[?]', width * height * 4)
    for i = 0, width * height * 4 - 1 do
        data[i] = i / 11 - seed
    end
    return { width = width, height = height, data = data }
end
local a, b, cape = doc(3, 1, 2.5), doc(3, 1, 5.25), doc(23, 8, 12)
local function original(document, resource, height)
    return {
        resource = resource,
        width = document.width,
        height = height or document.height,
        patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. D.encode(
            ffi.new('float[?]', document.width * (height or document.height) * 4),
            document.width,
            height or document.height
        ):sub(1, 148),
    }
end
local function entry(kind, key, document, section)
    return {
        kind = kind,
        key = key,
        document = document,
        original = original(document, old_texture),
        binding_source = {
            version = 1,
            verified = true,
            kind = kind,
            key = key,
            section = section,
            original_texture = old_texture,
            texture_slot = 0x81d4c49d,
            kit_override = false,
            material = material,
            unit = unit,
        },
    }
end
local entries = {
    entry('armor', 'p:0:2:1:0', a, 101),
    entry('helmet', 'p:0:0:1:0', b, 102),
    { kind = 'cape', key = '0:1:1:0', document = cape, original = original(cape, '13e2e070c0dcbd53', 5) },
}
local queries, rejected_id = {}, nil
local options = {
    binding_writer = B,
    id_available = function(kind, resource)
        queries[#queries + 1] = kind .. ':' .. resource
        return resource ~= rejected_id
    end,
}
local patch = P.encode_set(D, entries, options)
assert(
    patch.binding_aware and patch.archive == P.BASE_ARCHIVE and patch.count == 6,
    'Binding-aware patch did not emit three textures, two material variants and one retargeted unit'
)
local records, textures, materials, changed_unit = {}, {}, {}, nil
for _, record in ipairs(patch.records) do
    records[record.type .. ':' .. record.resource] = record
    if record.type == B.TEXTURE then
        textures[#textures + 1] = record
    end
    if record.type == B.MATERIAL then
        materials[#materials + 1] = record
    end
    if record.type == B.UNIT then
        changed_unit = record
    end
end
assert(
    not records[B.TEXTURE .. ':' .. old_texture] and not records[B.MATERIAL .. ':' .. old_material],
    'Conflicting resource variants overwrote the original shared resources'
)
assert(
    changed_unit.resource == unit_id
        and #materials == 2
        and changed_unit.gpu == unit.gpu
        and changed_unit.stream == unit.stream
)
local first_material, second_material = hex_at(changed_unit.main, 176), hex_at(changed_unit.main, 184)
assert(
    first_material ~= second_material and hex_at(changed_unit.main, 192) == old_material,
    'Material forks lost distinct SectionID assignments or changed an unselected section'
)
local expected_unit = replace(replace(unit_main, 176, hash(first_material)), 184, hash(second_material))
assert(
    changed_unit.main == expected_unit
        and changed_unit.unknowns == unit.toc:sub(41, 56)
        and changed_unit.flags == unit.toc:sub(69, 76),
    'Unit unknown/header/geometry/TOC bytes changed beyond verified IDs'
)
for index, resource in ipairs({ first_material, second_material }) do
    local material_record = assert(records[B.MATERIAL .. ':' .. resource])
    local texture = hex_at(material_record.main, 144)
    local texture_record = assert(records[B.TEXTURE .. ':' .. texture])
    local pixels, width, height = D.decode(texture_record.main:sub(193) .. texture_record.gpu)
    local document = entries[index].document
    assert(
        width == 3 and height == 1 and ffi.string(pixels, 48) == ffi.string(document.data, 48),
        'Cloned Pattern texture lost full-float pixels or its owning material assignment'
    )
    assert(
        material_record.main == replace(material_main, 144, hash(texture))
            and material_record.gpu == material.gpu
            and material_record.stream == material.stream
            and material_record.unknowns == material.toc:sub(41, 56)
            and material_record.flags == material.toc:sub(69, 76),
        'Material fork changed another texture slot, shader/unknown data or native sidecar'
    )
end
local toc = 72 + u(patch.main, 4) * 32
assert(u(patch.main, 4) == 3 and u(patch.main, 8) == 6)
for index = 0, patch.count - 1 do
    local at = toc + index * 80
    local resource, kind = hex_at(patch.main, at), hex_at(patch.main, at + 8)
    local expected = assert(records[kind .. ':' .. resource])
    local main_at, stream_at, gpu_at = u(patch.main, at + 16), u(patch.main, at + 24), u(patch.main, at + 32)
    local main_size, stream_size, gpu_size = u(patch.main, at + 56), u(patch.main, at + 60), u(patch.main, at + 64)
    assert(
        gpu_at % 64 == 0 and stream_at % 64 == 0 and u(patch.main, at + 76) == index + 1,
        'Mixed archive TOC alignment/index differs from the SDK contract'
    )
    assert(
        patch.main:sub(main_at + 1, main_at + main_size) == expected.main
            and patch.gpu:sub(gpu_at + 1, gpu_at + gpu_size) == expected.gpu
            and patch.stream:sub(stream_at + 1, stream_at + stream_size) == expected.stream,
        'Mixed archive round trip changed original record payloads'
    )
    assert(
        patch.main:sub(at + 41, at + 56) == expected.unknowns and patch.main:sub(at + 69, at + 76) == expected.flags,
        'Mixed archive lost source TOC unknown fields'
    )
end
local repeated = P.encode_set(D, { entries[2], entries[3], entries[1] }, options)
assert(
    patch.main == repeated.main and patch.gpu == repeated.gpu and patch.stream == repeated.stream,
    'Assignment-aware IDs or archive bytes depend on saved entry enumeration order'
)
rejected_id = queries[1]:sub(18)
local collision = P.encode_set(D, entries, options)
assert(
    collision.main ~= patch.main and not collision.main:find(hash(rejected_id), 1, true),
    'Allocated binding resource collided with the source catalog'
)
local collision_repeat = P.encode_set(D, entries, options)
assert(
    collision.main == collision_repeat.main and collision.gpu == collision_repeat.gpu,
    'Collision retry IDs are nondeterministic'
)
rejected_id = nil
local before_source = entries[1].binding_source
entries[1].binding_source = nil
assert(not pcall(P.encode_set, D, entries, options), 'Conflicting v2 preset guessed material/unit provenance')
entries[1].binding_source = before_source
local unit_toc = unit.toc
unit.toc = replace(unit.toc, 64, word(#unit.gpu + 1))
assert(not pcall(P.encode_set, D, entries, options), 'Stale original unit sidecar length bypassed TOC certification')
unit.toc = unit_toc
local material_toc = material.toc
material.toc = replace(material.toc, 8, hash(B.UNIT))
assert(not pcall(P.encode_set, D, entries, options), 'Material provenance accepted a different native resource type')
material.toc = material_toc
for _, setting in ipairs({
    { 'verified', false },
    { 'kit_override', true },
    { 'section', 999 },
    { 'texture_slot', 0x7e662968 },
    { 'original_texture', untouched },
    { 'key', 'p:0:2:9:0' },
}) do
    local field, bad = setting[1], setting[2]
    local previous = before_source[field]
    before_source[field] = bad
    assert(not pcall(P.encode_set, D, entries, options), 'Invalid binding proof accepted: ' .. field)
    before_source[field] = previous
end
local second_section = entries[2].binding_source.section
entries[2].binding_source.section = 101
assert(
    not pcall(P.encode_set, D, entries, options),
    'Two variants silently collapsed at one serialized material section'
)
entries[2].binding_source.section = second_section
assert(not pcall(P.encode_set, D, entries, { binding_writer = B }), 'Forked ID bypassed global collision certification')
assert(not pcall(P.encode_set, D, entries, {
    binding_writer = B,
    id_available = function()
        return false
    end,
}), 'Occupied clone-ID catalog did not stop preflight')
local created = 0
local exporter = P.new('tests/tmp/binding-prototype', {
    dds = D,
    binding_writer = B,
    available_name = function(name)
        return name
    end,
    directory_exists = function()
        return false
    end,
    mkdir_new = function()
        created = created + 1
    end,
    rmdir = function() end,
})
assert(
    not pcall(exporter.save, 'Missing Proof', entries) and created == 0,
    'Unverified binding export created a partial output directory'
)
local hydrated = {}
for _, entry in ipairs(entries) do
    hydrated[entry.key] = entry.binding_source
    entry.binding_source = nil
end
local via_provider = P.encode_set(D, entries, {
    binding_writer = B,
    id_available = options.id_available,
    provenance = function(entry)
        return hydrated[entry.key]
    end,
})
assert(
    via_provider.main == patch.main and via_provider.gpu == patch.gpu and via_provider.stream == patch.stream,
    'Ephemeral trusted hydration changed assignment serialization'
)
for _, entry in ipairs(entries) do
    entry.binding_source = hydrated[entry.key]
end
-- An unambiguous export is byte-identical to the established texture-only path.
local simple = { entries[1], entries[3] }
local legacy, configured = P.encode_set(D, simple), P.encode_set(D, simple, options)
assert(
    not configured.binding_aware
        and legacy.main == configured.main
        and legacy.gpu == configured.gpu
        and legacy.stream == configured.stream,
    'Unambiguous export changed its existing global texture representation'
)
-- Explicitly certified unique materials need no unit retarget. Unproven
-- sharing conservatively forks, retaining unrelated users of the originals.
local other_material = source('9876543210abcdef', B.MATERIAL, material_main, material.gpu, material.stream)
other_material.shared, material.shared = false, false
local other_unit =
    source('1111222233334444', B.UNIT, replace(unit_main, 184, hash(other_material.resource)), unit.gpu, unit.stream)
entries[2].binding_source.material, entries[2].binding_source.unit = other_material, other_unit
local unique_materials = P.encode_set(D, entries, options)
assert(unique_materials.count == 5, 'Certified unique materials unnecessarily rewrote units')
for _, resource in ipairs(unique_materials.records) do
    assert(resource.type ~= B.UNIT)
end
entries[2].binding_source.material, entries[2].binding_source.unit = material, unit
material.shared = nil
local cape_a, cape_b = doc(23, 8, 2), doc(23, 8, 7)
local material_entries = {}
for index, document in ipairs({ cape_a, cape_b }) do
    local kind = index == 1 and 'cape' or 'armor'
    local key = index == 1 and '0:1:1:0' or '0:2:1:0'
    material_entries[index] = {
        kind = kind,
        key = key,
        document = document,
        original = original(document, untouched),
        binding_source = {
            version = 1,
            verified = true,
            kind = kind,
            key = key,
            section = 100 + index,
            original_texture = untouched,
            texture_slot = 0x7e662968,
            kit_override = false,
            material = material,
            unit = unit,
        },
    }
end
local cape_forks = P.encode_set(D, material_entries, options)
assert(cape_forks.binding_aware and cape_forks.count == 5, 'Cape material LUT did not use its actual MaterialLut slot')
for _, record in ipairs(cape_forks.records) do
    if record.type == B.MATERIAL then
        assert(
            hex_at(record.main, 144) == old_texture and hex_at(record.main, 152) ~= untouched,
            'Cape material export changed Pattern/tint data instead of its MaterialLut binding'
        )
    end
end
material_entries[1].binding_source.texture_slot = 0x0e494183
assert(
    not pcall(P.encode_set, D, material_entries, options),
    'Cape tint identification slot was treated as saved material data'
)
assert(
    material.main == material_main and unit.main == unit_main and #entries == 3,
    'Prototype patch writer mutated saved assignments or source records'
)
-- Synthetic bytes only; used by the pinned-SDK serialization cross-check.
local f = assert(io.open('tests/tmp/binding-material-proof.bin', 'wb'))
assert(f:write(assert(records[B.MATERIAL .. ':' .. first_material]).main))
assert(f:close())
f = assert(io.open('tests/tmp/binding-unit-proof.bin', 'wb'))
assert(f:write(changed_unit.main))
assert(f:close())
print(
    'PASS binding patch prototype: deterministic texture/material forks, verified SectionID redirects, exact mixed TOC/main/GPU/stream records, unselected users, collision catalogs, strict provenance/kit guards and unchanged legacy exports'
)
