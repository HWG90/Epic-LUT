local core = dofile('vendor/menu/core.lua')
local menus = dofile('vendor/menu/menu.lua')
local F = dofile('src/platform/standalone_frontend.lua')
local keys, focused = {}, true
local draws, invalidations = 0, 0
local pending = false
local capture = { active = false }
function capture.sync(visible, focus)
    capture.active = visible and focus
    return true
end
function capture.release()
    capture.active = false
    return true
end
function capture.shutdown()
    if pending then
        return false, 'test pending restoration'
    end
    capture.active = false
    return true
end
local input = {
    poll = function() end,
    focused = function()
        return focused
    end,
    window = function()
        return 1
    end,
    down = function(k)
        return keys[k] or false
    end,
    wheel = function()
        return 0
    end,
    mouse = function()
        return nil
    end,
}
local view = {
    measure = function(s, size)
        return #s * size * 0.5
    end,
    draw = function()
        draws = draws + 1
    end,
    invalidate = function()
        invalidations = invalidations + 1
    end,
    release = function() end,
}
local prior = rawget(_G, 'DBFMCM')
_G.DBFMCM = {
    register = function()
        error('External MCM was touched')
    end,
}
local storage = {
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
}
local m = {
    ui_core = core,
    ui_menu = menus,
    ui_grouping = dofile('vendor/menu/grouping.lua'),
    ui_store = {
        new = function()
            return storage
        end,
    },
}
local clipboard = {
    get = function()
        return ''
    end,
    set = function()
        return true
    end,
}
local f = F.new(m, { settings_dir = 'tests/tmp', log = function() end }, {
    clipboard = clipboard,
    input = input,
    capture = capture,
    view = view,
    resolution = function()
        return 1920, 1080
    end,
})
local api = f.resolve()
assert(
    api.clipboard == clipboard and f.menu.clipboard == clipboard and f.clipboard == clipboard,
    'Frontend duplicated clipboard authority'
)
assert(api ~= _G.DBFMCM, 'Standalone frontend adopted MCM')
api.register({
    id = 'test_editor',
    name = 'Epic LUT',
    pages = {
        { id = 'direct', name = 'Import / Apply', controls = {} },
        { id = 'colors', name = 'LUT Editor', controls = {} },
    },
})
api.mods.test_editor.tabs_top = true
f.default_mod_id = 'test_editor'
f.preferences = dofile('src/platform/preferences.lua').new(storage)
local h = api.mods.test_editor.handle
-- Dynamic grid controls may be absent from page.controls, but must stay in mod.controls.
api.mods.test_editor.controls.grid_tool =
    { id = 'grid_tool', type = 'choice', choices = { 'Select', 'Draw' }, page = api.mods.test_editor.pages[2] }
api.mods.test_editor.values.grid_tool = 1
api.mods.test_editor.pages[2].render_layout = function(ui)
    ui.choice('grid_tool', ui.x + 10, ui.y + 40, 200)
end
keys[121] = true
f.tick(0.1)
assert(f.menu.visible, 'F10 did not open standalone editor')
keys[121] = false
f.tick(0.1)
assert(capture.active and f.menu.page == 1 and draws > 0)
assert(api.list()[1] == api.mods.test_editor, 'Standalone registry created a lossy grouping composite')
assert(#api.list() == 1, 'Hidden preferences leaked into standalone navigation')
f.menu.page = 2
local rendered = f.menu.compose(1920, 1080)
local selected = false
for _, c in ipairs(rendered) do
    if c.full_text == 'Select' then
        selected = true
    end
end
assert(selected, 'Hidden preferences caused the live grid-control assertion')
f.menu.page = 2
focused = false
keys[121] = true
f.tick(0.1)
assert(f.menu.visible and not capture.active)
focused = true
f.tick(0.1)
assert(f.menu.visible, 'Focus return replayed F10 and closed the menu')
keys[121] = false
f.tick(0.1)
keys[121] = true
f.tick(0.1)
assert(not f.menu.visible and not capture.active)
keys[121] = false
f.tick(0.1)
keys[121] = true
f.tick(0.1)
assert(f.menu.visible and f.menu.page == 2, 'Reopening forgot the last tab')
f.default_mod_id = 'test_editor'
local basic_page = {
    id = 'basic',
    name = 'Basic',
    controls = {},
    actions = {},
    pending = {},
    require_confirmation = false,
    render_layout = function() end,
}
api.mods.test_editor.pages[#api.mods.test_editor.pages + 1] = basic_page
local advanced_width, advanced_height = 1580, 1020
f.menu.window_width, f.menu.window_height = advanced_width, advanced_height
assert(f.preferences.save_size(advanced_width, advanced_height))
keys[121] = false
f.tick(0.1)
keys[120] = true
f.tick(0.1)
assert(f.menu.visible and f.menu.page == 3 and f.basic_mode, 'F9 did not open Basic')
assert(f.menu.basic_only, 'Basic navigation was not isolated')
assert(
    f.menu.window_width == 1100 and f.menu.window_height == 1000,
    'F9 kept the old Basic height instead of forcing the fallback minimum'
)
assert(f.full_size[1] == advanced_width and f.full_size[2] == advanced_height)
f.menu.key(34, false)
assert(f.menu.page == 3, 'Basic reached full editor through page navigation')
f.tick(0.1)
assert(f.menu.visible, 'Held F9 closed Basic')
keys[120] = false
f.tick(0.1)
keys[120] = true
f.tick(0.1)
assert(not f.menu.visible and f.basic_mode, 'F9 did not close Basic')
local saved_width, saved_height = f.preferences.size()
assert(saved_width == advanced_width and saved_height == advanced_height, 'Closing Basic overwrote Advanced dimensions')
keys[120] = false
f.tick(0.1)
keys[120] = true
f.tick(0.1)
assert(f.menu.visible and f.menu.window_height == 1000)
assert(
    f.full_size[1] == advanced_width and f.full_size[2] == advanced_height,
    'Reopening Basic replaced the remembered Advanced dimensions'
)
keys[120] = false
f.tick(0.1)
keys[121] = true
f.tick(0.1)
assert(f.menu.visible and f.menu.page == 1 and not f.basic_mode, 'F10 did not switch back to full editor')
assert(not f.menu.basic_only, 'Full menu retained Basic navigation')
assert(
    f.menu.window_width == advanced_width and f.menu.window_height == advanced_height,
    'F10 did not restore the original Advanced dimensions'
)
for _, c in ipairs(f.menu.compose(1920, 1080)) do
    assert(c.full_text ~= 'Basic', 'Basic tab leaked into F10 menu')
end
keys[121] = false
f.tick(0.1)
-- Both entry paths use the shared Basic height contract instead of a second literal.
m.basic_view = { minimum_height = 1040 }
assert(f.open_basic() and f.menu.window_width == 1100 and f.menu.window_height == 1040)
f.menu.window_width, f.menu.window_height = 1200, 1060
assert(f.open_basic() and f.menu.window_width == 1100 and f.menu.window_height == 1040)
assert(f.full_size[1] == advanced_width and f.full_size[2] == advanced_height)
assert(f.open_advanced() and f.menu.page == 2 and not f.basic_mode)
assert(f.menu.window_width == advanced_width and f.menu.window_height == advanced_height)
keys[120] = true
f.tick(0.1)
assert(
    f.menu.visible and f.menu.basic_only and f.menu.window_width == 1100 and f.menu.window_height == 1040,
    'F9 did not use the shared Basic minimum height'
)
keys[120] = false
f.tick(0.1)
assert(f.open_advanced())
m.basic_view.minimum_height = 1000
assert(f.menu.window_width == advanced_width and f.menu.window_height == advanced_height)
assert(invalidations > 0, 'Mode APIs did not redraw the resized frontend')
local ready = false
local released = 0
local preview_attempts = 0
local preview_error = false
local prior_release = capture.release
package.loaded['epic.player_preview.v1'] = {
    before_editor_close = function()
        preview_attempts = preview_attempts + 1
        if preview_error then
            error('test preview retirement failure')
        end
        return ready
    end,
}
capture.release = function()
    released = released + 1
    return prior_release()
end
keys[121] = true
f.tick(0.1)
assert(
    not f.menu.visible and not capture.active and released == 1 and f.preview_close_pending,
    'Pending preview cleanup trapped the editor or game input'
)
keys[121] = false
f.tick(0.1)
assert(released == 1 and preview_attempts == 2 and not f.menu.visible, 'Hidden preview cleanup did not retry')
keys[121] = true
f.tick(0.1)
assert(f.menu.visible and f.preview_close_pending, 'Retiring preview prevented reopening the editor')
keys[121] = false
f.tick(0.1)
preview_error = true
keys[27] = true
f.tick(0.1)
assert(not f.menu.visible and not capture.active and released == 2 and f.preview_close_pending)
keys[27] = false
f.tick(0.1)
assert(not f.menu.visible and f.preview_close_pending, 'Cleanup exception reopened the editor')
preview_error = false
ready = true
f.tick(0.1)
assert(not f.menu.visible and not capture.active and released == 2 and not f.preview_close_pending)
capture.release = prior_release
package.loaded['epic.player_preview.v1'] = nil
f.menu.visible = true
f.tick(0.1)
local cleared = 0
view.release = function()
    cleared = cleared + 1
    return true
end
assert(f.open_basic() and f.menu.window_width == 1100 and f.menu.window_height == 1000)
f.tick(0.1)
assert(f.dismiss() and not f.menu.visible and not capture.active and cleared == 1)
saved_width, saved_height = f.preferences.size()
assert(
    saved_width == advanced_width and saved_height == advanced_height,
    'Basic API dismissal saved its temporary dimensions'
)
assert(not f.closed and f.render_ready(), 'UI dismissal closed the frontend needed by native cleanup')
assert(package.loaded['dbf.epic_lut.frontend.v1'] == f, 'UI dismissal discarded its cleanup owner')
-- Photo owns capture until its cooperative release has completed.
local photo_ready, photo_lent = false, false
local prior_photo, prior_sync = rawget(_G, 'DBF_PHOTO_EDITOR_INPUT'), capture.sync
_G.DBF_PHOTO_EDITOR_INPUT = {
    acquire = function(owner)
        assert(owner == 'Epic LUT')
        if not photo_ready then
            return false, 'Photo restoration pending'
        end
        photo_lent = true
        return true
    end,
    release = function(owner)
        assert(owner == 'Epic LUT' and not capture.active, 'Photo resumed before editor input release')
        photo_lent = false
        return true
    end,
}
capture.sync = function(visible, focus)
    if visible and focus then
        assert(photo_lent, 'Editor captured input before Photo yielded')
    end
    return prior_sync(visible, focus)
end
assert(f.open_advanced())
f.tick(0.1)
assert(not capture.active and not photo_lent and f.menu.notice == 'Photo restoration pending')
photo_ready = true
f.tick(0.1)
assert(capture.active and photo_lent)
assert(f.dismiss() and not capture.active and not photo_lent)
capture.sync = prior_sync
_G.DBF_PHOTO_EDITOR_INPUT = prior_photo
assert(f.preferences.preview_key() == 117)
assert(f.preferences.handle.set('preview_key', 45))
assert(f.preferences.preview_key() == 45)
assert(f.open_advanced() and f.menu.window_width == advanced_width and f.menu.window_height == advanced_height)
assert(f.open_basic())
f.tick(0.1)
pending = true
assert(not f.close(), 'Cleanup discarded a pending cursor restoration')
pending = false
assert(f.close())
saved_width, saved_height = f.preferences.size()
assert(
    saved_width == advanced_width and saved_height == advanced_height,
    'Frontend closure saved Basic size over Advanced preferences'
)
assert(package.loaded['dbf.epic_lut.frontend.v1'] == nil)
_G.DBFMCM = prior
print(
    'PASS standalone frontend: shared Basic minimum, Advanced size preservation, independent UI dismissal, pending/failed preview retirement, reopening and retryable cleanup'
)
