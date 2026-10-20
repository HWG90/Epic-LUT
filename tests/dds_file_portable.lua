-- Publication orchestration contract; the native replacement has its own real test.
local old_m = m
local disk, opened, closed, fail_publish = {}, 0, 0, false
local platform, blocked = {}, nil
function platform.open(path, mode)
    if mode == 'rb' and path == blocked then return nil, 'read denied', 5 end
    if mode == 'rb' and not disk[path] then return nil, 'missing file' end
    assert(mode == 'rb' or mode == 'wb')
    opened = opened + 1
    if mode == 'wb' then disk[path] = '' end
    local released = false
    return {
        read = function(_, count) return disk[path]:sub(1, count) end,
        write = function(_, bytes) disk[path] = disk[path] .. bytes; return true end,
        close = function() assert(not released); released = true; closed = closed + 1; return true end,
    }
end
function platform.replace(source, destination)
    if fail_publish then return false, 'publication refused' end
    assert(disk[source])
    disk[destination], disk[source] = disk[source], nil
    return true
end
local Buffer = dofile('src/core/float_buffer.lua')
m = { platform = platform, float_buffer = Buffer, file_io = dofile('src/core/file_io.lua').new(platform) }
local DDS = dofile('src/core/dds.lua')
local path = 'Unicode \230\156\141\232\163\133/palette.dds'
local data = Buffer.new(4)
data[0], data[1], data[2], data[3] = 0.125, 0.25, 0.5, 1
local original = DDS.encode(data, 1, 1)
assert(DDS.write(path, data, 1, 1) == path and disk[path] == original)
assert(disk[path .. '.previous'] == nil and disk[path .. '.pending'] == nil)
data[0] = 0.75
local edited = DDS.encode(data, 1, 1)
assert(DDS.write(path, data, 1, 1) == path and disk[path] == edited)
assert(disk[path .. '.previous'] == original)
local copied, bytes = DDS.read(path, 1, 1)
assert(copied[0] == 0.75 and bytes == edited)
fail_publish, data[0] = true, 0.875
local ok, why = pcall(DDS.write, path, data, 1, 1)
assert(not ok and why:find('publication refused') and disk[path] == edited,
    'Failed portable publication modified the active DDS')
assert(disk[path .. '.previous'] == edited and disk[path .. '.pending'] == DDS.encode(data, 1, 1))
fail_publish, blocked = false, path
local previous = disk[path .. '.previous']
ok, why = pcall(DDS.write, path, data, 1, 1)
assert(not ok and why:find('read denied') and disk[path] == edited and disk[path .. '.previous'] == previous,
    'Optional snapshot read let atomic replacement overwrite an unreadable original')
assert(opened == closed, 'DDS publication leaked a stream')
m = old_m
print('PASS portable DDS files: exact bytes, Unicode paths, owned streams, previous copy and atomic publication refusal')
