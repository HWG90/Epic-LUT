-- Exercise the actual sidecar callbacks without a game or native renderer.
local identity = { unit = 1, body = 2, armor = 3, helmet = 4 }
local opens, renders, layouts, zooms = 0, 0, 0, 0
local setup_failure = false
local sync_failure = false
local logs = {}
local a = {
    capture = function()
        return identity
    end,
    quiesce = function()
        return true
    end,
}
for _, name in ipairs({ 'target', 'world', 'model', 'camera', 'viewport', 'panel' }) do
    a['create_' .. name] = function()
        if name == 'model' then
            opens = opens + 1
            assert(not setup_failure, 'Unavailable copied model')
        end
        return {}
    end
    a['destroy_' .. name] = function() end
end
a.render = function()
    renders = renders + 1
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
        on_enable = function() end,
        on_update = function() end,
        on_disable = function()
            return true
        end,
        on_cleanup_poll = function()
            return true
        end,
    },
    PREVIEW_INSPECT_ONLY = false,
    m = {
        player_preview_controls = dofile('src/preview/player_preview_controls.lua'),
        player_preview_input = dofile('src/preview/player_preview_input.lua'),
        player_preview = dofile('src/preview/player_preview.lua'),
        player_preview_native = {
            new = function()
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
    package = { loaded = registry },
    stingray = { Gui = {
        resolution = function()
            return 1920, 1080
        end,
    } },
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
    on_cleanup = function() end,
}
editor.on_enable(ctx)
local public = assert(registry['epic.player_preview.v1'])
assert(public.toggle())
editor.on_update(ctx, 0.1)
env.render()
assert(opens == 1 and renders == 1 and input.mouse ~= original)
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
x, y, down = 250, 250, false
local z = zooms
assert(input.wheel() == 0 and zooms == z + 1, 'Preview wheel zoom leaked to page')
x, y = 0, 0
assert(input.wheel() == 120, 'Preview consumed wheel outside its bounds')
assert(public.toggle())
editor.on_update(ctx, 0.01)
assert(opens == 8, 'Pop Out did not reopen at floating geometry')
assert(public.toggle())
editor.on_update(ctx, 0.01)
assert(opens == 8, 'Dock Back rebuilt the owned model unnecessarily')
registry['dbf.epic_lut.frontend.v1'].menu.visible = false
editor.on_update(ctx, 0.01)
assert(
    input.mouse == original and input.wheel == original_wheel,
    'Closing editor retained preview input/render resources'
)
assert(editor.on_disable() and registry['epic.player_preview.v1'] == nil and input.wheel == original_wheel)
print('PASS actual sidecar equipment rebuild, retry cap, focus cancellation, pointer restoration and public lifecycle')
