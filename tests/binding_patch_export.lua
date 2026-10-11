local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local P = dofile('src/presets/patch_export.lua')
local B = dofile('src/presets/binding_patch_export.lua')
local L = dofile('src/presets/binding_unit_layout.lua')
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
local mesh_ids, mesh_offsets = { 0x101001, 0x101002, 0x101003 }, { 192, 384, 576 }
local function unit_bytes(local_sections)
    local main = string.rep('\x5a', 896)
    main = replace(main, 16, qword(0))
    main = replace(main, 44, word(10800438))
    main = replace(main, 96, word(864))
    main = replace(main, 100, word(128))
    main = replace(main, 112, word(800))
    main = replace(
        main,
        128,
        word(3) .. word(64) .. word(256) .. word(448) .. word(mesh_ids[1]) .. word(mesh_ids[2]) .. word(mesh_ids[3])
    )
    for index, at in ipairs(mesh_offsets) do
        main = replace(main, at + 40, word(mesh_ids[index]))
        main = replace(main, at + 56, word(index - 1))
        main = replace(main, at + 104, word(1) .. word(128))
        main = replace(
            main,
            at + 120,
            word(1)
                .. word(132)
                .. word(local_sections[index])
                .. word(0)
                .. word(4)
                .. word(6)
                .. word(8)
                .. word(9)
                .. word(0)
        )
    end
    main = replace(main, 864, qword(3))
    return replace(
        main,
        800,
        word(3) .. word(101) .. word(102) .. word(103) .. hash(old_material) .. hash(old_material) .. hash(old_material)
    )
end
local unit_main = unit_bytes({ 101, 102, 103 })
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
    local mesh_index = section - 100
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
            mesh_verified = true,
            mesh_id = mesh_ids[mesh_index],
            material_slot = 0,
            material_slot_offset = mesh_offsets[mesh_index] + 128,
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
    unit_layout = L,
    original_patch = function(entry)
        local baseline = {
            width = entry.original.width,
            height = entry.original.height,
            data = ffi.new('float[?]', entry.original.width * entry.original.height * 4),
        }
        return P.encode(D, baseline, entry.original)
    end,
    id_available = function(kind, resource)
        queries[#queries + 1] = kind .. ':' .. resource
        return resource ~= rejected_id
    end,
}
local patch = P.encode_set(D, entries, options)
assert(
    patch.binding_aware and patch.archive == P.BASE_ARCHIVE and patch.count == 7,
    'Binding-aware patch did not emit baseline plus three textures, two material variants and one retargeted unit'
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
    records[B.TEXTURE .. ':' .. old_texture] and not records[B.MATERIAL .. ':' .. old_material],
    'Conflicting resource variants lost the baseline or overwrote the original shared material'
)
local baseline_patch = options.original_patch(entries[1])
assert(
    records[B.TEXTURE .. ':' .. old_texture].main == baseline_patch.main:sub(185)
        and records[B.TEXTURE .. ':' .. old_texture].gpu == baseline_patch.gpu,
    'Original texture ID received a changed palette instead of authenticated baseline bytes'
)
assert(
    changed_unit.resource == unit_id
        and #materials == 2
        and changed_unit.gpu == unit.gpu
        and changed_unit.stream == unit.stream
)
local changed_layout = L.parse(changed_unit.main)
local first_section, second_section = u(changed_unit.main, 320), u(changed_unit.main, 512)
local first_material = changed_layout.section_by_id[first_section].material
local second_material = changed_layout.section_by_id[second_section].material
assert(
    first_material ~= second_material
        and first_material ~= old_material
        and second_material ~= old_material
        and first_section ~= second_section
        and first_section ~= 101
        and second_section ~= 102
        and u(changed_unit.main, 704) == 103
        and #changed_layout.sections == 5,
    'Selected mesh forks lost distinct assignments or changed an unselected mesh'
)
for index = 1, 3 do
    assert(
        changed_layout.sections[index].section == 100 + index
            and changed_layout.sections[index].material == old_material,
        'Extended Unit material table changed original entries or their order'
    )
end
local expected_unit = replace(
    replace(
        replace(replace(unit_main, 96, word(u(changed_unit.main, 96))), 112, word(changed_layout.materials_offset)),
        320,
        word(first_section)
    ),
    512,
    word(second_section)
)
local new_table_end = changed_layout.materials_offset + 4 + #changed_layout.sections * 12
assert(
    changed_unit.main:sub(1, #unit_main) == expected_unit
        and changed_layout.materials_offset >= #unit_main
        and changed_unit.main:sub(new_table_end + 1) == unit_main:sub(841)
        and u(changed_unit.main, 96) == new_table_end + 24
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
assert(u(patch.main, 4) == 3 and u(patch.main, 8) == 7)
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
    { 'mesh_verified', false },
    { 'mesh_id', 0xffffffff },
    { 'material_slot', 1 },
    { 'material_slot_offset', 321 },
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
local second_source = entries[2].binding_source
entries[2].binding_source = {}
for key, value in pairs(before_source) do
    entries[2].binding_source[key] = value
end
entries[2].binding_source.kind, entries[2].binding_source.key = entries[2].kind, entries[2].key
assert(
    not pcall(P.encode_set, D, entries, options),
    'Two variants silently collapsed at one authenticated mesh material slot'
)
entries[2].binding_source = second_source
for _, field in ipairs({ 'mesh_verified', 'mesh_id', 'material_slot', 'material_slot_offset' }) do
    local previous = before_source[field]
    before_source[field] = nil
    assert(not pcall(P.encode_set, D, entries, options), 'Missing mesh proof accepted: ' .. field)
    before_source[field] = previous
end
local layout_provider, baseline_provider = options.unit_layout, options.original_patch
options.unit_layout = nil
assert(not pcall(P.encode_set, D, entries, options), 'Precise mesh proof bypassed layout authentication')
options.unit_layout = layout_provider
options.original_patch = nil
assert(not pcall(P.encode_set, D, entries, options), 'Conflicting palettes accepted without a pristine baseline')
options.original_patch = function(entry)
    if entry == entries[2] then
        return P.encode(D, b, entry.original)
    end
    return baseline_provider(entry)
end
assert(not pcall(P.encode_set, D, entries, options), 'One texture accepted disagreeing original baseline signatures')
options.original_patch = baseline_provider
local composite = source(unit_id, B.UNIT, replace(unit_main, 16, hash('0011223344556677')), unit.gpu, unit.stream)
before_source.unit = composite
assert(not pcall(P.encode_set, D, entries, options), 'Composite Unit accepted an inline mesh section split')
before_source.unit = unit
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
    unit_layout = L,
    original_patch = options.original_patch,
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
-- A material is conservatively forked even when older metadata calls it unique.
-- That preserves the original for unselected users and baseline assignments.
local other_material = source('9876543210abcdef', B.MATERIAL, material_main, material.gpu, material.stream)
other_material.shared, material.shared = false, false
local other_unit =
    source('1111222233334444', B.UNIT, replace(unit_main, 824, hash(other_material.resource)), unit.gpu, unit.stream)
entries[2].binding_source.material, entries[2].binding_source.unit = other_material, other_unit
local unique_materials = P.encode_set(D, entries, options)
assert(unique_materials.count == 8, 'Changed unique material did not retain baseline and isolated mesh forks')
local rewritten_units = 0
for _, resource in ipairs(unique_materials.records) do
    if resource.type == B.UNIT then
        rewritten_units = rewritten_units + 1
    end
    assert(
        resource.type ~= B.MATERIAL
            or (resource.resource ~= material.resource and resource.resource ~= other_material.resource),
        'Unique-material claim allowed an original material overwrite'
    )
end
assert(rewritten_units == 2, 'Two independently selected Unit slots did not receive isolated forks')
entries[2].binding_source.material, entries[2].binding_source.unit = material, unit
material.shared = nil
local function record_map(result)
    local out, changed = {}, nil
    for _, value in ipairs(result.records) do
        out[value.type .. ':' .. value.resource] = value
        if value.type == B.UNIT then
            changed = value
        end
    end
    return out, changed
end
-- Several LOD meshes can share one global SectionID. Only changed selections
-- receive local forks; a selected baseline and unselected mesh keep originals.
local shared_main = unit_bytes({ 101, 101, 101 })
local shared_unit = source(unit_id, B.UNIT, shared_main, unit.gpu, unit.stream)
local zero = { width = 3, height = 1, data = ffi.new('float[12]') }
local shared_entries = {
    entry('armor', 'p:0:2:0:0', a, 101),
    entry('armor', 'p:0:2:1:0', b, 101),
    { kind = 'armor', key = 'p:0:2:2:0', document = zero, original = original(zero, old_texture) },
}
for index = 1, 2 do
    local proof = shared_entries[index].binding_source
    proof.unit, proof.mesh_id, proof.material_slot_offset = shared_unit, mesh_ids[index], mesh_offsets[index] + 128
end
local shared_patch = P.encode_set(D, shared_entries, options)
local shared_records, shared_changed = record_map(shared_patch)
local shared_layout = L.parse(shared_changed.main)
local shared_first, shared_second = u(shared_changed.main, 320), u(shared_changed.main, 512)
assert(
    shared_entries[3].binding_source == nil
        and shared_patch.count == 6
        and shared_first ~= shared_second
        and shared_first ~= 101
        and shared_second ~= 101
        and u(shared_changed.main, 704) == 101
        and shared_layout.section_by_id[101].material == old_material,
    'Divergent LOD palettes changed the shared original section or a selected baseline mesh'
)
assert(
    shared_records[B.TEXTURE .. ':' .. old_texture].gpu == options.original_patch(shared_entries[3]).gpu,
    'Selected baseline mesh lost its original texture payload'
)
local shared_expected = replace(
    replace(
        replace(replace(shared_main, 96, word(u(shared_changed.main, 96))), 112, word(shared_layout.materials_offset)),
        320,
        word(shared_first)
    ),
    512,
    word(shared_second)
)
assert(
    shared_changed.main:sub(1, #shared_main) == shared_expected
        and shared_changed.gpu == unit.gpu
        and shared_changed.stream == unit.stream
        and shared_changed.main:sub(shared_layout.materials_offset + 4 + #shared_layout.sections * 12 + 1)
            == shared_main:sub(841),
    'Shared-section split changed bytes beyond selected local slots, exact pointers and copied pristine trailer'
)
local shared_repeat = P.encode_set(D, { shared_entries[3], shared_entries[2], shared_entries[1] }, options)
assert(
    shared_patch.main == shared_repeat.main and shared_patch.gpu == shared_repeat.gpu,
    'Shared-section split depends on selected or baseline assignment order'
)
local unselected_patch = P.encode_set(D, { shared_entries[1], shared_entries[2] }, options)
local _, unselected_changed = record_map(unselected_patch)
assert(
    unselected_changed.main == shared_changed.main and u(unselected_changed.main, 704) == 101,
    'Unselected shared-section mesh did not retain the same baseline as an explicit baseline selection'
)
-- Occupied global SectionIDs and unmapped local slot IDs both block allocation.
for _, scope in ipairs({ 'global', 'local', 'mesh' }) do
    local collision_main = unit_main
    if scope == 'global' then
        collision_main = replace(
            collision_main,
            800,
            word(4)
                .. word(101)
                .. word(102)
                .. word(103)
                .. word(first_section)
                .. hash(old_material)
                .. hash(old_material)
                .. hash(old_material)
                .. hash(old_material)
        )
    elseif scope == 'local' then
        collision_main = replace(collision_main, 704, word(first_section))
    else
        collision_main = replace(replace(collision_main, 152, word(first_section)), 616, word(first_section))
    end
    local collision_unit = source(unit_id, B.UNIT, collision_main, unit.gpu, unit.stream)
    before_source.unit, second_source.unit = collision_unit, collision_unit
    local collision_patch = P.encode_set(D, entries, options)
    local _, collision_changed = record_map(collision_patch)
    assert(
        u(collision_changed.main, 320) ~= first_section,
        'Section allocator reused an occupied ' .. scope .. ' Unit ID'
    )
    if scope == 'local' then
        local old_layout, next_layout = L.parse(collision_main), L.parse(collision_changed.main)
        assert(
            not old_layout.meshes[3].material_slots[1].mapped
                and not next_layout.meshes[3].material_slots[1].mapped
                and u(collision_changed.main, 704) == first_section
                and next_layout.section_by_id[101].material == old_material,
            'Unselected fallback without a global identity was rewritten or adopted by a new section'
        )
        local collision_records = record_map(collision_patch)
        assert(
            collision_records[B.TEXTURE .. ':' .. old_texture].gpu == baseline_patch.gpu,
            'Unselected unmapped fallback lost the original texture payload'
        )
    end
    local repeated_collision = P.encode_set(D, { entries[2], entries[1], entries[3] }, options)
    assert(
        collision_patch.main == repeated_collision.main and collision_patch.gpu == repeated_collision.gpu,
        'Section collision retry is nondeterministic for ' .. scope .. ' IDs'
    )
end
before_source.unit, second_source.unit = unit, unit
-- The exceptional legacy route requires explicit ownership of the entire
-- section; it still preserves the original table and moves a pristine trailer.
local legacy_entries = { entry('armor', 'p:0:2:0:0', a, 101), entry('helmet', 'p:0:0:1:0', b, 102) }
for _, value in ipairs(legacy_entries) do
    local proof = value.binding_source
    proof.mesh_verified, proof.mesh_id, proof.material_slot, proof.material_slot_offset = nil, nil, nil, nil
    proof.section_owned = true
end
local legacy_patch = P.encode_set(D, legacy_entries, options)
local _, legacy_changed = record_map(legacy_patch)
local legacy_layout = L.parse(legacy_changed.main)
assert(
    #legacy_layout.sections == 3
        and legacy_layout.section_by_id[101].material ~= old_material
        and legacy_layout.section_by_id[102].material ~= old_material
        and legacy_layout.section_by_id[103].material == old_material
        and u(legacy_changed.main, 320) == 101
        and u(legacy_changed.main, 512) == 102,
    'Explicit whole-section ownership did not preserve local slots and the unselected original section'
)
legacy_entries[2].binding_source.section = 101
assert(
    not pcall(P.encode_set, D, legacy_entries, options),
    'Legacy whole-section ownership allowed divergent variants at one global SectionID'
)
legacy_entries[2].binding_source.section = 102
legacy_entries[1].binding_source.unit, legacy_entries[2].binding_source.unit = composite, composite
assert(
    not pcall(P.encode_set, D, legacy_entries, options),
    'Legacy whole-section ownership bypassed composite Unit refusal'
)
for _, ending in ipairs({ 839, 890 }) do
    local bad_unit = source(unit_id, B.UNIT, replace(unit_main, 96, word(ending)), unit.gpu, unit.stream)
    before_source.unit, second_source.unit = bad_unit, bad_unit
    assert(not pcall(P.encode_set, D, entries, options), 'Invalid Unit ending bounds accepted: ' .. ending)
end
before_source.unit, second_source.unit = unit, unit
-- A valid source at the shared 64-material limit cannot accommodate two new
-- precise SectionIDs. Refuse before emitting a Unit that its reader rejects.
local capacity_sections, capacity_materials = {}, {}
for index = 1, 64 do
    capacity_sections[index], capacity_materials[index] = word(100 + index), hash(old_material)
end
local capacity_main = unit_main .. string.rep('\x6c', 800)
capacity_main =
    replace(capacity_main, 800, word(64) .. table.concat(capacity_sections) .. table.concat(capacity_materials))
capacity_main = replace(replace(capacity_main, 96, word(1600)), 1600, qword(3))
local capacity_unit = source(unit_id, B.UNIT, capacity_main, unit.gpu, unit.stream)
local capacity_layout = L.parse(capacity_main)
assert(
    capacity_layout.supported
        and #capacity_layout.sections == 64
        and capacity_layout.meshes[1].material_slots[1].offset == before_source.material_slot_offset
        and capacity_layout.meshes[2].material_slots[1].offset == second_source.material_slot_offset
        and capacity_layout.meshes[1].material_slots[1].material == old_material
        and capacity_layout.meshes[2].material_slots[1].material == old_material,
    'Capacity rejection fixture did not independently parse with both exact proved source slots'
)
before_source.unit, second_source.unit = capacity_unit, capacity_unit
local capacity_ok, capacity_error = pcall(P.encode_set, D, entries, options)
assert(
    not capacity_ok and tostring(capacity_error):find('Extended Unit material table exceeds its limit', 1, true),
    'Two exact split slots exceeded the 64-entry Unit table limit or failed for an unrelated reason'
)
assert(
    capacity_unit.main == capacity_main and capacity_unit.gpu == unit.gpu and capacity_unit.stream == unit.stream,
    'Refused capacity split mutated its pristine source'
)
before_source.unit, second_source.unit = unit, unit
-- Independent Pattern and Material LUT edits on one selected mesh share one
-- material fork and one local SectionID, preserving the other texture slots.
local combined = {
    entry('armor', 'p:0:2:0:0', a, 101),
    { kind = 'armor', key = 'p:0:2:1:0', document = zero, original = original(zero, old_texture) },
    entry('armor', '0:2:0:0', cape, 101),
    { kind = 'armor', key = '0:2:1:0', document = doc(23, 8, 0), original = original(cape, untouched) },
}
combined[3].binding_source.texture_slot, combined[3].binding_source.original_texture = 0x7e662968, untouched
combined[3].original = original(cape, untouched)
combined[4].document.data = ffi.new('float[?]', 23 * 8 * 4)
local combined_patch = P.encode_set(D, combined, options)
local combined_records, combined_unit = record_map(combined_patch)
local combined_layout = L.parse(combined_unit.main)
local combined_material =
    combined_records[B.MATERIAL .. ':' .. combined_layout.section_by_id[u(combined_unit.main, 320)].material]
local combined_material_count = 0
for _, value in ipairs(combined_patch.records) do
    if value.type == B.MATERIAL then
        combined_material_count = combined_material_count + 1
    end
end
assert(
    combined_material_count == 1
        and #combined_layout.sections == 4
        and hex_at(combined_material.main, 144) ~= old_texture
        and hex_at(combined_material.main, 152) ~= untouched
        and u(combined_unit.main, 512) == 102
        and u(combined_unit.main, 704) == 103,
    'Independent texture-slot edits failed to combine in one isolated mesh material fork'
)
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
            mesh_verified = true,
            mesh_id = mesh_ids[index],
            material_slot = 0,
            material_slot_offset = mesh_offsets[index] + 128,
            original_texture = untouched,
            texture_slot = 0x7e662968,
            kit_override = false,
            material = material,
            unit = unit,
        },
    }
end
local cape_forks = P.encode_set(D, material_entries, options)
assert(
    cape_forks.binding_aware and cape_forks.count == 6,
    'Cape material LUT did not retain baseline and actual MaterialLut slot'
)
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
f = assert(io.open('tests/tmp/binding-unit-original-proof.bin', 'wb'))
assert(f:write(unit_main))
assert(f:close())
f = assert(io.open('tests/tmp/binding-unit-shared-proof.bin', 'wb'))
assert(f:write(shared_changed.main))
assert(f:close())
f = assert(io.open('tests/tmp/binding-unit-shared-original-proof.bin', 'wb'))
assert(f:write(shared_main))
assert(f:close())
print(
    'PASS binding patch prototype: authenticated baselines, isolated mesh SectionID/material forks, divergent shared-section palettes, exact unchanged geometry/GPU/stream/TOC bytes, collision retries and strict provenance guards'
)
