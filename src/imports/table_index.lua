-- Cooperative DDS indexing. One document per resume; callers own cancellation.
local I = {}
function I.new(deps)
    local self = {}
    function self.start(paths, documents, resources)
        -- A snapshot prevents later source selection from changing this job's input.
        local queue = {}
        for i, path in ipairs(paths) do
            queue[i] = path
        end
        return coroutine.create(function()
            for _, path in ipairs(queue) do
                if not documents[path] then
                    local bytes = deps.read(path, deps.max_bytes)
                    local data, width, height = deps.decode(bytes)
                    if width == 23 or (width == 3 and height == 1) then
                        documents[path] =
                            { data = data, width = width, height = height, source = path, resource = resources[path] }
                    end
                    coroutine.yield()
                end
            end
        end)
    end
    return self
end
return I
