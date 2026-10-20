-- Validated named DDS files. UI and gear state are deliberately outside this service.
local L = {}
-- Shared suffix formatting keeps exact IDs out of the user-name truncation budget.
function L.naming_suffix(document, original, naming, label, ids, ordinal)
    naming = naming or 1
    assert(type(naming) == 'number' and naming % 1 == 0 and naming >= 1 and naming <= 6, 'Choose an export naming format')
    if naming == 6 then return '' end
    local resource = original and original.resource or document.resource
    local display = label or ((document.width == 3 and document.height == 1 and 'PatternLUT' or 'LUT') .. tostring(ordinal or 1))
    display = display:gsub('[^%w _()%-]', '_'):sub(1, 64)
    local id = resource
    if id then
        assert(type(id) == 'string' and #id == 16 and id:match('^%x+$'), 'Invalid LUT resource ID')
        id = id:lower()
        if naming == 2 or naming == 5 then id = assert(ids.format(id, true):match('^%[(%d+)%]$')) end
    end
    if naming == 1 or naming == 2 then return ' ' .. display .. (id and '-' .. id or '') end
    if naming == 3 then return ' ' .. display end
    return ' ' .. (id or display)
end
function L.available_name(name, exists, suffix)
    assert(
        type(name) == 'string'
            and #name > 0
            and #name <= 48
            and name:match('^[%w _()%-]+$')
            and not name:match('^%s')
            and not name:match('%s$'),
        'Invalid export name'
    )
    suffix = suffix or ''
    assert(type(suffix) == 'string' and #suffix <= 120 and not suffix:find('[^%w _()%-]'), 'Invalid export suffix')
    local stamp = suffix .. '-' .. os.date('%Y-%m-%d_%H-%M-%S')
    local candidate = name:sub(1, math.max(1, 48 - (#stamp - #suffix))):gsub('%s+$', '') .. stamp
    if not exists(candidate) then
        return candidate
    end
    for i = 1, 10000 do
        local numbered = stamp .. '-' .. string.format('%02d', i)
        candidate = name:sub(1, math.max(1, 48 - (#numbered - #suffix))):gsub('%s+$', '') .. numbered
        if not exists(candidate) then
            return candidate
        end
    end
    error('Too many exports with this name')
end
function L.new(folder, deps)
    local open_file = deps.open or (m and m.file_io and m.file_io.open) or io.open
    local self = {}
    local function path(name, prefix)
        assert(
            folder and type(name) == 'string' and #name > 0 and name:match('^[%w _()%-]+$'),
            'Invalid DDS preset name'
        )
        return folder .. '/' .. (prefix or '') .. name .. '.dds'
    end
    function self.exists(name, prefix)
        local f = open_file(path(name, prefix), 'rb')
        if not f then
            return false
        end
        f:close()
        return true
    end
    function self.save(name, document, prefix)
        return deps.dds.write(path(name, prefix), document.data, document.width, document.height)
    end
    function self.save_unique(name, document, suffix)
        local chosen = L.available_name(name, self.exists, suffix)
        self.save(chosen, document)
        return chosen
    end
    function self.save_row(name, document, row)
        assert(type(row) == 'number' and row % 1 == 0 and row >= 1 and row <= document.height, 'Invalid preset row')
        return deps.dds.write(path(name, 'row-'), document.data + (row - 1) * document.width * 4, document.width, 1)
    end
    function self.load_row(name)
        local bytes = deps.read(path(name, 'row-'), deps.dds.MAX_BYTES)
        return deps.dds.decode(bytes, 23, 1)
    end
    local function delete_named(name, prefix)
        local source = path(name, prefix)
        local function file_exists(filename)
            local file = open_file(filename, 'rb')
            if not file then
                return false
            end
            file:close()
            return true
        end
        local exists, move = deps.exists or file_exists, deps.move or (m and m.file_io and m.file_io.rename) or os.rename
        assert(exists(source), 'Saved preset not found')
        for index = 1, 10000 do
            local backup = source .. '.deleted' .. (index == 1 and '' or '-' .. index)
            if not exists(backup) then
                -- Windows rename refuses an existing destination, including a
                -- backup created after the existence check. Never overwrite it.
                local ok, why = move(source, backup)
                assert(ok, why or 'Could not delete saved preset')
                return backup
            end
        end
        error('Too many deleted preset backups with this name')
    end
    function self.delete_row(name)
        return delete_named(name, 'row-')
    end
    function self.delete_palette(name)
        return delete_named(name, 'palette-')
    end
    function self.row_names()
        return deps.row_names and deps.row_names(folder) or {}
    end
    return self
end
return L
