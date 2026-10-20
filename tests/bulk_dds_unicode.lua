-- Real preset -> bulk DDS exporter; display labels may be Unicode, preset names stay ASCII.
local function scoped(path, modules)
    return setfenv(assert(loadfile(path)), setmetatable({ m = modules }, { __index = _G }))()
end
local files, directories = {}, { ['exports-服装'] = true }
local opens, handles, closes, made, removed = 0, 0, 0, 0, 0
local refuse_rename = false
local platform = {}
function platform.open(path, mode)
    opens = opens + 1
    assert(directories[path:match('^(.*)/[^/]+$')], 'Missing owned parent directory')
    if mode == 'rb' and files[path] == nil then return nil, 'missing', 2 end
    assert(mode == 'rb' or mode == 'wb')
    if mode == 'wb' then files[path] = '' end
    handles = handles + 1
    local closed = false
    return {
        read = function(_, count) assert(not closed and mode == 'rb'); return files[path]:sub(1, count) end,
        write = function(self, bytes)
            assert(not closed and mode == 'wb'); files[path] = files[path] .. bytes; return self
        end,
        close = function() assert(not closed); closed = true; closes = closes + 1; return true end,
    }
end
function platform.rename(source, destination)
    if refuse_rename then return nil, 'refused publication' end
    assert(directories[source] and not directories[destination])
    local moved = {}
    for name, bytes in pairs(files) do
        if name:sub(1, #source + 1) == source .. '/' then moved[name] = bytes end
    end
    for name, bytes in pairs(moved) do files[destination .. name:sub(#source + 1)], files[name] = bytes, nil end
    directories[destination], directories[source] = true, nil
    return true
end
function platform.remove(path) assert(files[path]); files[path] = nil; removed = removed + 1; return true end
local paths = {
    exports = 'exports-服装', directory_exists = function(path) return directories[path] == true end,
    mkdir_new = function(path) assert(not directories[path]); directories[path] = true; made = made + 1 end,
    rmdir = function(path)
        for name in pairs(files) do assert(name:sub(1, #path + 1) ~= path .. '/', 'Removed a nonempty directory') end
        assert(directories[path]); directories[path] = nil; return true
    end,
}
local model = { platform = platform, float_buffer = require('src.core.float_buffer') }
model.file_io = scoped('src/core/file_io.lua', model)
model.dds = scoped('src/core/dds.lua', model)
model.lut_files = scoped('src/presets/lut_files.lua', model)
model.patch_export = scoped('src/presets/patch_export.lua', model)
model.bulk_dds_export = scoped('src/presets/bulk_dds_export.lua', model)
model.export_pairing = scoped('src/presets/export_pairing.lua', model)
model.resource_ids = scoped('src/core/resource_ids.lua', model)
local Preset = scoped('src/presets/preset_export.lua', model)
local prior_open, prior_remove, prior_rename = io.open, os.remove, os.rename
local function forbidden() error('Unicode export bypassed shared IO', 0) end
io.open, os.remove, os.rename = forbidden, forbidden, forbidden
local document = { width = 23, height = 1, data = model.float_buffer.new(92) }
document.data[0], document.data[1], document.data[2] = -1 / math.huge, 2 ^ -149, 123456
local resource = '0123456789abcdef'
local entry = { document = document, kind = 'armor', ordinal = 1, original = { resource = resource } }
local expected = model.dds.encode(document.data, 23, 1)
local bulk = model.bulk_dds_export.new(model, paths)
assert(opens == 0 and made == 0, 'Exporter construction performed IO')
for _, label in ipairs({ '服装', 'Élite – 服装', 'ชุดเกราะ' }) do
    entry.label = label
    local folder, count = bulk.save('Palette', { entry }, 1)
    assert(count == 1 and files[folder .. '/Palette ' .. label .. '-' .. resource .. '.dds'] == expected,
        'Unicode display filename or raw DDS bytes changed')
end
local exporter = Preset.new(model, paths, { lut_label = function(hash)
    assert(hash == resource); return '服装'
end })
local folder = exporter.save('Preset', { entries = {
    { kind = 'armor', key = '0:1:0:0', document = document, original = entry.original },
} }, 5, 1, 1)
assert(files[folder .. '/Preset 服装-' .. resource .. '.dds'] == expected,
    'Preset exporter did not preserve its injected Unicode display label')
assert(handles == closes)
local before_open, before_made = opens, made
for byte = 0, 31 do
    entry.label = '服装' .. string.char(byte) .. 'Invalid'
    assert(not pcall(bulk.save, 'Rejected', { entry }, 1), 'ASCII control byte accepted: ' .. byte)
end
for _, value in ipairs({ string.char(127), '\\', '/', ':', '*', '?', '"', '<', '>', '|' }) do
    entry.label = '服装' .. value .. 'Invalid'
    assert(not pcall(bulk.save, 'Rejected', { entry }, 1), 'Reserved filename byte accepted')
end
entry.label = string.rep('服装', 50)
assert(not pcall(bulk.save, 'Rejected', { entry }, 1), 'Filename byte bound weakened')
entry.label = '服装'
assert(not pcall(bulk.save, '服装', { entry }, 1), 'Explicit ASCII-only preset prefix policy broadened')
assert(opens == before_open and made == before_made, 'Rejected filename started filesystem work')
refuse_rename = true
assert(not pcall(bulk.save, 'Rollback', { entry }, 1), 'Publication failure reported success')
assert(removed == 1 and handles == closes)
for name in pairs(directories) do assert(not name:find('Rollback', 1, true), 'Owned staging directory leaked') end
for name in pairs(files) do assert(not name:find('Rollback', 1, true), 'Owned staging file leaked') end
io.open, os.remove, os.rename = prior_open, prior_remove, prior_rename
print('PASS Unicode display exports: actual preset/bulk/DDS/shared IO, exact bytes, ASCII control/reserved/length guards, unchanged prefix policy and transactional cleanup')
