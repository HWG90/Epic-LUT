local Live = dofile('src/editor/live_edit.lua')
for _, fps in ipairs({ 60, 240 }) do
    local gate = Live.new()
    local document = { revision = 0 }
    local uploaded, uploaded_revision, time = {}, 0, 0
    local duration = 4
    for frame = 1, duration * fps do
        time = time + 1 / fps
        document.revision = frame
        if gate.ready(document.revision ~= uploaded_revision, true, 1 / fps) then
            uploaded[#uploaded + 1] = { revision = document.revision, time = time }
            uploaded_revision = document.revision
        end
    end
    assert(
        #uploaded >= duration * 14 and #uploaded <= duration * 15 + 1,
        'Live edit did not maintain a responsive bounded cadence'
    )
    assert(uploaded[1].revision == 1, 'First dirty drag revision was delayed')
    for i = 2, #uploaded do
        assert(uploaded[i].time - uploaded[i - 1].time >= Live.INTERVAL - 1e-8, 'Drag uploaded faster than 15Hz')
        assert(
            uploaded[i].revision > uploaded[i - 1].revision + 1,
            'Intermediate drag revisions were queued instead of coalesced'
        )
    end
    -- Releasing or canceling updates the latest document, with no timer delay.
    document.revision = duration * fps + 1
    assert(gate.ready(document.revision ~= uploaded_revision, false, 0), 'Release dropped the final revision')
    uploaded_revision = document.revision
    assert(not gate.ready(document.revision ~= uploaded_revision, false, 0), 'Clean release uploaded twice')
    document.revision = document.revision + 1 -- Picker Cancel restores its bytes as a new revision.
    assert(gate.ready(true, false, 0), 'Cancel restoration waited for another frame interval')
end
local gate = Live.new()
assert(gate.ready(true, false, 0) and gate.ready(true, false, 0), 'Discrete idle edits were throttled')
assert(not gate.ready(false, false, 0), 'Clean idle document uploaded')
assert(gate.ready(true, true, 0), 'First dirty revision after idle was delayed')
for _, dt in ipairs({ 0, -1, 0 / 0, math.huge, 'missing' }) do
    assert(not gate.ready(true, true, dt), 'Invalid or paused delta created upload credit')
end
assert(not gate.ready(true, true, nil), 'Missing delta created upload credit')
assert(gate.ready(true, true, 1000000), 'A long frame did not deliver its latest edit')
assert(not gate.ready(true, true, 0), 'Long delta accumulated unbounded catch-up uploads')
for _ = 1, 1000 do
    assert(not gate.ready(false, true, 1000))
end
assert(gate.ready(true, true, 0), 'Clean active frames did not preserve one bounded credit')
assert(not gate.ready(true, true, 0), 'Clean frames accumulated multiple upload credits')
gate.reset()
assert(gate.ready(true, true, 0), 'A new document inherited the previous throttle')
assert(gate.ready(true, false, 0), 'Interaction end failed to flush immediately')
assert(gate.ready(true, true, 0), 'A new interaction delayed its first edit')
print(
    'PASS live edit gate: 60/240Hz latest-only drags at15Hz, immediate first/idle/release/cancel revisions, reset and bounded invalid/long-frame credit'
)
