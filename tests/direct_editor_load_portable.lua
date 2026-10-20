-- Load the real composition without a native provider, then reject an
-- unsupported legacy build before selecting FFI. This is not game activation.
local imported, paths, reads, engines = 0, 0, 0, 0
local expected_platform, expected_storage
local modules = {
    version = 'portable-contract', export_provenance = { PENDING = 'pending' }, resource_ids = {},
    paths = { new = function(model)
        assert(model.platform == expected_platform and model.storage == expected_storage,
            'Direct Editor created paths before selecting shared runtime services')
        paths = paths + 1
        return { settings = 'fixture', presets = 'fixture', exports = 'fixture' }
    end },
    lut_files = { new = function() return {} end },
    file_io = { read = function() reads = reads + 1; error('Unexpected file read') end },
    bingus_memory = { new = function() return { verify_build = function() return false, 'Unsupported legacy game build' end } end },
    engine = { open = function() engines = engines + 1; error('Unverified engine opened') end },
    runtime_services = dofile('src/platform/runtime_services.lua'),
}
local chunk = assert(loadfile('src/editor/direct_editor.lua'))
setfenv(chunk, setmetatable({ m = modules, require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Native import before verified activation')
    imported = imported + 1
    return require(name)
end }, { __index = _G }))
local descriptor = chunk()
assert(type(descriptor.on_enable) == 'function' and type(descriptor.on_update) == 'function')
assert(paths == 0 and reads == 0 and engines == 0, 'Loading a descriptor performed IO or engine work')
local prior = imported
for _ = 1, 1000 do assert(descriptor.on_cleanup_poll() == true) end
assert(imported == prior and paths == 0 and reads == 0 and engines == 0)
local ok, why = pcall(descriptor.on_enable, { log = function() end })
assert(not ok and tostring(why):find('Unsupported legacy game build', 1, true))
assert(imported == prior and engines == 0 and reads == 0 and paths == 1,
    'Rejected activation imported/called the legacy engine boundary')
assert(descriptor.on_disable() == true)
local closed = 0
expected_platform = { close = function() closed = closed + 1; error('Borrowed platform was closed') end }
expected_storage = { load = function() return {} end, save = function() return true end }
local context = { log = function() end, platform = expected_platform, storage = expected_storage }
ok, why = pcall(descriptor.on_enable, context)
assert(not ok and tostring(why):find('Unsupported legacy game build', 1, true) and paths == 2)
assert(modules.platform == expected_platform and modules.storage == expected_storage,
    'Failed activation lost its cleanup lease')
assert(descriptor.on_disable() == true and closed == 0)
assert(modules.platform == nil and modules.storage == nil and context.platform == expected_platform
    and context.storage == expected_storage, 'Cleanup did not restore only the bootstrap-owned publications')
-- Keep the actual editor cleanup closure and its shared lease alive while a
-- consumer is still canceling an external launch; no native engine is needed.
local function upvalue(name, value, replace)
    for index = 1, 100 do
        local found, current = debug.getupvalue(descriptor.on_disable, index)
        if not found then break end
        if found == name then
            if replace then debug.setupvalue(descriptor.on_disable, index, value) end
            return current
        end
    end
    error('Cleanup fixture seam missing: ' .. name)
end
local original_ready, update_ready, platform_retirements = false, false, 0
upvalue('original_luts', { close = function() return original_ready end }, true)
upvalue('updates', { close = function() return update_ready end }, true)
upvalue('operations').runtime_services = { close = function()
    platform_retirements = platform_retirements + 1; return true
end }
assert(descriptor.on_disable() == false and platform_retirements == 0,
    'Pending original-source launch lost its platform owner')
original_ready = true
assert(descriptor.on_disable() == false and platform_retirements == 0,
    'Pending update launch lost its platform owner')
update_ready = true
assert(descriptor.on_disable() == true and platform_retirements == 1)
upvalue('original_luts', nil, true); upvalue('updates', nil, true)
print('PASS portable Direct Editor descriptor: lazy legacy buffers, cold cleanup and unsupported-build rejection before native imports/calls')
