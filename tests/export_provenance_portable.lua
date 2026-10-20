-- Composition must preserve the shared services; legacy raw reads stay lazy.
local chunk = assert(loadfile('src/presets/export_provenance.lua'))
local imports, original_require = 0, require
setfenv(chunk, setmetatable({ require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Native dependency during portable composition')
    imports = imports + 1
    return original_require(name)
end }, { __index = _G }))
local Export = chunk()
local files, platform, expected = {}, {}, {}
local created = 0
local modules = {
    binding_provenance = { new = function() return expected end },
    binding_source_cache = { new = function(services)
        assert(services.file_io == files and services.platform == platform, 'Source cache lost the portable provider')
        created = created + 1
        return {}
    end },
    binding_provenance_script = {}, binding_provenance_reader = {}, binding_unit_layout = {}, binding_names = {},
    unit_identity = { new = function() return {} end }, material_identity = { new = function() return {} end },
    file_io = files, platform = platform,
}
local source = Export.new(modules, { lua_engine = function() return {} end })
assert(source.ensure() == expected and created == 1)
local prior = imports
for _ = 1, 1000 do assert(source.ensure() == expected) end
assert(created == 1 and imports == prior, 'Stable export composition rebuilt its source services')
local reads, bytes = 0, string.char(0, 255, 128, 127, 1, 2, 3, 4)
local snapshot = Export.new({}, { read_snapshot = function(address, size)
    reads = reads + 1
    assert(address == 65536 and size == 8)
    return bytes
end })
assert(snapshot.read(65536, 8) == bytes and reads == 1 and imports == prior,
    'Portable snapshot selected the legacy native fallback')
for _, args in ipairs({ { 1, 8 }, { 65536.5, 8 }, { 65536, 0 }, { 65536, 97 }, { 65536, 1.5 } }) do
    assert(not pcall(snapshot.read, args[1], args[2]) and reads == 1,
        'Invalid snapshot read reached the provider')
end
for _, value in ipairs({ true, {}, 'short', bytes .. 'extra' }) do
    local rejected = Export.new({}, { read_snapshot = function() return value end })
    assert(not pcall(rejected.read, 65536, 8), 'Invalid snapshot result accepted')
end
assert(Export.new({}, { read_snapshot = function() return nil end }).read(65536, 8) == nil)
for _, service in ipairs({ false, true, {} }) do
    assert(not pcall(Export.new({}, { read_snapshot = service }).read, 65536, 8)
        and imports == prior, 'Invalid snapshot service selected a legacy fallback')
end
local legacy_reads = 0
local legacy = Export.new({ legacy_memory = { read = function(memory, address, size)
    legacy_reads = legacy_reads + 1
    assert(memory == expected and address == 65536 and size == 8)
    return bytes
end } }, { memory = expected })
assert(legacy.read(65536, 8) == bytes and legacy_reads == 1 and imports == prior,
    'Explicit legacy boundary was not selected lazily')
print('PASS portable export provenance composition: provider forwarding, cached resolver and lazy legacy memory boundary')
