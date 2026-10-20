-- Real bootstrap and public LLL project/config; native effects are explicit.
assert(_VERSION == 'Lua 5.1')
local previous_require = require
ffi, bit, jit = nil, nil, nil
require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
    return previous_require(name)
end
local Runtime = dofile('src/platform/runtime_services.lua')
local Store = dofile('src/platform/loader_store.lua')
local noop_model, noop_ctx = {}, {}
local noop = Runtime.start(noop_model, noop_ctx)
assert(noop.ready and not noop.platform and not noop.storage and not noop.owned_platform)
assert(not noop.close(false) and noop.close(true) and noop.close(true))
assert(Runtime.start(noop_model, noop_ctx).close(true), 'Closed no-op lease prevented restart')
local borrowed_closes = 0
local borrowed = { close = function() borrowed_closes = borrowed_closes + 1;error('Borrowed owner closed') end }
local storage = { load = function() return {} end, save = function() return true end }
local model, ctx = { storage = storage }, { platform = borrowed }
local lease = Runtime.start(model, ctx)
assert(lease.ready and lease.platform == borrowed and lease.storage == storage)
assert(model.platform == borrowed and ctx.storage == storage and not lease.owned_platform and not lease.owned_storage)
assert(not pcall(Runtime.start, model, ctx), 'Duplicate owner was silently borrowed')
local replacement = {}
model.platform = replacement
assert(lease.close(true) and borrowed_closes == 0)
assert(model.platform == replacement and ctx.platform == borrowed and model.storage == storage and ctx.storage == nil)
local left, right = {}, {}
assert(not pcall(Runtime.start, { platform = left }, { platform = right }), 'Conflicting platforms were overwritten')
assert(not pcall(Runtime.start, { storage = storage }, { storage = { load = storage.load, save = storage.save } }),
    'Conflicting stores were overwritten')
local starts, closes, close_ready, close_throw = 0, 0, true, false
local created
local factory = { new = function(options)
    starts = starts + 1
    assert(options.library == 'C:/private package/platform-fingerprint.dll')
    created = { close = function()
        closes = closes + 1
        if close_throw then error('native cleanup failed', 0) end
        return close_ready, 'native cleanup pending'
    end }
    return created
end }
local function owner()
    return { native_platform_name = 'platform-fingerprint.dll', native_platform = factory, loader_store = Store }
end
model, ctx = owner(), { dir = 'C:/private package', storage = storage }
lease = Runtime.start(model, ctx)
assert(lease.ready and lease.owned_platform and not lease.owned_storage and starts == 1 and closes == 0)
for _ = 1, 1000 do assert(not lease.close(false)) end
assert(closes == 0 and model.platform == created, 'Pending consumer cleanup retired or polled its platform')
close_ready = false
assert(not lease.close(true) and closes == 1 and ctx.platform == created)
close_ready, close_throw = true, true
assert(not lease.close(true) and closes == 2 and model.platform == created)
close_throw = false
assert(lease.close(true) and closes == 3 and model.platform == nil and ctx.platform == nil)
assert(ctx.storage == storage and model.storage == nil)
local future = { version = 999, stores = {} }
model, ctx = owner(), { dir = 'C:/private package', config = { epic_lut_ui = future }, set = function() error('Unexpected save') end }
local before = closes
assert(not pcall(Runtime.start, model, ctx))
assert(closes == before + 1 and model.platform == nil and ctx.platform == nil and ctx.config.epic_lut_ui == future,
    'Failed storage construction did not roll back its new native owner')
close_ready = false
local failed, why = Runtime.start(model, ctx)
assert(failed.ready == false and why:find('cleanup pending', 1, true) and model.platform == failed.platform)
assert(failed.owned_platform and failed.storage == nil and not pcall(Runtime.start, model, ctx))
assert(not failed.close(false) and not failed.close(true) and ctx.platform == failed.platform)
close_ready = true
assert(failed.close(true) and model.platform == nil and ctx.platform == nil)
model.native_platform_name = '../unsafe.dll'
before = starts
assert(not pcall(Runtime.start, model, ctx) and starts == before and model.platform == nil)
model.native_platform_name = 'platform-fingerprint.dll'
model.native_platform = { new = function() error('Constructor failed before returning an owner', 0) end }
assert(not pcall(Runtime.start, model, ctx) and model.platform == nil and ctx.platform == nil)
model.native_platform = factory
ctx.storage = storage
assert(Runtime.start(model, ctx).close(true), 'Failed constructor stranded a shared bootstrap owner')
local invalid_created = {}
model.native_platform = { new = function() return invalid_created end }
failed, why = Runtime.start(model, ctx)
assert(not failed.ready and failed.owned_platform and failed.platform == invalid_created
    and why:find('Invalid created platform', 1, true), 'Invalid created owner was silently forgotten')
invalid_created.close = function() return true end
assert(failed.close(true) and model.platform == nil and ctx.platform == nil)

local root = os.getenv('EPIC_LLL_TEST_ROOT')
    or assert(os.getenv('USERPROFILE')) .. '/OneDrive/Documents/GitHub/DBF-Suite/LLL'
LLL_METADATA, LLL_CONFIG = dofile(root .. '/src/metadata.lua'), dofile(root .. '/src/config.lua')
local Project = dofile(root .. '/src/project.lua')
local disk = { ['mod/main.lua'] = 'return mod', ['mod/config/defaults.cfg'] = '{"unrelated":{"enabled":true}}' }
local writes = 0
local host_platform = { native_ffi = false, settings = 'settings',
    read = function(path, limit) local bytes = disk[path];return bytes and #bytes <= limit and bytes or nil end,
    write = function(path, bytes) writes = writes + 1;disk[path] = bytes;return true end,
    mkdir = function() return true end }
local entry, spec = { id = 'runtime_services', dir = 'mod' }, { entry = 'main.lua', defaults = 'config/defaults.cfg', modules = {} }
local function restart()
    return Project.instantiate(host_platform, entry, Project.snapshot(host_platform, entry, spec), function() end)
end
local host = restart()
host.platform = borrowed
model = { loader_store = Store }
before = writes
lease = Runtime.start(model, host)
assert(lease.ready and lease.platform == borrowed and lease.owned_storage and not lease.owned_platform)
assert(model.storage == host.storage and writes == before, 'Bootstrap persisted defaults instead of selecting the actual loader store')
assert(lease.storage.save('epic_lut_preferences', { ui_scale = 115 }))
assert(host.config.unrelated.enabled and host.config.epic_lut_ui.stores.epic_lut_preferences.ui_scale == 115)
before = writes
assert(lease.storage.save('epic_lut_preferences', { ui_scale = 115 }) and writes == before)
assert(lease.close(true) and borrowed_closes == 0 and model.storage == nil and host.storage == nil)
host = restart()
lease = Runtime.start({ loader_store = Store }, host)
assert(lease.ready and lease.storage.load('epic_lut_preferences').ui_scale == 115 and host.config.unrelated.enabled)
assert(lease.close(true))
local legacy = { loader_host = host, loader_store = Store }
lease = Runtime.start(legacy, {})
assert(lease.ready and lease.storage == nil and lease.platform == nil, 'Loader metadata silently migrated legacy settings')
assert(lease.close(true))
legacy.use_loader_storage = true
lease = Runtime.start(legacy, {})
assert(lease.ready and lease.owned_storage and lease.storage.load('epic_lut_preferences').ui_scale == 115)
assert(lease.close(true))
model = { loader_host = host, loader_store = Store }
local mdl_ctx = { dir = 'mod', platform = borrowed }
lease = Runtime.start(model, mdl_ctx)
assert(lease.ready and lease.owned_storage and mdl_ctx.storage == model.storage and host.storage == nil,
    'MDL context did not select the separate actual public loader host')
assert(lease.storage.load('epic_lut_preferences').ui_scale == 115 and lease.close(true) and borrowed_closes == 0)
require = previous_require
print('PASS runtime services: actual LLL config restart, same selected scopes, owned/borrowed cleanup, pending leases, constructor rollback, conflict rejection and no idle work')
