-- Production loader project/config + Epic LUT core/preferences/frontend contracts.
assert(_VERSION == 'Lua 5.1')
local prior_require = require
ffi, bit, jit = nil, nil, nil
require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
    return prior_require(name)
end
local root = os.getenv('EPIC_LLL_TEST_ROOT')
    or assert(os.getenv('USERPROFILE')) .. '/OneDrive/Documents/GitHub/DBF-Suite/LLL'
LLL_METADATA = dofile(root .. '/src/metadata.lua')
LLL_CONFIG = dofile(root .. '/src/config.lua')
local Project = dofile(root .. '/src/project.lua')
local Store = dofile('src/platform/loader_store.lua')
local Core = dofile('vendor/menu/core.lua')
local Preferences = dofile('src/platform/preferences.lua')
local Frontend = dofile('src/platform/standalone_frontend.lua')
local disk = { ['mod/main.lua'] = 'return mod', ['mod/config/defaults.cfg'] = '{"unrelated":{"enabled":true}}' }
local writes, reads, fail_write = 0, 0, false
local platform = { native_ffi = false, settings = 'settings' }
function platform.read(path, limit)
    reads = reads + 1
    local bytes = disk[path]
    if bytes and #bytes <= limit then return bytes end
end
function platform.write(path, bytes)
    writes = writes + 1
    if fail_write then return false end
    disk[path] = bytes
    return true
end
function platform.mkdir() return true end
local entry = { id = 'epic_lut', dir = 'mod' }
local spec = { entry = 'main.lua', defaults = 'config/defaults.cfg', modules = {} }
local function restart()
    return Project.instantiate(platform, entry, Project.snapshot(platform, entry, spec), function() end)
end
local host = restart()
local store = Store.new(host)
local before = writes
assert(next(store.load('epic_lut_preferences')) == nil and writes == before, 'Opening new settings persisted defaults')
assert(store.legacy_migration == 'explicit only' and store.source == 'loader-config')
assert(store.save('unrelated_owner', { enabled = true, hue = '#123456' }))
local loaded = store.load('unrelated_owner')
loaded.enabled = false
assert(store.load('unrelated_owner').enabled, 'Caller changed persisted settings through load result')

local frontend = Frontend.new({
    ui_core = Core, ui_menu = dofile('vendor/menu/menu.lua'),
    ui_store = { new = function() error('Portable frontend initialized legacy filesystem store') end },
}, { log = function() end }, {
    storage = store, clipboard = {},
    input = { poll = function() end, focused = function() return true end, window = function() return nil end },
    capture = { release = function() return true end, shutdown = function() return true end },
    view = { measure = function(text, size) return #text * size / 2 end, release = function() end },
    resolution = function() return 1920, 1080 end,
})
local prefs = Preferences.new(store)
local handle = prefs.mount(frontend.resolve())
assert(prefs.save_scale(115) and prefs.scale() == 115)
assert(prefs.save_size(1600, 1000))
assert(frontend.resolve().save_swatch('#aabbcc'))
assert(host.config.unrelated.enabled and host.config[Store.KEY].stores.unrelated_owner.enabled,
    'Preference commit replaced unrelated root/owner values')
before = writes
assert(prefs.save_scale(115) and writes == before, 'Unchanged setting wrote config again')
fail_write = true
assert(not prefs.save_scale(120) and prefs.scale() == 115, 'Failed save published unsaved preference')
assert(host.config[Store.KEY].stores.epic_lut_preferences.ui_scale == 115)
assert(not store.save('invalid', { setting = function() end }))
assert(not store.save('invalid', { setting = 0 / 0 }))
assert(not store.save('../invalid', { enabled = true }))
assert(not store.save('invalid', { setting = string.rep('a', 49) }))
local excessive = {}
for index = 1, 4097 do excessive['key_' .. index] = true end
assert(not store.save('invalid', excessive), 'Unbounded settings map accepted')
fail_write = false
prefs.close()
assert(frontend.close())

host = restart()
store = Store.new(host)
prefs = Preferences.new(store)
prefs.mount(Core.new(store))
assert(prefs.scale() == 115 and prefs.size() == 1600, 'Preferences did not survive actual loader restart')
assert(store.load('mcm_custom_palette').swatch_1 == '#AABBCC')
assert(store.save('epic_lut_labels', { ['1234567890abcdef'] = 'Local name' }))
assert(store.save('epic_lut_labels', {}) and next(store.load('epic_lut_labels')) == nil,
    'Replacement semantics resurrected deleted labels')

local legacy = 'font_size=16\r\nfont_bold=false\r\nui_scale=105\nname=@Custom Palette\ncolor=#aabbcc\n'
local reader_calls = 0
before = writes
assert(store.import_legacy('explicit_legacy', function(id)
    reader_calls = reader_calls + 1
    assert(id == 'explicit_legacy')
    return legacy
end))
assert(reader_calls == 1 and writes == before + 1, 'Explicit import did not use one atomic save')
local migrated = store.load('explicit_legacy')
assert(migrated.font_size == 16 and migrated.font_bold == false and migrated.color == '#AABBCC')
assert(migrated.name == 'Custom Palette' and migrated.ui_scale == 105)
before = writes
assert(not store.import_legacy('explicit_legacy', 'font_size=18\n') and writes == before,
    'Import overwrote existing loader preferences')
assert(not store.import_legacy('duplicate_legacy', 'a=1\na=2\n'))
assert(not store.import_legacy('bad_legacy', 'not a settings line\n'))
assert(not store.import_legacy('bad_legacy', 'name=@illegal!\n'))
assert(not store.import_legacy('bad_legacy', string.rep('a', 65537)))
assert(host.config[Store.KEY].stores.duplicate_legacy == nil and writes == before)
fail_write = true
assert(not store.import_legacy('failed_import', 'ui_scale=125\n'))
assert(host.config[Store.KEY].stores.failed_import == nil, 'Failed import published unsaved settings')
fail_write = false
before = writes
local old_state = host.config[Store.KEY]
host.config[Store.KEY] = { version = 999, stores = {} }
assert(not pcall(Store.new, host), 'Future schema was silently reset')
assert(not store.save('epic_lut_preferences', { ui_scale = 120 }) and writes == before)
host.config[Store.KEY] = { version = 1, stores = { broken = { invalid = {} } } }
assert(not pcall(Store.new, host), 'Damaged schema was silently discarded')
host.config[Store.KEY] = old_state
local r, w = reads, writes
for _ = 1, 1000 do assert(prefs.scale() == 115) end
assert(reads == r and writes == w, 'Unchanged preferences performed host IO')
prefs.close()
print('PASS portable loader settings: actual project restart, production frontend/core preferences, failure atomicity, namespace isolation and explicit legacy bytes')
