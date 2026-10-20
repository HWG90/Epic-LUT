-- Pure dispatch contracts; native UTF-16 filesystem behavior has its own tests.
assert(_VERSION == 'Lua 5.1')
local original_require, original_getenv = require, os.getenv
ffi, bit, jit = nil, nil, nil
require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
    return original_require(name)
end
local local_app_data = 'C:/Users/\208\148\208\176\208\178\208\184\208\180/\232\183\175\229\190\132/AppData/Local'
os.getenv = function(name)
    if name == 'LOCALAPPDATA' then return local_app_data end
    return original_getenv(name)
end
local Paths = dofile('src/platform/paths.lua')
local calls, attributes = {}, {}
local function record(operation, path) calls[#calls + 1] = { operation, path } end
local platform = {}
function platform.mkdir(path)
    record('mkdir', path)
    if attributes[path] then return false, 'already exists' end
    attributes[path] = 16
    return true
end
function platform.directory_exists(path)
    record('directory_exists', path)
    local mask = attributes[path]
    return mask ~= nil and math.floor(mask / 16) % 2 == 1
end
function platform.mkdir_new(path)
    record('mkdir_new', path)
    if attributes[path] then return false, 'exclusive creation conflict' end
    attributes[path] = 16
    return true
end
function platform.rmdir(path)
    record('rmdir', path)
    if attributes[path] ~= 16 then return false end
    attributes[path] = nil
    return true
end
local fail_open = false
function platform.open_folder(path)
    record('open_folder', path)
    return not fail_open, fail_open and 'folder opening failed' or nil
end
local storage, stores, stored_folder = {}, 0, nil
local ui_store = { new = function(folder)
    stores, stored_folder = stores + 1, folder
    return storage
end }
local paths = Paths.new({ platform = platform, ui_store = ui_store })
local expected = {
    local_app_data .. '/Epic LUT', local_app_data .. '/Epic LUT/settings',
    local_app_data .. '/Epic LUT/files', local_app_data .. '/Epic LUT/presets',
    local_app_data .. '/Epic LUT/cache', local_app_data .. '/Epic LUT/originals',
    local_app_data .. '/Epic LUT/files/exports',
}
assert(#calls == 14 and stores == 1 and stored_folder == expected[2] and paths.storage == storage)
for index, folder in ipairs(expected) do
    assert(calls[index * 2 - 1][1] == 'mkdir' and calls[index * 2 - 1][2] == folder)
    assert(calls[index * 2][1] == 'directory_exists' and calls[index * 2][2] == folder,
        'Constructor lost Unicode path bytes or changed directory order')
end
assert(paths.root == expected[1] and paths.settings == expected[2] and paths.files == expected[3]
    and paths.presets == expected[4] and paths.cache == expected[5]
    and paths.originals == expected[6] and paths.exports == expected[7])
local explicit = {}
calls = {}
assert(Paths.new({ platform = platform, storage = explicit }).storage == explicit)
assert(#calls == 14 and stores == 1, 'Existing directories skipped validation or explicit storage was replaced')
local staging = paths.exports .. '/Shared Preset.pending'
assert(paths.mkdir_new(staging) == nil and paths.directory_exists(staging))
local ok, why = pcall(paths.mkdir_new, staging)
assert(not ok and tostring(why):find('exclusive creation conflict', 1, true), 'Exclusive creation overwrote an existing folder')
assert(paths.rmdir(staging) and not paths.rmdir(staging), 'Directory removal result was masked')
local file = paths.files .. '/preset.dds'
attributes[file] = 32
assert(paths.directory_exists(file) == false, 'Regular-file attributes were accepted as a directory')
assert(paths.open_exports() and calls[#calls][1] == 'open_folder' and calls[#calls][2] == paths.exports)
fail_open = true
assert(not pcall(paths.open_exports), 'Folder-open failure was swallowed')
fail_open = false

attributes[paths.settings] = 32
ok, why = pcall(Paths.new, { platform = platform, storage = explicit })
assert(not ok and tostring(why):find(paths.settings, 1, true), 'A file occupying the settings directory was accepted')
assert(attributes[paths.settings] == 32 and stores == 1, 'Failed construction replaced settings data')
attributes[paths.settings] = 16
local legacy_result, legacy_calls, legacy = {}, 0, nil
legacy = { new = function(m)
    legacy_calls = legacy_calls + 1
    assert(m.legacy_paths == legacy, 'Legacy dispatch changed its module context')
    return legacy_result
end }
assert(Paths.new({ legacy_paths = legacy }) == legacy_result and legacy_calls == 1)
local before = #calls
assert(not pcall(Paths.new, { platform = {}, storage = explicit }) and #calls == before,
    'Incomplete service performed partial construction')
os.getenv = function(name)
    if name ~= 'LOCALAPPDATA' then return original_getenv(name) end
end
assert(not pcall(Paths.new, { platform = platform, storage = explicit }) and #calls == before,
    'Missing app-data root performed filesystem work')
os.getenv, require = original_getenv, original_require
print('PASS portable paths: same folders/creation order, exact Unicode bytes, exclusive exports, directory masks, explicit storage and isolated legacy dispatch')
