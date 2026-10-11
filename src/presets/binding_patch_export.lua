-- Original-byte material/unit edits for assignment-preserving texture variants.
-- Factual offsets verified against HD2SDK CE 5a886256; no SDK runtime dependency.
local bit = require('bit')
local B = { MAX_BINDINGS = 4096, MAX_RECORDS = 12288, MAX_PART_BYTES = 8 * 1024 * 1024, MAX_UNIT_MATERIALS = 64 }
B.TEXTURE, B.MATERIAL, B.UNIT = 'cd4238c6a0c69e32', 'eac0b497876adedf', 'e0a48d0be9a7453f'
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function qword(n)
    return word(n) .. word(0)
end
local function id(value)
    assert(type(value) == 'string' and #value == 16 and value:match('^%x+$'), 'Missing exact binding resource ID')
    return value:lower()
end
local function hash(value)
    value = id(value)
    local bytes = {}
    for i = 15, 1, -2 do
        bytes[#bytes + 1] = string.char(tonumber(value:sub(i, i + 1), 16))
    end
    return table.concat(bytes)
end
local function uint(bytes, at)
    assert(type(bytes) == 'string' and at >= 0 and at + 4 <= #bytes, 'Truncated binding resource record')
    local a, b, c, d = bytes:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function hex_at(bytes, at)
    assert(at >= 0 and at + 8 <= #bytes, 'Truncated binding resource ID')
    local text = ''
    for i = at + 8, at + 1, -1 do
        text = text .. string.format('%02x', bytes:byte(i))
    end
    return text
end
local function replace(bytes, at, value)
    assert(at >= 0 and at + #value <= #bytes, 'Binding edit exceeds original record')
    return bytes:sub(1, at) .. value .. bytes:sub(at + #value + 1)
end
local function record(source, kind)
    assert(type(source) == 'table', 'Certified binding source unavailable')
    local value = {
        resource = id(source.resource),
        type = kind,
        main = source.main,
        gpu = source.gpu or '',
        stream = source.stream or '',
        unknowns = source.unknowns or string.rep('\0', 16),
        flags = source.flags or word(16) .. word(64),
    }
    for _, part in ipairs({ 'main', 'gpu', 'stream' }) do
        assert(
            type(value[part]) == 'string' and #value[part] <= B.MAX_PART_BYTES,
            'Binding source payload exceeds budget'
        )
    end
    assert(#value.main > 0, 'Binding source main record unavailable')
    if source.toc then
        assert(
            type(source.toc) == 'string'
                and #source.toc == 80
                and hex_at(source.toc, 0) == value.resource
                and hex_at(source.toc, 8) == kind
                and uint(source.toc, 56) == #value.main
                and uint(source.toc, 60) == #value.stream
                and uint(source.toc, 64) == #value.gpu,
            'Original binding TOC provenance differs from captured payload'
        )
        value.unknowns, value.flags = source.toc:sub(41, 56), source.toc:sub(69, 76)
    end
    assert(
        type(value.unknowns) == 'string'
            and #value.unknowns == 16
            and type(value.flags) == 'string'
            and #value.flags == 8,
        'Invalid preserved native TOC fields'
    )
    return value
end
local function same_record(a, b)
    return a.main == b.main
        and a.gpu == b.gpu
        and a.stream == b.stream
        and a.unknowns == b.unknowns
        and a.flags == b.flags
end
local function material_slots(source)
    assert(#source.main >= 136, 'Truncated native material record')
    local count, slots = uint(source.main, 64), {}
    assert(count <= 64 and 136 + 12 * count <= #source.main, 'Invalid native material texture table')
    for i = 0, count - 1 do
        local slot = uint(source.main, 136 + i * 4)
        assert(not slots[slot], 'Ambiguous duplicate native material texture slot')
        slots[slot] = 136 + count * 4 + i * 8
    end
    return slots
end
local function unit_sections(source)
    assert(#source.main >= 116, 'Truncated native unit record')
    local at = uint(source.main, 112)
    assert(at >= 116, 'Unsupported native unit material table')
    local count, sections = uint(source.main, at), {}
    assert(count >= 1 and count <= 4096 and at + 4 + count * 12 <= #source.main, 'Invalid native unit material table')
    for i = 0, count - 1 do
        local section = uint(source.main, at + 4 + i * 4)
        local offset = at + 4 + count * 4 + i * 8
        local existing = sections[section]
        assert(
            not existing or hex_at(source.main, existing[1]) == hex_at(source.main, offset),
            'Ambiguous native unit material SectionID'
        )
        sections[section] = existing or {}
        sections[section][#sections[section] + 1] = offset
    end
    return sections
end
-- Deterministic CRC32/FNV32 pair; no floating-point64-bit ID conversions.
local crc = {}
for n = 0, 255 do
    local value = n
    for _ = 1, 8 do
        value = bit.bxor(bit.rshift(value, 1), bit.band(value, 1) ~= 0 and 0xedb88320 or 0)
    end
    crc[n] = value
end
local function fingerprint(bytes)
    local a, b = -1, bit.tobit(2166136261)
    for i = 1, #bytes do
        local byte = bytes:byte(i)
        a = bit.bxor(bit.rshift(a, 8), crc[bit.band(bit.bxor(a, byte), 255)])
        b = bit.bxor(b, byte)
        local low, high = bit.band(b, 65535), bit.rshift(b, 16)
        b = bit.tobit(low * 403 + bit.lshift((high * 403 + low * 256) % 65536, 16))
    end
    return string.format('%08x%08x', bit.bnot(a) % 4294967296, b % 4294967296)
end
function B.archive(archive, records)
    id(archive)
    assert(
        type(records) == 'table' and #records > 0 and #records <= B.MAX_RECORDS,
        'Invalid binding patch resource count'
    )
    local types, counts, ordered, seen = {}, {}, {}, {}
    for _, source in ipairs(records) do
        local item = record(source, id(source.type))
        local key = item.type .. ':' .. item.resource
        assert(not seen[key], 'Duplicate binding patch resource record')
        seen[key], ordered[#ordered + 1] = true, item
        if not counts[item.type] then
            types[#types + 1] = item.type
        end
        counts[item.type] = (counts[item.type] or 0) + 1
    end
    table.sort(types)
    table.sort(ordered, function(a, b)
        return a.type == b.type and a.resource < b.resource or a.type < b.type
    end)
    local descriptors = {}
    for _, kind in ipairs(types) do
        descriptors[#descriptors + 1] = qword(0) .. hash(kind) .. qword(counts[kind]) .. word(16) .. word(64)
    end
    local offset, gpu_offset, stream_offset = 72 + #types * 32 + #ordered * 80, 0, 0
    local entries, main, gpu, stream = {}, {}, {}, {}
    for index, item in ipairs(ordered) do
        local ga, sa = math.ceil(gpu_offset / 64) * 64, math.ceil(stream_offset / 64) * 64
        gpu[#gpu + 1], stream[#stream + 1] = string.rep('\0', ga - gpu_offset), string.rep('\0', sa - stream_offset)
        gpu[#gpu + 1], stream[#stream + 1] = item.gpu, item.stream
        entries[#entries + 1] = hash(item.resource)
            .. hash(item.type)
            .. qword(offset)
            .. qword(sa)
            .. qword(ga)
            .. item.unknowns
            .. word(#item.main)
            .. word(#item.stream)
            .. word(#item.gpu)
            .. item.flags
            .. word(index)
        main[#main + 1] = item.main
        offset, gpu_offset, stream_offset = offset + #item.main, ga + #item.gpu, sa + #item.stream
        assert(
            offset <= B.MAX_PART_BYTES and gpu_offset <= B.MAX_PART_BYTES and stream_offset <= B.MAX_PART_BYTES,
            'Binding patch triplet exceeds payload budget'
        )
    end
    return {
        archive = archive,
        resource = #ordered .. ' binding resources',
        count = #ordered,
        records = ordered,
        main = word(0xf0000011) .. word(#types) .. word(#ordered) .. word(0) .. string.rep('\0', 56) .. table.concat(
            descriptors
        ) .. table.concat(entries) .. table.concat(main),
        gpu = table.concat(gpu),
        stream = table.concat(stream),
        binding_aware = true,
    }
end
function B.encode(archive, documents, patches, options)
    options = options or {}
    assert(
        type(documents) == 'table'
            and type(patches) == 'table'
            and #documents > 0
            and #documents <= B.MAX_BINDINGS
            and #documents == #patches,
        'Invalid binding patch assignment count'
    )
    local by_texture, used = {}, {}
    for index, patch in ipairs(patches) do
        local resource = id(patch.resource)
        used[B.TEXTURE .. ':' .. resource] = true
        local group = by_texture[resource] or { variants = {}, items = {} }
        by_texture[resource] = group
        local signature = patch.main:sub(185) .. patch.gpu
        group.variants[signature] = group.variants[signature] or { patch = patch, indices = {} }
        local variant = group.variants[signature]
        variant.indices[#variant.indices + 1] = index
    end
    local sources, units, materials, fixed_sources = {}, {}, {}, {}
    for _, group in pairs(by_texture) do
        local count = 0
        for _ in pairs(group.variants) do
            count = count + 1
        end
        group.conflict = count > 1
        if group.conflict then
            local captured, fixed = {}, nil
            for _, variant in pairs(group.variants) do
                for _, index in ipairs(variant.indices) do
                    local entry = documents[index]
                    local source = options.provenance and options.provenance(entry) or entry.binding_source
                    local pattern = entry.document.width == 3 and entry.document.height == 1
                    assert(
                        (entry.kind == 'armor' or entry.kind == 'helmet' or entry.kind == 'cape')
                            and type(entry.key) == 'string'
                            and #entry.key <= 96
                            and (pattern and entry.key:match('^p:%d+:%d+:%d+:%d+$') or not pattern and entry.key:match(
                                '^%d+:%d+:%d+:%d+$'
                            ))
                            and type(source) == 'table'
                            and source.version == 1
                            and source.verified == true
                            and source.kind == entry.kind
                            and source.key == entry.key
                            and type(source.kit_override) == 'boolean'
                            and source.texture_slot == (pattern and 0x81d4c49d or 0x7e662968)
                            and id(source.original_texture) == patches[index].resource,
                        'Binding assignment provenance unavailable; no destinations guessed'
                    )
                    captured[index] = source
                    if source.kit_override or source.fixed_texture == true then
                        fixed_sources[index] = source
                        assert(
                            source.kit
                                and (
                                    source.kit_override
                                        and id(source.kit.override_texture) == source.original_texture
                                    or source.kit_override == false
                                        and source.fixed_texture == true
                                        and source.kit.matches == 0
                                ),
                            'Fixed binding texture proof differs from its effective original'
                        )
                        local material, unit = record(source.material, B.MATERIAL), record(source.unit, B.UNIT)
                        assert(source.material.toc and source.unit.toc, 'Certified fixed material/unit TOC unavailable')
                        local section =
                            assert(unit_sections(unit)[source.section], 'Certified fixed Unit SectionID unavailable')
                        for _, at in ipairs(section) do
                            assert(
                                hex_at(unit.main, at) == material.resource,
                                'Fixed Unit material assignment differs from certified source'
                            )
                        end
                        for _, item in ipairs({ material, unit }) do
                            local cache = item.type == B.MATERIAL and materials or units
                            assert(
                                not cache[item.resource] or same_record(cache[item.resource], item),
                                'Conflicting original binding resource bytes'
                            )
                            cache[item.resource] = cache[item.resource] or item
                            used[item.type .. ':' .. item.resource] = true
                        end
                        local signature = variant.patch.main:sub(185) .. variant.patch.gpu
                        assert(
                            not fixed or fixed == signature,
                            'Shared texture has different kit-fixed palettes; existing kit assignments require one original texture payload'
                        )
                        fixed = signature
                    end
                end
            end
            group.baseline, group.fixed, group.anchors = fixed, fixed ~= nil, {}
            local baseline
            assert(type(options.original_patch) == 'function', 'Original baseline texture snapshot unavailable')
            for _, variant in pairs(group.variants) do
                for _, index in ipairs(variant.indices) do
                    local original = options.original_patch(documents[index])
                    assert(
                        type(original) == 'table'
                            and id(original.resource) == patches[index].resource
                            and type(original.main) == 'string'
                            and #original.main >= 184
                            and type(original.gpu) == 'string'
                            and #original.gpu > 0
                            and #original.gpu <= B.MAX_PART_BYTES
                            and (original.stream or '') == '',
                        'Invalid original baseline texture patch'
                    )
                    local signature = original.main:sub(185) .. original.gpu
                    assert(
                        not baseline or group.original_baseline == signature,
                        'Conflicting original texture baselines'
                    )
                    baseline, group.original_baseline = original, signature
                end
            end
            group.baseline = group.baseline or group.original_baseline
            group.variants[group.original_baseline] = group.variants[group.original_baseline]
                or { patch = baseline, indices = {} }
            for signature, variant in pairs(group.variants) do
                if signature ~= group.baseline or group.fixed then
                    for _, index in ipairs(variant.indices) do
                        if not fixed_sources[index] then
                            local entry = documents[index]
                            local pattern = entry.document.width == 3 and entry.document.height == 1
                            assert(
                                (entry.kind == 'armor' or entry.kind == 'helmet' or entry.kind == 'cape')
                                    and type(entry.key) == 'string'
                                    and #entry.key <= 96
                                    and (
                                        pattern and entry.key:match('^p:%d+:%d+:%d+:%d+$')
                                        or not pattern and entry.key:match('^%d+:%d+:%d+:%d+$')
                                    ),
                                'Binding export requires an exact saved gear/destination key'
                            )
                            local source = captured[index]
                            assert(
                                type(source) == 'table'
                                    and source.version == 1
                                    and source.verified == true
                                    and source.kind == entry.kind
                                    and source.key == entry.key
                                    and source.kit_override == false
                                    and source.fixed_texture ~= true,
                                'Binding assignment provenance unavailable or kit override unsupported; no destinations guessed'
                            )
                            assert(
                                type(source.section) == 'number'
                                    and source.section >= 0
                                    and source.section < 4294967296
                                    and source.section % 1 == 0,
                                'Invalid certified native SectionID'
                            )
                            -- Cape material palettes use MaterialLut too. The separate
                            -- cape-tint slot is identification data and stays untouched.
                            local expected_slot = pattern and 0x81d4c49d or 0x7e662968
                            assert(
                                source.texture_slot == expected_slot
                                    and id(source.original_texture) == patches[index].resource,
                                'Binding source texture family/identity differs from the saved destination'
                            )
                            assert(
                                source.material and source.material.toc and source.unit and source.unit.toc,
                                'Certified material/unit TOC provenance unavailable'
                            )
                            local material, unit = record(source.material, B.MATERIAL), record(source.unit, B.UNIT)
                            local slots, sections = material_slots(material), unit_sections(unit)
                            assert(
                                hex_at(unit.main, 16) == '0000000000000000',
                                'Composite mesh material splitting is unsupported'
                            )
                            local slot =
                                assert(slots[source.texture_slot], 'Certified material texture slot unavailable')
                            assert(
                                hex_at(material.main, slot) == patches[index].resource,
                                'Material original texture ID changed'
                            )
                            local section = assert(sections[source.section], 'Certified unit SectionID unavailable')
                            for _, at in ipairs(section) do
                                assert(
                                    hex_at(unit.main, at) == material.resource,
                                    'Unit material assignment differs from certified source'
                                )
                            end
                            local precise = source.mesh_id ~= nil
                                or source.material_slot ~= nil
                                or source.material_slot_offset ~= nil
                            local layout
                            if precise then
                                assert(
                                    source.mesh_verified == true
                                        and type(options.unit_layout) == 'table'
                                        and type(options.unit_layout.parse) == 'function',
                                    'Verified named mesh layout proof unavailable'
                                )
                                for _, field in ipairs({ 'mesh_id', 'material_slot', 'material_slot_offset' }) do
                                    local value = source[field]
                                    assert(
                                        type(value) == 'number' and value >= 0 and value < 4294967296 and value % 1 == 0,
                                        'Invalid certified mesh material slot locator'
                                    )
                                end
                                layout = options.unit_layout.parse(unit.main)
                                assert(layout.supported == true, 'Composite mesh material splitting is unsupported')
                                local found
                                for _, mesh in ipairs(layout.meshes) do
                                    if mesh.id == source.mesh_id then
                                        local slot = mesh.material_slots[source.material_slot + 1]
                                        assert(
                                            slot
                                                and slot.index == source.material_slot
                                                and slot.offset == source.material_slot_offset
                                                and slot.section == source.section
                                                and slot.material == material.resource,
                                            'Certified mesh material slot differs from pristine Unit layout'
                                        )
                                        found = true
                                    end
                                end
                                assert(found, 'Certified MeshID unavailable in pristine Unit layout')
                            else
                                assert(source.section_owned == true, 'Whole Unit SectionID ownership proof unavailable')
                            end
                            for _, item in ipairs({ material, unit }) do
                                local cache = item.type == B.MATERIAL and materials or units
                                assert(
                                    not cache[item.resource] or same_record(cache[item.resource], item),
                                    'Conflicting original binding resource bytes'
                                )
                                cache[item.resource] = cache[item.resource] or item
                                used[item.type .. ':' .. item.resource] = true
                            end
                            sources[index] = {
                                source = source,
                                material = material,
                                unit = unit,
                                slot = slot,
                                section_offsets = section,
                                precise = precise,
                                layout = layout,
                            }
                            group.anchors[unit.resource] = sources[index]
                        end
                    end
                end
            end
        end
    end
    assert(type(options.id_available) == 'function', 'Binding export resource-collision catalog unavailable')
    local function allocate(kind, old, bytes)
        for salt = 0, 1023 do
            local candidate = fingerprint('EPIC-LUT-binding-v1\0' .. kind .. old .. bytes .. word(salt))
            local key = kind .. ':' .. candidate
            if not used[key] and options.id_available(kind, candidate) == true then
                used[key] = true
                return candidate
            end
        end
        error('Unable to allocate a collision-free deterministic binding resource ID', 0)
    end
    local records, destinations, section_modes = {}, {}, {}
    local function destination(proof, target, selected)
        local section_key = proof.unit.resource .. ':' .. proof.source.section
        local mode = proof.precise and 'mesh' or 'whole'
        assert(
            not section_modes[section_key] or section_modes[section_key] == mode,
            'Whole SectionID and mesh-local proofs cannot be combined'
        )
        section_modes[section_key] = mode
        local key = section_key .. (proof.precise and (':mesh:' .. proof.source.material_slot_offset) or ':whole')
        local value = destinations[key] or { proof = proof, changes = {}, selected = {} }
        assert(
            value.proof.material.resource == proof.material.resource,
            'Conflicting material identities at one unit SectionID'
        )
        local previous
        if selected then
            previous = value.selected[proof.slot]
        else
            previous = value.changes[proof.slot]
        end
        assert(not previous or previous == target, 'One serialized unit SectionID has conflicting saved assignments')
        if selected then
            value.selected[proof.slot] = target
        end
        value.changes[proof.slot] = target
        destinations[key] = value
    end
    local texture_ids = {}
    for resource in pairs(by_texture) do
        texture_ids[#texture_ids + 1] = resource
    end
    table.sort(texture_ids)
    for _, resource in ipairs(texture_ids) do
        local group, signatures = by_texture[resource], {}
        group.targets = {}
        for signature in pairs(group.variants) do
            signatures[#signatures + 1] = signature
        end
        table.sort(signatures)
        for _, signature in ipairs(signatures) do
            local variant = group.variants[signature]
            local changed = group.conflict and signature ~= group.baseline
            local target = changed and allocate(B.TEXTURE, resource, signature) or resource
            group.targets[signature] = target
            records[#records + 1] = {
                resource = target,
                type = B.TEXTURE,
                main = variant.patch.main:sub(185),
                gpu = variant.patch.gpu,
                stream = '',
            }
        end
    end
    -- A forced original-ID replacement must not recolor unselected meshes/LODs
    -- in affected non-kit Units. Their exact serialized slots retain the
    -- authentic original payload, before selected assignments overlay them.
    for _, resource in ipairs(texture_ids) do
        local group = by_texture[resource]
        if group.fixed and group.original_baseline ~= group.baseline then
            for _, anchor in pairs(group.anchors) do
                assert(
                    anchor.precise and anchor.layout and anchor.layout.supported,
                    'Verified mesh layout required to preserve original kit-conflict fallbacks'
                )
                local unit, layout, fixed_slots = anchor.unit, anchor.layout, {}
                for _, fixed in pairs(fixed_sources) do
                    if
                        fixed.unit.resource == unit.resource
                        and fixed.texture_slot == anchor.source.texture_slot
                        and fixed.original_texture == resource
                    then
                        assert(
                            fixed.mesh_verified == true and fixed.material_slot_offset ~= nil,
                            'Verified fixed mesh slot required to preserve original fallbacks'
                        )
                        local found
                        for _, mesh in ipairs(layout.meshes) do
                            if mesh.id == fixed.mesh_id then
                                local slot = mesh.material_slots[fixed.material_slot + 1]
                                assert(
                                    slot
                                        and slot.offset == fixed.material_slot_offset
                                        and slot.section == fixed.section
                                        and slot.material == fixed.material.resource,
                                    'Fixed mesh slot differs from pristine fallback layout'
                                )
                                fixed_slots[slot.offset], found = true, true
                            end
                        end
                        assert(found, 'Fixed mesh unavailable in pristine fallback layout')
                    end
                end
                for _, section in ipairs(layout.sections) do
                    local material = materials[section.material]
                    if not material then
                        local raw = options.material_source and options.material_source(section.material)
                        assert(raw and raw.toc, 'Original fallback material source unavailable')
                        material = record(raw, B.MATERIAL)
                        assert(material.resource == section.material, 'Original fallback material resource differs')
                        materials[section.material] = material
                        used[B.MATERIAL .. ':' .. material.resource] = true
                    end
                    material_slots(material)
                end
                local sections = unit_sections(unit)
                for _, mesh in ipairs(layout.meshes) do
                    for _, slot in ipairs(mesh.material_slots) do
                        -- Opaque unmapped slots have no serialized Material
                        -- texture link. Keep their exact slot bytes untouched.
                        if slot.mapped then
                            assert(materials[slot.material], 'Original fallback mesh material source unavailable')
                            local material = materials[slot.material]
                            local at = material_slots(material)[anchor.source.texture_slot]
                            if at and hex_at(material.main, at) == resource and not fixed_slots[slot.offset] then
                                destination({
                                    source = {
                                        section = slot.section,
                                        mesh_id = mesh.id,
                                        material_slot = slot.index,
                                        material_slot_offset = slot.offset,
                                    },
                                    unit = unit,
                                    material = material,
                                    slot = at,
                                    section_offsets = sections[slot.section],
                                    precise = true,
                                    layout = layout,
                                }, group.targets[group.original_baseline], false)
                            end
                        end
                    end
                end
            end
        end
    end
    for _, resource in ipairs(texture_ids) do
        local group = by_texture[resource]
        for signature, variant in pairs(group.variants) do
            if
                group.conflict
                and (signature ~= group.baseline or group.fixed and group.original_baseline ~= group.baseline)
            then
                for _, index in ipairs(variant.indices) do
                    if sources[index] then
                        destination(sources[index], group.targets[signature], true)
                    end
                end
            end
        end
    end
    local material_groups = {}
    for _, destination in pairs(destinations) do
        local proof, main = destination.proof, destination.proof.material.main
        for at, target in pairs(destination.changes) do
            main = replace(main, at, hash(target))
        end
        local group = material_groups[proof.material.resource] or { source = proof.material, variants = {} }
        material_groups[proof.material.resource] = group
        local variant = group.variants[main] or { main = main, destinations = {} }
        group.variants[main] = variant
        variant.destinations[#variant.destinations + 1] = destination
    end
    local unit_changes, material_ids = {}, {}
    for resource in pairs(material_groups) do
        material_ids[#material_ids + 1] = resource
    end
    table.sort(material_ids)
    for _, resource in ipairs(material_ids) do
        local group, mains = material_groups[resource], {}
        for main in pairs(group.variants) do
            mains[#mains + 1] = main
        end
        table.sort(mains)
        for _, main in ipairs(mains) do
            local variant = group.variants[main]
            -- A SectionID ownership proof does not establish exclusive ownership
            -- of the material resource across unrelated Units.
            local target = allocate(B.MATERIAL, resource, main .. group.source.gpu .. group.source.stream)
            records[#records + 1] = {
                resource = target,
                type = B.MATERIAL,
                main = main,
                gpu = group.source.gpu,
                stream = group.source.stream,
                unknowns = group.source.unknowns,
                flags = group.source.flags,
            }
            for _, destination in ipairs(variant.destinations) do
                local proof = destination.proof
                local changes = unit_changes[proof.unit.resource] or { global = {}, slots = {}, layout = proof.layout }
                unit_changes[proof.unit.resource] = changes
                if proof.precise then
                    changes.layout = changes.layout or proof.layout
                    local at = proof.source.material_slot_offset
                    assert(
                        not changes.slots[at] or changes.slots[at].material == target,
                        'Conflicting retargets for one mesh material slot'
                    )
                    changes.slots[at] = { proof = proof, material = target }
                else
                    assert(
                        not changes.global[proof.source.section] or changes.global[proof.source.section] == target,
                        'Conflicting retargets for a whole Unit SectionID'
                    )
                    changes.global[proof.source.section] = target
                end
            end
        end
    end
    for resource, changes in pairs(unit_changes) do
        local source, main = units[resource], units[resource].main
        local table_at = uint(main, 112)
        local count = uint(main, table_at)
        local sections = main:sub(table_at + 5, table_at + 4 + count * 4)
        local materials_out = {}
        local used_sections = {}
        for index = 0, count - 1 do
            local section = uint(main, table_at + 4 + index * 4)
            used_sections[section] = true
            local old = hex_at(main, table_at + 4 + count * 4 + index * 8)
            materials_out[#materials_out + 1] = hash(changes.global[section] or old)
        end
        if changes.layout then
            for _, mesh in ipairs(changes.layout.meshes) do
                used_sections[mesh.id] = true
                for _, slot in ipairs(mesh.material_slots) do
                    used_sections[slot.section] = true
                end
            end
        end
        local offsets = {}
        for at in pairs(changes.slots) do
            offsets[#offsets + 1] = at
        end
        table.sort(offsets)
        for _, at in ipairs(offsets) do
            local change = changes.slots[at]
            local proof = change.proof.source
            local seed = resource
                .. word(proof.section)
                .. word(proof.mesh_id)
                .. word(proof.material_slot)
                .. word(at)
                .. change.material
            local allocated
            for salt = 0, 1023 do
                local candidate =
                    tonumber(fingerprint('EPIC-LUT-mesh-section-v1\0' .. seed .. word(salt)):sub(1, 8), 16)
                if candidate ~= 0 and candidate ~= 4294967295 and not used_sections[candidate] then
                    allocated, used_sections[candidate] = candidate, true
                    break
                end
            end
            assert(allocated, 'Unable to allocate a collision-free deterministic mesh SectionID')
            main = replace(main, at, word(allocated))
            sections = sections .. word(allocated)
            materials_out[#materials_out + 1] = hash(change.material)
        end
        local extended_count = count + #offsets
        assert(extended_count <= B.MAX_UNIT_MATERIALS, 'Extended Unit material table exceeds its limit')
        local append_at = math.ceil(#main / 4) * 4
        local original_table_end = table_at + 4 + count * 12
        local original_ending = uint(source.main, 96)
        assert(
            original_ending >= original_table_end and original_ending + 8 <= #source.main,
            'Unsupported original Unit ending region'
        )
        local extended = word(extended_count) .. sections .. table.concat(materials_out)
        -- SDK reads opaque bytes from the material table end to EndingOffset,
        -- then its trailing mesh-count word. Relocate that exact suffix too;
        -- the pristine original table and suffix stay at their old offsets.
        local ending = append_at + #extended + original_ending - original_table_end
        main = replace(replace(main, 96, word(ending)), 112, word(append_at))
            .. string.rep('\0', append_at - #main)
            .. extended
            .. source.main:sub(original_table_end + 1)
        assert(#main <= B.MAX_PART_BYTES, 'Extended Unit main exceeds its payload budget')
        for _, mesh in ipairs(changes.layout and changes.layout.meshes or {}) do
            for _, slot in ipairs(mesh.material_slots) do
                if not changes.slots[slot.offset] then
                    assert(uint(main, slot.offset) == slot.section, 'Unselected mesh material slot changed')
                end
            end
        end
        records[#records + 1] = {
            resource = resource,
            type = B.UNIT,
            main = main,
            gpu = source.gpu,
            stream = source.stream,
            unknowns = source.unknowns,
            flags = source.flags,
        }
    end
    return B.archive(archive, records)
end
return B
