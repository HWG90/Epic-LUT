assert(_VERSION == 'Lua 5.1')
local original_require = require
ffi, bit, jit = nil, nil, nil
require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
    return original_require(name)
end
local Windows = dofile('src/platform/windows.lua')
local unicode = '\208\148\208\176\208\178\208\184\208\180'
local calls, bulk, listed_pattern = {}, true, nil
local function count(name) calls[name] = (calls[name] or 0) + 1 end
local file_names = { 'z.dds', 'row-Blue.dds', 'row-Alpha.dds' }
local directory_names = { 'folder.dds' }
local platform = {}
function platform.process_id() count('process_id'); return 1234 end
function platform.executable_path() count('executable_path'); return 'C:\\Games\\' .. unicode .. '\\bin\\helldivers2.exe' end
function platform.files(folder, pattern)
    count('files'); listed_pattern = pattern
    assert(folder == 'C:/Data/' .. unicode)
    local names = pattern == 'row-*.dds' and { 'row-Blue.dds', 'row-Alpha.dds' } or file_names
    local dirs = pattern == 'row-*.dds' and {} or directory_names
    local receipts = {}
    for _, name in ipairs(names) do receipts[name] = 'F:0000000000000004:0000000000000010' end
    for _, name in ipairs(dirs) do receipts[name] = 'D:0000000000000000:0000000000000010' end
    return names, dirs, bulk and receipts or nil
end
function platform.stat(path)
    count('stat')
    return { directory = path:match('/folder%.dds$') ~= nil, size_hex = '0000000000000004', stamp = '0000000000000010' }
end
local running, stopped, closed, failed_stop = 0, 0, 0, false
local worker = { pid = 5678, handle = {} }
function worker.running() running = running + 1; return closed == 0 end
function worker.stop()
    stopped = stopped + 1
    return not failed_stop, failed_stop and 'owned termination pending' or nil
end
function worker.close() closed = closed + 1; return true end
function platform.launch_worker(args, folder)
    count('launch_worker')
    assert(args == '-NoProfile -File "C:/Data/' .. unicode .. '/task.ps1"')
    assert(folder == 'C:/Data/' .. unicode)
    return worker
end
function platform.replace(source, destination)
    count('replace')
    assert(source == 'C:/Data/' .. unicode .. '/state.pending' and destination == 'C:/Data/' .. unicode .. '/state')
    return true
end
local windows = Windows.new(platform)
assert(next(calls) == nil, 'Constructing Windows adapter performed native work')
assert(windows.process_id() == 1234)
assert(windows.game_data() == 'C:/Games/' .. unicode .. '/data')
local names, receipts = windows.files('C:/Data/' .. unicode, '*.dds')
assert(#names == 4 and names[1] == 'folder.dds' and names[4] == 'z.dds')
assert(receipts['row-Blue.dds'] == 'F:0000000000000004:0000000000000010')
assert(calls.files == 1 and calls.stat == nil and listed_pattern == '*.dds', 'Bulk receipts caused per-file stat work')
bulk = false
names, receipts = windows.files('C:/Data/' .. unicode, '*.dds')
assert(calls.files == 2 and calls.stat == 4 and receipts['z.dds'] == 'F:0000000000000004:0000000000000010')
local rows = windows.row_presets('C:/Data/' .. unicode)
assert(#rows == 2 and rows[1] == 'Alpha' and rows[2] == 'Blue' and listed_pattern == 'row-*.dds')
assert(calls.stat == 4, 'Row names unnecessarily queried metadata')
assert(windows.launch_worker('-NoProfile -File "C:/Data/' .. unicode .. '/task.ps1"', 'C:/Data/' .. unicode) == worker)
assert(windows.replace('C:/Data/' .. unicode .. '/state.pending', 'C:/Data/' .. unicode .. '/state') and calls.replace == 1)
assert(running == 0 and stopped == 0 and closed == 0, 'Launching sampled or closed a live worker')
failed_stop = true
assert(not worker.stop() and worker.handle ~= nil)
failed_stop = false
assert(worker.stop() and worker.close() and closed == 1)
local before = calls.launch_worker
for _, invalid in ipairs({ 'bad\0argument', '\255', string.rep('a', 32767), '\237\160\128' }) do
    assert(not pcall(windows.launch_worker, invalid, 'C:/Data/' .. unicode))
end
assert(calls.launch_worker == before, 'Invalid worker arguments reached service')
assert(not pcall(windows.replace, 'bad\0path', 'destination') and calls.replace == 1)
assert(not pcall(windows.files, 'C:/Data/' .. unicode, '../*'))
assert(not pcall(windows.verify_interface), 'Portable code received a fake Win32/FFI interface')
local missing = Windows.new({})
assert(not pcall(missing.game_data) and not pcall(missing.launch_worker, '-NoProfile', 'C:/Data'))
local saved_stat = platform.stat
platform.stat = function() return nil end
assert(not pcall(windows.files, 'C:/Data/' .. unicode, '*.dds'), 'Disappeared files received invented receipts')
platform.stat = saved_stat
file_names = { '../outside.dds' }
assert(not pcall(windows.files, 'C:/Data/' .. unicode, '*.dds'), 'Foreign child path was accepted')
file_names = { 'duplicate.dds', 'duplicate.dds' }
assert(not pcall(windows.files, 'C:/Data/' .. unicode, '*.dds'), 'Ambiguous duplicate listing accepted')
local original_files = platform.files
platform.files = function() return nil end
assert(not pcall(windows.files, 'C:/Data/' .. unicode, '*.dds'), 'Missing listing became fake empty success')
platform.files = original_files
local old_m, legacy_calls = m, 0
m = { platform = platform }
assert(Windows.process_id() == 1234, 'Default methods did not dispatch explicit model service')
m = { legacy_windows = { files = function(folder, pattern)
    legacy_calls = legacy_calls + 1;return { folder, pattern }, { exact = true }
end } }
local legacy_names, legacy_receipts = Windows.files('old', 'filter')
assert(legacy_calls == 1 and legacy_names[1] == 'old' and legacy_receipts.exact)
m, require = old_m, original_require
print('PASS portable Windows: Unicode paths, sorted names/receipts, bulk metadata, explicit owned workers, strict bounds, no raw kernel shim and legacy dispatch')
