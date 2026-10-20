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
print('PASS portable export provenance composition: provider forwarding, cached resolver and lazy legacy memory boundary')
