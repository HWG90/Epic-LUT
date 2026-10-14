local Capture = dofile('vendor/menu/capture.lua')
local flags = { focus = true, cursor = false, clip = false }
local window = {}
for _, pair in ipairs({ { 'mouse_focus', 'focus' }, { 'show_cursor', 'cursor' }, { 'clip_cursor', 'clip' } }) do
    local getter, key = pair[1], pair[2]
    window[getter] = function()
        return flags[key]
    end
    window['set_' .. getter] = function(v)
        flags[key] = v
    end
end
local active, art, changes = 0, 2, 0
local native = {
    mcm_install = function()
        return 1
    end,
    mcm_capture = function(p)
        assert(p == 1)
        active = 1
        return 1
    end,
    mcm_captured = function()
        return active
    end,
    mcm_release = function()
        active = 0
        art = 2
    end,
    mcm_set_cursor_mode = function(m)
        art = m
        changes = changes + 1
        return 1
    end,
}
local c = Capture.new(native, window, function() end)
assert(c.sync(true, true, 1, 'game') and active == 1 and art == 2 and flags.cursor)
assert(c.sync(true, true, 1, 'hardware') and active == 1 and art == 1 and flags.cursor)
assert(c.sync(true, true, 1, 'game') and art == 2 and changes == 3)
assert(c.sync(false, true, 1) and active == 0 and flags.focus and not flags.cursor and not flags.clip)
assert(c.sync(true, true, 1, 'game'))
assert(c.sync(true, false, 1) and flags.focus and not flags.cursor)
local Core = dofile('vendor/menu/core.lua')
local saved = {}
local store = {
    load = function()
        return saved
    end,
    save = function(_, data)
        saved = data
        return true
    end,
}
local api = Core.new(store)
local prefs = dofile('src/platform/preferences.lua').new(store)
local h = prefs.mount(api)
assert(prefs.cursor_mode() == 'game' and prefs.confirm_overwrites())
assert(h.set('cursor_mode', 2))
assert(prefs.cursor_mode() == 'hardware')
assert(h.set('cursor_mode', 1))
assert(prefs.cursor_mode() == 'game')
assert(prefs.save_confirm_overwrites(false))
assert(not prefs.confirm_overwrites())
assert(prefs.save_confirm_overwrites(true))
assert(prefs.confirm_overwrites())
print('PASS hardware artwork switches, native input isolation, restoration and reversible confirmations')
