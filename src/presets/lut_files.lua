-- Validated named DDS files. UI and gear state are deliberately outside this service.
local L = {}
function L.new(folder, deps)
    local self = {}
    local function path(name, prefix)
        assert(folder and type(name) == 'string' and #name > 0 and name:match('^[%w _-]+$'), 'Invalid DDS preset name')
        return folder .. '/' .. (prefix or '') .. name .. '.dds'
    end
    function self.exists(name)
        local f = io.open(path(name), 'rb')
        if not f then
            return false
        end
        f:close()
        return true
    end
    function self.save(name, document, prefix)
        return deps.dds.write(path(name, prefix), document.data, document.width, document.height)
    end
    function self.save_row(name, document, row)
        assert(type(row) == 'number' and row % 1 == 0 and row >= 1 and row <= document.height, 'Invalid preset row')
        return deps.dds.write(path(name, 'row-'), document.data + (row - 1) * document.width * 4, document.width, 1)
    end
    function self.load_row(name)
        local bytes = deps.read(path(name, 'row-'), deps.dds.MAX_BYTES)
        return deps.dds.decode(bytes, 23, 1)
    end
    function self.row_names()
        return deps.row_names and deps.row_names(folder) or {}
    end
    return self
end
return L
