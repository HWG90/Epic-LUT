-- Local gear discovery and pure application scopes. No UI or texture writes.
local G = {}
function G.kind(binding)
    return binding.cape and 'cape' or binding.helmet and 'helmet' or 'armor'
end
function G.label(kind)
    return kind == 'cape' and 'Cape material' or kind == 'armor' and 'Armor' or 'Helmet'
end
function G.new(deps)
    local self = {}
    function self.refresh(owned, previous_object)
        local identity, why = deps.identity()
        assert(identity, why)
        local found, seen, kept, active = {}, {}, {}, {}
        for _, b in ipairs(owned) do
            if deps.present(b) and deps.binding(b) == b.current then
                kept[deps.key(b)] = b
                active[#active + 1] = b
            end
        end
        owned = active
        for _, u in ipairs(deps.units(identity)) do
            local unit_name = deps.resource_name and deps.resource_name(u.unit)
            for vi, v in ipairs(deps.materials(u.unit)) do
                local b = { unit = u.unit, mesh = v.mesh, material = v.material }
                local existing = kept[deps.key(b)]
                local object = existing and existing.original or deps.binding(b)
                if object and object ~= 0 then
                    local key = v.material .. ':' .. v.mesh
                    if not seen[key] then
                        local group = found[object]
                        if not group then
                            group = { object = object, bindings = {}, helmet = false, armor = false, cape = false }
                            found[object] = group
                        end
                        local cape = deps.is_cape and deps.is_cape(b) or false
                        local kind = cape and 'cape' or u.slot == 0 and 'helmet' or 'armor'
                        group[kind] = true
                        b = existing or b
                        b.original = object
                        b.current = existing and existing.current or object
                        b.kind, b.cape = kind, cape
                        b.helmet, b.armor = kind == 'helmet', kind == 'armor'
                        b.resource_name = unit_name
                        b.save_key = (u.type or 0)
                            .. ':'
                            .. (u.slot or 0)
                            .. ':'
                            .. (v.mesh_index or 0)
                            .. ':'
                            .. (v.material_index or vi - 1)
                        group.bindings[#group.bindings + 1] = b
                        seen[key] = true
                    end
                end
            end
        end
        local groups = {}
        for _, group in pairs(found) do
            groups[#groups + 1] = group
        end
        table.sort(groups, function(a, b)
            return a.object < b.object
        end)
        assert(#groups > 0, 'No local live LUT bindings yet; refresh after loading the character')
        local labels = {}
        for i, g in ipairs(groups) do
            local kinds = {}
            for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
                if g[kind] then
                    kinds[#kinds + 1] = G.label(kind)
                end
            end
            local target = (#kinds > 1 and 'Shared ' or '') .. table.concat(kinds, ' / ')
            labels[i] = target .. ' LUT ' .. i
            local names = {}
            for _, b in ipairs(g.bindings) do
                if b.resource_name then
                    names[b.resource_name] = true
                end
            end
            local ordered = {}
            for name in pairs(names) do
                ordered[#ordered + 1] = name
            end
            table.sort(ordered)
            g.resource_names = ordered
            if #ordered == 1 then
                labels[i] = labels[i] .. ' / ' .. ordered[1]
            end
        end
        local selected = 1
        for i, g in ipairs(groups) do
            if g.object == previous_object then
                selected = i
                break
            end
        end
        local signature = {}
        for _, group in ipairs(groups) do
            for _, b in ipairs(group.bindings) do
                signature[#signature + 1] = tostring(group.object) .. ':' .. tostring(b.unit) .. ':' .. b.save_key
            end
        end
        return {
            groups = groups,
            owned = owned,
            labels = labels,
            selected = selected,
            signature = table.concat(signature, ';'),
        }
    end
    return self
end
function G.targets(groups, scope, selected, kind, basic_kind)
    local targets = {}
    for index, group in ipairs(groups) do
        if
            (scope == 4 and (group.armor or group.helmet))
            or (scope == 2 and group.armor)
            or (scope == 3 and group.helmet)
            or (scope == 1 and index == selected)
        then
            for _, binding in ipairs(group.bindings) do
                local in_scope = scope == 1
                    or (scope == 4 and (binding.armor or binding.helmet))
                    or (scope == 2 and binding.armor)
                    or (scope == 3 and binding.helmet)
                if
                    in_scope
                    and (kind == 'cape' or not binding.cape)
                    and (not kind or binding[kind])
                    and (scope ~= 1 or not basic_kind or binding[basic_kind])
                then
                    targets[#targets + 1] = binding
                end
            end
        end
    end
    return targets
end
return G
