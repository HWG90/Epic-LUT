local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local P = dofile('src/presets/patch_export.lua')
local function u(s, at)
    local a, b, c, d = s:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local document = { width = 23, height = 2, data = ffi.new('float[?]', 23 * 2 * 4) }
for i = 0, 23 * 2 * 4 - 1 do
    document.data[i] = i / 17 - 2
end
local original = {
    width = 23,
    height = 2,
    resource = 'fedcba9876543210',
    patch_source = '0123456789abcdef\n'
        .. '\x12\x34\x56\x78'
        .. string.rep('\x7f', 188)
        .. D.encode(document.data, 23, 2):sub(1, 148),
}
local p = P.encode(D, document, original)
assert(p.archive == '9ba626afa44a3aa3' and p.resource == original.resource)
assert(p.source_archive == '0123456789abcdef', 'Source archive provenance lost')
-- Duplicate texture occurrences must not redirect the output to a prop/tutorial package.
local other = {}
for key, value in pairs(original) do
    other[key] = value
end
other.patch_source = '09985dc611a3a8b6' .. original.patch_source:sub(17)
local alternate = P.encode(D, document, other)
assert(alternate.archive == p.archive and alternate.source_archive == '09985dc611a3a8b6')
assert(
    alternate.main == p.main and alternate.gpu == p.gpu and P.zip(alternate) == P.zip(p),
    'Snapshot discovery order changed exported patch destination or payload'
)
assert(#p.main == 524 and #p.gpu == 23 * 2 * 16 and p.stream == '')
assert(u(p.main, 0) == 0xf0000011 and u(p.main, 4) == 1 and u(p.main, 8) == 1)
assert(p.main:sub(105, 112) == '\x10\x32\x54\x76\x98\xba\xdc\xfe', '64-bit resource ID lost precision')
assert(p.main:sub(113, 120) == '\x32\x9e\xc6\xa0\xc6\x38\x42\xcd')
assert(u(p.main, 120) == 184 and u(p.main, 160) == 340 and u(p.main, 164) == 0 and u(p.main, 168) == #p.gpu)
assert(u(p.main, 176) == 64 and u(p.main, 180) == 1)
local main = p.main:sub(185)
assert(main:sub(1, 4) == '\x12\x34\x56\x78' and u(main, 4) == 0 and u(main, 8) == 4294967295)
assert(main:sub(13, 192) == string.rep('\0', 180), 'Stale stream/mip offsets retained')
local pixels, w, h = D.decode(main:sub(193) .. p.gpu)
assert(w == 23 and h == 2 and ffi.string(pixels, #p.gpu) == ffi.string(document.data, #p.gpu))
assert(not pcall(P.encode, D, document, { width = 23, height = 2, resource = original.resource }))
assert(not pcall(P.encode, D, { width = 23, height = 1, data = document.data }, original))
-- Multi-LUT palette: one TOC, exact IDs, independently aligned GPU ranges, all channels retained.
local items = {}
for i = 1, 10 do
    local pixels = ffi.new('float[?]', 23 * 2 * 4)
    ffi.copy(pixels, document.data, 23 * 2 * 16)
    pixels[0] = i + 0.25
    local orig = {}
    for key, value in pairs(original) do
        orig[key] = value
    end
    orig.resource = string.format('%016x', i)
    items[#items + 1] = { document = { width = 23, height = 2, data = pixels }, original = orig }
end
local batch = P.encode_set(D, items)
assert(batch.count == 10 and u(batch.main, 8) == 10 and u(batch.main, 88) == 10)
for i = 1, 10 do
    local at = 104 + (i - 1) * 80
    assert(u(batch.main, at) == i and u(batch.main, at + 76) == i)
    local body_at, gpu_at, size = u(batch.main, at + 16), u(batch.main, at + 32), u(batch.main, at + 64)
    assert(gpu_at % 64 == 0 and body_at + 340 <= #batch.main and gpu_at + size <= #batch.gpu)
    local data, width, height =
        D.decode(batch.main:sub(body_at + 193, body_at + 340) .. batch.gpu:sub(gpu_at + 1, gpu_at + size))
    assert(width == 23 and height == 2 and ffi.string(data, size) == ffi.string(items[i].document.data, size))
end
local pattern_data = ffi.new('float[12]')
pattern_data[0], pattern_data[3], pattern_data[7] = 0.125, 0.5, 0.75
local pattern_original = {
    width = 3,
    height = 1,
    resource = '0000000000000011',
    patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. D.encode(pattern_data, 3, 1):sub(1, 148),
}
local mixed = {}
for i, item in ipairs(items) do
    mixed[i] = item
end
mixed[#mixed + 1] = { document = { width = 3, height = 1, data = pattern_data }, original = pattern_original }
local combined = P.encode_set(D, mixed)
assert(combined.count == 11 and u(combined.main, 8) == 11)
local last = 104 + 10 * 80
local patbody, patgpu, patsize = u(combined.main, last + 16), u(combined.main, last + 32), u(combined.main, last + 64)
local pat, w, h =
    D.decode(combined.main:sub(patbody + 193, patbody + 340) .. combined.gpu:sub(patgpu + 1, patgpu + patsize))
assert(
    w == 3 and h == 1 and ffi.string(pat, 48) == ffi.string(pattern_data, 48),
    'Pattern LUT lost from mixed palette patch'
)
items[#items + 1] = items[1]
assert(P.encode_set(D, items).count == 10, 'Shared LUT not deduplicated')
local conflict = { document = items[2].document, original = items[1].original }
items[#items + 1] = conflict
assert(not pcall(P.encode_set, D, items), 'Conflicting shared LUT silently overwritten')
assert(not pcall(P.encode_set, D, {}), 'Empty full palette exported')
document.data[0] = 0 / 0
assert(not pcall(P.encode, D, document, original), 'Nonfinite pixels exported')
document.data[0] = -2
-- Filesystem transaction: publish only a complete triplet; no overwrite or partial output.
local root = os.getenv('TEMP')
    .. '/EpicLUT-patch-export-'
    .. tostring(os.time())
    .. '-'
    .. tostring(math.floor(os.clock() * 1000000))
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
kernel.CreateDirectoryW(wide(root), nil)
local function exists(path)
    return os.rename(path, path) ~= nil
end
local function mkdir(path)
    assert(not exists(path))
    assert(kernel.CreateDirectoryW(wide(path), nil) ~= 0)
end
local function rmdir(path)
    assert(kernel.RemoveDirectoryW(wide(path)) ~= 0)
end
local name = 'test-' .. tostring(os.time())
local exporter = P.new(root, {
    available_name = dofile('src/presets/lut_files.lua').available_name,
    dds = D,
    directory_exists = exists,
    mkdir_new = mkdir,
    rmdir = rmdir,
})
local destination, resource, zip_path = exporter.save(name, document, original)
assert(resource == original.resource and zip_path == destination .. '/' .. destination:match('[^/]+$') .. '.zip')
local zip_file = assert(io.open(zip_path, 'rb'))
local zip_bytes = zip_file:read('*a')
zip_file:close()
assert(zip_bytes == P.zip(p) and u(zip_bytes, 0) == 0x04034b50)
local proof = assert(io.open(os.getenv('EPIC_LUT_TEST_ROOT') .. '/tests/tmp/patch-export-proof.zip', 'wb'))
assert(proof:write(zip_bytes))
assert(proof:close())
local files = { '', '.gpu_resources', '.stream' }
for _, suffix in ipairs(files) do
    local f = assert(io.open(destination .. '/' .. p.archive .. '.patch_0' .. suffix, 'rb'))
    local contents = f:read('*a')
    f:close()
    assert(contents == (suffix == '' and p.main or suffix == '.stream' and p.stream or p.gpu))
end
local extra, _, extra_zip = exporter.save(name, document, original)
assert(
    extra ~= destination and extra:match('%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d'),
    'Duplicate patch did not use a timestamp'
)
for _, suffix in ipairs(files) do
    os.remove(extra .. '/' .. p.archive .. '.patch_0' .. suffix)
end
os.remove(extra_zip)
rmdir(extra)
assert(not pcall(exporter.save, '../escape', document, original))
assert(not pcall(exporter.save, 'CON', document, original))
local rename = os.rename
os.rename = function()
    return nil, 'injected publish failure'
end
assert(not pcall(exporter.save, name .. '-fail', document, original))
os.rename = rename
assert(not exists(root .. '/' .. name .. '-fail.pending'), 'Failed transaction left staging directory')
for _, suffix in ipairs(files) do
    os.remove(destination .. '/' .. p.archive .. '.patch_0' .. suffix)
end
os.remove(zip_path)
rmdir(destination)
rmdir(root)
print(
    'PASS patch export: exact 64-bit IDs, native wrapper, float pixel round trip, complete triplet, no overwrite, rollback and malformed-input rejection'
)

local custom_pixels = ffi.new('float[?]', 23 * 32 * 4)
custom_pixels[31 * 23 * 4] = 0.75
local custom_source = {
    width = 23,
    height = 8,
    resource = '1234567890abcdef',
    patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. D.encode(ffi.new('float[736]'), 23, 8):sub(1, 148),
}
local custom_patch = P.encode(D, { width = 23, height = 32, data = custom_pixels }, custom_source)
local custom_data, cw, ch = D.decode(custom_patch.main:sub(377) .. custom_patch.gpu)
assert(cw == 23 and ch == 32 and custom_data[31 * 23 * 4] == 0.75, 'Patch export truncated custom row count')
