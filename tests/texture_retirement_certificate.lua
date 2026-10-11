-- Reclamation is allowed only after immutable, scalar-only snapshots prove
-- that every target touched by this activation is still present and original.
local ffi = require('ffi')
local B = dofile('src/gear/binding_session.lua')
local function document(value)
    local result = { width = 23, height = 1, data = ffi.new('float[92]') }
    result.data[0] = value or 0.25
    return result
end
local function fixture()
    local cohort = {}
    local retain = { records = {}, cache = {}, bytes = 0, cohort = cohort }
    local live, bindings, creates, writes, native_reads = {}, {}, 0, 0, 0
    local failure, identity_failure, read_failure
    local function key(b)
        if identity_failure then
            error('Identity lookup failed')
        end
        return b.unit .. ':' .. b.mesh .. ':' .. b.material .. ':' .. b.slot
    end
    local function target(material, original)
        local b = { unit = 1, mesh = 2, material = material, slot = 3, original = original, current = original }
        live[key(b)] = { object = original, present = true }
        bindings[b] = true
        return b
    end
    local function session(explicit, dead)
        return B.new({
            retain = retain,
            cohort = explicit,
            dead = dead,
            key = key,
            present = function(b)
                native_reads = native_reads + 1
                if not bindings[b] then
                    assert(not b.texture and not b.document and not b.data, 'Certificate snapshot pinned upload data')
                end
                local entry = live[key(b)]
                return entry and entry.present
            end,
            binding = function(b)
                native_reads = native_reads + 1
                if read_failure then
                    error('Native readback failed')
                end
                return live[key(b)].object
            end,
            create_texture = function(_, _, data)
                creates = creates + 1
                if failure == 'create' then
                    error('Unknown partial native create')
                end
                return { object = 100 + creates, handle = 200 + creates, data = data }
            end,
            bind = function(b, object)
                writes = writes + 1
                local entry = live[key(b)]
                if failure == 'unchanged' then
                    error('Native write rejected')
                elseif failure == 'foreign' then
                    entry.object = 999
                    error('Native write left foreign state')
                elseif failure == 'partial' then
                    entry.object = object
                    entry.present = false
                    error('Native write completed before target vanished')
                end
                entry.object = object
            end,
        })
    end
    return {
        cohort = cohort,
        retain = retain,
        live = live,
        key = key,
        target = target,
        session = session,
        counters = function()
            return creates, writes, native_reads
        end,
        fail = function(value)
            failure = value
        end,
        fail_identity = function(value)
            identity_failure = value
        end,
        fail_read = function(value)
            read_failure = value
        end,
    }
end
do
    local f = fixture()
    local session, b = f.session(), f.target(4, 10)
    assert(f.cohort.sessions[1] == session)
    session.apply(document(), { b })
    local keep = f.retain.records[1]
    assert(keep.cohort == f.cohort and keep.bytes == 368 and keep.owned and keep.texture == b.texture)
    assert(not session.retirement_certificate(), 'An active native binding was certified')
    assert(session.restore() and #session.owned == 0 and session.retirement_certificate())
    assert(#f.retain.records == 1 and f.retain.bytes == 368, 'Certificate reclaimed resources itself')
    -- Neither dropping owned metadata nor editing the old binding-table fields
    -- can erase or redirect the immutable native-target proof.
    b.material, b.original = 888, 888
    assert(session.retirement_certificate(), 'Certificate followed mutable binding-table metadata')
    f.live['1:2:4:3'].object = 999
    assert(not session.retirement_certificate(), 'A later foreign binding was certified')
    f.live['1:2:4:3'].object = 10
    f.live['1:2:4:3'].present = false
    assert(not session.retirement_certificate(), 'An inaccessible target was certified')
    f.live['1:2:4:3'].present = true
    f.fail_identity(true)
    assert(not session.retirement_certificate(), 'Identity callback errors escaped or certified')
    f.fail_identity(false)
    f.fail_read(true)
    assert(not session.retirement_certificate(), 'Readback errors escaped or certified')
end
do
    -- Sessions which borrow the same cached resource all remain registered.
    local f = fixture()
    local a, b = f.target(4, 10), f.target(5, 20)
    local first, second = f.session(), f.session()
    first.apply(document(), { a })
    second.apply(document(), { b })
    assert(f.counters() == 1 and #f.retain.records == 1 and #f.cohort.sessions == 2)
    assert(first.restore() and first.retirement_certificate())
    assert(not second.retirement_certificate(), 'A cached resource user was lost from the retirement proof')
    assert(second.restore() and second.retirement_certificate())
end
do
    -- Restore-to-original is insufficient if that original is itself a native
    -- texture owned by the cohort about to be destroyed.
    local f = fixture()
    local first, second = f.session(), f.session()
    local a = f.target(4, 10)
    first.apply(document(), { a })
    local borrowed = f.target(5, a.texture.object)
    second.apply(document(0.5), { borrowed })
    assert(second.restore())
    local valid, reason = second.retirement_certificate()
    assert(not valid and reason:find('original belongs to the retiring cohort', 1, true))
end
do
    -- A pre-cohort legacy resource remains pinned; it is not incorrectly
    -- counted as a reclaimable original of this new cohort.
    local f = fixture()
    local legacy = { texture = { object = 10, handle = 50 }, data = ffi.new('float[92]') }
    f.retain.records[1], f.retain.bytes = legacy, 368
    local session, b = f.session(), f.target(4, 10)
    session.apply(document(), { b })
    assert(not legacy.cohort and not legacy.owned and not legacy.bytes)
    assert(session.restore() and session.retirement_certificate())
    assert(f.retain.records[1] == legacy)
end
for _, mode in ipairs({ 'unchanged', 'foreign', 'partial' }) do
    local f = fixture()
    local session, b = f.session(), f.target(4, 10)
    f.fail(mode)
    assert(not pcall(session.apply, document(), { b }))
    f.fail(nil)
    assert(session.restore())
    local certified = session.retirement_certificate()
    assert(certified == (mode == 'unchanged'), 'A partial native write lost its conservative target proof')
end
do
    local f = fixture()
    local session, b = f.session(), f.target(4, 10)
    f.fail('create')
    assert(not pcall(session.apply, document(), { b }))
    local keep = f.retain.records[1]
    assert(keep.cohort == f.cohort and keep.bytes == 368 and not keep.owned and not keep.texture)
    assert(f.retain.bytes == 368 and next(f.retain.cache) == nil)
    assert(session.retirement_certificate(), 'An untouched target became an unprovable native write')
    -- Lifetime must quarantine this unknown allocation despite the target
    -- certificate: there is deliberately no owned texture/handle to destroy.
end
do
    local f = fixture()
    local explicit = {}
    local session, b = f.session(explicit), f.target(4, 10)
    session.apply(document(), { b })
    assert(explicit.sessions[1] == session and not f.cohort.sessions)
    assert(f.retain.records[1].cohort == explicit)
    assert(session.restore() and session.retirement_certificate())
end
do
    local f = fixture()
    local old, b = f.session(), f.target(4, 10)
    local doc = document()
    old.apply(doc, { b })
    local former, old_data = b.texture, b.texture.data
    assert(old.restore())
    former.retiring = true
    local fresh = f.session()
    fresh.apply(doc, { b })
    assert(f.counters() == 2 and b.texture ~= former and b.current ~= former.object)
    assert(f.retain.records[1].texture == former and f.retain.records[1].data == old_data)
    assert(old_data[0] == 0.25 and f.retain.bytes == 736 and #f.retain.records == 2)
    local cache_key = '23:1:' .. ffi.string(doc.data, 368)
    assert(f.retain.cache[cache_key] == b.texture, 'Fresh allocation did not replace a retiring cache entry')
    assert(fresh.restore() and fresh.retirement_certificate())
end
do
    local f = fixture()
    local session, b = f.session(), f.target(4, 10)
    local cached = document()
    session.apply(cached, { b })
    assert(session.restore())
    f.cohort.closing = true
    local creates, writes, native_reads = f.counters()
    local bytes, records = f.retain.bytes, #f.retain.records
    for _, wanted in ipairs({ cached, document(0.75) }) do
        local ok, reason = pcall(session.apply, wanted, { b })
        assert(not ok and reason:find('Texture cohort is closing', 1, true))
        local next_creates, next_writes, next_reads = f.counters()
        assert(
            next_creates == creates and next_writes == writes and next_reads == native_reads,
            'Closing cohort performed native reads, creation or writes before rejecting a late apply'
        )
        assert(f.retain.bytes == bytes and #f.retain.records == records)
    end
end
do
    -- An absent-but-alive material remains unprovable. Only strict true from
    -- the explicit native unit-death check may bypass material readback.
    for _, answer in ipairs({ false, 'nil', 'throw', 1, true }) do
        local f = fixture()
        local checks = 0
        local session = f.session(nil, function(captured)
            checks = checks + 1
            assert(captured.unit == 1 and captured.material == 4 and not captured.texture)
            if answer == 'throw' then
                error('Unit-death check failed')
            elseif answer == 'nil' then
                return nil
            end
            return answer
        end)
        local b = f.target(4, 10)
        session.apply(document(), { b })
        f.live[f.key(b)].present = false
        assert(session.restore())
        local _, _, before_reads = f.counters()
        local certified = session.retirement_certificate()
        assert(certified == (answer == true), 'Unit-death certificate accepted an ambiguous native result')
        local _, _, after_reads = f.counters()
        if answer == true or answer == 'throw' then
            assert(after_reads == before_reads, 'Confirmed-dead or failed death check performed material reads')
        else
            assert(after_reads == before_reads + 1, 'Alive/unknown target skipped the strict presence check')
        end
        assert(checks == 1)
    end
end
do
    -- A destroyed unit cannot retain its former material, even when that
    -- material's captured original was another texture in this cohort.
    local f = fixture()
    local first = f.session()
    local a = f.target(4, 10)
    first.apply(document(), { a })
    local borrowed = f.target(5, a.texture.object)
    local second = f.session(nil, function(captured)
        return captured.material == 5
    end)
    second.apply(document(0.5), { borrowed })
    f.live[f.key(borrowed)].present = false
    assert(second.restore() and second.retirement_certificate())
end
do
    local legacy = B.new({ retain = { records = {}, cache = {}, bytes = 0 } })
    assert(not legacy.retirement_certificate(), 'Legacy sessions gained a speculative certificate')
end
print(
    'PASS texture retirement certificates: immutable target snapshots, complete cohort session registration, exact restored readback, inaccessible/foreign quarantine, borrowed originals and partial-create retention'
)
