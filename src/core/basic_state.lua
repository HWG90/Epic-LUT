-- Independent editor copies, keyed by target and original resource object.
local B = {}
local ffi = require('ffi')
local weapon_metadata =
    { 'kind', 'family', 'weapon_slot', 'weapon_resource', 'weapon_resource64', 'source_resource', 'mixed' }
function B.clone(source, label, skip_binding_documents, seen)
    seen = seen or {}
    if seen[source] then
        return seen[source]
    end
    local data = ffi.new('float[?]', source.width * source.height * 4)
    ffi.copy(data, source.data, source.width * source.height * 16)
    local result =
        { data = data, width = source.width, height = source.height, source = label or source.source, revision = 0 }
    seen[source] = result
    if source.kind == 'weapon' then
        for _, field in ipairs(weapon_metadata) do
            result[field] = source[field]
        end
        if source.binding_documents and not skip_binding_documents then
            result.binding_documents = {}
            for key, document in pairs(source.binding_documents) do
                result.binding_documents[key] = B.clone(document, nil, false, seen)
            end
        end
    end
    return result
end
-- History copies preserve metadata and original pixels; normal edit copies start a new revision.
function B.copier()
    local copies = {}
    local self = { bytes = 0 }
    function self.copy(source)
        if not source then
            return nil
        end
        if copies[source] then
            return copies[source]
        end
        local copy = B.clone(source, source.source, true)
        copies[source] = copy
        copy.revision = source.revision
        copy.saved_pixels = source.saved_pixels
        copy.resource = source.resource
        copy.resource_object = source.resource_object
        local bytes = source.width * source.height * 16
        if source.original then
            copy.original = ffi.new('float[?]', source.width * source.height * 4)
            ffi.copy(copy.original, source.original, bytes)
            self.bytes = self.bytes + bytes
        end
        if source.kind == 'weapon' and source.binding_documents then
            copy.binding_documents = {}
            for key, document in pairs(source.binding_documents) do
                copy.binding_documents[key] = self.copy(document)
            end
        end
        self.bytes = self.bytes + bytes
        return copy
    end
    return self
end
function B.copy(destination, source)
    assert(destination.width == source.width, 'Palette columns differ')
    local rows = math.min(destination.height, source.height)
    ffi.copy(destination.data, source.data, rows * destination.width * 16)
    destination.revision = (destination.revision or 0) + 1
    return rows
end
function B.new()
    local self = { documents = {}, camo = {} }
    function self.get(key, source, label)
        if not self.documents[key] and source then
            self.documents[key] = B.clone(source, label)
        end
        return self.documents[key]
    end
    function self.camo_rows(key, document, kind, proof)
        if
            not key
            or not document
            or document.width ~= 23
            or document.height < 1
            or document.height > 64
            or document.stale
            or document.read_only
        then
            return nil, 0
        end
        local scope = self.camo[key]
        if
            not scope
            or scope.height ~= document.height
            or scope.kind ~= kind
            or (proof and scope.proof and proof ~= scope.proof)
        then
            scope = { rows = {}, height = document.height, kind = kind, proof = proof }
            for row = 1, document.height do
                scope.rows[row] = false
            end
            self.camo[key] = scope
        elseif proof then
            scope.proof = proof
        end
        local count = 0
        for row = 1, document.height do
            if scope.rows[row] then
                count = count + 1
            end
        end
        return scope.rows, count
    end
    function self.clear(keep_camo)
        for key in pairs(self.documents) do
            self.documents[key] = nil
        end
        if not keep_camo then
            self.camo = {}
        end
    end
    return self
end
return B
