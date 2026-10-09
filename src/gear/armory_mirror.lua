-- Mirrors only applied tables onto this player's matching Armory actor. Never thumbnails or other kits.
local A = {}
function A.new(deps)
    local ffi = require('ffi')
    local self = { age = 0 }
    local watch, where, slot, signature
    local session = deps.session()
    local function restore()
        if not session.restore() then
            return false
        end
        signature = nil
        return true
    end
    function self.tick(dt)
        self.age = self.age + math.max(0, dt or 0)
        if self.age < 0.1 then
            return
        end
        self.age = 0
        local identity = deps.identity()
        if not identity then
            restore()
            return
        end
        if not where or slot ~= identity.ui_slot then
            if not restore() then
                return
            end
            slot = identity.ui_slot
            where = deps.locate(identity.ui_slot)
            watch = where and deps.watch(where)
        end
        if not watch or watch.poll() == 'absent' then
            restore()
            where, watch = nil, nil
            return
        end
        local helmet, armor, body = watch.kits()
        if body ~= identity.body then
            restore()
            return
        end
        local allowed = { armor = armor == identity.armor, helmet = helmet == identity.helmet }
        local entries = deps.entries()
        local parts = { tostring(helmet), tostring(armor), tostring(body) }
        local units = deps.units(where)
        for _, u in ipairs(units) do
            parts[#parts + 1] = u.unit
        end
        for key, entry in pairs(entries) do
            local kind = entry.helmet and 'helmet' or 'armor'
            if allowed[kind] then
                parts[#parts + 1] = key
                    .. ':'
                    .. ffi.string(entry.document.data, entry.document.width * entry.document.height * 16)
            end
        end
        table.sort(parts, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local next_signature = table.concat(parts, '|')
        if next_signature == signature then
            return
        end
        if not restore() then
            return
        end
        local batches = {}
        for _, u in ipairs(units) do
            local kind = u.slot == 0 and 'helmet' or 'armor'
            if allowed[kind] then
                for i, material in ipairs(deps.materials(u.unit)) do
                    local key = (u.type or 0)
                        .. ':'
                        .. u.slot
                        .. ':'
                        .. (material.mesh_index or 0)
                        .. ':'
                        .. (material.material_index or i - 1)
                    for _, pattern in ipairs({ false, true }) do
                        local entry = entries[(pattern and 'p:' or '') .. key]
                        if entry and not deps.is_cape(material) then
                            local b = {
                                unit = u.unit,
                                mesh = material.mesh,
                                material = material.material,
                                slot = deps.slot(pattern),
                            }
                            local original = deps.binding(b)
                            if original and original ~= 0 then
                                b.original, b.current = original, original
                                local doc = entry.document
                                batches[doc] = batches[doc] or {}
                                batches[doc][#batches[doc] + 1] = b
                            end
                        end
                    end
                end
            end
        end
        for doc, targets in pairs(batches) do
            session.apply(doc, targets)
        end
        signature = next_signature
    end
    function self.close()
        return restore()
    end
    return self
end
return A
