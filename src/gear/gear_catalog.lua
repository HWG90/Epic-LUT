-- Local gear discovery and pure application scopes. No UI or texture writes.
local G = {}
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
            for vi, v in ipairs(deps.materials(u.unit)) do
                local b = { unit = u.unit, mesh = v.mesh, material = v.material }
                local existing = kept[deps.key(b)]
                local object = existing and existing.original or deps.binding(b)
                if object and object ~= 0 then
                    local key = v.material .. ':' .. v.mesh
                    if not seen[key] then
                        local group = found[object]
                        if not group then
                            group = { object = object, bindings = {}, helmet = false, armor = false }
                            found[object] = group
                        end
                        if u.slot == 0 then
                            group.helmet = true
                        else
                            group.armor = true
                        end
                        b = existing or b
                        b.original = object
                        b.current = existing and existing.current or object
                        b.helmet = u.slot == 0
                        b.armor = not b.helmet
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
            local target = g.helmet and (g.armor and 'Shared Armor / Helmet' or 'Helmet') or 'Armor'
            labels[i] = target .. ' LUT ' .. i
        end
        local selected = 1
        for i, g in ipairs(groups) do
            if g.object == previous_object then
                selected = i
                break
            end
        end
        return { groups = groups, owned = owned, labels = labels, selected = selected }
    end
    return self
end
function G.targets(groups, scope, selected, kind, basic_kind)
    local targets = {}
    for index, group in ipairs(groups) do
        if
            scope == 4
            or (scope == 2 and group.armor)
            or (scope == 3 and group.helmet)
            or (scope == 1 and index == selected)
        then
            for _, binding in ipairs(group.bindings) do
                local in_scope = scope == 1
                    or scope == 4
                    or (scope == 2 and binding.armor)
                    or (scope == 3 and binding.helmet)
                if
                    in_scope
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
