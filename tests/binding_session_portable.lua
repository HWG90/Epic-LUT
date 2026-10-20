-- Production ownership/transaction logic with an explicit injected engine surface.
-- This verifies Lua 5.1 behavior, not the game's native API or renderer.
local Buffer = require('src.core.float_buffer')
local Session = dofile('src/gear/binding_session.lua')
local function document(value)
    local data = Buffer.new(12)
    data[0], data[1], data[2], data[3] = value or 0.25, -2.5, 2 ^ -149, -1 / math.huge
    return { width = 3, height = 1, data = data }
end
local function fixture()
    local f = { live = {}, creates = 0, writes = {}, reads = 0, cohort = {} }
    f.retain = { cache = {}, records = {}, bytes = 0, cohort = f.cohort }
    local function key(b)
        return b.unit .. ':' .. b.mesh .. ':' .. b.material .. ':' .. b.slot
    end
    function f.target(material, original)
        local b = { unit = 1, mesh = 2, material = material, slot = 3, original = original, current = original }
        f.live[key(b)] = { object = original, present = true }
        return b
    end
    f.first, f.second = f.target(4, 10), f.target(5, 20)
    local host = {
        retain = f.retain,
        key = key,
        present = function(b)
            f.reads = f.reads + 1
            local entry = f.live[key(b)]
            return entry and entry.present
        end,
        binding = function(b)
            f.reads = f.reads + 1
            return f.live[key(b)].object
        end,
        create_texture = function(w, h, data)
            assert(w == 3 and h == 1 and Buffer.count(data) == 12)
            f.creates = f.creates + 1
            return { object = 100 + f.creates, data = data }
        end,
        bind = function(b, value)
            local entry = f.live[key(b)]
            f.writes[#f.writes + 1] = { material = b.material, object = value }
            entry.object = value
            if f.failure and b == f.second and value >= 100 then
                if f.failure == 'foreign' then entry.object = 999 end
                error('Explicit engine rejection', 0)
            end
        end,
    }
    f.session = Session.new(host)
    function f.current(b) return f.live[key(b)].object end
    function f.set_current(b, value) f.live[key(b)].object = value end
    return f
end

do
    local f, doc = fixture(), document()
    local original = Buffer.bytes(doc.data, 12)
    local plan = f.session.prepare(doc, { f.first, f.second })
    assert(f.creates == 1 and #f.writes == 0 and f.current(f.first) == 10, 'Preparation wrote a material')
    assert(#f.retain.records == 1 and f.retain.bytes == 48)
    doc.data[0] = 0.75
    assert(Buffer.bytes(plan.texture.data, 12) == original, 'Prepared GPU upload followed a mutable draft')
    assert(1 / plan.texture.data[3] == -math.huge, 'Immutable upload erased signed zero')
    local count = f.session.commit(plan)
    assert(count == 2 and #f.writes == 2 and f.current(f.first) == plan.texture.object)
    Buffer.copy(doc.data, original, 12)
    for _ = 1, 1000 do f.session.apply(doc, { f.first, f.second }) end
    assert(f.creates == 1 and #f.writes == 2 and #f.retain.records == 1, 'Unchanged apply allocated or rebound')
    assert(not f.session.retirement_certificate(), 'Bound textures were certified for retirement')
    assert(f.session.restore() and f.current(f.first) == 10 and f.current(f.second) == 20)
    assert(f.session.retirement_certificate(), 'Restored, owned originals did not certify')
    assert(f.retain.bytes == 48 and #f.retain.records == 1, 'Restore prematurely freed upload buffers')
end

do
    local f, doc = fixture(), document()
    local plan = f.session.prepare(doc, { f.first })
    f.first.mesh = 99
    assert(not pcall(f.session.commit, plan) and #f.writes == 0, 'Changed receipt reached the native writer')
    f.first.mesh = 2
    f.set_current(f.first, 999)
    assert(not pcall(f.session.commit, plan) and #f.writes == 0, 'Foreign binding was overwritten')
    f.set_current(f.first, 10)
    f.live['1:2:4:3'].present = false
    assert(not pcall(f.session.commit, plan) and #f.writes == 0, 'Missing owner reached the native writer')
    f.live['1:2:4:3'].present = true
    local other = fixture()
    assert(not pcall(other.session.commit, plan) and #other.writes == 0, 'Cross-session plan was accepted')
    f.cohort.closing = true
    local reads = f.reads
    assert(not pcall(f.session.prepare, doc, { f.first }) and reads == f.reads, 'Closing cohort touched engine state')
end

for _, failure in ipairs({ 'partial', 'foreign' }) do
    local f, doc = fixture(), document()
    f.failure = failure
    assert(not pcall(f.session.apply, doc, { f.first, f.second }), 'Rejected native transaction succeeded')
    assert(f.current(f.first) == 10 and f.first.current == 10 and f.first.previous == nil)
    if failure == 'partial' then
        assert(f.current(f.second) == 20 and f.second.current == 20 and #f.writes == 4, 'Partial write was not rolled back')
    else
        assert(f.current(f.second) == 999 and #f.writes == 3, 'Rollback overwrote a foreign replacement')
    end
    local writes = #f.writes
    assert(f.session.restore() and #f.writes == writes, 'Restore repeated rollback or overwrote foreign state')
    assert(#f.retain.records == 1 and f.retain.bytes == 48, 'Failure prematurely released native upload backing')
end
print('PASS portable binding session: immutable prepare, exact cache, receipts/ownership, partial rollback and retirement safeguards')
