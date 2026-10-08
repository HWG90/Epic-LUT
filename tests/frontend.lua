local m = {}
for _, name in ipairs({ 'core', 'store', 'menu', 'capture', 'grouping', 'legacy' }) do
    m['ui_' .. name] = dofile('vendor/menu/' .. name .. '.lua')
end
local F = dofile('src/legacy/frontend.lua')
local folder = 'tests/tmp'
local logs = {}
local focused = true
local keys = {}
local captured = false
local releases = 0
local refuse = false
local flags = { focus = true, cursor = false, clip = true }
local fail_capture = false
local native = {
    mcm_install = function()
        return 1
    end,
    mcm_capture = function()
        if fail_capture then
            return 0
        end
        captured = true
        return 1
    end,
    mcm_captured = function()
        return captured and 1 or 0
    end,
    mcm_release = function()
        captured = false
        releases = releases + 1
    end,
}
local window = {
    mouse_focus = function()
        return flags.focus
    end,
    show_cursor = function()
        return flags.cursor
    end,
    clip_cursor = function()
        return flags.clip
    end,
    set_mouse_focus = function(v)
        if refuse then
            return false
        end
        flags.focus = v
    end,
    set_show_cursor = function(v)
        flags.cursor = v
    end,
    set_clip_cursor = function(v)
        flags.clip = v
    end,
}
local capture = m.ui_capture.new(native, window, function() end)
local input = {
    poll = function() end,
    focused = function()
        return focused
    end,
    window = function()
        return focused and 1
    end,
    down = function(code)
        return focused and keys[code] == true
    end,
    mouse = function()
        return nil
    end,
    wheel = function()
        return 0
    end,
}
local view = { draw = function() end, release = function() end }
local ctx = {
    dir = folder,
    log = function(s)
        logs[#logs + 1] = s
    end,
}
DBFMCM = nil
ModOptionsMenu = nil
local f = F.new(m, ctx, {
    folder = folder,
    keep_physical_hotkey = true,
    input = input,
    capture = capture,
    view = view,
    resolution = function()
        return 1920, 1080
    end,
})
local own = f.resolve()
assert(own and not DBFMCM and f.active, 'Fallback required/published MCM')
local state = { revision = 1, mods = {}, options = {}, callbacks = {} }
for _, name in ipairs({ 'Match Your Colors', 'Better Lobby Management', 'Shallow Water Diving' }) do
    state.mods[name] = { order = { { id = name, type = 'toggle', kind = 'toggle', label = name, default = false } } }
    state.options[name] = false
end
ModOptionsMenu = {
    api = 1,
    register_option = function()
        return state
    end,
    get = function(id)
        return state.options[id]
    end,
    set = function(id, value)
        state.options[id] = value
        return true
    end,
}
f.tick(0.016)
local imported = 0
for _, mod in pairs(own.mods) do
    if mod.legacy then
        imported = imported + 1
        assert(mod.name == 'Match Your Colors', 'Unrelated Bingus page leaked into Epic LUT')
    end
end
assert(imported == 1, 'Original Match Your Colors submenu missing')
ModOptionsMenu = nil
f.tick(0.016)
local spec = {
    id = 'frontend_fixture',
    name = 'Epic LUT',
    pages = {
        {
            id = 'general',
            name = 'Quick Load',
            require_confirmation = false,
            controls = { { id = 'enabled', type = 'toggle', label = 'Enabled', default = false } },
        },
    },
}
local h = own.register(spec)
assert(h.set('enabled', true))
f.menu.visible = true
f.tick(0.016)
assert(captured and not flags.focus)
local leaf = own.register({
    id = 'leaf_fixture',
    name = 'Leaf fixture',
    categories = { { id = 'general', name = 'General Settings', style = 'page' } },
    pages = {
        {
            id = 'general_settings',
            name = 'General Settings',
            category = 'general',
            controls = {
                { type = 'text', label = 'Settings' },
            },
        },
    },
})
local navigation = f.menu.navigation(own.mods[leaf.id])
assert(
    #navigation == 1 and navigation[1].kind == 'page' and navigation[1].depth == 0,
    'General Settings remained an expandable branch'
)
local maintained_menu = dofile(assert(os.getenv('MCM_SOURCE_DIR')) .. '/src/menu.lua').new(own)
navigation = maintained_menu.navigation(own.mods[leaf.id])
assert(
    #navigation == 1 and navigation[1].kind == 'page' and navigation[1].depth == 0,
    'Maintained MCM did not expose the direct settings entry'
)
leaf.unregister()
focused = false
keys[121] = true
f.tick(0.016)
assert(f.menu.visible and not captured and flags.focus)
focused = true
f.tick(0.016)
assert(f.menu.visible and captured, 'Held foreign key closed fallback')
focused = false
f.tick(0.016)
fail_capture = true
focused = true
f.tick(0.016)
assert(f.menu.visible and not captured, 'Transient capture failure closed the menu after a picker')
fail_capture = false
f.tick(0.016)
assert(f.menu.visible and captured, 'Menu did not resume after capture became available')
keys[121] = false
f.tick(0.016)
keys[121] = true
f.tick(0.016)
assert(not f.menu.visible and not captured)
keys[121] = false
f.menu.visible = true
f.tick(0.016)
refuse = true
local external = m.ui_core.new(m.ui_store.new(folder), nil, m.ui_grouping)
DBFMCM = external
assert(not f.resolve() and capture.status().pending_restore, 'Failed restore yielded ownership')
refuse = false
assert(f.resolve() == external and not f.active and not captured and flags.focus)
local prior = releases
assert(f.resolve() == external and releases == prior, 'Inactive fallback released another frontend input')
local replacement = external.register(spec)
assert(replacement.get('enabled'), 'Settings namespace changed across frontend switch')
h.unregister()
DBFMCM = nil
assert(f.resolve() == own and f.active)
local again = own.register(spec)
assert(again.get('enabled'))
assert(f.close() and not captured and not package.loaded['dbf.epic_lut.frontend.v1'])
print(
    'PASS: own menu without MCM, shared stored values/specs, absent/present transitions, blur and held-key safety, explicit close, deferred restoration, and no inactive native release'
)
m.diagnostic_registry_only = true
m.ui_menu = {
    new = function()
        error('Registry-only initialized menu controller')
    end,
}
m.ui_capture = {
    new = function()
        error('Registry-only initialized capture')
    end,
}
m.ui_view = {
    new = function()
        error('Registry-only initialized renderer')
    end,
}
local registry = F.new(m, { settings_dir = folder, log = function() end })
local api = registry.resolve()
local handle = api.register(spec)
assert(handle.get('enabled'))
registry.tick(0.016)
assert(not api.is_open())
assert(registry.close())
assert(not package.loaded['dbf.epic_lut.frontend.v1'])
print('PASS registry-only retains registration and persistence without native input or rendering')
m.diagnostic_input_library = true
m.frontend_native_name = 'mcm_input_9bc2033ffbb3.dll'
local native_registry = F.new(
    m,
    { settings_dir = folder, dir = assert(os.getenv('MCM_SOURCE_DIR')) .. '/native/build', log = function() end }
)
assert(native_registry.input_library)
assert(native_registry.resolve().register(spec))
native_registry.tick(0.016)
assert(native_registry.close())
print('PASS registry diagnostic loads actual pinned input DLL and validates symbols without capture or rendering')
m.diagnostic_idle_poll = true
local idle_polls = 0
local polling_registry = F.new(
    m,
    { settings_dir = folder, dir = assert(os.getenv('MCM_SOURCE_DIR')) .. '/native/build', log = function() end },
    { input = {
        poll = function()
            idle_polls = idle_polls + 1
        end,
    } }
)
polling_registry.tick(0.016)
assert(idle_polls == 1)
assert(not polling_registry.resolve().is_open())
assert(polling_registry.close())
print('PASS idle polling diagnostic retains closed registry and performs exactly one passive poll per tick')
m.diagnostic_registry_only = false
m.diagnostic_readonly_menu = true
m.ui_menu = dofile('vendor/menu/menu.lua')
local draws = 0
local passive = F.new(m, { settings_dir = folder, log = function() end }, {
    folder = folder,
    input = input,
    capture = {
        status = function()
            return { pending_restore = false }
        end,
        shutdown = function()
            return true
        end,
        release = function()
            return true
        end,
        sync = function()
            error('Read-only renderer acquired input')
        end,
    },
    view = {
        draw = function(commands)
            assert(#commands > 0)
            draws = draws + 1
        end,
        release = function() end,
    },
    resolution = function()
        return 1920, 1080
    end,
})
passive.resolve().register(spec)
passive.tick(0.016)
assert(draws == 1 and passive.api.is_open())
assert(passive.close())
print('PASS read-only full menu composes and renders without input capture')
m.diagnostic_readonly_menu = false
m.diagnostic_without_binding_adapter = false
m.direct_menu_keys = true
local direct = F.new(m, { settings_dir = folder, log = function() end }, {
    folder = folder,
    input = input,
    capture = capture,
    view = view,
    resolution = function()
        return 1920, 1080
    end,
})
direct.resolve().register(spec)
assert(direct.menu.toggle_key == 121, 'Direct diagnostic lacks its independent F10 path')
local current = direct.api.mods[spec.id]
current.pages[#current.pages + 1] = { id = 'quick_load', name = 'Quick Load', controls = {} }
direct.api.revision = direct.api.revision + 1
direct.default_mod_id = spec.id
focused = true
fail_capture = false
refuse = false
keys = {}
direct.api.open()
direct.tick(0.016)
local opening = direct.api.list()[direct.menu.selected].pages[direct.menu.page]
assert(opening.id == 'quick_load', 'Opening the menu did not select Quick Load')
assert(direct.api.close())
direct.tick(0.016)
direct.menu.page = 1
direct.api.open()
direct.tick(0.016)
assert(
    direct.api.list()[direct.menu.selected].pages[direct.menu.page].id == 'quick_load',
    'Reopening did not select Quick Load'
)
direct.preferences = {
    key = function()
        return 122
    end,
}
direct.tick(0.016)
assert(direct.menu.toggle_key == 122, 'Direct keyboard path ignored the authoritative saved key')
assert(direct.close())
print('PASS direct F10 diagnostic selects existing menu hotkey without separate binding adapter')
