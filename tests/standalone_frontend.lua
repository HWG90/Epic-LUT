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
-- Initialized-but-closed gameplay frames retain input handling without font/GUI work.
f.tick(0.01)
local idle_draws,idle_releases=draws,cleared
local font_refreshes,hidden_compositions=0,0
local old_refresh_font,old_compose=view.refresh_font,f.menu.compose
view.refresh_font=function()font_refreshes=font_refreshes+1;return false end
f.menu.compose=function(...)hidden_compositions=hidden_compositions+1;return old_compose(...)end
for frame=1,6000 do f.tick(1/120)end
assert(draws==idle_draws and cleared==idle_releases and font_refreshes==0 and hidden_compositions==0,
    'Closed Epic LUT must skip font refresh, composition, drawing and repeated GUI release')
f.menu.compose=old_compose
assert(f.open_advanced());f.tick(.01)
assert(font_refreshes>0 and draws>idle_draws,'Reopen must resume fonts and rendering')
view.refresh_font=old_refresh_font
assert(f.dismiss())
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
-- Exercise the real capture implementation: a native release or window restore
-- must finish before returning the pinned Photo provider's lease.
local real_capture = dofile('vendor/menu/capture.lua')
local function handoff_fixture()
    local s = {
        keys = {},
        focused = true,
        native = false,
        acquired = 0,
        released = 0,
        flags = { focus = true, cursor = false, clip = true },
    }
    local native = {
        mcm_install = function()
            return 1
        end,
        mcm_set_cursor_mode = function()
            return 1
        end,
        mcm_capture = function()
            s.native = true
            return 1
        end,
        mcm_captured = function()
            return s.native and 1 or 0
        end,
        mcm_release = function()
            if not s.native_pending then
                s.native = false
            end
        end,
    }
    local window = {}
    for name, field in pairs({ mouse_focus = 'focus', show_cursor = 'cursor', clip_cursor = 'clip' }) do
        window[name] = function()
            return s.flags[field]
        end
    end
    for name, field in pairs({ set_mouse_focus = 'focus', set_show_cursor = 'cursor', set_clip_cursor = 'clip' }) do
        window[name] = function(value)
            if s.restore_pending and field == 'focus' and value == true then
                return false
            end
            s.flags[field] = value
            return true
        end
    end
    local c = real_capture.new(native, window, function() end)
    local v = {
        measure = view.measure,
        clear = function() end,
        release = function()
            return true
        end,
        draw = function()
            if s.draw_error then
                error('draw failed')
            end
        end,
    }
    local i = {
        poll = function() end,
        focused = function()
            return s.focused
        end,
        window = function()
            return 1
        end,
        down = function(key)
            return s.keys[key] == true
        end,
        wheel = function()
            return 0
        end,
        mouse = function() end,
    }
    s.front = F.new(m, {
        settings_dir = 'tests/tmp',
        log = function(message)
            s.log = message
        end,
    }, {
        input = i,
        capture = c,
        view = v,
        resolution = function()
            return 1920, 1080
        end,
    })
    s.front
        .resolve()
        .register({ id = 'handoff', name = 'Editor', pages = { { id = 'colors', name = 'Colors', controls = {} } } })
    s.front.default_mod_id = 'handoff'
    s.capture = c
    function s.provider()
        return {
            acquire = function(owner)
                assert(
                    owner == 'Epic LUT' and not c.active and not s.native and s.flags.focus,
                    'Photo handoff preceded editor native restoration'
                )
                s.acquired = s.acquired + 1
                if s.acquire_error then
                    error('Photo acquire failed')
                end
                if s.acquire_pending then
                    return false, 'Photo acquire pending'
                end
                s.lent = true
                return true
            end,
            release = function(owner)
                assert(
                    owner == 'Epic LUT' and not c.active and not s.native and s.flags.focus,
                    'Photo resumed before native capture and cursor readback'
                )
                s.released = s.released + 1
                if s.release_error then
                    error('Photo release failed')
                end
                if s.release_pending then
                    return false, 'Photo release pending'
                end
                if s.release_nil then
                    return nil
                end
                s.lent = false
                return true
            end,
        }
    end
    return s
end
do
    local s = handoff_fixture()
    local photo = s.provider()
    _G.DBF_PHOTO_EDITOR_INPUT = photo
    s.front.open_advanced()
    s.front.tick(0.1)
    s.front.tick(0.1)
    assert(
        s.front.is_open() and s.capture.active and s.acquired == 1,
        'Held editor lease was reacquired instead of retained: ' .. tostring(s.log)
    )
    s.native_pending = true
    assert(
        s.front.recover_input() == false and s.released == 0 and s.front.photo_input_bridge == photo,
        'Native release failure lost the Photo provider'
    )
    s.native_pending = false
    s.restore_pending = true
    assert(
        s.front.recover_input() == false and s.released == 0 and s.capture.status().pending_restore,
        'Window readback failure released Photo early'
    )
    s.restore_pending = false
    s.release_pending = true
    assert(s.front.recover_input() == false and not s.native and s.front.input_status().photo_borrowed)
    s.front.tick(0.1)
    assert(
        s.front.photo_input_bridge == photo and s.acquired == 1 and s.front.input_status().pending_restore,
        'Pending Photo acknowledgment was forgotten'
    )
    s.release_pending = false
    s.release_nil = true
    assert(
        s.front.recover_input() == false and s.front.photo_input_bridge == photo,
        'Nil Photo release acknowledgment was accepted'
    )
    s.release_nil = false
    s.focused = false
    assert(
        s.front.recover_input() and not s.lent and not s.front.input_status().pending_restore,
        'Input recovery unnecessarily waited for GUI focus'
    )
    s.focused = true
    assert(s.front.close())
end
do
    local s = handoff_fixture()
    local first = s.provider()
    _G.DBF_PHOTO_EDITOR_INPUT = first
    s.front.open_advanced()
    s.front.tick(0.1)
    local second_acquires = 0
    local second = {
        acquire = function()
            second_acquires = second_acquires + 1
            return true
        end,
        release = function()
            return true
        end,
    }
    s.release_pending = true
    _G.DBF_PHOTO_EDITOR_INPUT = second
    s.front.tick(0.1)
    assert(
        s.front.photo_input_bridge == first and not s.capture.active and second_acquires == 0,
        'Replacement overwrote the original provider before acknowledgment'
    )
    s.release_pending = false
    s.front.tick(0.1)
    assert(
        s.front.photo_input_bridge == second and s.capture.active and second_acquires == 1 and s.front.is_open(),
        'Provider replacement lost the open composition'
    )
    assert(s.front.close())
end
do
    local s = handoff_fixture()
    local photo = s.provider()
    _G.DBF_PHOTO_EDITOR_INPUT = photo
    s.front.open_advanced()
    s.front.tick(0.1)
    local replaced = 0
    photo.release = function()
        replaced = replaced + 1
        return true
    end
    s.front.tick(0.1)
    assert(
        s.released == 1 and replaced == 0 and s.acquired == 2,
        'Mutated provider bypassed its captured original release function'
    )
    assert(s.front.close() and replaced == 1)
end
do
    local s = handoff_fixture()
    _G.DBF_PHOTO_EDITOR_INPUT = nil
    s.front.open_advanced()
    s.front.tick(0.1)
    assert(s.capture.active)
    local photo = s.provider()
    _G.DBF_PHOTO_EDITOR_INPUT = photo
    s.front.tick(0.1)
    assert(
        s.acquired == 1 and s.capture.active and s.front.is_open(),
        'Late Photo provider could not transfer an already-open editor safely'
    )
    _G.DBF_PHOTO_EDITOR_INPUT = nil
    s.front.tick(0.1)
    assert(
        s.released == 1 and not s.front.photo_input_bridge and s.capture.active,
        'Removed global provider orphaned its saved lease'
    )
    assert(s.front.close())
end
do
    local s = handoff_fixture()
    local photo = s.provider()
    _G.DBF_PHOTO_EDITOR_INPUT = photo
    s.acquire_pending = true
    s.front.open_advanced()
    s.front.tick(0.1)
    assert(not s.native and not s.capture.active and not s.front.photo_input_bridge)
    s.acquire_pending = false
    s.acquire_error = true
    s.front.tick(0.1)
    assert(not s.native and s.front.menu.notice:find('Photo acquire failed', 1, true))
    s.acquire_error = false
    s.release_error = true
    s.draw_error = true
    s.front.tick(0.1)
    assert(
        not s.front.is_open()
            and not s.native
            and s.front.photo_input_bridge == photo
            and s.front.input_status().pending_restore,
        'Draw error dropped pending Photo cleanup'
    )
    s.draw_error = false
    s.release_error = false
    s.front.tick(0.1)
    assert(
        not s.front.photo_input_bridge and not s.front.input_status().pending_restore and not s.lent,
        'Error cleanup did not retry on subsequent ticks'
    )
    assert(s.front.close())
end
do
    local s = handoff_fixture()
    _G.DBF_PHOTO_EDITOR_INPUT = nil
    local token = assert(s.capture.acquire('foreign preview'))
    local focus = s.flags.focus
    assert(
        s.front.recover_input() == false and s.capture.owns(token) and s.flags.focus == focus,
        'Recovery forced flags across a foreign capture owner'
    )
    assert(s.capture.release(token))
    assert(s.front.recover_input())
    assert(s.front.close())
end
for _, key in ipairs({ 121, 120 }) do
    local s = handoff_fixture()
    _G.DBF_PHOTO_EDITOR_INPUT = nil
    s.front.resolve().mods.handoff.pages[#s.front.resolve().mods.handoff.pages + 1] = {
        id = 'basic',
        name = 'Basic',
        controls = {},
        actions = {},
        pending = {},
        require_confirmation = false,
        render_layout = function() end,
    }
    s.front.tick(0.01) -- Match recovery running before the normal editor tick.
    s.keys[17], s.keys[16], s.keys[key] = true, true, true
    assert(s.front.recover_input())
    s.front.tick(0.01)
    s.front.tick(0.01)
    assert(not s.front.is_open() and not s.capture.active, 'Held recovery chord reopened the editor')
    assert(s.front.recover_input())
    s.front.tick(0.01)
    assert(not s.front.is_open(), 'Repeated recovery replayed its held opener')
    s.keys[key] = false
    s.front.tick(0.01)
    s.keys[17], s.keys[16] = false, false
    s.keys[key] = true
    s.front.tick(0.01)
    assert(
        s.front.is_open() and (key ~= 120 or s.front.basic_mode),
        'Fresh shortcut did not reopen after recovery key release: ' .. key .. ' ' .. tostring(s.log)
    )
    assert(s.front.close())
end
_G.DBF_PHOTO_EDITOR_INPUT = prior_photo
print(
    'PASS standalone frontend: shared Basic minimum, Advanced size preservation, independent UI dismissal, pending/failed preview retirement, reopening and retryable cleanup'
)
