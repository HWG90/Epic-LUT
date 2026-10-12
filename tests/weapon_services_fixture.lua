local ffi = require('ffi')
local Mapping = dofile('src/editor/weapon_mapping.lua')
local F = {}
function F.document(width, height, value, resource)
    local document =
        { width = width, height = height, data = ffi.new('float[?]', width * height * 4), resource = resource }
    document.data[0], document.data[3] = value or 0, -0.375
    ffi.cast('uint32_t *', document.data)[1] = 0x80000000
    return document
end
function F.new()
    local self = {
        groups = {},
        imports = {},
        documents = {},
        menu = {},
        calls = 0,
        config = {
            '5fecab819f96a3e8',
            '1111111111111111',
            '2222222222222222',
        },
    }
    local catalogs, actual = {}, {}
    function self.group(slot, family, index, texture, value, count)
        catalogs[slot] = catalogs[slot] or { material = {}, pattern = {} }
        local group = {
            kind = 'weapon',
            weapon = true,
            weapon_slot = slot,
            family = family,
            index = index,
            weapon_resource = self.config[slot],
            source_resource = texture,
            object = 50000 + #self.groups,
            source_document = F.document(
                family == 'pattern' and 3 or 23,
                family == 'pattern' and 1 or 8,
                value,
                texture
            ),
            bindings = {},
        }
        group.width, group.height = group.source_document.width, group.source_document.height
        for member = 1, count or 1 do
            local mesh = (index - 1) * 4 + member - 1
            local b = {
                kind = 'weapon',
                unit = 1000 + slot,
                mesh = 100000 + slot * 1000 + mesh,
                material = 200000 + slot * 1000 + mesh,
                slot = family == 'pattern' and 0x81d4c49d or 0x7e662968,
                save_key = '3:' .. slot .. ':' .. mesh .. ':0',
                original = group.object,
                current = group.object,
                weapon_slot = slot,
                weapon_resource = self.config[slot],
                mesh_index = mesh,
                material_index = 0,
            }
            actual[b], group.bindings[#group.bindings + 1] = b.current, b
        end
        self.groups[#self.groups + 1], catalogs[slot][family][index] = group, group
        return group
    end
    function self.import(path, document)
        self.imports[#self.imports + 1], self.documents[path] = path, document
    end
    local runtime = { supports_target_subsets = true }
    function runtime.target(slot, index, family)
        local group = assert(catalogs[slot] and catalogs[slot][family][index])
        for _, b in ipairs(group.bindings) do
            assert(actual[b] == b.current, 'Foreign live binding')
        end
        return group
    end
    function runtime.load(slot, index, family)
        local group = runtime.target(slot, index, family)
        return group.source_document, group
    end
    function runtime.apply_plan(plan)
        self.calls = self.calls + 1
        self.plan = plan
        if self.fail then
            error('Injected atomic application refusal')
        end
        local results = {}
        for _, entry in ipairs(plan) do
            local group = runtime.target(entry.weapon_slot, entry.index, entry.family)
            assert(entry.weapon_resource == group.weapon_resource and entry.source_resource == group.source_resource)
            assert(entry.document.width == group.width and entry.document.height == group.height)
            for _, b in ipairs(entry.targets or group.bindings) do
                local found = false
                for _, candidate in ipairs(group.bindings) do
                    found = found or candidate == b
                end
                assert(found)
            end
        end
        for _, entry in ipairs(plan) do
            local group = runtime.target(entry.weapon_slot, entry.index, entry.family)
            for _, b in ipairs(entry.targets or group.bindings) do
                b.current, b.document = b.current + 100, Mapping.copy(entry.document)
                actual[b] = b.current
            end
            results[#results + 1] = { count = #(entry.targets or group.bindings) }
        end
        return results
    end
    self.runtime = runtime
    self.host = {
        runtime = runtime,
        menu = function()
            return self.menu
        end,
        imports = {
            palettes = function()
                return self.imports
            end,
            document = function(path)
                return self.documents[path]
            end,
            resource = function(_, document)
                return document.resource
            end,
            pending = function()
                return self.pending == true
            end,
            indexing = function()
                return self.indexing == true
            end,
        },
        groups = function()
            return self.groups
        end,
    }
    function self.set_document(b, document)
        b.document, b.current = document, b.current + 100
        actual[b] = b.current
    end
    function self.foreign(b)
        actual[b] = b.current + 500
    end
    return self
end
return F
