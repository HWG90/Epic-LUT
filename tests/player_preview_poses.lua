-- Exercise the actual lifecycle adapter with the ordinary static package gate.
local Clip = dofile('src/preview/player_authored_clip.lua')
local controls, host, public
local opened, destroyed, drivers, pose_writes, sources, logs = {}, 0, 0, 0, {}, {}
local quiesced, focused, outcome, source_close = true, true, 'loading', true
local model_failure, pose_failure
local identity = { unit = 1, body = 2, armor = 3, helmet = 4 }
local current_model
local input = {
    mouse = function()
        return 0, 0
    end,
    wheel = function()
        return 0
    end,
    down = function()
        return false
    end,
    focused = function()
        return focused
    end,
}
local front = {
    preview_cleanup_guard = true,
    input = input,
    menu = { visible = true, window_bounds = { x = 10, y = 20, scale = 2 } },
}
front.menu.open_dropdown = function(state)
    front.menu.dropdown = state
end
local adapter = {
    capture = function(gear)
        assert(gear == identity)
        return gear
    end,
    quiesce = function()
        return quiesced
    end,
    apply_luts = function() end,
    layout_panel = function() end,
    zoom = function() end,
    rotate = function() end,
    create_model = function()
        assert(not model_failure, 'Copied model failed')
        current_model = { pose = controls.pose }
        opened[#opened + 1] = current_model
        if controls.pose ~= 'idle' then
            assert(host.get_animation_source().get(), 'Pose opened before authored data was ready')
            if pose_failure then
                current_model.animation_failed = true
                controls.animation_error = 'Owned hierarchy unavailable'
            else
                drivers = drivers + 1
            end
        end
        return current_model
    end,
    advance_model = function(model, dt)
        if model.pose == 'idle' or model.animation_failed or model.posed or dt <= 0 then
            return false
        end
        model.posed = true
        pose_writes = pose_writes + 1
        return true
    end,
    render = function() end,
}
for _, kind in ipairs({ 'target', 'world', 'camera', 'viewport', 'panel' }) do
    adapter['create_' .. kind] = function()
        return {}
    end
end
for _, kind in ipairs({ 'target', 'world', 'model', 'camera', 'viewport', 'panel' }) do
    adapter['destroy_' .. kind] = function()
        destroyed = destroyed + 1
    end
end
local registry = { ['dbf.epic_lut.frontend.v1'] = front }
local env = setmetatable({
    PREVIEW_ANIMATION_ENABLED = false,
    PREVIEW_INSPECT_ONLY = false,
    editor = {
        on_enable = function() end,
        on_update = function() end,
        on_disable = function()
            return true
        end,
        on_cleanup_poll = function()
            return true
        end,
    },
    m = {
        player_preview_controls = dofile('src/preview/player_preview_controls.lua'),
        player_preview_input = dofile('src/preview/player_preview_input.lua'),
        player_preview = dofile('src/preview/player_preview.lua'),
        player_authored_clip = Clip,
        player_authored_source = {
            new = function()
                local source = { state = 'idle', starts = 0, ticks = 0, closes = 0 }
                function source.start()
                    if source.state == 'idle' then
                        source.state = 'loading'
                        source.starts = source.starts + 1
                    end
                end
                function source.tick()
                    source.ticks = source.ticks + 1
                    if source.state == 'loading' and outcome ~= 'loading' then
                        source.state = outcome
                        source.error = outcome == 'failed' and 'Missing Wave clip' or nil
                    end
                end
                function source.get()
                    return source.state == 'ready' and {} or nil
                end
                function source.close()
                    source.closes = source.closes + 1
                    if not source_close then
                        return false
                    end
                    source.state = 'closed'
                    return true
                end
                sources[#sources + 1] = source
                return source
            end,
        },
        player_preview_native = {
            new = function(_, _, value)
                host, controls = value, value.controls
                assert(host.animate == false and controls.pose == 'idle', 'Static package did not default to Idle')
                return adapter
            end,
        },
        player_preview_submit = {
            new = function()
                return function() end
            end,
        },
        bingus_memory = {
            new = function()
                return {
                    module = function()
                        return 1
                    end,
                    address = function(v)
                        return v
                    end,
                    time = function()
                        return 100
                    end,
                }
            end,
        },
        engine = {
            open = function()
                return {}
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
    },
    package = { loaded = registry },
    io = {
        open = function()
            return nil
        end,
    },
    os = {
        getenv = function()
            return 'test'
        end,
        remove = function() end,
    },
    stingray = {
        Gui = {
            resolution = function()
                return 3840, 2160
            end,
        },
        Application = {
            save_render_target = function() end,
        },
    },
    render = function() end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile('src/preview/player_preview_candidate.lua'))
setfenv(chunk, env)
local editor = chunk()
local ctx = {
    log = function(text)
        logs[#logs + 1] = text
    end,
    on_cleanup = function() end,
}
local function tick()
    editor.on_update(ctx, 0.1)
end
local function activate()
    front.menu.visible = true
    editor.on_enable(ctx)
    public = assert(registry['epic.player_preview.v1'])
end
activate()
assert(public.get_pose() == 'idle' and #sources == 0 and public.toggle())
tick()
assert(#opened == 1 and drivers == 0 and pose_writes == 0 and #sources == 0, 'Idle launched animation work')
assert(not public.set_pose('invented') and #sources == 0)
controls.x, controls.y, controls.w, controls.h = 2500, 400, 240, 400
controls.yaw, controls.fov, controls.pan_x, controls.pan_y = 135, 45, 0.2, -0.4
local function camera_kept()
    assert(controls.x == 2500 and controls.y == 400 and controls.w == 240 and controls.h == 400)
    assert(
        controls.yaw == 135 and controls.fov == 45 and controls.pan_x == 0.2 and controls.pan_y == -0.4,
        'Pose rebuild reset camera controls'
    )
end
assert(public.open_pose_dropdown())
local popup = assert(front.menu.dropdown)
assert(popup.owner == nil and popup.screen_anchor and popup.preview_owner == public)
assert(popup.x == (controls.x + controls.w / 3 - 10) / 2 and popup.top == (controls.y - 20) / 2)
assert(popup.control.choices[3] == 'Wave' and popup.mod.handle.set(popup.control.id, 3))
assert(not front.menu.dropdown and public.get_pose() == 'wave')
tick()
assert(#sources == 1 and sources[1].starts == 1 and #opened == 1 and controls.animation_pending)
assert(public.open_pose_dropdown(), 'Loading blocked the chooser')
assert(front.menu.dropdown.mod.handle.set('player_preview_pose', 4) and public.get_pose() == 'taunt')
outcome, quiesced = 'ready', false
tick()
assert(#opened == 1 and destroyed == 0 and not public.is_ready(), 'Pose wrote before retirement fence')
assert(public.set_pose('highfive'))
quiesced = true
tick()
assert(#opened == 2 and opened[2].pose == 'highfive' and drivers == 1 and destroyed == 6)
camera_kept()
tick()
local held_writes = pose_writes
for _ = 1, 20 do
    tick()
end
assert(pose_writes == held_writes and held_writes == 1 and #sources == 1, 'Held pose cycled or reloaded')
assert(public.set_pose('idle'))
quiesced = false
tick()
assert(#opened == 2 and not public.is_ready())
quiesced = true
tick()
tick()
assert(#opened == 3 and opened[3].pose == 'idle' and drivers == 1 and #sources == 1)
camera_kept()
local foreign = { owner = 'other menu' }
front.menu.dropdown = foreign
assert(public.toggle() and front.menu.dropdown == foreign, 'Preview close cleared a foreign dropdown')
assert(editor.on_disable())
front.menu.dropdown = nil

-- A user-closed pane cannot be reopened by late data, including delayed source
-- cancellation; the next activation again starts Idle without a worker.
outcome = 'loading'
activate()
assert(public.toggle())
tick()
assert(public.set_pose('wave'))
tick()
local late = sources[#sources]
assert(public.toggle() and not public.is_ready())
local before_late = #opened
outcome = 'ready'
for _ = 1, 3 do
    tick()
end
assert(#opened == before_late and not public.is_ready(), 'Late pose data reopened a user-closed preview')
assert(editor.on_disable() and late.state == 'closed')

-- An asynchronous worker/decode failure reports once and cannot automatically
-- recreate workers. Only another explicit selection retries the failed attempt.
outcome = 'loading'
activate()
assert(public.toggle())
tick()
assert(public.set_pose('wave'))
tick()
local failing = sources[#sources]
local before_failure = #sources
outcome = 'failed'
tick()
assert(public.get_pose() == 'idle' and public.is_ready() and not controls.animation_pending)
assert(controls.animation_error:find('Missing Wave clip', 1, true))
for _ = 1, 5 do
    tick()
end
assert(#sources == before_failure and failing.starts == 1, 'Source failure automatically retried')
outcome = 'loading'
assert(public.set_pose('wave'))
tick()
assert(#sources == before_failure + 1, 'Explicit retry did not replace the failed source')
assert(public.set_pose('idle'))
source_close = false
tick()
local before_idle = #opened
tick()
assert(#opened == before_idle, 'Idle ignored pending source cancellation')
source_close = true
tick()
tick()
assert(public.get_pose() == 'idle' and public.is_ready())
assert(editor.on_disable())

-- An unsupported owned hierarchy leaves the ordinary static portrait usable,
-- with no repeated rebuild. A native model setup error also reverts to Idle.
outcome = 'ready'
activate()
assert(public.toggle())
tick()
pose_failure = true
assert(public.set_pose('taunt'))
tick()
tick()
assert(public.is_ready() and public.get_pose() == 'idle' and controls.animation_error)
local unsupported_opens = #opened
for _ = 1, 4 do
    tick()
end
assert(#opened == unsupported_opens, 'Unavailable pose repeatedly rebuilt the portrait')
pose_failure = false
model_failure = true
assert(public.set_pose('wave'))
tick()
assert(public.get_pose() == 'idle' and not public.is_ready())
model_failure = false
assert(public.toggle())
tick()
assert(public.is_ready() and opened[#opened].pose == 'idle')
assert(editor.on_disable())
print(
    'PASS preview pose lifecycle: Idle default, lazy/coalesced real pose choices, held frames, fenced rebuild/camera preservation, chooser during loading, user-close cancellation, explicit-only failure retry and static fallback'
)
