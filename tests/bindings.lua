local B = dofile('src/bindings.lua')
local P = dofile('src/preferences.lua')
local Core = dofile('vendor/menu/core.lua')
local Store = dofile('vendor/menu/store.lua')
local prefs = P.new(Store.new('tests/tmp'))
local api = Core.new()
prefs.mount(api)
assert(prefs.handle.set('menu_key', 121))
local visible = false
local editing = false
local focused = true
local physical = false
local native = false
local toggles = 0
local focuses = 0
local registrations = 0
api.is_open = function()
    return visible
end
api.toggle = function()
    visible = not visible
    toggles = toggles + 1
end
api.menu_binding_status = function()
    return { editing = editing }
end
api.focus_page = function()
    visible = true
    focuses = focuses + 1
end
local frontend = { api = api, current_api = api }
local platform = {
    focused = function()
        return focused
    end,
    down = function(key)
        return physical and key == prefs.key()
    end,
    native_editing = function()
        return false
    end,
}
ModBindingsMenu = {
    api = 1,
    version = 3,
    register_binding = function(id, label, slot, options)
        assert(id == 'goose.epic_lut.open_menu' and slot == nil and options.category == 'Epic LUT')
        registrations = registrations + 1
        return true
    end,
    is_down = function()
        return native
    end,
}
local b = B.new({}, frontend, prefs, { log = function() end }, platform)
b.root_id = 'root'
b.tick()
physical = true
native = true
b.tick()
b.tick()
assert(toggles == 1 and registrations == 1, 'Physical/native activation doubled')
editing = true
physical = false
native = false
b.tick()
physical = true
b.tick()
editing = false
b.tick()
assert(toggles == 1, 'Rebind held key replayed')
physical = false
native = false
b.tick()
focused = false
physical = true
b.tick()
focused = true
b.tick()
assert(toggles == 1, 'External held key replayed')
physical = false
b.tick()
frontend.api = {}
physical = true
visible = false
b.tick()
assert(not visible and toggles == 1, 'Epic LUT took over MCM F10')
visible = true
b.tick()
assert(focuses == 1)
assert(prefs.handle.set('menu_key', 119))
physical = false
b.tick()
physical = true
b.tick()
assert(focuses == 2)
local fresh = P.new(Store.new('tests/tmp'))
local other = Core.new()
fresh.mount(other)
assert(fresh.key() == 119, 'Shared preference did not persist across frontend')
assert(fresh.handle.activate('reset_key') and fresh.key() == 121)
b.close()
physical = false
b.tick()
physical = true
b.tick()
assert(focuses == 2, 'Retired binding polled native input')
prefs.close()
fresh.close()
ModBindingsMenu = nil
os.remove('tests/tmp/epic_lut_preferences.ini')
os.remove('tests/tmp/epic_lut_preferences.ini.bak')
print(
    'PASS: documented Bingus registration, one activation for combined sources, typing/focus held-key suppression, MCM F10 ownership, custom focus shortcut, shared saved preference, reset and cleanup'
)
