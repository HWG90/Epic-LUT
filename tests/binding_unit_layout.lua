local L = dofile('src/presets/binding_unit_layout.lua')
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function hash(hex)
    local out = ''
    for i = 15, 1, -2 do
        out = out .. string.char(tonumber(hex:sub(i, i + 1), 16))
    end
    return out
end
local function replace(data, at, value)
    return data:sub(1, at) .. value .. data:sub(at + #value + 1)
end
local function draw(index)
    return word(index) .. word(7) .. word(50) .. word(12) .. word(30) .. word(9)
end
local function mesh(id, slots, indices)
    local data = string.rep('\0', 128)
    data = replace(data, 40, word(id))
    data = replace(data, 56, word(4294967295))
    data = replace(data, 104, word(#slots) .. word(128))
    data = replace(data, 120, word(#indices) .. word(128 + #slots * 4))
    for _, slot in ipairs(slots) do
        data = data .. word(slot)
    end
    for _, index in ipairs(indices) do
        data = data .. draw(index)
    end
    return data
end
local a, b, fallback = 0x0bf81d82, 0xa838f8a6, 0x093fc934
local ma, mb = 'a781f50f508ed81b', '79006f535c1b73c7'
local first = mesh(0x11111111, { a, b }, { 1, 0, 1 })
local second = mesh(0x22222222, { b, a, fallback }, { 0, 1, 2 })
local first_at, second_at = 148, 148 + #first
local material_at = second_at + #second
local main = string.rep('\0', 128)
main = replace(main, 44, word(10800438))
main = replace(main, 100, word(128))
main = replace(main, 112, word(material_at))
main = main
    .. word(2)
    .. word(first_at - 128)
    .. word(second_at - 128)
    .. word(0x11111111)
    .. word(0x22222222)
    .. first
    .. second
    .. word(2)
    .. word(a)
    .. word(b)
    .. hash(ma)
    .. hash(mb)
local layout = L.parse(main)
assert(layout.supported and not layout.unsupported and layout.composite == '0000000000000000')
assert(layout.materials_offset == material_at and #layout.sections == 2 and #layout.meshes == 2)
assert(layout.sections[1].section == a and layout.sections[1].material == ma)
assert(layout.sections[1].section_offset == material_at + 4)
assert(layout.sections[1].material_offset == material_at + 12)
assert(layout.meshes[1].id == 0x11111111 and layout.meshes[1].index == 0 and layout.meshes[1].lod == -1)
assert(layout.meshes[1].offset == first_at and layout.meshes[1].offset_field == 132)
assert(layout.meshes[1].material_slots[1].index == 0)
assert(layout.meshes[1].material_slots[1].offset == first_at + 128)
assert(layout.meshes[1].material_slots[1].section == a and layout.meshes[1].material_slots[1].material == ma)
assert(layout.meshes[2].material_slots[1].section == b and layout.meshes[2].material_slots[2].section == a)
assert(not layout.meshes[2].material_slots[3].mapped and not layout.meshes[2].material_slots[3].material)
assert(layout.meshes[1].draw_sections[1].section == b)
assert(layout.meshes[1].draw_sections[1].vertex_count == 50)
assert(layout.meshes[1].draw_sections[1].index_count == 30)
assert(layout.meshes[1].draw_sections[1].group_index == 9)
assert(layout.meshes[1].draw_sections[1].offset == first_at + 136)
local changed = replace(main, layout.meshes[2].material_slots[1].offset, word(0x12345678))
assert(main:sub(1, second_at + 128) == changed:sub(1, second_at + 128))
assert(main:sub(second_at + 133) == changed:sub(second_at + 133))
local composite = L.parse(replace(main, 16, hash('c6a69260cc389bcd')))
assert(not composite.supported and composite.unsupported == 'composite_geometry' and #composite.meshes == 0)
assert(composite.composite == 'c6a69260cc389bcd' and composite.sections[1].material == ma)
assert(L.parse(replace(main, 44, word(10800437))).supported)
local function refuses(bytes, message)
    local ok, why = pcall(L.parse, bytes)
    assert(not ok and tostring(why):find(message, 1, true), 'Expected refusal: ' .. message .. ' / ' .. tostring(why))
end
refuses(nil, 'Invalid Unit main part')
refuses(main:sub(1, 127), 'Invalid Unit main part')
refuses(string.rep('\0', L.MAX_BYTES + 1), 'Invalid Unit main part')
refuses(replace(main, 44, word(1)), 'Unsupported Unit version')
refuses(replace(main, 112, word(100)), 'Invalid Unit materials offset')
refuses(main:sub(1, #main - 1), 'Truncated Unit materials table')
refuses(replace(main, material_at, word(65)), 'Unit material count exceeds its limit')
refuses(replace(main, material_at + 8, word(a)), 'Ambiguous Unit global SectionID')
refuses(replace(main, 100, word(100)), 'Invalid Unit mesh offset')
refuses(replace(main, 128, word(65)), 'Unit mesh count exceeds its limit')
refuses(replace(main, 132, word(4294967295)), 'Truncated Unit mesh record')
refuses(replace(main, first_at + 40, word(0)), 'Unit mesh hash table differs')
refuses(replace(replace(main, second_at + 40, word(0x11111111)), 144, word(0x11111111)), 'Ambiguous Unit mesh ID')
refuses(replace(main, 112, word(first_at)), 'Overlapping Unit mesh record')
refuses(replace(main, first_at + 104, word(65)), 'Unit mesh count exceeds its limit')
refuses(replace(main, first_at + 108, word(132)), 'Unsupported inline Unit mesh offsets')
refuses(replace(main, first_at + 124, word(128)), 'Unsupported inline Unit mesh offsets')
refuses(replace(main, first_at + 132, word(a)), 'Ambiguous Unit mesh material slot')
refuses(replace(main, first_at + 136, word(2)), 'Invalid Unit draw section material index')
refuses(replace(main, first_at + 120, word(256)), 'Truncated Unit mesh record')
print(
    'PASS bounded inline Unit layout: exact offsets, draw sections, reordered slots, fallback slots, composite refusal and malformed records'
)
