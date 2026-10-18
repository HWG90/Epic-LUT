local fixture = dofile('tests/weapon_fixture.lua')
local desired, calls = {}, 0
local lease = {
    sync = function(bindings)
        desired = {}; for _, b in ipairs(bindings) do desired[b] = true end
        calls = calls + 1
    end,
    pending = function() return next(desired) ~= nil end,
}
local f = fixture(lease)
f.runtime.refresh(1)
local document = f.runtime.load(1, 1, 'material')
local before = calls
f.runtime.apply(document, 1, 1, 'material')
assert(calls == before + 2 and next(desired), 'Apply did not acquire and reconcile source ownership')
assert(not f.runtime.retirement_certificate(), 'Live source lease certified retired')
local assigned = {}; for b in pairs(desired) do assigned[b] = true end
f.fail_write = #f.writes + 1
document.data[0] = document.data[0] + 0.25
assert(not pcall(f.runtime.apply, document, 1, 1, 'material'))
for b in pairs(assigned) do assert(desired[b], 'Failed apply released previous source ownership') end
f.fail_write = nil
assert(f.runtime.restore(1) and not next(desired), 'Restore leaked source ownership')
assert(f.runtime.retirement_certificate())
print('PASS weapon source transaction: acquire before native apply, preserve prior lease on rollback, release on Restore')
