-- Read-only named material identity on a verified local Lua Unit handle.
-- Literal names come from a hash-verified catalog, never a guessed ordinal.
local M = { MAX_SECTIONS = 64, MAX_MESHES = 512, MAX_SLOTS = 64 }
local function integer(value, limit)
    return type(value) == 'number' and value % 1 == 0 and value >= 0 and value <= limit
end
local function literal(value)
    return type(value) == 'string'
        and #value > 0
        and #value <= 192
        and not value:find('%z')
        and not value:find('^#ID%[')
end
function M.new(E, deps)
    local ffi = require('ffi')
    local U, Mesh = E.Unit, E.Mesh
    assert(
        U
            and Mesh
            and type(U.num_meshes) == 'function'
            and type(U.mesh) == 'function'
            and type(Mesh.has_material) == 'function'
            and type(Mesh.material) == 'function'
            and deps.unit_identity
            and type(deps.unit_identity.handle) == 'function'
            and type(deps.unit_identity.validate) == 'function'
            and type(deps.section_name) == 'function',
        'Named Lua material identity APIs unavailable'
    )
    local self = {}
    local function pointer(handle)
        local kind = type(handle)
        if kind ~= 'userdata' and kind ~= 'cdata' then
            return nil
        end
        if kind == 'cdata' and not tostring(ffi.typeof(handle)):match('%*%s*>$') then
            return nil
        end
        local ok, value = pcall(function()
            return tonumber(ffi.cast('uintptr_t', handle))
        end)
        return ok and value and value % 1 == 0 and value >= 65536 and value < 2 ^ 47 and value or nil
    end
    local function target(value, name)
        assert(integer(value, 2 ^ 47 - 1) and value >= 65536, 'Invalid native ' .. name .. ' pointer')
        return value
    end
    local function named_mesh(unit, receipt, binding, meshes)
        if not meshes or not deps.mesh_name or type(U.has_mesh) ~= 'function' then
            return nil, 'Verified named mesh layout/API unavailable'
        end
        assert(type(meshes) == 'table' and #meshes <= M.MAX_MESHES, 'Serialized mesh layout bounds changed')
        local names, seen = {}, {}
        for _, record in ipairs(meshes) do
            assert(integer(record.id, 0xffffffff) and not seen[record.id], 'Ambiguous serialized MeshName ID')
            seen[record.id] = true
            local name = deps.mesh_name(record.id)
            if literal(name) then
                names[#names + 1] = { record = record, name = name }
            end
        end
        local selected
        for _, entry in ipairs(names) do
            deps.unit_identity.validate(receipt)
            if U.has_mesh(unit, entry.name) == true then
                local named = U.mesh(unit, entry.name)
                assert(pointer(named), 'Named mesh did not return a Lua Mesh handle')
                if pointer(named) == binding.mesh then
                    assert(not selected, 'Ambiguous named mesh pointer proof')
                    selected = entry.record
                end
            end
        end
        if not selected then
            return nil, 'No verified literal mesh name matches the native binding'
        end
        return selected
    end
    local function mesh_proof(unit, receipt, binding, match, meshes)
        local selected, why = named_mesh(unit, receipt, binding, meshes)
        if not selected then
            return nil, why
        end
        local slots = selected.material_slots
        assert(type(slots) == 'table' and #slots <= M.MAX_SLOTS, 'Serialized material slot bounds changed')
        local slot, seen_slots = nil, {}
        for _, entry in ipairs(slots) do
            assert(
                integer(entry.section, 0xffffffff)
                    and integer(entry.index, M.MAX_SLOTS - 1)
                    and integer(entry.offset, 8 * 1024 * 1024 - 4)
                    and not seen_slots[entry.index],
                'Invalid serialized material slot locator'
            )
            seen_slots[entry.index] = true
            if entry.section == match.section then
                if slot then
                    return nil, 'Repeated material SectionID within the named mesh'
                end
                slot = entry
            end
        end
        if not slot then
            return nil, 'Named mesh does not carry the selected material SectionID'
        end
        return { id = selected.id, index = slot.index, offset = slot.offset }
    end
    function self.resolve(binding, candidates, expected, meshes)
        assert(
            type(binding) == 'table' and integer(binding.mesh_index, M.MAX_MESHES - 1),
            'Verified runtime mesh index unavailable'
        )
        target(binding.mesh, 'Mesh')
        target(binding.material, 'Material')
        assert(
            type(candidates) == 'table' and #candidates >= 1 and #candidates <= M.MAX_SECTIONS,
            'Serialized material section bounds changed'
        )
        local named, seen = {}, {}
        for _, candidate in ipairs(candidates) do
            assert(
                integer(candidate.section, 0xffffffff) and not seen[candidate.section],
                'Ambiguous serialized material SectionID'
            )
            assert(
                type(candidate.material) == 'string'
                    and #candidate.material == 16
                    and candidate.material:match('^%x+$')
                    and candidate.material ~= '0000000000000000',
                'Invalid serialized Material resource ID'
            )
            seen[candidate.section] = true
            local name = deps.section_name(candidate.section)
            if literal(name) then
                named[#named + 1] = { section = candidate.section, material = candidate.material:lower(), name = name }
            end
        end
        local unit, receipt = deps.unit_identity.handle(binding.unit, expected)
        deps.unit_identity.validate(receipt)
        local count = U.num_meshes(unit)
        assert(integer(count, M.MAX_MESHES) and binding.mesh_index < count, 'Runtime mesh index is out of bounds')
        -- This runtime index finds a handle only. It never selects a serialized
        -- mesh record or material-table slot.
        local mesh = U.mesh(unit, binding.mesh_index + 1)
        assert(pointer(mesh) == binding.mesh, 'Lua Mesh handle differs from the native binding')
        local match
        for _, candidate in ipairs(named) do
            deps.unit_identity.validate(receipt)
            if Mesh.has_material(mesh, candidate.name) == true then
                local material = Mesh.material(mesh, candidate.name)
                assert(pointer(material), 'Named material did not return a Lua Material handle')
                if pointer(material) == binding.material then
                    assert(not match, 'Ambiguous named material pointer proof')
                    match = candidate
                end
            end
        end
        if not match and type(deps.single_material) == 'function' then
            local selected = named_mesh(unit, receipt, binding, meshes)
            local slots = selected and selected.material_slots
            -- Two singleton sets have one possible correspondence. The exact
            -- named mesh identity still comes from Lua handles, never indices.
            if
                type(slots) == 'table'
                and #slots == 1
                and slots[1].mapped == true
                and slots[1].index == 0
                and not literal(deps.section_name(slots[1].section))
            then
                local slot = slots[1]
                for _, candidate in ipairs(candidates) do
                    if candidate.section == slot.section and candidate.material:lower() == slot.material then
                        deps.unit_identity.validate(receipt)
                        if deps.single_material(binding) == true then
                            match =
                                { section = candidate.section, material = candidate.material:lower(), singleton = true }
                        end
                        deps.unit_identity.validate(receipt)
                    end
                end
            end
        end
        assert(
            match,
            'No verified material slot matches the native binding; selected literal material slot name unavailable'
        )
        local specific, why = mesh_proof(unit, receipt, binding, match, meshes)
        deps.unit_identity.validate(receipt)
        assert(pointer(U.mesh(unit, binding.mesh_index + 1)) == binding.mesh, 'Runtime Mesh handle changed')
        if match.singleton then
            assert(specific and deps.single_material(binding) == true, 'Runtime sole Material count/handle changed')
        else
            assert(
                Mesh.has_material(mesh, match.name) == true
                    and pointer(Mesh.material(mesh, match.name)) == binding.material,
                'Runtime Material handle changed'
            )
        end
        deps.unit_identity.validate(receipt)
        return {
            section = match.section,
            material = match.material,
            slot_name = match.name,
            singleton = match.singleton == true,
            unit_receipt = receipt,
            mesh_index = binding.mesh_index,
            mesh_verified = specific ~= nil,
            mesh_error = why,
            mesh_id = specific and specific.id or nil,
            material_slot = specific and specific.index or nil,
            material_slot_offset = specific and specific.offset or nil,
        }
    end
    return self
end
return M
