local P = dofile('src/player_preview.lua')
local events = {}
local failure
local id = 0
local a = {}
for _, name in ipairs({ 'world', 'model', 'camera', 'target', 'viewport', 'panel' }) do
    a['create_' .. name] = function()
        if failure == name then
            error('failed ' .. name)
        end
        id = id + 1
        events[#events + 1] = 'create ' .. name
        return id
    end
    a['destroy_' .. name] = function()
        events[#events + 1] = 'destroy ' .. name
    end
end
local applied = 0
a.apply_luts = function()
    applied = applied + 1
end
a.render = function()
    if failure == 'render' then
        error('render failed')
    end
end
local p = P.new(a)
local gear = { body = 1, armor = 2, helmet = 3 }
assert(p.open(gear) and p.state == 'ready')
assert(p.sync({}, 1) and p.sync({}, 1) and applied == 1, 'Redundant LUT uploads')
assert(p.close() and events[#events] == 'destroy target' and events[#events - 1] == 'destroy world')
assert(events[#events - 5] == 'destroy panel', 'Wrong teardown order')
failure = 'camera'
assert(not p.open(gear) and p.state == 'closed' and #p.resources == 0)
failure = nil
assert(p.open(gear))
failure = 'render'
assert(
    not p.render() and p.state == 'closing' and #p.resources == 6,
    'Render failure destroyed resources in rendering scope'
)
assert(p.close() and p.state == 'closed', 'Deferred render cleanup failed')
failure = nil
assert(p.open(gear))
local original = a.destroy_world
a.destroy_world = function()
    error('cleanup failed')
end
-- Existing receipts keep the destructor captured at creation.
assert(p.close())
assert(p.open(gear))
assert(not p.close() and p.state == 'cleanup_failed')
local count = id
assert(not p.open(gear) and id == count, 'Spawned over leaked resources')
for _, resource in ipairs(p.resources) do
    if resource.name == 'world' then
        resource.destroy = original
    end
end
assert(p.close())
local drained = false
a.destroy_world = original
a.quiesce = function()
    return drained
end
assert(p.open(gear))
local event_count = #events
assert(not p.close() and p.state == 'closing' and #events == event_count, 'Resources destroyed before renderer drained')
assert(not p.open(gear) and #events == event_count, 'New preview spawned while drain pending')
drained = true
assert(p.close() and p.state == 'closed', 'Drained preview did not release')
print('PASS player preview ownership, partial setup, reverse cleanup, retries and LUT revisions')
