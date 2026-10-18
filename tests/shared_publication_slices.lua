local S = dofile('src/gear/shared_appearance.lua')
local revision, encoded, published = 1, 0, nil
local identity = { body = 1, armor = 2, helmet = 3 }
local deps = {
    defer_publication = true,
    identity = function()
        return identity
    end,
    identity_key = function()
        return identity.armor
    end,
    revision = function()
        return revision
    end,
    highlighting = function()
        return false
    end,
    entries = function(value)
        assert(value == identity, 'Publication repeated or lost identity')
        return {}
    end,
    codec = {
        encode = function(_, _, checkpoint)
            for _ = 1, 4 do
                checkpoint(true)
            end
            encoded = encoded + 1
            return 'packet-' .. revision
        end,
    },
    sync = {
        session = function()
            return {
                poll = function(_, out)
                    published = out
                    return {}
                end,
                clear = function()
                    return true
                end,
            }
        end,
    },
    note = function() end,
}
local s = S.new(deps)
s.tick(2, true)
assert(encoded == 0, 'Whole packet built in the scheduling frame')
s.tick(0, true)
revision = 2
for _ = 1, 10 do
    s.tick(0, true)
end
assert(encoded == 1)
s.tick(2, true)
assert(published == nil, 'Stale in-flight packet was published')
for _ = 1, 10 do
    s.tick(0, true)
end
s.tick(2, true)
assert(published == 'packet-2')
for _ = 1, 100 do
    s.tick(2, true)
end
assert(encoded == 2, 'Unchanged deferred publication was rebuilt')
revision = 3
s.tick(2, true)
s.close()
for _ = 1, 10 do
    s.tick(0, false)
end
assert(encoded == 2, 'Closed publication job kept running')
print(
    'PASS publication slices: bounded stages, exact identity reuse, stale generation rejection, idle cache and close cancellation'
)

local before = encoded
revision = 4
s.tick(2, true)
s.tick(0, true)
s.invalidate()
for _ = 1, 10 do
    s.tick(0, true)
end
s.tick(2, true)
assert(published ~= 'packet-4', 'Lifecycle invalidation during a job was lost')
for _ = 1, 10 do
    s.tick(0, true)
end
s.tick(2, true)
assert(published == 'packet-4' and encoded == before + 2)
s.close()
