local ffi = require('ffi')
local Engine = dofile('vendor/engine.lua')
local Session = dofile('src/gear/binding_session.lua')
local commits, counts, live, targets = {}, {}, {}, {}
local native = {commit = function(mesh)
    commits[#commits + 1] = mesh
    counts[mesh] = (counts[mesh] or 0) + 1
end}
local original_commit = native.commit
for i = 1, 202 do
    local mesh = (i - 1) % 41 + 1
    targets[i] = {material = i, mesh = mesh, original = 1000 + i, current = 1000 + i}
    live[i] = 1000 + i
end
local fail_at
local session = Session.new({
    retain = {records = {}, bytes = 0, cache = {}},
    key = function(b) return b.material end,
    present = function() return true end,
    binding = function(b) return live[b.material] end,
    create_texture = function() return {object = 9999} end,
    bind = function(b, object)
        live[b.material] = object
        native.commit(b.mesh)
        if b.material == fail_at then fail_at = nil; error('partial bind') end
    end,
})
local document = {width = 23, height = 8, data = ffi.new('float[736]')}
local count, missing, value = Engine.batch_commits(native, function()
    return session.apply(document, targets), nil, 'preserved'
end)
assert(count == 202 and missing == nil and value == 'preserved')
assert(#commits == 41 and native.commit == original_commit)
for _, n in pairs(counts) do assert(n == 1) end
commits, counts = {}, {}
assert(Engine.batch_commits(native, session.restore))
assert(#commits == 41 and native.commit == original_commit)
for _, b in ipairs(targets) do assert(live[b.material] == b.original) end
-- CPU rollback finishes before any coalesced mesh commit is flushed.
commits, counts = {}, {}
fail_at = 87
local ok, why = pcall(Engine.batch_commits, native, function() session.apply(document, targets) end)
assert(not ok and tostring(why):find('partial bind', 1, true))
assert(native.commit == original_commit and #commits == 41)
for _, b in ipairs(targets) do assert(live[b.material] == b.original) end
-- Nested action wrappers share the outer native flush and preserve touch order.
commits = {}
Engine.batch_commits(native, function()
    native.commit(9)
    Engine.batch_commits(native, function() native.commit(9); native.commit(3) end)
    native.commit(3)
end)
assert(#commits == 2 and commits[1] == 9 and commits[2] == 3)
commits = {}
Engine.batch_commits(native, function() end)
assert(#commits == 0)
local attempts = 0
local failing = function() attempts = attempts + 1; error('commit failed') end
native.commit = failing
assert(not pcall(Engine.batch_commits, native, function() native.commit(1); native.commit(2) end))
assert(native.commit == failing and attempts == 2)
print('PASS mesh commits: 202 bindings -> 41 commits for Apply/Restore, rollback, nested scopes, idle and dispatch recovery')
