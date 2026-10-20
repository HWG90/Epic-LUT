local ffi = require('ffi')
local called
local data = ffi.new('float[184]')
data[92] = 0.75
local files = dofile('src/presets/lut_files.lua').new('folder', {
    dds = {
        MAX_BYTES = 100,
        write = function(path, pixels, w, h)
            called = { path = path, pixels = pixels, w = w, h = h }
            return path
        end,
        decode = function(bytes, w, h)
            assert(bytes == 'dds' and w == 23 and h == 1)
            return 'pixels'
        end,
    },
    read = function(path, limit)
        assert(path == 'folder/row-Example.dds' and limit == 100)
        return 'dds'
    end,
    row_names = function(folder)
        assert(folder == 'folder')
        return { 'Example' }
    end,
})
files.save_row('Example', { data = data, width = 23, height = 2 }, 2)
assert(called.path == 'folder/row-Example.dds' and called.pixels[0] == 0.75 and called.h == 1, 'Wrong row exported')
assert(files.load_row('Example') == 'pixels' and files.row_names()[1] == 'Example')
assert(
    not pcall(files.load_row, '../escape') and not pcall(files.save_row, 'Example', { height = 2 }, 3),
    'Unsafe name/row accepted'
)
files.save('Export', { data = data, width = 23, height = 2 })
assert(called.path == 'folder/Export.dds' and called.h == 2, 'Full export shape lost')
-- Deletion archives only the requested custom row, without touching an editor
-- buffer, ordinary palettes, siblings or an existing deleted-row backup.
local DDS = dofile('src/core/dds.lua')
local IO = dofile('src/core/file_io.lua')
local Windows = dofile('src/platform/windows.lua')
pcall(
    ffi.cdef,
    [[
    int epic_lut_files_mkdir(const char *, void *) __asm__("CreateDirectoryA");
    int epic_lut_files_rmdir(const char *) __asm__("RemoveDirectoryA");
]]
)
local kernel = ffi.load('kernel32')
local folder = 'tests/tmp/presets/row-delete-fixture-' .. os.time()
assert(kernel.epic_lut_files_mkdir(folder, nil) ~= 0, 'Could not create fresh deletion fixture')
local store = dofile('src/presets/lut_files.lua').new(folder, {
    dds = DDS,
    read = IO.read,
    row_names = Windows.row_presets,
})
local pixels = ffi.new('float[92]')
for i = 0, 91 do
    pixels[i] = (i - 30) / 4
end
ffi.cast('uint32_t *', pixels)[3] = 0x80000000
local bytes = DDS.encode(pixels, 23, 1)
local source, sibling, ordinary = folder .. '/row-Example.dds', folder .. '/row-Sibling.dds', folder .. '/Example.dds'
IO.write(source, bytes)
IO.write(sibling, bytes)
IO.write(ordinary, 'ordinary palette retained')
IO.write(source .. '.deleted', 'foreign backup retained')
local backup = store.delete_row('Example')
assert(
    backup == source .. '.deleted-2' and IO.read(backup, 1024) == bytes,
    'Deleted row was not recoverable byte-for-byte'
)
assert(not IO.read(source, 1024, true) and store.row_names()[1] == 'Sibling' and #store.row_names() == 1)
assert(IO.read(sibling, 1024) == bytes and IO.read(ordinary, 1024) == 'ordinary palette retained')
assert(IO.read(source .. '.deleted', 1024) == 'foreign backup retained', 'Existing backup overwritten')
assert(ffi.string(pixels, 368) == bytes:sub(149), 'Deleting a preset changed the current row buffer')
for _, name in ipairs({ '', '../escape', 'Example.dds', 'folder/Example', 'folder\\Example', 'file:stream' }) do
    assert(not pcall(store.delete_row, name), 'Unsafe deletion name accepted')
end
assert(not pcall(store.delete_row, 'Missing'), 'Deleting a missing row reported success')
-- A failed rename retains the original, and a race-created backup is protected
-- by the actual Windows rename operation rather than only a preflight check.
IO.write(source, bytes)
local failed = dofile('src/presets/lut_files.lua').new(folder, {
    move = function()
        return nil, 'Simulated rename failure'
    end,
})
assert(not pcall(failed.delete_row, 'Example') and IO.read(source, 1024) == bytes)
local raced = dofile('src/presets/lut_files.lua').new(folder, {
    exists = function(filename)
        if filename == source .. '.deleted-3' then
            IO.write(filename, 'racing foreign backup')
            return false
        end
        return IO.read(filename, 1024, true) ~= nil
    end,
})
assert(not pcall(raced.delete_row, 'Example'), 'Rename replaced a racing backup')
assert(IO.read(source, 1024) == bytes and IO.read(source .. '.deleted-3', 1024) == 'racing foreign backup')
local probes = 0
local saturated = dofile('src/presets/lut_files.lua').new(folder, {
    exists = function()
        probes = probes + 1
        return true
    end,
    move = function()
        error('Saturated backups must not attempt a rename')
    end,
})
assert(not pcall(saturated.delete_row, 'Example') and probes == 10001, 'Deleted-backup collisions were not bounded')
assert(IO.read(source, 1024) == bytes)
local palette, palette_sibling = folder .. '/palette-Example.dds', folder .. '/palette-Sibling.dds'
IO.write(palette, bytes)
IO.write(palette_sibling, bytes)
IO.write(palette .. '.deleted', 'foreign palette backup retained')
local palette_backup = store.delete_palette('Example')
assert(
    palette_backup == palette .. '.deleted-2' and IO.read(palette_backup, 1024) == bytes,
    'Saved palette deletion lost its exact recoverable bytes'
)
assert(not IO.read(palette, 1024, true) and IO.read(palette_sibling, 1024) == bytes)
assert(IO.read(palette .. '.deleted', 1024) == 'foreign palette backup retained')
assert(IO.read(source, 1024) == bytes and IO.read(sibling, 1024) == bytes, 'Palette deletion changed a row preset')
assert(IO.read(ordinary, 1024) == 'ordinary palette retained', 'Palette deletion changed ordinary imported DDS')
for _, name in ipairs({ '', '../escape', 'Example.dds', 'folder/Example', 'folder\\Example', 'file:stream' }) do
    assert(not pcall(store.delete_palette, name), 'Unsafe palette deletion name accepted')
end
assert(not pcall(store.delete_palette, 'Missing'), 'Deleting a missing palette reported success')
for _, filename in ipairs({
    source,
    sibling,
    ordinary,
    source .. '.deleted',
    backup,
    source .. '.deleted-3',
    palette_sibling,
    palette .. '.deleted',
    palette_backup,
}) do
    assert(os.remove(filename))
end
assert(kernel.epic_lut_files_rmdir(folder) ~= 0)
print(
    'PASS LUT files: validated names/exact rows; reversible row/palette deletion, sibling/backup preservation, bounded conflicts and failed/raced rename guards'
)

-- Exact identity suffixes survive timestamp/name truncation; no intermediate floats.
local L = dofile('src/presets/lut_files.lua')
local ids = dofile('src/core/resource_ids.lua')
local d, o = {width=23,height=8}, {resource='ffffffffffffffff'}
assert(L.naming_suffix(d,o,2,nil,ids,3)==' LUT3-18446744073709551615')
assert(L.naming_suffix(d,o,3,'Desert',ids,3)==' Desert')
assert(L.naming_suffix(d,o,4,nil,ids,3)==' ffffffffffffffff')
assert(L.naming_suffix(d,o,6,'Desert',ids,3)=='')
local calls = 0
local named=L.available_name(string.rep('A',48),function() calls=calls+1; return calls==1 end,L.naming_suffix(d,o,2,nil,ids,3))
assert(named:find('LUT3-18446744073709551615-',1,true) and named:match('%-01$'))
assert(not pcall(L.available_name,'Safe',function()return false end,'/escape'))
