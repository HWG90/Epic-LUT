local ffi = require('ffi')
local Units = dofile('src/gear/unit_identity.lua')
local Materials = dofile('src/gear/material_identity.lua')
local unit, portrait = ffi.cast('void *', 492), ffi.cast('void *', 4000)
local mesh, other_mesh = ffi.cast('void *', 100000), ffi.cast('void *', 110000)
local material, other_material = ffi.cast('void *', 200000), ffi.cast('void *', 210000)
local identity = { player = 7, unit = 8, avatar = 9, avatar_index = 0, units_at = 65536 }
local alive, garments = true, { { unit = 123, type = 0, slot = 1, preview = false } }
local calls, present = {}, { m_body = true, m_gibs = true }
local material_handles = { m_body = material, m_gibs = other_material }
local mesh_handles = { mesh_body = mesh, mesh_gibs = other_mesh }
local mesh_count, runtime_mesh, material_changed, mesh_changed, on_material = 2, mesh, false, false, nil
local on_has_mesh
local has_seen = {}
local E = {
    Application = {
        worlds = function()
            return { 'game', 'portrait' }
        end,
    },
    World = {
        units = function(world)
            return world == 'game' and { unit } or { portrait }
        end,
    },
    Unit = {
        alive = function(value)
            assert(value == unit)
            return alive
        end,
        resource_name = function()
            error('Material helper unnecessarily read Unit resource_name', 0)
        end,
        num_meshes = function(value)
            assert(type(value) == 'cdata' and value == unit)
            calls[#calls + 1] = 'num_meshes'
            return mesh_count
        end,
        mesh = function(value, index)
            assert(type(value) == 'cdata' and value == unit, 'Native uint32 ref reached Unit.mesh')
            calls[#calls + 1] = 'mesh:' .. tostring(index)
            if type(index) == 'string' then
                return mesh_handles[index]
            end
            assert(index == 1)
            if mesh_changed and #calls > 2 then
                return other_mesh
            end
            return runtime_mesh
        end,
        has_mesh = function(value, name)
            assert(value == unit and type(name) == 'string')
            calls[#calls + 1] = 'has_mesh:' .. name
            if on_has_mesh then
                on_has_mesh()
            end
            return mesh_handles[name] ~= nil
        end,
    },
    Mesh = {
        has_material = function(value, name)
            assert(type(value) == 'cdata' and value == mesh and type(name) == 'string')
            calls[#calls + 1] = 'has_material:' .. name
            has_seen[name] = true
            return present[name] == true
        end,
        material = function(value, name)
            assert(value == mesh and has_seen[name] and present[name], 'Material was queried before has_material')
            has_seen[name] = nil
            calls[#calls + 1] = 'material:' .. name
            if on_material then
                on_material()
            end
            if material_changed and #calls > 6 then
                return other_material
            end
            return material_handles[name]
        end,
    },
}
local unit_identity = Units.new(E, {
    avatar = {
        resolve_live = function()
            return identity
        end,
        units = function(_, _, preview)
            assert(preview == nil)
            return garments
        end,
    },
})
local section_names = { [11] = 'm_body', [22] = 'm_gibs', [33] = 'm_alias' }
local mesh_names = { [99] = 'mesh_body', [88] = 'mesh_gibs' }
local deps = {
    unit_identity = unit_identity,
    section_name = function(section)
        return section_names[section]
    end,
    mesh_name = function(id)
        return mesh_names[id]
    end,
}
local helper = Materials.new(E, deps)
local binding = { unit = 123, mesh = 100000, material = 200000, mesh_index = 0 }
local candidates = { { section = 11, material = 'ABCDEF0123456789' }, { section = 22, material = '0000000000000022' } }
-- SDK ordering deliberately differs from the runtime index. Names/pointers,
-- never ordinal matching, select mesh99's material slot3 at byteoffset800.
local layout = {
    { id = 88, material_slots = { { section = 22, index = 0, offset = 700 } } },
    {
        id = 99,
        material_slots = { { section = 22, index = 0, offset = 780 }, { section = 11, index = 3, offset = 800 } },
    },
}
local function resolve(records, meshes)
    return helper.resolve(binding, records or candidates, identity, meshes)
end
local function refuse(fn, needle)
    calls, has_seen = {}, {}
    local ok, why = pcall(fn)
    assert(not ok and tostring(why):find(needle, 1, true), tostring(why))
end
local proof = resolve(nil, layout)
assert(proof.section == 11 and proof.material == 'abcdef0123456789' and proof.slot_name == 'm_body')
assert(proof.mesh_verified and proof.mesh_id == 99 and proof.material_slot == 3 and proof.material_slot_offset == 800)
assert(unit_identity.validate(proof.unit_receipt))
local partial = resolve()
assert(not partial.mesh_verified and not partial.mesh_id and partial.mesh_error:find('unavailable', 1, true))
local old_has_mesh = E.Unit.has_mesh
E.Unit.has_mesh = nil
partial = resolve(nil, layout)
assert(not partial.mesh_verified and not partial.material_slot)
E.Unit.has_mesh = old_has_mesh
mesh_names[88] = nil
partial = resolve(nil, layout)
assert(not partial.mesh_verified and partial.mesh_error:find('literal mesh name', 1, true))
mesh_names[88] = 'mesh_gibs'

binding.mesh_index = nil
refuse(resolve, 'runtime mesh index unavailable')
assert(#calls == 0)
binding.mesh_index = 0
binding.mesh = 1
refuse(resolve, 'Invalid native Mesh pointer')
assert(#calls == 0)
binding.mesh = 100000
binding.unit = 250
refuse(resolve, 'not a current local garment')
assert(#calls == 0)
binding.unit = 123
alive = false
refuse(resolve, 'Unit disappeared')
assert(#calls == 0)
alive = true
section_names[11] = nil
refuse(resolve, 'literal material slot name unavailable')
assert(#calls == 0)
section_names[11] = '#ID[0000000b]'
refuse(resolve, 'literal material slot name unavailable')
assert(#calls == 0)
section_names[11] = 'm_body'
refuse(function()
    resolve({ candidates[1], candidates[1] })
end, 'Ambiguous serialized material SectionID')
assert(#calls == 0)
mesh_count = 0
refuse(resolve, 'Runtime mesh index is out of bounds')
assert(#calls == 1 and calls[1] == 'num_meshes')
mesh_count = 2
runtime_mesh = other_mesh
refuse(resolve, 'Lua Mesh handle differs')
assert(#calls == 2)
runtime_mesh = 100000
refuse(resolve, 'Lua Mesh handle differs')
assert(#calls == 2, 'Numeric Mesh handle reached Mesh APIs')
runtime_mesh = mesh
present.m_body = false
refuse(resolve, 'No verified material slot matches')
for _, name in ipairs(calls) do
    assert(name ~= 'material:m_body')
end
present.m_body = true
material_handles.m_body = 200000
refuse(resolve, 'Lua Material handle')
material_handles.m_body = material
material_handles.m_body = other_material
refuse(resolve, 'No verified material slot matches')
material_handles.m_body = material
present.m_alias, material_handles.m_alias = true, material
refuse(function()
    resolve({ candidates[1], { section = 33, material = '0000000000000033' } })
end, 'Ambiguous named material pointer proof')
present.m_alias, material_handles.m_alias = nil, nil

mesh_changed = true
refuse(resolve, 'Runtime Mesh handle changed')
mesh_changed = false
material_changed = true
refuse(resolve, 'Runtime Material handle changed')
material_changed = false
on_material = function()
    garments = {}
end
refuse(resolve, 'not a current local garment')
on_material = nil
garments = { { unit = 123, type = 0, slot = 1, preview = false } }
mesh_handles.mesh_gibs = mesh
refuse(function()
    resolve(nil, layout)
end, 'Ambiguous named mesh pointer proof')
mesh_handles.mesh_gibs = other_mesh
on_has_mesh = function()
    material_handles.m_body = other_material
end
refuse(function()
    resolve(nil, layout)
end, 'Runtime Material handle changed')
on_has_mesh, material_handles.m_body = nil, material
refuse(function()
    resolve(nil, { layout[1], layout[1] })
end, 'Ambiguous serialized MeshName ID')
local old_slot = layout[2].material_slots[2]
layout[2].material_slots[2] = { section = 11, index = 0, offset = 800 }
refuse(function()
    resolve(nil, layout)
end, 'Invalid serialized material slot locator')
layout[2].material_slots[2] = old_slot
layout[2].material_slots[3] = { section = 11, index = 4, offset = 804 }
partial = resolve(nil, layout)
assert(not partial.mesh_verified and partial.mesh_error:find('Repeated material SectionID', 1, true))
layout[2].material_slots[3] = nil
local old_material = E.Mesh.material
E.Mesh.material = nil
refuse(function()
    Materials.new(E, deps)
end, 'identity APIs unavailable')
E.Mesh.material = old_material
print(
    'PASS named material identity: genuine local Unit/Mesh/Material handles, has-before-get, exact named SectionID proof, optional named SDK mesh/slot proof without ordinal guesses, bounded/stale/ambiguous refusal; no ResourceManager calls'
)
