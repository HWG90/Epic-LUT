local Recovery = dofile('src/editor/appearance_recovery.lua')
local function fixture()
    local edit, operations, counts, pending, proof =
        {}, {
            discovery_binding = function()
                return function() end
            end,
            pattern_session = {},
        }, { scans = 0, proofs = 0, patterns = 0 }, {}, { value = { armor = 'a', helmet = 'h' } }
    local state = {edit=edit, operations=operations, pending=pending,
        appearance={count=function()return 1 end,remember=function()return 0 end,batches=function()return {}end},
        frontend={menu={visible=false}}, resource=function()end,
        proof=function()counts.proofs=counts.proofs+1;return proof.value end,
        refresh=function()counts.scans=counts.scans+1 end, groups={},bindings={},
        patterns={flashing=function()return false end,scan=function()counts.patterns=counts.patterns+1;return {}end}}
    local function tick(dt) return Recovery.update(state,dt) end
    local function request()
        edit.appearance_generation = (edit.appearance_generation or 0) + 1
        edit.appearance_retry = 0
        edit.appearance_wake = true
    end
    return tick, request, counts, edit, pending, proof, operations
end
local tick, request, c, e, p, proof = fixture()
for _ = 1, 1000 do
    tick(1)
end
assert(c.scans == 0 and c.proofs == 0, 'Idle recovery read/scanned native gear')
request()
for _ = 1, 4 do
    tick(0.01)
end
assert(c.scans == 1 and c.patterns == 1)
for _ = 1, 1000 do
    tick(1)
end
assert(c.scans == 1 and c.proofs == 4, 'Completed event restarted recovery')
request()
tick(0.01)
request()
for _ = 1, 7 do
    tick(0.6)
end
assert(c.scans == 3, 'Event during an active pass was lost or replayed repeatedly')
proof.value = nil
request()
for _ = 1, 200 do
    tick(1)
end
local reads = c.proofs
for _ = 1, 200 do
    tick(1)
end
assert(c.proofs == reads and e.appearance_retry == 40, 'Unavailable avatar retried forever')
proof.value = { armor = 'b', helmet = 'h' }
request()
for _ = 1, 4 do
    tick(0.01)
end
assert(c.scans == 4, 'New lifecycle did not wake exhausted retry')
print(
    'PASS appearance recovery events: zero idle reads/scans, coalesced stages, mid-job events, bounded unavailable retry and wake'
)

do
    local tick, request, counts, edit, _, _, operations = fixture()
    local changed, probes = false, 0
    operations.appearance_changed = function()
        probes = probes + 1
        local result = changed
        changed = false
        return result
    end
    operations.invalidate_appearance = request
    edit.appearance_has_events = false
    for _ = 1, 200 do tick(0.01) end
    assert(probes == 0 and counts.scans == 0,
        'Missing third-party event bus enabled idle polling')
    changed = true
    tick(0.5)
    for _=1,3 do tick(0) end
    assert(counts.scans==0 and probes==0, 'Idle state consulted a legacy signature')
    request()
    for _=1,4 do tick(0.5) end
    assert(counts.scans==1, 'Explicit lifecycle did not schedule recovery')
    for _=1,20 do tick(0.5) end
    assert(counts.scans==1, 'Unchanged legacy signature repeated native discovery')
    edit.appearance_has_events = true
    local prior = probes
    for _=1,20 do tick(1) end
    assert(probes==prior, 'Event-capable loader still polled the legacy detector')
end
print('PASS recovery compatibility: zero detector polling without third-party event bus; explicit lifecycle wakes recovery')
