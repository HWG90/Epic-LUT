local Lifetime = dofile('src/gear/texture_lifetime.lua')
local function fixture()
    local cohort = { sessions = { 'certificate callback' } }
    local old, a, b = { handle = 1 }, { handle = 2 }, { handle = 3 }
    local legacy = { texture = old, data = 'legacy' }
    local first = { texture = a, data = 'first', owned = true, bytes = 16, cohort = cohort }
    local second = { texture = b, data = 'second', owned = true, bytes = 32, cohort = cohort }
    local retain = { records = { legacy, first, second }, bytes = 64, cache = { old = old, a = a, b = b } }
    local calls, receipts = {}, {}
    local f = {
        retain = retain,
        cohort = cohort,
        a = a,
        b = b,
        old = old,
        first = first,
        second = second,
        legacy = legacy,
        calls = calls,
        certified = true,
    }
    f.service = Lifetime.new({
        retain = retain,
        cohort = cohort,
        certified = function()
            calls[#calls + 1] = 'certificate'
            return f.certified, 'Foreign/stale binding retained'
        end,
        drain = function()
            calls[#calls + 1] = 'fence'
            if f.fence_throw then
                error('Fence call uncertain', 0)
            end
            if f.pending_first and #receipts == 0 or f.pending_second and #receipts == 1 then
                return nil, 'Waiting for game focus'
            end
            local receipt = { id = #receipts + 1, data = 'owned fence backing' }
            receipts[#receipts + 1] = receipt
            return receipt
        end,
        destroy = function(texture)
            assert(texture ~= old and texture.retiring, 'Legacy or reusable handle reached disposal')
            assert(
                #retain.records == 3 and retain.bytes == 64 and retain.cache.a == a,
                'Backing/cache released before disposal ack'
            )
            calls[#calls + 1] = 'destroy' .. texture.handle
            if f.destroy_throw and texture == b then
                error('Dispose result uncertain', 0)
            end
            if f.destroy_false and texture == b then
                return false, 'Rejected disposal'
            end
        end,
    })
    return f
end
local f = fixture()
f.pending_first = true
assert(not f.service.close() and f.service.state == 'draining' and #f.calls == 2)
assert(f.cohort.closing == true, 'Pending first fence left its certified upload cohort open')
assert(f.retain.bytes == 64 and #f.retain.records == 3 and not f.a.retiring)
f.pending_first = false
f.pending_second = true
assert(not f.service.close() and f.service.state == 'retiring')
assert(table.concat(f.calls, ',') == 'certificate,fence,fence,destroy2,destroy3,fence')
assert(f.retain.bytes == 64 and #f.retain.records == 3 and f.retain.cache.a == f.a)
local calls = #f.calls
assert(not f.service.close() and #f.calls == calls + 1, 'Pending second fence repeated disposal')
f.pending_second = false
assert(f.service.close() and f.service.state == 'closed')
assert(f.service.freed_count == 2 and f.service.freed_bytes == 48)
assert(f.retain.bytes == 16 and #f.retain.records == 1 and f.retain.records[1] == f.legacy)
assert(f.retain.cache.a == nil and f.retain.cache.b == nil and f.retain.cache.old == f.old)
assert(#f.retain.fences == 2 and f.cohort.sessions == nil)
calls = #f.calls
assert(f.service.close() and #f.calls == calls, 'Completed retirement retried native calls')

for _, fault in ipairs({
    'certificate',
    'missing_handle',
    'unknown_create',
    'bad_bytes',
    'duplicate_handle',
    'legacy_alias',
    'cache_alias',
    'accounting',
}) do
    local x = fixture()
    if fault == 'certificate' then
        x.certified = false
    elseif fault == 'missing_handle' then
        x.a.handle = nil
    elseif fault == 'unknown_create' then
        x.first.owned = nil
    elseif fault == 'bad_bytes' then
        x.first.bytes = 0 / 0
    elseif fault == 'duplicate_handle' then
        x.b.handle = x.a.handle
    elseif fault == 'legacy_alias' then
        x.old.handle = x.a.handle
    elseif fault == 'cache_alias' then
        x.retain.cache.foreign = { handle = x.a.handle }
    else
        x.retain.bytes = 40
    end
    assert(
        x.service.close() and x.service.state == 'quarantined' and x.service.reason,
        'Uncertified cohort reclaimed: ' .. fault
    )
    assert(#x.retain.records == 3 and x.retain.cache.a == x.a and x.cohort.sessions == nil)
    assert(not x.a.retiring and x.service.freed_count == 0)
    for _, call in ipairs(x.calls) do
        assert(call == 'certificate', 'Uncertified cohort reached a native callback')
    end
end
for _, fault in ipairs({ 'destroy_throw', 'destroy_false', 'fence_throw' }) do
    local x = fixture()
    x[fault] = true
    assert(x.service.close() and x.service.state == 'quarantined')
    assert(#x.retain.records == 3 and x.retain.bytes == 64 and x.service.freed_count == 0)
    calls = #x.calls
    assert(x.service.close() and #x.calls == calls, 'Ambiguous native disposal was retried blindly')
    if fault ~= 'fence_throw' then
        assert(x.a.retiring and x.b.retiring, 'Partial disposal left a reusable dead cache value')
    end
end
-- A newer cache entry is not removed by retirement of its former value.
local x = fixture()
x.pending_second = true
assert(not x.service.close())
local replacement = { handle = 9 }
x.retain.cache.a = replacement
local newer = { texture = replacement, owned = true, bytes = 8, cohort = { sessions = {} } }
x.retain.records[#x.retain.records + 1] = newer
x.retain.bytes = x.retain.bytes + 8
x.pending_second = false
assert(x.service.close())
assert(x.retain.cache.a == replacement and x.retain.records[2] == newer and x.retain.bytes == 24)
print(
    'PASS texture retirement: complete certified cohorts only, two fences, exact owned disposal/accounting, legacy/unknown quarantine, pending retries, ambiguous-call retention and no dead cache reuse'
)
