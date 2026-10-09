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
document.data[0] = 0 / 0
assert(not pcall(P.encode, D, document, original), 'Nonfinite pixels exported')
document.data[0] = -2
-- Filesystem transaction: publish only a complete triplet; no overwrite or partial output.
local root = os.getenv('EPIC_LUT_TEST_ROOT') .. '/tests/tmp/patch-export'
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
local exporter = P.new(root, { dds = D, directory_exists = exists, mkdir_new = mkdir, rmdir = rmdir })
local destination, resource, zip_path = exporter.save(name, document, original)
assert(resource == original.resource and zip_path == destination .. '/' .. name .. '.zip')
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
assert(not pcall(exporter.save, name, document, original), 'Existing export overwritten')
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
