-- Actual frontend/composer/view: Alt-Tab and minimization cannot enqueue zero-font GUI work.
local Core = dofile('vendor/menu/core.lua')
local Menu = dofile('vendor/menu/menu.lua')
local View = dofile('vendor/menu/view.lua')
local Frontend = dofile('src/platform/standalone_frontend.lua')
local focused, width, height = true, 1920, 1080
local native_calls, measurements, next_id = 0, 0, 0
local world, gui = {}, {}
local function allocation()
    native_calls, next_id = native_calls + 1, next_id + 1
    return next_id
end
local function destroy()
    native_calls = native_calls + 1
end
local sr = {
    Application = {
        worlds = function()
            return { world }
        end,
        main_world = function()
            return world
        end,
        can_get = function()
            return false
        end,
    },
    World = {
        create_screen_gui = function()
            allocation()
            return gui
        end,
        destroy_gui = destroy,
    },
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Color = function(a, r, g, b)
        return { a = a, r = r, g = g, b = b }
    end,
    Gui = {
        resolution = function()
            return width, height
        end,
        rect = allocation,
        text = function(_, _, _, size)
            assert(size > 0 and size < math.huge, 'Invalid font reached native GUI')
            return allocation()
        end,
        text_extents = function(_, label, _, size)
            assert(size > 0 and size < math.huge, 'Invalid font reached native measurement')
            measurements = measurements + 1
            return { x = 0, y = -size * 0.2 }, { x = #label * size * 0.5, y = size * 0.7 }
        end,
        destroy_rect = destroy,
        destroy_text = destroy,
    },
}
local view = View.new(sr, true)
local capture = { active = false }
function capture.sync(visible, ready)
    capture.active = visible and ready
    return true
end
function capture.release()
    capture.active = false
    return true
end
capture.shutdown = capture.release
local store = {
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
}
local front = Frontend.new({
    ui_core = Core,
    ui_menu = Menu,
    ui_store = {
        new = function()
            return store
        end,
    },
}, { settings_dir = 'tests/tmp', log = function() end }, {
    input = {
        poll = function() end,
        focused = function()
            return focused
        end,
        window = function()
            return 1
        end,
        down = function()
            return false
        end,
        mouse = function()
            return nil
        end,
        wheel = function()
            return 0
        end,
    },
    capture = capture,
    view = view,
    resolution = sr.Gui.resolution,
})
local handle = front.api.register({
    id = 'test',
    name = 'Epic LUT',
    pages = {
        { id = 'first', name = 'First', controls = {} },
        {
            id = 'second',
            name = 'Second',
            controls = {
                { id = 'name', type = 'input', label = 'Name', default = 'SEAF' },
            },
        },
    },
})
front.menu.visible, front.menu.page = true, 2
front.tick(0.1)
assert(native_calls > 0 and front.menu.visible and capture.active)
assert(handle.set('name', 'SEAF-Custom'))
local before, measured = native_calls, measurements
focused = false
front.tick(0.1)
assert(native_calls == before and measurements == measured, 'Blur rendered or destroyed native GUI')
assert(front.menu.visible and front.menu.page == 2 and handle.get('name') == 'SEAF-Custom')
view.measure('new glyph', 19)
view.text_metrics(19, 'New label')
assert(measurements == measured, 'Blur measured native text')
assert(view.clear() == false and view.release() == false and view.invalidate() == false)
assert(native_calls == before, 'Blur destroyed retained primitives')
focused = true
for _, dimension in ipairs({ { 0, 0 }, { 1920, 0 }, { 0, 1080 }, { -1, 1080 }, { 0 / 0, 1080 }, { math.huge, 1080 } }) do
    width, height = dimension[1], dimension[2]
    front.tick(0.1)
    assert(#front.menu.compose(width, height) == 0, 'Invalid display composed zero-scale GUI')
    view.measure('another glyph', 20)
    view.text_metrics(20, 'Another label')
    view.draw({ { type = 'text', text = 'blocked', size = 12, x = 0, y = 0, a = 1, c = { 255, 255, 255 } } })
    assert(native_calls == before and measurements == measured, 'Minimized display reached native GUI')
    assert(front.menu.visible and front.menu.page == 2 and handle.get('name') == 'SEAF-Custom')
end
width, height = 1920, 1080
front.tick(0.1)
assert(front.render_ready() and capture.active)
assert(front.menu.visible and front.menu.page == 2 and handle.get('name') == 'SEAF-Custom')
assert(native_calls > before, 'Valid display failed to resume rendering')
measured = measurements
assert(view.measure('bad', 0) == 0 and view.text_metrics(0, 'bad').height == 0)
assert(view.measure('bad', math.huge) == 0 and view.text_metrics(0 / 0, 'bad').height == 0)
assert(measurements == measured, 'Invalid font reached text_extents')
view.draw({ { type = 'text', text = 'bad', size = 0, x = 0, y = 0, a = 1, c = { 255, 255, 255 } } })
front.tick(0.1)
before = native_calls
focused = false
assert(front.close() == false and native_calls == before, 'Blur cleanup destroyed native GUI')
assert(
    not front.menu.visible and not capture.active and not front.closed,
    'Deferred cleanup retained menu input or lost its owner'
)
focused = true
width, height = 0, 0
assert(front.close() == false and native_calls == before, 'Minimized cleanup destroyed native GUI')
width, height = 1920, 1080
assert(front.close() and native_calls > before, 'Deferred GUI cleanup failed to resume')
assert(front.close(), 'Completed frontend cleanup was not idempotent')
print(
    'PASS Alt-Tab suspension: no zero-font composition/native GUI work, retained state on blur, valid-dimension resume and deferred cleanup'
)
