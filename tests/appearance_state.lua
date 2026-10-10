local State = dofile('src/gear/appearance_state.lua')
local state = State.new()
local a = { object = 100, data = {}, width = 23, height = 8 }
local p = { object = 200, data = {}, width = 3, height = 1 }
local proof = { armor = 'body:armor-a', helmet = 'helmet-a' }
local b = { armor = true, save_key = '0:1:0:0', original = 10, texture = a, resource = '0123456789ABCDEF' }
local function resource(binding)
    return binding.resource
end
local function current(binding)
    return binding.live
end
assert(state.remember({ b }, false, proof, resource) == 1 and state.count() == 1)
local entries = state.entries()
assert(entries[1].texture == a and entries[1].resource == '0123456789abcdef' and entries[1].proof == proof.armor)
entries[1].proof = 'changed'
assert(state.entries()[1].proof == proof.armor, 'Returned entries mutated registry identity')
local fresh = { armor = true, save_key = b.save_key, original = 99, live = 99, resource = b.resource }
local batches = state.batches({ fresh }, false, proof, resource, current)
assert(
    #batches == 1 and batches[1].document == a and batches[1].targets[1] == fresh,
    'New binding pointer did not match verified intent'
)
assert(fresh.texture == nil and fresh.live == 99, 'Intent lookup changed a binding')
fresh.live = 100
assert(#state.batches({ fresh }, false, proof, resource, current) == 0, 'Owned texture was not a no-op')
fresh.live = 777
assert(#state.batches({ fresh }, false, proof, resource, current) == 0, 'Foreign texture was targeted')
fresh.live = 99
assert(
    #state.batches({ fresh }, false, { armor = 'body:armor-b', helmet = proof.helmet }, resource, current) == 0,
    'Different gear inherited intent'
)
fresh.resource = 'fedcba9876543210'
assert(#state.batches({ fresh }, false, proof, resource, current) == 0, 'Different original resource inherited intent')
fresh.resource = b.resource
assert(#state.batches({ fresh }, true, proof, resource, current) == 0, 'Pattern/material types shared intent')
local replacement = { object = 101, data = {}, width = 23, height = 8 }
b.texture = replacement
assert(state.remember({ b }, false, proof, resource) == 1 and state.count() == 1)
assert(
    state.batches({ fresh }, false, proof, resource, current)[1].document == replacement,
    'Same exact identity did not replace intent'
)
local pattern = { armor = true, save_key = b.save_key, original = 20, texture = p, resource = b.resource }
assert(state.remember({ pattern }, true, proof, resource) == 1 and state.count() == 2)
assert(state.clear(nil, true) == 1 and state.count() == 1, 'Pattern-only restore cleared material intent')

local delayed = { helmet = true, save_key = '0:0:1:0', original = 30, texture = a }
local count, pending = state.remember({ delayed }, false, proof, resource)
assert(
    count == 0
        and #pending == 1
        and pending[1].texture == a
        and pending[1].proof == proof.helmet
        and pending[1].original == 30
)
delayed.texture = replacement
assert(pending[1].texture == a, 'Pending metadata followed a mutable binding texture')
pending[1].resource = '1111111111111111'
assert(state.remember(pending, false, { helmet = pending[1].proof }, resource) == 1 and state.count() == 2)
assert(state.remember({ b }, false, nil, resource) == 0, 'Missing gear proof was guessed')

local bounded = State.new()
local slots = {}
for n = 1, State.MAX_PROFILE + 1 do
    slots[n] = {
        armor = true,
        save_key = 'slot:' .. n,
        original = n + 1000,
        texture = a,
        resource = string.format('%016x', n),
    }
end
assert(
    not pcall(bounded.remember, slots, false, proof, resource) and bounded.count() == 0,
    'Profile overflow partially committed'
)
table.remove(slots)
for profile = 1, 4 do
    assert(bounded.remember(slots, false, { armor = 'body:armor-' .. profile }, resource) == State.MAX_PROFILE)
end
assert(bounded.count() == State.MAX_RECORDS)
assert(
    not pcall(bounded.remember, { slots[1] }, false, { armor = 'body:extra' }, resource)
        and bounded.count() == State.MAX_RECORDS,
    'Global appearance budget grew unbounded'
)
-- Large profiles survive snapshots and restore all fresh duplicate instances
-- through one shared immutable texture, preserving every semantic target.
local large_snapshot = bounded.entries()
assert(#large_snapshot == State.MAX_RECORDS)
assert(bounded.replace(large_snapshot) == State.MAX_RECORDS)
local batches = bounded.batches(slots, false, { armor = 'body:armor-1' }, resource, function(binding)
    return binding.original
end)
assert(#batches == 1 and #batches[1].targets == State.MAX_PROFILE and batches[1].document == a)
assert(bounded.clear('armor', false) == State.MAX_RECORDS and bounded.count() == 0)

-- Restore/Undo/Redo swap verified intent snapshots, preserving the exact cached
-- textures without changing live bindings or accepting a partial bad snapshot.
local before_restore = state.entries()
assert(state.clear() == 2 and state.count() == 0)
assert(state.replace(before_restore) == 2 and state.count() == 2)
local recovered = state.entries()
for i, record in ipairs(before_restore) do
    assert(
        recovered[i].texture == record.texture
            and recovered[i].resource == record.resource
            and recovered[i].proof == record.proof
            and recovered[i].save_key == record.save_key
    )
end
assert(
    state.batches({ fresh }, false, proof, resource, current)[1].document == replacement,
    'Undo snapshot did not restore the desired cached texture'
)
before_restore[1].proof = 'caller changed snapshot'
assert(state.entries()[1].proof ~= before_restore[1].proof, 'Replacement retained mutable snapshot headers')
local valid = state.entries()
local function copy(record)
    local out = {}
    for key, value in pairs(record) do
        out[key] = value
    end
    return out
end
local invalid = { copy(valid[1]), copy(valid[2]) }
invalid[2].resource = 'unverified'
assert(
    not pcall(state.replace, invalid) and state.count() == 2 and state.entries()[1].texture == valid[1].texture,
    'Invalid replacement partially committed'
)
assert(not pcall(state.replace, { valid[1], valid[1] }), 'Duplicate snapshot identities were accepted')
assert(not pcall(state.replace, { [1] = valid[1], [3] = valid[2] }), 'Sparse snapshot silently lost intent')
local overflow = {}
for i = 1, State.MAX_PROFILE + 1 do
    overflow[i] = copy(valid[1])
    overflow[i].save_key = 'slot:' .. i
end
assert(not pcall(state.replace, overflow) and state.count() == 2, 'Profile overflow replacement was not atomic')
overflow = {}
for i = 1, State.MAX_RECORDS + 1 do
    overflow[i] = copy(valid[1])
    overflow[i].proof = 'gear:' .. i
end
assert(not pcall(state.replace, overflow) and state.count() == 2, 'Global overflow replacement was not atomic')
assert(state.replace({}) == 0 and state.count() == 0, 'Redo of a cleared snapshot did not clear all intent')
print(
    'PASS appearance intent: exact gear/slot/resource matching, replacement, immutable pending metadata, no foreign writes, pattern scope and atomic bounded capacity'
)
