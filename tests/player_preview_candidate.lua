-- Exercise the actual sidecar callbacks without a game or native renderer.
local identity = { unit = 1, body = 2, armor = 3, helmet = 4 }
local opens, renders, layouts, zooms = 0, 0, 0, 0
local resources, captures, updates, destroyed, syncs = 0, 0, 0, 0, 0
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
local advance_calls, animation_steps = 0, 0
local advance_dts = {}
local advance_failure = false
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
    syncs = syncs + 1
    assert(not sync_failure, 'Preview garment disappeared')
end
a.advance_model = function(_, dt)
    advance_calls = advance_calls + 1
    advance_dts[#advance_dts + 1] = dt
    assert(not advance_failure, type(advance_failure) == 'string' and advance_failure or 'Owned animation failed')
    if current_controls.animating == false or dt <= 0 then
        return false
    end
    animation_steps = animation_steps + 1
    return true
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
local display_width, display_height = 1920, 1080
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
local frame_time = 100
local memory = {
    time = function()
        return frame_time
    end,
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
    -- Isolated fake-engine coverage only. Release builders keep this false.
    PREVIEW_ANIMATION_ENABLED = true,
    m = {
        player_preview_controls = dofile('src/preview/player_preview_controls.lua'),
        player_preview_input = dofile('src/preview/player_preview_input.lua'),
        player_preview = dofile('src/preview/player_preview.lua'),
        player_preview_native = {
            new = function(_, _, host)
                factories = factories + 1
                current_controls = host.controls
                assert(
                    host.animate == true and current_controls.animating == true,
                    'Candidate did not enable owned animation'
                )
                current_controls.animation_available = true
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
                return display_width, display_height
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
local animated_draws, animated_opens = renders, opens
editor.on_update(ctx, 0.01)
env.render()
assert(
    renders == animated_draws + 1 and opens == animated_opens,
    'Changed animation did not submit between palette ticks'
)
input.mouse() -- Release the canceled press from the disabled state.
x, y, down = current_controls.x + current_controls.w / 2, current_controls.y - 10, true
assert(
    input.mouse() == nil and not current_controls.animating and layouts == 1 and opens == animated_opens,
    'Pause control leaked its click, failed to redraw, or rebuilt the model'
)
down = false
input.mouse()
local paused_steps, paused_draws = animation_steps, renders
editor.on_update(ctx, 0.01)
env.render()
assert(
    animation_steps == paused_steps and renders == paused_draws and opens == animated_opens,
    'Pause caption redraw stepped or rebuilt the model'
)
editor.on_update(ctx, 0.01)
env.render()
assert(
    animation_steps == paused_steps and renders == paused_draws,
    'Paused animation kept drawing between palette ticks'
)
down = true
assert(
    input.mouse() == nil and current_controls.animating and layouts == 2 and opens == animated_opens,
    'Play control failed to redraw without rebuilding'
)
down = false
input.mouse()
layouts = 0 -- Track the following drag independently from footer redraws.
-- Loader callbacks can omit delta or supply only a numeric first argument.
-- Actual pose steps and submissions must continue, without blur catch-up.
local timing_steps, timing_draws = animation_steps, renders
editor.on_update(0.01)
env.render()
assert(animation_steps == timing_steps + 1 and renders == timing_draws + 1, 'One-argument update froze animation')
editor.on_update(ctx)
env.render()
frame_time = frame_time + 0.02
editor.on_update(ctx)
env.render()
assert(
    animation_steps == timing_steps + 2 and renders == timing_draws + 2,
    'Missing update delta froze animation/redraw'
)
assert(math.abs(advance_dts[#advance_dts] - 0.02) < 1e-7, 'Missing delta did not use the measured clock')
frame_time = frame_time + 10
editor.on_update(ctx, 0 / 0)
assert(advance_dts[#advance_dts] == 0.05, 'Invalid delta caught up a stalled clock')
focused = false
frame_time = frame_time + 0.02
editor.on_update(ctx)
focused = true
frame_time = frame_time + 10
editor.on_update(ctx)
assert(advance_dts[#advance_dts] == 0, 'Missing-delta resume stepped on a focus transition')
frame_time = frame_time + 0.02
editor.on_update(ctx)
assert(math.abs(advance_dts[#advance_dts] - 0.02) < 1e-7, 'Measured animation clock did not resume normally')
local timed_steps = animation_steps
editor.on_update(ctx, 0)
assert(animation_steps == timed_steps, 'An explicit paused game delta advanced animation')
local measured_clock = memory.time
memory.time = nil
editor.on_update(ctx)
assert(advance_dts[#advance_dts] == 1 / 60, 'No clock/delta fallback left animation frozen')
memory.time = measured_clock
env.render()
input.mouse() -- Release the focus-cancelled pointer before the drag test.
x, y, down = 40, 660, true
assert(input.mouse() == nil, 'Panel click leaked to editor')
x, y = 80, 700
input.mouse()
assert(layouts == 1)
input.mouse()
assert(layouts == 1, 'Stationary pointer rebuilt GUI')
local rendered_before, synced_before, destroyed_before = renders, syncs, destroyed
local advanced_before, stepped_before = advance_calls, animation_steps
focused = false
editor.on_update(ctx, 0.1)
env.render()
assert(
    renders == rendered_before
        and syncs == synced_before
        and destroyed == destroyed_before
        and advance_calls == advanced_before,
    'Blur submitted, synchronized or destroyed native preview resources'
)
focused = true
for _, dimensions in ipairs({ { 0, 0 }, { 1920, 0 }, { 0, 1080 }, { 0 / 0, 1080 } }) do
    display_width, display_height = dimensions[1], dimensions[2]
    editor.on_update(ctx, 0.1)
    env.render()
    assert(
        renders == rendered_before
            and syncs == synced_before
            and destroyed == destroyed_before
            and advance_calls == advanced_before,
        'Invalid display reached native preview work'
    )
end
display_width, display_height = 1920, 1080
editor.on_update(ctx, 0.1)
env.render()
assert(renders > rendered_before and syncs > synced_before, 'Valid foreground failed to resume preview')
assert(
    advance_dts[#advance_dts] == 0 and animation_steps == stepped_before,
    'Focus resume advanced a catch-up animation step'
)
editor.on_update(ctx, 0.01)
env.render()
assert(
    advance_dts[#advance_dts] == 0.01 and animation_steps == stepped_before + 1,
    'Animation did not resume on the next ordinary frame'
)
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
advanced_before = advance_calls
editor.on_update(ctx, 0.01)
assert(
    input.mouse == original and input.wheel == original_wheel,
    'Closing editor retained preview input/render resources'
)
assert(advance_calls == advanced_before, 'Hidden editor stepped its animation')
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
local cape_opens, existing_unit = opens, identity.unit
identity.cape = 17
editor.on_update(ctx, 1)
editor.on_update(ctx, 1.1)
assert(
    identity.unit == existing_unit and opens == cape_opens + 1,
    'Cape kit changed on the same mount unit without rebuilding preview'
)
local cleanup_before = destroyed
focused = false
assert(editor.on_disable() == false and destroyed == cleanup_before, 'Blur destroyed preview resources')
assert(editor.on_cleanup_poll() == false and destroyed == cleanup_before, 'Blur cleanup poll touched renderer')
focused = true
display_width, display_height = 0, 0
assert(editor.on_cleanup_poll() == false and destroyed == cleanup_before, 'Minimized cleanup poll touched renderer')
display_width, display_height = 1920, 1080
assert(editor.on_disable())
assert(destroyed == cleanup_before + 6, 'Foreground failed to finish deferred preview cleanup')
-- A driver fault uses ordinary deferred cleanup and cannot repeatedly reopen
-- an automatically requested dock while the same activation remains failed.
local animation_pointer = input.mouse
editor.on_enable(ctx)
public.dock({ x = 100, y = 100, w = 180, h = 300 })
editor.on_update(ctx, 0.01)
local animation_opens, animation_destroyed = opens, destroyed
advance_failure, quiesced = true, false
editor.on_update(ctx, 0.01)
assert(
    not public.is_ready() and destroyed == animation_destroyed and input.mouse == animation_pointer,
    'Animation fault destroyed before the fence or retained pointer ownership'
)
assert(logs[#logs]:find('Owned animation failed', 1, true), 'Animation failure omitted its diagnostic')
quiesced = true
for i = 1, 4 do
    public.dock({ x = 100, y = 100, w = 180, h = 300 })
    editor.on_update(ctx, 0.01)
end
assert(opens == animation_opens and destroyed == animation_destroyed + 6, 'Failed docked animation repeatedly reopened')
advance_failure = false
assert(public.toggle())
editor.on_update(ctx, 0.01)
assert(public.is_ready() and opens == animation_opens + 1, 'Explicit animation retry could not recover')
assert(editor.on_disable())
-- An active driver cannot turn the explicit one-frame request into a live
-- animation/render loop. Live can resume the same model intentionally.
editor.on_enable(ctx)
request = 'once'
local once_opens, once_calls, once_draws = opens, advance_calls, renders
editor.on_update(ctx, 0.3)
env.render()
assert(opens == once_opens + 1 and advance_calls == once_calls + 1 and renders == once_draws + 1)
local once_steps = animation_steps
for i = 1, 5 do
    editor.on_update(ctx, 0.11)
    env.render()
end
assert(
    advance_calls == once_calls + 1 and animation_steps == once_steps and renders == once_draws + 1,
    'One-frame request continued animation or rendering after its first frame'
)
request = 'live'
editor.on_update(ctx, 0.3)
env.render()
assert(
    opens == once_opens + 1 and advance_calls == once_calls + 2 and renders == once_draws + 2,
    'Live request did not resume the existing one-frame model'
)
assert(editor.on_disable())
-- Animation identity failures use the same bounded source/context recovery as
-- material synchronization. Persistent failure must stop after three rebuilds.
for _, failure_text in ipairs({
    'Equipped source changed; rebuild preview',
    'Preview animation driver disappeared',
}) do
    editor.on_enable(ctx)
    assert(public.toggle())
    editor.on_update(ctx, 0.01)
    local recovery_opens, recovery_destroyed, recovery_calls = opens, destroyed, advance_calls
    advance_failure = failure_text
    editor.on_update(ctx, 0.01)
    assert(not public.is_ready() and destroyed == recovery_destroyed + 6)
    for i = 1, 4 do
        editor.on_update(ctx, 1.1)
    end
    assert(
        opens == recovery_opens + 3 and advance_calls == recovery_calls + 4 and not public.is_ready(),
        'Transient animation failure did not use the three-rebuild recovery cap: ' .. failure_text
    )
    local stopped_opens, stopped_calls = opens, advance_calls
    editor.on_update(ctx, 10)
    assert(opens == stopped_opens and advance_calls == stopped_calls, 'Retired animation resumed beyond its retry cap')
    advance_failure = false
    assert(public.toggle())
    editor.on_update(ctx, 0.01)
    assert(public.is_ready() and opens == stopped_opens + 1, 'Explicit retry did not reset animation recovery')
    assert(editor.on_disable())
end
-- Unload must dismiss the owned editor before a permanently pending or
-- throwing render fence, while retaining every native resource receipt.
local dismissal_calls, dismissal_ready, dismissal_throws = 0, true, false
local fence_throws = false
local saved_quiesce = a.quiesce
front.dismiss = function()
    dismissal_calls = dismissal_calls + 1
    front.menu.visible = false
    if dismissal_throws then
        error('Menu GUI dismissal unavailable')
    end
    return dismissal_ready
end
a.quiesce = function()
    assert(not front.menu.visible and dismissal_calls > 0, 'Native retirement ran before editor dismissal')
    assert(not fence_throws, 'Render fence unavailable')
    return quiesced
end
for _, throwing in ipairs({ false, true }) do
    editor.on_enable(ctx)
    front.menu.visible = true
    local mouse_before_unload, wheel_before_unload = input.mouse, input.wheel
    assert(public.toggle())
    editor.on_update(ctx, 0.1)
    local receipt_count, destroyed_before_unload, cleanup_count = resources, destroyed, base_cleanups
    local rendered = env.render
    quiesced, fence_throws = false, throwing
    assert(not editor.on_disable(), 'Pending render cleanup completed unload')
    assert(not front.menu.visible and env.render ~= rendered, 'Pending cleanup retained visible editor/render hook')
    assert(
        input.mouse == mouse_before_unload and input.wheel == wheel_before_unload,
        'Pending cleanup retained preview input'
    )
    for _ = 1, 3 do
        assert(not editor.on_cleanup_poll(), 'Permanent render fault discarded pending cleanup')
    end
    assert(
        resources == receipt_count and destroyed == destroyed_before_unload and base_cleanups == cleanup_count,
        'Pending render cleanup freed receipts or invoked base cleanup'
    )
    quiesced, fence_throws, dismissal_ready = true, false, false
    assert(not editor.on_cleanup_poll(), 'Missing UI acknowledgement completed unload')
    assert(destroyed == destroyed_before_unload + 6 and base_cleanups == cleanup_count)
    assert(registry['epic.player_preview.v1'] == public, 'UI retry discarded the preview owner')
    dismissal_throws = true
    assert(not editor.on_cleanup_poll() and base_cleanups == cleanup_count, 'Throwing UI dismissal completed unload')
    dismissal_ready, dismissal_throws = true, false
    assert(editor.on_cleanup_poll() and base_cleanups == cleanup_count + 1)
    assert(destroyed == destroyed_before_unload + 6, 'UI acknowledgement retried completed native destruction')
end
a.quiesce = saved_quiesce
-- A diagnostic still frame must not leak into the next ordinary UI opening.
editor.on_enable(ctx)
front.menu.visible = true
request = 'once'
editor.on_update(ctx, 0.3)
env.render()
local still_draws = renders
editor.on_update(ctx, 0.1)
env.render()
assert(renders == still_draws, 'The explicit one-frame request kept rendering')
assert(public.toggle() and not public.is_ready())
assert(public.toggle() and public.is_ready())
editor.on_update(ctx, 0.01)
env.render()
editor.on_update(ctx, 0.01)
env.render()
assert(renders == still_draws + 2, 'One-frame diagnostic froze the next UI preview')
assert(editor.on_disable())
-- The authored data worker is independent of native portrait retirement, but
-- unloading must retain its receipt until its own cancellation acknowledges.
local authored_records = {}
env.m.preview_animation = 'authored_salute'
env.m.player_authored_source = {
    new = function()
        local source = { starts = 0, polls = 0, can_close = false, state = 'idle' }
        source.start = function()
            if source.state == 'idle' then
                source.starts = source.starts + 1
                source.state = 'loading'
            end
        end
        source.tick = function()
            source.polls = source.polls + 1
        end
        source.close = function()
            if not source.can_close then
                return false
            end
            source.state = 'closed'
            return true
        end
        authored_records[#authored_records + 1] = source
        return source
    end,
}
editor.on_enable(ctx)
front.menu.visible = true
local authored_worker = authored_records[#authored_records]
assert(authored_worker.starts == 1 and public.toggle())
editor.on_update(ctx, 0.1)
assert(authored_worker.polls == 1)
local pending_base_disables = base_disables
assert(not editor.on_disable() and not front.menu.visible and base_disables == pending_base_disables)
assert(not editor.on_cleanup_poll(), 'Authored worker lost its pending cancellation receipt')
authored_worker.can_close = true
assert(editor.on_cleanup_poll() and authored_worker.state == 'closed')
disabled = true
editor.on_enable(ctx)
authored_worker = authored_records[#authored_records]
assert(authored_worker.starts == 0, 'Disabled Player Preview started an authored game-data worker')
authored_worker.can_close = true
assert(editor.on_disable())
disabled = false
env.m.preview_animation, env.m.player_authored_source = nil, nil
-- A frontend replaced by another owner cannot be dismissed by our unload.
editor.on_enable(ctx)
local foreign_frontend = {
    menu = { visible = true },
    input = input,
    dismiss = function()
        error('Foreign frontend was dismissed')
    end,
}
registry['dbf.epic_lut.frontend.v1'] = foreign_frontend
assert(editor.on_disable() and foreign_frontend.menu.visible, 'Preview stopped a foreign frontend')
registry['dbf.epic_lut.frontend.v1'] = front
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
