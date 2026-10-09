-- Exercise the actual sidecar callbacks without a game or native renderer.
local identity = { unit = 1, body = 2, armor = 3, helmet = 4 }
local opens, renders, layouts, zooms = 0, 0, 0, 0
local resources, captures, updates, destroyed = 0, 0, 0, 0
local quiesced = true
local disabled = false
local request
local setup_failure = false
local sync_failure = false
local render_failure = false
local logs = {}
local factories, base_enables, base_disables, base_cleanups = 0, 0, 0, 0
local current_controls
local cleanups = {}
local frame_saves, debug_saves = 0, 0
local a = {
    capture = function()
        captures = captures + 1
        return identity
    end,
    quiesce = function()
        return quiesced
    end,
}
for _, name in ipairs({ 'target', 'world', 'model', 'camera', 'viewport', 'panel' }) do
    a['create_' .. name] = function()
        resources = resources + 1
        if name == 'model' then
            opens = opens + 1
            assert(not setup_failure, 'Unavailable copied model')
        end
        return {}
    end
    a['destroy_' .. name] = function()
        destroyed = destroyed + 1
    end
end
a.render = function()
    renders = renders + 1
    assert(not render_failure, 'UI preview Camera.projection unavailable')
end
a.apply_luts = function()
    assert(not sync_failure, 'Preview garment disappeared')
end
a.zoom = function()
    zooms = zooms + 1
end
a.rotate = function() end
a.layout_panel = function()
    layouts = layouts + 1
end
a.debug_target = function()
    debug_saves = debug_saves + 1
end
local x, y, down, focused = 0, 0, false, true
local original = function()
    return x, y
end
local original_wheel = function()
    return 120
end
local input = {
    mouse = original,
    wheel = original_wheel,
    focused = function()
        return focused
    end,
    down = function()
        return down
    end,
}
local registry =
    { ['dbf.epic_lut.frontend.v1'] = { preview_cleanup_guard = true, menu = { visible = true }, input = input } }
local memory = {
    module = function()
        return 100000
    end,
    address = function(v)
        return v
    end,
}
local env = setmetatable({
    editor = {
        on_enable = function()
            base_enables = base_enables + 1
        end,
        on_update = function()
            updates = updates + 1
        end,
        on_disable = function()
            base_disables = base_disables + 1
            return true
        end,
        on_cleanup_poll = function()
            base_cleanups = base_cleanups + 1
            return true
        end,
    },
    PREVIEW_INSPECT_ONLY = false,
    m = {
        player_preview_controls = dofile('src/preview/player_preview_controls.lua'),
        player_preview_input = dofile('src/preview/player_preview_input.lua'),
        player_preview = dofile('src/preview/player_preview.lua'),
        player_preview_native = {
            new = function(_, _, host)
                factories = factories + 1
                current_controls = host.controls
                return a
            end,
        },
        player_preview_submit = {
            new = function()
                return function() end
            end,
        },
        avatar = {
            resolve = function()
                return identity
            end,
            units = function()
                return { { unit = identity.unit } }
            end,
        },
        bingus_memory = {
            new = function()
                return memory
            end,
        },
        engine = {
            open = function()
                return {}
            end,
        },
    },
    io = {
        open = function(path, mode)
            if mode == 'rb' and request then
                return {
                    read = function()
                        return request
                    end,
                    close = function() end,
                }
            end
            return nil
        end,
    },
    os = {
        getenv = function()
            return 'test'
        end,
        remove = function()
            request = nil
        end,
    },
    package = { loaded = registry },
    stingray = {
        Application = {
            save_render_target = function()
                frame_saves = frame_saves + 1
            end,
        },
        Gui = {
            resolution = function()
                return 1920, 1080
            end,
        },
    },
    render = function() end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile('src/preview/player_preview_candidate.lua'))
setfenv(chunk, env)
local editor = chunk()
local ctx = {
    log = function(line)
        logs[#logs + 1] = line
    end,
    on_cleanup = function(fn)
        cleanups[#cleanups + 1] = fn
    end,
}
request = 'live'
editor.on_enable(ctx)
assert(request == nil and opens == 0 and resources == 0, 'Initialization replayed a stale preview request')
local public = assert(registry['epic.player_preview.v1'])
assert(public.is_enabled(), 'Preview was disabled before the setting registered')
for _, name in ipairs({
    'material_info',
    'material_report',
    'material_masks',
    'set_material_mask',
    'probe_material_mask',
    'reset_material_masks',
    'meshes',
    'set_mesh',
    'reset_meshes',
}) do
    assert(public[name] == nil, 'Preview still exposes inspector API ' .. name)
end
local front = registry['dbf.epic_lut.frontend.v1']
front.api = {
    mods = {
        epic_direct_lut = {
            controls = { disable_player_preview = {} },
            handle = {
                get = function(id)
                    assert(id == 'disable_player_preview')
                    return disabled
                end,
            },
        },
    },
}
front.menu.window_bounds = { x = 10, y = 20, scale = 2 }
disabled = true
assert(not public.is_enabled())
local disabled_updates, disabled_logs = updates, #logs
public.dock({ x = 100, y = 100, w = 180, h = 300 })
request, down = 'open', true
editor.on_update(ctx, 0.25)
editor.on_update(ctx, 0.25)
assert(updates == disabled_updates + 2, 'Disabled preview skipped the editor update')
assert(
    not public.is_docked() and opens == 0 and resources == 0 and captures == 0,
    'Saved disable still opened a dock, handled a key, or captured a model'
)
assert(request == nil, 'Disabled preview retained an open request')
assert(#logs == disabled_logs + 1, 'Disabled preview logged on every frame')
local ok, why = public.toggle()
assert(not ok and why:find('Configuration', 1, true))
assert(resources == 0 and captures == 0, 'Disabled toggle called preview resource APIs')
disabled, down = false, false
assert(public.toggle())
editor.on_update(ctx, 0.1)
env.render()
assert(opens == 1 and renders == 1 and input.mouse ~= original)
input.mouse() -- Release the canceled press from the disabled state.
x, y, down = 40, 660, true
assert(input.mouse() == nil, 'Panel click leaked to editor')
x, y = 80, 700
input.mouse()
assert(layouts == 1)
input.mouse()
assert(layouts == 1, 'Stationary pointer rebuilt GUI')
focused = false
editor.on_update(ctx, 0.1)
focused = true
x, y = 100, 720
input.mouse()
assert(layouts == 1, 'Drag resumed after focus/menu loss')
down = false
input.mouse()
identity.armor = 9
editor.on_update(ctx, 1)
assert(input.mouse == original, 'Rebuild did not release pointer wrapper')
editor.on_update(ctx, 1.1)
assert(opens == 2, 'Equipment change did not rebuild preview')
editor.on_update(ctx, 0.1)
assert(public.toggle() and input.mouse == original, 'Explicit close did not restore pointer')
assert(public.toggle())
sync_failure = true
editor.on_update(ctx, 0.1)
setup_failure = true
for i = 1, 5 do
    editor.on_update(ctx, 1.1)
end
assert(opens == 6, 'Recovery did not stop after three retries')
local count = opens
editor.on_update(ctx, 10)
assert(opens == count)
setup_failure = false
sync_failure = false
registry['dbf.epic_lut.frontend.v1'].menu.window_bounds = { x = 10, y = 20, scale = 2 }
public.dock({ x = 100, y = 100, w = 180, h = 300 })
editor.on_update(ctx, 0.01)
assert(opens == 7, 'Editor dock did not open')
assert(public.is_docked(), 'Visible dock did not report its layout reservation')
x, y, down = 250, 250, false
local z = zooms
assert(input.wheel() == 0 and zooms == z + 1, 'Preview wheel zoom leaked to page')
x, y = 0, 0
assert(input.wheel() == 120, 'Preview consumed wheel outside its bounds')
assert(public.toggle())
editor.on_update(ctx, 0.01)
assert(opens == 8, 'Pop Out did not reopen at floating geometry')
assert(not public.is_docked(), 'Floating preview retained a dock width reservation')
assert(public.toggle())
editor.on_update(ctx, 0.01)
assert(opens == 8, 'Dock Back rebuilt the owned model unnecessarily')
registry['dbf.epic_lut.frontend.v1'].menu.visible = false
editor.on_update(ctx, 0.01)
assert(
    input.mouse == original and input.wheel == original_wheel,
    'Closing editor retained preview input/render resources'
)
-- Turning off a running portrait must honor the cleanup fence and still let
-- the editor tick. Re-enabling must reuse the public API and create cleanly.
editor.on_update(ctx, 0.25) -- Expire the last editor dock request.
front.menu.visible = true
assert(public.toggle())
editor.on_update(ctx, 0.1)
assert(input.mouse ~= original)
local created_before, destroyed_before, updates_before = resources, destroyed, updates
disabled, quiesced = true, false
editor.on_update(ctx, 0.1)
assert(updates == updates_before + 1)
assert(input.mouse == original and input.wheel == original_wheel, 'Saved disable retained input ownership')
assert(destroyed == destroyed_before, 'Saved disable destroyed resources before the render fence')
assert(not public.is_docked() and not public.is_enabled())
assert(not public.toggle() and resources == created_before, 'Disabled toggle reopened a retiring portrait')
quiesced = true
editor.on_update(ctx, 0.1)
assert(destroyed == destroyed_before + 6, 'Disabled preview failed to finish ordinary cleanup')
disabled = false
assert(public.is_enabled() and public.toggle(), 'Preview could not re-enable after saved disable')
editor.on_update(ctx, 0.1)
assert(input.mouse ~= original)
-- A permanent render failure closes through the fence and latches until an
-- explicit retry. Repeated dock requests must not allocate/reopen each frame.
assert(public.before_editor_close())
public.dock({ x = 100, y = 100, w = 180, h = 300 })
editor.on_update(ctx, 0.11)
local opened_before_failure = opens
render_failure = true
env.render()
assert(public.last_error() and public.last_error():find('Camera.projection unavailable', 1, true))
for i = 1, 120 do
    public.dock({ x = 100, y = 100, w = 180, h = 300 })
    editor.on_update(ctx, 0.01)
    env.render()
end
assert(opens == opened_before_failure, 'Permanent render failure rapidly reopened the dock')
assert(not public.is_ready() and input.mouse == original, 'Failed portrait retained active input')
render_failure = false
assert(public.toggle())
editor.on_update(ctx, 0.11)
env.render()
assert(opens == opened_before_failure + 1 and public.last_error() == nil, 'Explicit retry did not clear render fault')
assert(editor.on_disable() and registry['epic.player_preview.v1'] == nil and input.wheel == original_wheel)
-- Same-instance enable is a fresh activation. Old callbacks cannot close a
-- replacement, and a retiring render fence must prevent its construction.
local old_cleanup, started = cleanups[1], opens
request = 'live'
editor.on_enable(ctx)
assert(request == nil and public == registry['epic.player_preview.v1'])
editor.on_update(ctx, 0.3)
assert(opens == started and not public.is_docked() and public.last_error() == nil, 'Stale dock/fault reopened preview')
assert(current_controls.x == 32 and current_controls.y == 150 and current_controls.fov == 30)
assert(current_controls.yaw == 0 and current_controls.pan_y == 0)
assert(public.toggle())
editor.on_update(ctx, 0.1)
local render_hook, destroyed_at_open = env.render, destroyed
assert(
    old_cleanup() and public.is_ready() and env.render == render_hook and destroyed == destroyed_at_open,
    'An old activation cleanup closed the replacement'
)
request = 'once'
editor.on_update(ctx, 0.3)
env.render()
current_controls.x, current_controls.y, current_controls.yaw = 800, 900, 180
current_controls.fov, current_controls.pan_y = 65, 1
public.dock({ x = 100, y = 100, w = 180, h = 300 })
request = 'debug'
editor.on_update(ctx, 0.25) -- Leave a capture queued without running render.
quiesced = false
local old_controls, factory_count, enabled_count = current_controls, factories, base_enables
local live_resources, retired = resources, destroyed
assert(editor.on_disable() == false and registry['epic.player_preview.v1'] == public)
request = 'live'
assert(not pcall(editor.on_enable, ctx), 'Re-enable replaced a retiring preview controller')
assert(request == nil and factories == factory_count and base_enables == enabled_count)
assert(resources == live_resources and destroyed == retired and current_controls == old_controls)
quiesced = true
assert(editor.on_cleanup_poll() and destroyed == retired + 6 and registry['epic.player_preview.v1'] == nil)
editor.on_enable(ctx)
editor.on_update(ctx, 0.3)
assert(factories == factory_count + 1 and opens == started + 1, 'Initialization retained a pending dock/request')
assert(current_controls.x == 32 and current_controls.y == 150 and current_controls.fov == 30)
assert(current_controls.yaw == 0 and current_controls.pan_x == 0 and current_controls.pan_y == 0)
assert(public.toggle())
local draws = renders
editor.on_update(ctx, 0.1)
env.render()
editor.on_update(ctx, 0.1)
env.render()
assert(renders == draws + 2, 'The old single-frame flag survived re-enable')
assert(frame_saves == 0 and debug_saves == 0, 'Initialization retained a pending capture')
render_failure = true
editor.on_update(ctx, 0.1)
env.render()
assert(public.last_error())
assert(editor.on_disable())
render_failure = false
editor.on_enable(ctx)
editor.on_update(ctx, 0.3)
assert(public.last_error() == nil and not public.is_ready(), 'Initialization retained a render fault')
assert(editor.on_disable())
-- Foreign wrappers may retain old functions. Their old callbacks become
-- inert instead of operating on the newer activation's controller.
editor.on_enable(ctx)
assert(public.toggle())
editor.on_update(ctx, 0.1)
local held_render, held_mouse = env.render, input.mouse
env.render = function(...)
    return held_render(...)
end
input.mouse = function(...)
    return held_mouse(...)
end
assert(editor.on_disable())
editor.on_enable(ctx)
assert(public.toggle())
editor.on_update(ctx, 0.1)
local draw_count = renders
held_render()
assert(renders == draw_count, 'A retained old render wrapper submitted the new controller')
x, y, down = 40, 180, true
assert(held_mouse() == x, 'A retained old input wrapper consumed the new activation pointer')
down = false
env.render()
assert(renders == draw_count + 1)
assert(editor.on_disable())
-- A second owner is neither stopped nor overwritten, including failed-enable
-- cleanup. Its request belongs to that active owner too.
local foreign = {
    before_editor_close = function()
        error('Foreign preview was stopped')
    end,
}
registry['epic.player_preview.v1'] = foreign
request = 'live'
factory_count, enabled_count = factories, base_enables
local disabled_count = base_disables
assert(not pcall(editor.on_enable, ctx) and registry['epic.player_preview.v1'] == foreign)
assert(request == 'live' and factories == factory_count and base_enables == enabled_count)
assert(editor.on_disable() and registry['epic.player_preview.v1'] == foreign and base_disables == disabled_count)
print(
    'PASS actual sidecar equipment rebuild, retry cap, saved disable, cleanup fence, pointer restoration and public lifecycle'
)
