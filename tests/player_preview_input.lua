local P = dofile('src/preview/player_preview_input.lua')
local x, y = 5, 5
local focused = true
local ready = true
local zooms = 0
local events = 0
local canceled = 0
local controls = {
    x = 0,
    y = 0,
    w = 10,
    h = 10,
    fov = 40,
    cancel = function()
        canceled = canceled + 1
    end,
    pointer = function()
        return true, 'pan'
    end,
}
local mouse = function()
    return x, y
end
local wheel = function()
    return 120
end
local input = {
    mouse = mouse,
    wheel = wheel,
    focused = function()
        return focused
    end,
    down = function()
        return false
    end,
}
local front = { input = input, menu = { visible = true } }
local bridge = P.new({
    controls = controls,
    ready = function()
        return ready
    end,
    resolution = function()
        return 100, 100
    end,
    event = function(event)
        assert(event == 'pan')
        events = events + 1
    end,
    zoom = function()
        zooms = zooms + 1
    end,
    changed = function() end,
    failed = function()
        error('unexpected failure')
    end,
})
bridge.attach(front)
local wrapper = input.mouse
bridge.attach(front)
assert(input.mouse == wrapper, 'Repeated attach nested wrappers')
assert(input.mouse() == nil and events == 1, 'Preview pointer did not consume hit')
assert(input.wheel() == 0 and controls.fov == 35 and zooms == 1, 'Preview wheel did not isolate zoom')
focused = false
assert(input.mouse() == 5 and canceled == 1)
focused = true
x = 20
assert(input.wheel() == 120, 'Outside wheel was consumed')
local foreign = function()
    return 'foreign'
end
input.mouse = foreign
bridge.release()
assert(input.mouse == foreign and input.wheel == wheel, 'Release overwrote another addon wrapper')
bridge.release()
assert(input.mouse == foreign, 'Repeated release mutated foreign input')
print(
    'PASS preview input bridge: single ownership, hit/zoom isolation, focus cancellation and foreign-wrapper preservation'
)
