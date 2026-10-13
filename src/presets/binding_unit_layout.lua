-- Read-only inline Unit layout at SDK revision 5a886256e54db52b5d228335eae20ce796f87fc0.
-- Offsets are zero-based bytes in the pristine main part. No ordinal is a live identity proof.
local L = { MAX_BYTES = 8 * 1024 * 1024, MAX_MESHES = 64, MAX_MATERIALS = 64, MAX_SECTIONS = 256 }
local function range(data, at, size, label)
    assert(
        type(at) == 'number' and at >= 0 and at % 1 == 0 and size >= 0 and at + size <= #data,
        'Truncated Unit ' .. label
    )
end
local function uint(data, at)
    range(data, at, 4, 'integer')
    local a, b, c, d = data:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function hex64(data, at)
    range(data, at, 8, 'resource ID')
    local out = ''
    for i = at + 8, at + 1, -1 do
        out = out .. string.format('%02x', data:byte(i))
    end
    return out
end
function L.parse(main)
    assert(type(main) == 'string' and #main >= 128 and #main <= L.MAX_BYTES, 'Invalid Unit main part')
    local version = uint(main, 44)
    assert(version == 10800437 or version == 10800438, 'Unsupported Unit version')
    local result = {
        version = version,
        composite = hex64(main, 16),
        mesh_info_offset = uint(main, 100),
        materials_offset = uint(main, 112),
        sections = {},
        unique_sections = {},
        section_by_id = {},
        meshes = {},
    }
    local ranges = { { 0, 128 } }
    local function claim(at, size, label)
        range(main, at, size, label)
        for _, old in ipairs(ranges) do
            assert(at + size <= old[1] or at >= old[2], 'Overlapping Unit ' .. label)
        end
        ranges[#ranges + 1] = { at, at + size }
    end
    local table_at = result.materials_offset
    assert(table_at >= 128, 'Invalid Unit materials offset')
    local count = uint(main, table_at)
    assert(count <= L.MAX_MATERIALS, 'Unit material count exceeds its limit')
    claim(table_at, 4 + count * 12, 'materials table')
    for index = 0, count - 1 do
        local section_at, material_at = table_at + 4 + index * 4, table_at + 4 + count * 4 + index * 8
        local entry = {
            index = index,
            section = uint(main, section_at),
            material = hex64(main, material_at),
            section_offset = section_at,
            material_offset = material_at,
        }
        local previous = result.section_by_id[entry.section]
        assert(not previous or previous.material == entry.material, 'Ambiguous Unit global SectionID')
        result.sections[#result.sections + 1] = entry
        if not previous then
            result.section_by_id[entry.section] = entry
            result.unique_sections[#result.unique_sections + 1] = entry
        end
    end
    if result.composite ~= '0000000000000000' then
        result.supported, result.unsupported = false, 'composite_geometry'
        return result
    end
    local mesh_at = result.mesh_info_offset
    assert(mesh_at >= 128, 'Invalid Unit mesh offset')
    local meshes = uint(main, mesh_at)
    assert(meshes >= 1 and meshes <= L.MAX_MESHES, 'Unit mesh count exceeds its limit')
    claim(mesh_at, 4 + meshes * 8, 'mesh table')
    local seen_meshes = {}
    for index = 0, meshes - 1 do
        local offset_at = mesh_at + 4 + index * 4
        local at = mesh_at + uint(main, offset_at)
        range(main, at, 128, 'mesh record')
        local id = uint(main, at + 40)
        assert(id == uint(main, mesh_at + 4 + meshes * 4 + index * 4), 'Unit mesh hash table differs')
        assert(not seen_meshes[id], 'Ambiguous Unit mesh ID')
        seen_meshes[id] = true
        local materials, sections = uint(main, at + 104), uint(main, at + 120)
        assert(materials <= L.MAX_MATERIALS and sections <= L.MAX_SECTIONS, 'Unit mesh count exceeds its limit')
        assert(
            uint(main, at + 108) == 128 and uint(main, at + 124) == 128 + materials * 4,
            'Unsupported inline Unit mesh offsets'
        )
        claim(at, 128 + materials * 4 + sections * 24, 'mesh record')
        local lod = uint(main, at + 56)
        local mesh = {
            index = index,
            id = id,
            hash = string.format('%08x', id),
            offset = at,
            offset_field = offset_at,
            lod = lod >= 2147483648 and lod - 4294967296 or lod,
            material_count = materials,
            section_count = sections,
            material_slots_offset = at + 128,
            draw_sections_offset = at + 128 + materials * 4,
            material_slots = {},
            draw_sections = {},
        }
        local seen_slots = {}
        for slot_index = 0, materials - 1 do
            local offset = mesh.material_slots_offset + slot_index * 4
            local section = uint(main, offset)
            assert(not seen_slots[section], 'Ambiguous Unit mesh material slot')
            seen_slots[section] = true
            local global = result.section_by_id[section]
            mesh.material_slots[#mesh.material_slots + 1] = {
                section = section,
                index = slot_index,
                offset = offset,
                material = global and global.material or nil,
                mapped = global ~= nil,
            }
        end
        for section_index = 0, sections - 1 do
            local offset = mesh.draw_sections_offset + section_index * 24
            local material_index = uint(main, offset)
            assert(material_index < materials, 'Invalid Unit draw section material index')
            mesh.draw_sections[#mesh.draw_sections + 1] = {
                index = section_index,
                offset = offset,
                material_index = material_index,
                section = mesh.material_slots[material_index + 1].section,
                vertex_offset = uint(main, offset + 4),
                vertex_count = uint(main, offset + 8),
                index_offset = uint(main, offset + 12),
                index_count = uint(main, offset + 16),
                group_index = uint(main, offset + 20),
            }
        end
        result.meshes[#result.meshes + 1] = mesh
    end
    result.supported = true
    return result
end
return L
