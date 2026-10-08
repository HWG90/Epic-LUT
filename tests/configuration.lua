local C = dofile('src/configuration.lua')
local stored = { menu_key = 121, font_size = 12 }
local saved
local owner = {
    id = 'preferences',
    controls = {
        menu_key = { id = 'menu_key', type = 'keybind', label = 'Open Advanced' },
        font_size = { id = 'font_size', type = 'slider', label = 'Font size' },
    },
    handle = {
        get = function(id)
            return stored[id]
        end,
        set = function(id, value)
            stored[id] = value
            return true
        end,
    },
}
local prefs = {
    mount = function() end,
    auto_updates = function()
        return false
    end,
    save_auto_updates = function(value)
        saved = value
    end,
}
local action_calls = 0
local refresh_calls = 0
local pages = { { controls = {} }, { controls = { { id = 'load', type = 'button' } } } }
local editor_action = { id = 'undo', type = 'button' }
C.append(pages, { { id = 'colors', controls = {} }, { id = 'save', controls = { editor_action } } }, {
    api = { mods = { epic_lut_preferences = owner } },
    preferences = prefs,
    resource_changed = function()
        refresh_calls = refresh_calls + 1
    end,
    updates = {
        status = 'Ready',
        check = function()
            return 'Checked'
        end,
        open = function()
            return 'Opened'
        end,
    },
    action = function(fn)
        action_calls = action_calls + 1
        return fn()
    end,
    message = function(value)
        return value
    end,
})
assert(pages[1].controls[1] == editor_action, 'Editor action was discarded')
local page = pages[3]
assert(page.name == 'Configuration')
local controls = {}
for _, c in ipairs(page.controls) do
    controls[c.id] = c
end
assert(controls.configuration_menu_key.default == 121)
controls.configuration_menu_key.on_change(45)
controls.configuration_font_size.on_change(14)
assert(stored.menu_key == 45 and stored.font_size == 14, 'Configuration writes missed authoritative preference store')
assert(owner.controls.menu_key.id == 'menu_key', 'Preference definition mutated by aliasing')
assert(controls.manual_fallback.children[1].id == 'load', 'Manual fallback lost')
assert(controls.check_updates.on_activate() == 'Checked' and action_calls == 1)
controls.resource_format.on_change()
assert(refresh_calls == 1)
controls.auto_updates.on_change(true)
assert(saved == true)
print('PASS configuration: authoritative preferences, preserved editor actions, fallback and update routing')
