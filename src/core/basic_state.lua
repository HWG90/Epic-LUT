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
    local self = { documents = {} }
    function self.get(key, source, label)
        if not self.documents[key] and source then
            self.documents[key] = B.clone(source, label)
        end
        return self.documents[key]
    end
    function self.clear()
        for key in pairs(self.documents) do
            self.documents[key] = nil
        end
    end
    return self
end
return B
