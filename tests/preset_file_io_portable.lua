-- Actual preset/export controllers with an explicit Unicode file service only.
local Buffer = require('src.core.float_buffer')
local FIO = dofile('src/core/file_io.lua')
local Outfit = dofile('src/presets/outfit_presets.lua')
local Patch = dofile('src/presets/patch_export.lua')
local Preset = dofile('src/presets/preset_export.lua')
local Bulk = dofile('src/presets/bulk_dds_export.lua')
local Rows = dofile('src/presets/paydex_rows.lua')
local LUT = dofile('src/presets/lut_files.lua')
local files, directories = {}, { ['presets-Ω'] = true, ['exports-Ω'] = true, ['job-Ω'] = true }
local opened, closed, replaced, removed, renamed = 0, 0, 0, {}, 0
local fail_replace, fail_rename = false, false
local service = {}
function service.open(path, mode)
    if mode == 'rb' and files[path] == nil then return nil, 'missing fixture file' end
    assert(mode == 'rb' or mode == 'wb')
    assert(directories[path:match('^(.*)/[^/]+$')], 'Missing parent directory: ' .. path)
    if mode == 'wb' then files[path] = '' end
    local at, finished = 1, false
    opened = opened + 1
    return {
        read = function(_, count)
            assert(not finished and mode == 'rb')
            if at > #files[path] then return nil end
            local result = files[path]:sub(at, at + count - 1)
            at = at + #result
            return result
        end,
        write = function(self, bytes)
            assert(not finished and mode == 'wb')
            files[path] = files[path] .. bytes
            return self
        end,
        close = function() assert(not finished); finished = true; closed = closed + 1; return true end,
    }
end
function service.remove(path)
    assert(not path:match('/outfit%-[^/]+%.tsv$'), 'Portable save removed the live manifest')
    removed[#removed + 1] = path
    files[path] = nil
    return true
end
function service.rename(source, destination)
    if fail_rename then return nil, 'injected publication failure' end
    if files[destination] or directories[destination] then return nil, 'destination already exists' end
    renamed = renamed + 1
    if files[source] then files[destination], files[source] = files[source], nil; return true end
    assert(directories[source], 'Missing rename source')
    local moved = {}
    for path, bytes in pairs(files) do
        if path:sub(1, #source + 1) == source .. '/' then moved[path] = bytes end
    end
    for path, bytes in pairs(moved) do files[destination .. path:sub(#source + 1)], files[path] = bytes, nil end
    directories[destination], directories[source] = true, nil
    return true
end
function service.replace(source, destination)
    assert(files[source], 'Atomic publication has no staged bytes')
    if fail_replace then return nil, 'injected atomic replacement failure' end
    replaced = replaced + 1
    files[destination], files[source] = files[source], nil
    return true
end
local modules = {
    float_buffer = Buffer, file_io = FIO.new(service), platform = service,
    lut_files = LUT, patch_export = Patch, bulk_dds_export = Bulk,
    export_pairing = dofile('src/presets/export_pairing.lua'),
}
local dds_chunk = assert(loadfile('src/core/dds.lua'))
setfenv(dds_chunk, setmetatable({ m = modules }, { __index = _G }))
local DDS = dds_chunk()
modules.dds = DDS
local paths = {
    exports = 'exports-Ω',
    directory_exists = function(path) return directories[path] or files[path] ~= nil end,
    mkdir_new = function(path) assert(not directories[path] and not files[path]); directories[path] = true end,
    rmdir = function(path)
        for file in pairs(files) do assert(file:sub(1, #path + 1) ~= path .. '/', 'Nonempty staging folder') end
        directories[path] = nil
        return true
    end,
}
modules.windows = { files = function(folder)
    local names = {}
    for path in pairs(files) do
        local name = path:match('^' .. folder .. '/([^/]+)$')
        if name then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end }
local original_open, original_rename, original_remove = io.open, os.rename, os.remove
local function forbidden() error('Global filesystem bypass', 0) end
io.open, os.rename, os.remove = forbidden, forbidden, forbidden

local data = Buffer.new(92)
for i = 0, 91 do data[i] = (i - 30) / 17 end
data[0], data[3], data[52] = 2 ^ -149, -1 / math.huge, 1000000
local document = { data = data, width = 23, height = 1 }
local original = {
    width = 23, height = 1, resource = '0123456789abcdef',
    patch_source = 'fedcba9876543210\n' .. string.rep('\0', 192) .. DDS.encode(data, 23, 1):sub(1, 148),
}
local entries = { { kind = 'armor', key = '0:1:0:0', document = document, original = original } }
local store = Outfit.new(modules, 'presets-Ω')
store.save('Saved Set', entries)
local manifest = 'presets-Ω/outfit-Saved Set.tsv'
local previous = files[manifest]
data[4] = 0.875
fail_replace = true
assert(not pcall(store.save, 'Saved Set', entries))
assert(files[manifest] == previous and files[manifest .. '.previous'] == previous,
    'Failed atomic publication lost or replaced the previous manifest')
assert(store.load('Saved Set').entries[1].document.data[4] ~= data[4], 'Failed save exposed uncommitted pixels')
fail_replace = false
assert(store.save('Saved Set', entries) and files[manifest] ~= previous)
assert(store.load('Saved Set').entries[1].document.data[4] == data[4])
assert(store.rename('Saved Set', 'Renamed Set'))
assert(store.delete('Renamed Set') and files['presets-Ω/outfit-Renamed Set.tsv.deleted'])

local patch = Patch.new(paths.exports, {
    file_io = modules.file_io, dds = DDS, available_name = LUT.available_name,
    directory_exists = paths.directory_exists, mkdir_new = paths.mkdir_new, rmdir = paths.rmdir,
})
local destination, _, zipped = patch.save('Direct Patch', document, original)
assert(directories[destination] and files[zipped]:sub(1, 4) == 'PK\3\4')
assert(files[destination .. '/' .. Patch.BASE_ARCHIVE .. '.patch_0.gpu_resources'] == Buffer.bytes(data, 92))
fail_rename = true
assert(not pcall(patch.save, 'Failed Patch', document, original))
for path in pairs(directories) do assert(not path:find('Failed Patch', 1, true), 'Patch staging directory leaked') end
fail_rename = false

local export = Preset.new(modules, paths)
local preset = { entries = entries }
local shared = export.save('Shared Set', preset, 1, 1)
assert(files[shared]:sub(1, 4) == 'PK\3\4')
local selected_patch = export.save('Selected Patch', preset, 2, 1)
assert(directories[selected_patch], 'Preset exporter dropped the explicit patch IO service')
local raw = export.save('Raw LUT', preset, 4, 1)
assert(files[raw] == DDS.encode(data, 23, 1), 'Raw preset bytes changed')
local bulk = export.save('Raw Set', preset, 5, 1)
assert(directories[bulk])
fail_rename = true
assert(not pcall(export.save, 'Failed Shared', preset, 1, 1))
assert(not pcall(export.save, 'Failed Raw Set', preset, 5, 1))
for path in pairs(files) do assert(not path:find('Failed ', 1, true), 'Owned export staging file leaked') end
for path in pairs(directories) do assert(not path:find('Failed ', 1, true), 'Owned export staging directory leaked') end
fail_rename = false

files['job-Ω/rows.tsv'], files['job-Ω/row-Copper.dds'] = 'row-Copper.dds\n', DDS.encode(data, 23, 1)
local rows = Rows.new({ folder = 'presets-Ω', dds = DDS, file_io = modules.file_io })
local names, count = rows.import('job-Ω', 'rows.tsv')
assert(names[1] == 'Copper' and count == 1 and files['presets-Ω/row-Copper.dds'] == DDS.encode(data, 23, 1))
names, count = rows.import('job-Ω', 'rows.tsv')
assert(names[1] == 'Copper' and count == 0, 'Unchanged row import wrote again')
assert(opened == closed and replaced >= 3 and renamed > 0 and #removed > 0, 'Missing service operation or leaked stream')
io.open, os.rename, os.remove = original_open, original_rename, original_remove
print('PASS portable preset IO: exact DDS/patch/ZIP/row bytes, Unicode service dispatch, atomic manifest rollback, explicit constructor plumbing and owned staging cleanup with global filesystem forbidden')
