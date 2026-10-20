-- Actual named-row service + DDS + shared IO, with detached IEEE754 buffers.
local Buffer = require('src.core.float_buffer')
local function scoped(path, modules)
    return setfenv(assert(loadfile(path)), setmetatable({ m = modules }, { __index = _G }))()
end
local files, opens, handles, closes, publications = {}, 0, 0, 0, 0
local platform = {}
function platform.open(path, mode)
    opens = opens + 1
    assert(path:sub(1, #'presets-服装/') == 'presets-服装/' and (mode == 'rb' or mode == 'wb'))
    if mode == 'rb' and files[path] == nil then return nil, 'missing row', 2 end
    if mode == 'wb' then files[path] = '' end
    local done, at = false, 1
    handles = handles + 1
    return {
        read = function(_, count)
            assert(not done and mode == 'rb')
            if at > #files[path] then return nil end
            local bytes = files[path]:sub(at, at + count - 1)
            at = at + #bytes
            return bytes
        end,
        write = function(self, bytes)
            assert(not done and mode == 'wb')
            files[path] = files[path] .. bytes
            return self
        end,
        close = function() assert(not done); done = true; closes = closes + 1; return true end,
    }
end
function platform.replace(source, destination)
    assert(files[source], 'Row publication lost staged bytes')
    files[destination], files[source] = files[source], nil
    publications = publications + 1
    return true
end
local modules = { platform = platform, float_buffer = Buffer }
modules.file_io = scoped('src/core/file_io.lua', modules)
modules.dds = scoped('src/core/dds.lua', modules)
local LUT = scoped('src/presets/lut_files.lua', modules)
local store = LUT.new('presets-服装', { dds = modules.dds, read = modules.file_io.read })
local prior_open, prior_remove, prior_rename = io.open, os.remove, os.rename
local function forbidden() error('Row service bypassed shared IO', 0) end
io.open, os.remove, os.rename = forbidden, forbidden, forbidden
for _ = 1, 1000 do LUT.new('presets-服装', { dds = modules.dds, read = modules.file_io.read }) end
assert(opens == 0, 'Creating row services performed idle IO')

-- Independently specified float32 words include both zeros, subnormals, HDR,
-- negative values and the greatest finite magnitudes, across all RGBA channels.
local vectors = { 0, 2147483648, 1, 2147483649, 8388607, 2155872255,
    8388608, 2155872256, 1065353216, 3212836864, 1036831949, 2139095039, 4286578687 }
local parts = {}
for index = 0, 275 do
    local word = vectors[(index + math.floor(index / 92) * 3) % #vectors + 1]
    parts[#parts + 1] = string.char(word % 256, math.floor(word / 256) % 256,
        math.floor(word / 65536) % 256, math.floor(word / 16777216) % 256)
end
local raw = table.concat(parts)
local document = { data = Buffer.from_bytes(raw, 276), width = 23, height = 3 }
local selected_values, real_write = nil, modules.dds.write
modules.dds.write = function(path, data, width, height)
    assert(data ~= document.data and Buffer.count(data) == 92 and width == 23 and height == 1,
        'Row save did not provide exactly one owned detached row')
    selected_values = data
    return real_write(path, data, width, height)
end
for row = 1, 3 do
    local name = 'Exact ' .. row
    local path = assert(store.save_row(name, document, row))
    local expected = raw:sub((row - 1) * 368 + 1, row * 368)
    assert(path == 'presets-服装/row-' .. name .. '.dds' and files[path]:sub(149) == expected,
        'Saved row bytes or destination differ')
    local loaded, width, height = store.load_row(name)
    assert(width == 23 and height == 1 and Buffer.bytes(loaded, 92) == expected, 'Loaded row lost float precision')
    assert(Buffer.bytes(selected_values, 92) == expected and Buffer.bytes(document.data, 276) == raw,
        'Save/load mutated or aliased the source document')
    loaded[0] = 0.5
    assert(files[path]:sub(149) == expected and Buffer.bytes(document.data, 276) == raw)
end
assert(publications == 3 and handles == closes)
local before = files['presets-服装/row-Exact 3.dds']
local detached = Buffer.bytes(selected_values, 92)
document.data[184] = 0.625
assert(Buffer.bytes(selected_values, 92) == detached, 'Retained row copy followed later document edits')
assert(store.save_row('Exact 3', document, 3))
assert(files['presets-服装/row-Exact 3.dds.previous'] == before, 'Overwriting lost the previous exact row')

local attempts = opens
for _, row in ipairs({ 0, -1, 4, 1.5, math.huge, 0 / 0, '1', false }) do
    assert(not pcall(store.save_row, 'Invalid', document, row), 'Invalid row accepted')
end
assert(not pcall(store.save_row, 'Invalid', document, nil))
assert(not pcall(store.save_row, '../escape', document, 1))
assert(not pcall(store.save_row, 'Short', { width = 23, height = 1, data = Buffer.new(91) }, 1),
    'Read past a proven owned buffer')
assert(opens == attempts and handles == closes, 'Rejected row touched files or leaked a stream')
io.open, os.remove, os.rename = prior_open, prior_remove, prior_rename
print('PASS exact row files: stock/legacy owned row slices, raw IEEE754 RGBA, save/load/previous bytes, source isolation and invalid bounds before IO')
