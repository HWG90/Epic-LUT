local ffi = require('ffi')
local B = dofile('src/presets/bulk_dds_export.lua')
local D = dofile('src/core/dds.lua')
local L = dofile('src/presets/lut_files.lua')
local F = dofile('src/core/file_io.lua')
local R = dofile('src/core/resource_ids.lua')
ffi.cdef(
    'int CreateDirectoryW(const uint16_t *,void *); int RemoveDirectoryW(const uint16_t *); uint32_t GetFileAttributesW(const uint16_t *);'
)
local kernel = ffi.load('kernel32')
local function wide(path)
    local result = ffi.new('uint16_t[?]', #path + 1)
    for i = 1, #path do
        result[i - 1] = path:byte(i)
    end
    return result
end
local function exists(path)
    return tonumber(kernel.GetFileAttributesW(wide(path))) ~= 4294967295
end
local function mkdir(path)
    assert(not exists(path), 'Test folder already exists')
    assert(kernel.CreateDirectoryW(wide(path), nil) ~= 0)
end
local function rmdir(path)
    return kernel.RemoveDirectoryW(wide(path)) ~= 0
end
local root = assert(os.getenv('TEMP')) .. '/EpicLUT-bulk-dds-' .. os.time() .. '-' .. math.floor(os.clock() * 1000000)
mkdir(root)
local made, writes, last_stage, published = 0, 0, nil, {}
local paths = {
    exports = root,
    directory_exists = exists,
    mkdir_new = function(path)
        made = made + 1
        last_stage = path
        mkdir(path)
    end,
    rmdir = rmdir,
}
local modules = {
    dds = D,
    lut_files = L,
    resource_ids = R,
    file_io = {
        write = function(path, bytes)
            writes = writes + 1
            return F.write(path, bytes)
        end,
    },
}
local export = B.new(modules, paths)
local material = { width = 23, height = 8, data = ffi.new('float[736]') }
material.data[0], material.data[7], material.data[31] = 16.25, -2.625, 0.3125
ffi.cast('uint32_t *', material.data)[4] = 0x80000000 -- Preserve negative zero exactly.
local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
pattern.data[0], pattern.data[7], pattern.data[11] = 1.5, 0.375, -0.125
local function entry(doc, kind, ordinal, resource)
    return { document = doc, kind = kind, ordinal = ordinal, original = resource and { resource = resource } or nil }
end
local function assert_file(folder, name, doc)
    local bytes = F.read(folder .. '/' .. name, D.MAX_BYTES)
    assert(bytes == D.encode(doc.data, doc.width, doc.height), 'DDS export lost exact float bytes: ' .. name)
    local decoded, width, height = D.decode(bytes)
    assert(width == doc.width and height == doc.height)
    assert(ffi.string(decoded, width * height * 16) == ffi.string(doc.data, width * height * 16))
end
local function save(prefix, entries, format, filenames)
    local folder, count = export.save(prefix, entries, format)
    assert(count == #filenames and not exists(folder .. '.pending'))
    published[#published + 1] = { folder = folder, filenames = filenames }
    return folder
end
assert(table.concat(B.formats, '|') == 'LUT# + HEX|LUT# + Decimal|LUT#|HEX|Decimal')
local resources = {
    entry(material, 'armor', 3, 'd3ce605892d5331b'),
    entry(pattern, 'helmet', 3, 'ffffffffffffffff'),
}
local names = {
    { 'HONK LUT3-d3ce605892d5331b.dds', 'HONK PatternLUT3-ffffffffffffffff.dds' },
    {
        'HONK LUT3-' .. R.format('d3ce605892d5331b', true):sub(2, -2) .. '.dds',
        'HONK PatternLUT3-18446744073709551615.dds',
    },
    { 'HONK LUT3.dds', 'HONK PatternLUT3.dds' },
    { 'HONK d3ce605892d5331b.dds', 'HONK ffffffffffffffff.dds' },
    { 'HONK ' .. R.format('d3ce605892d5331b', true):sub(2, -2) .. '.dds', 'HONK 18446744073709551615.dds' },
}
local previous
for format = 1, 5 do
    local folder = save('HONK', resources, format, names[format])
    assert_file(folder, names[format][1], material)
    assert_file(folder, names[format][2], pattern)
    assert(
        folder ~= previous and folder:match('%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d'),
        'Exports overwrote an existing folder'
    )
    previous = folder
end
-- Unknown IDs fall back to an ordinal instead of inventing a resource ID.
for _, format in ipairs({ 1, 2, 4, 5 }) do
    local folder = save('Unknown', { entry(material, 'helmet', 12) }, format, { 'Unknown LUT12.dds' })
    assert_file(folder, 'Unknown LUT12.dds', material)
end
-- Duplicate IDs collapse only when every raw float and dimension matches.
local folder = save(
    'Reuse',
    { resources[1], entry(material, 'helmet', 8, 'D3CE605892D5331B') },
    1,
    { 'Reuse LUT3-d3ce605892d5331b.dds' }
)
assert_file(folder, 'Reuse LUT3-d3ce605892d5331b.dds', material)
local transmog = {}
for i = 1, B.MAX_BINDINGS do
    transmog[i] = entry(material, 'armor', i, 'd3ce605892d5331b')
end
folder = save('Transmog', transmog, 1, { 'Transmog LUT1-d3ce605892d5331b.dds' })
assert_file(folder, 'Transmog LUT1-d3ce605892d5331b.dds', material)
local distinct, distinct_names = {}, {}
for i = 1, 129 do
    distinct[i] = entry(material, 'armor', i, string.format('%016x', i))
    distinct_names[i] = 'Distinct LUT' .. i .. '-' .. string.format('%016x', i) .. '.dds'
end
folder = save('Distinct', distinct, 1, distinct_names)
for _, name in ipairs(distinct_names) do
    assert_file(folder, name, material)
end
local unknown_reuse = save('No ID Reuse', {
    entry(material, 'armor', 6),
    entry(material, 'armor', 6),
    entry(pattern, 'armor', 6),
    entry(material, 'helmet', 6),
}, 1, { 'No ID Reuse LUT6-Armor.dds', 'No ID Reuse PatternLUT6.dds', 'No ID Reuse LUT6-Helmet.dds' })
assert_file(unknown_reuse, 'No ID Reuse LUT6-Armor.dds', material)
assert_file(unknown_reuse, 'No ID Reuse PatternLUT6.dds', pattern)
assert_file(unknown_reuse, 'No ID Reuse LUT6-Helmet.dds', material)
local collided = {
    entry(material, 'armor', 3, '0000000000000001'),
    entry(material, 'helmet', 3, '0000000000000002'),
    entry(pattern, 'helmet', 3),
    entry(material, 'armor', 3, '0000000000000003'),
}
local collision_names =
    { 'Kinds LUT3-Armor.dds', 'Kinds LUT3-Helmet.dds', 'Kinds PatternLUT3.dds', 'Kinds LUT3-Armor-02.dds' }
folder = save('Kinds', collided, 3, collision_names)
for i, name in ipairs(collision_names) do
    assert_file(folder, name, collided[i].document)
end
local long_prefix = string.rep('A', 48)
local long_name = long_prefix .. ' LUT3-d3ce605892d5331b.dds'
folder = save(long_prefix, { resources[1] }, 1, { long_name })
assert_file(folder, long_name, material)
assert(#long_name > 48, 'Filename incorrectly truncated a resource ID to the prefix limit')
-- All invalid pixels, IDs, formats and conflicts fail before any filesystem write.
local before_made, before_writes = made, writes
local different = { width = 23, height = 8, data = ffi.new('float[736]') }
ffi.copy(different.data, material.data, 2944)
different.data[0] = 0.75
local cape_variants = {
    resources[1],
    entry(different, 'cape', 3, 'd3ce605892d5331b'),
}
local cape_names = { 'Cape Variants LUT3-d3ce605892d5331b-Armor.dds', 'Cape Variants LUT3-d3ce605892d5331b-Cape.dds' }
folder = save('Cape Variants', cape_variants, 1, cape_names)
assert_file(folder, cape_names[1], material)
assert_file(folder, cape_names[2], different)
local shared_ids =
    save('Cape IDs', cape_variants, 4, { 'Cape IDs d3ce605892d5331b-Armor.dds', 'Cape IDs d3ce605892d5331b-Cape.dds' })
assert_file(shared_ids, 'Cape IDs d3ce605892d5331b-Cape.dds', different)
before_made, before_writes = made, writes
local ok, why = pcall(export.save, 'Conflict', { resources[1], entry(different, 'armor', 3, 'd3ce605892d5331b') }, 1)
assert(not ok and tostring(why):find('Conflicting LUT values', 1, true), 'Conflicting resource values were discarded')
assert(
    not pcall(export.save, 'Unknown Conflict', { entry(material, 'armor', 6), entry(different, 'armor', 6) }, 1),
    'Conflicting unknown ordinal values were discarded'
)
local nonfinite = { width = 23, height = 8, data = ffi.new('float[736]') }
nonfinite.data[735] = math.huge
assert(not pcall(export.save, 'Invalid', { resources[1], entry(nonfinite, 'helmet', 1) }, 1))
assert(not pcall(export.save, '../escape', resources, 1))
assert(not pcall(export.save, string.rep('A', 49), resources, 1))
assert(not pcall(export.save, 'Bad ID', { entry(material, 'armor', 1, 'not an id') }, 1))
assert(not pcall(export.save, 'Bad Mode', resources, 6))
assert(not pcall(export.save, 'Bad Ordinal', { entry(material, 'armor', 0) }, 1))
local too_many = {}
for i = 1, B.MAX_BINDINGS + 1 do
    too_many[i] = entry(material, 'armor', i)
end
assert(not pcall(export.save, 'Too Many', too_many, 1))
assert(made == before_made and writes == before_writes, 'Validation made a partial export folder')
-- Partial writes and failed publication remove only known files in the owned staging folder.
local actual_write = modules.file_io.write
local failed_write = false
modules.file_io.write = function(path, bytes)
    F.write(path, bytes:sub(1, 32))
    failed_write = true
    error('injected write failure')
end
ok, why = pcall(export.save, 'Write Fail', resources, 1)
assert(not ok and failed_write and not exists(last_stage), 'Partial DDS write was not rolled back')
modules.file_io.write = actual_write
local actual_rename = os.rename
os.rename = function()
    return nil, 'injected publish failure'
end
ok, why = pcall(export.save, 'Publish Fail', resources, 1)
os.rename = actual_rename
assert(not ok and not exists(last_stage), 'Failed publication retained staging files')
-- A competing destination is preserved; rollback never deletes foreign final contents.
local foreign_path
os.rename = function(source, destination)
    mkdir(destination)
    foreign_path = destination .. '/foreign.txt'
    F.write(foreign_path, 'untouched')
    return nil, 'destination collision'
end
ok = pcall(export.save, 'Collision', resources, 1)
os.rename = actual_rename
assert(
    not ok and not exists(last_stage) and F.read(foreign_path, 64) == 'untouched',
    'Publish collision removed another destination'
)
os.remove(foreign_path)
assert(rmdir(foreign_path:match('^(.*)/[^/]+$')))
-- No recursive cleanup: an unrelated staging file is retained on failure.
local foreign_staging
modules.file_io.write = function(path, bytes)
    F.write(path, bytes)
    foreign_staging = path:match('^(.*)/[^/]+$') .. '/foreign.txt'
    F.write(foreign_staging, 'untouched')
    error('injected foreign staging file')
end
ok = pcall(export.save, 'Owned Only', resources, 1)
modules.file_io.write = actual_write
assert(
    not ok and exists(last_stage) and F.read(foreign_staging, 64) == 'untouched',
    'Rollback deleted an unowned staging file'
)
os.remove(foreign_staging)
assert(rmdir(last_stage))
for _, output in ipairs(published) do
    for _, name in ipairs(output.filenames) do
        assert(os.remove(output.folder .. '/' .. name))
    end
    assert(rmdir(output.folder))
end
assert(rmdir(root))
print(
    'PASS bulk DDS: 4096 bindings, 129 unique IDs, five naming formats, exact HDR/signed-zero pixels, deterministic dedup/collisions and owned rollback'
)
