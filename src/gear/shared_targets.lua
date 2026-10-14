-- Stable native destination receipts for remote garment LUTs. Bound textures are
-- deliberately excluded: our own upload must not look like a new destination.
local T = {}
function T.garments(units, appearance, materials, binding, material_key, lut_slot, pattern_slot)
    local targets, marks, seen = {}, {}, {}
    for _, unit in ipairs(units) do
        marks[#marks + 1] = 'u:' .. tostring(unit.unit)
        for i, material in ipairs(materials(unit.unit)) do
            local key = (unit.type or 0)
                .. ':'
                .. unit.slot
                .. ':'
                .. (material.mesh_index or 0)
                .. ':'
                .. (material.material_index or i - 1)
            for _, pattern in ipairs({ false, true }) do
                local entry = appearance.entries[(pattern and 'p:' or '') .. key]
                if entry then
                    local b = {
                        unit = unit.unit,
                        mesh = material.mesh,
                        material = material.material,
                        slot = pattern and pattern_slot or lut_slot,
                    }
                    local bound = binding(b)
                    local tag = material_key(b) .. ':' .. b.slot
                    if bound and bound ~= 0 and not seen[tag] then
                        seen[tag] = true
                        b.original, b.current = bound, bound
                        marks[#marks + 1] = 'b:'
                            .. tag
                            .. ':'
                            .. tostring(b.unit)
                            .. ':'
                            .. tostring(b.mesh)
                            .. ':'
                            .. tostring(b.material)
                        local document = entry.document
                        targets[document] = targets[document] or {}
                        targets[document][#targets[document] + 1] = b
                    end
                end
            end
        end
    end
    table.sort(marks)
    return targets, table.concat(marks, '|')
end
return T
