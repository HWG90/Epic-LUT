-- Independent editor copies, keyed by target and original resource object.
local B = {}
local ffi = require('ffi')
function B.clone(source, label)
    local data = ffi.new('float[?]', source.width * source.height * 4)
    ffi.copy(data, source.data, source.width * source.height * 16)
    return { data = data, width = source.width, height = source.height, source = label or source.source, revision = 0 }
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
        local copy = B.clone(source, source.source)
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
        copies[source] = copy
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
