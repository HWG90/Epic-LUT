local S = dofile('src/gear/shared_appearance.lua')
local peer = { peer_low = 12, peer_high = 0, unit = 7 }
local appearance = { body = 1, armor = 2, helmet = 3 }
local identity = { body = 1, armor = 2, helmet = 3 }
local packet, members, posted, applied, restored, cleared = 'full', {}, nil, 0, 0, false
local unit_signature, original = '7', 100
local doc = {}
local deps = {
    memory = {},
    game = 0,
    sync = {
        natives = function() end,
        session = function()
            return {
                poll = function(_, text)
                    posted = text
                    return members
                end,
                clear = function()
                    cleared = true
                end,
            }
        end,
    },
    codec = {
        encode = function()
            return packet
        end,
        decode = function(text)
            assert(text == 'full' or text == 'updated')
            return appearance
        end,
    },
    note = function() end,
    highlighting = function()
        return false
    end,
    entries = function()
        return {}
    end,
    identity = function()
        return identity
    end,
    players = function()
        return { peer }
    end,
    resolve = function()
        return identity
    end,
    targets = function()
        return { [doc] = { { original = original } } }, unit_signature
    end,
    bindings = function()
        return {
            apply = function(_, targets)
                assert(targets[1].original == 100, 'Targets captured before restore')
                applied = applied + 1
                original = 200
            end,
            restore = function()
                restored = restored + 1
                original = 100
                return true
            end,
        }
    end,
}
local service = S.new(deps)
members = { { peer_low = 12, peer_high = 0, text = 'full' } }
service.tick(2, true)
service.tick(0.1, true)
assert(applied == 1 and posted == 'full')
service.tick(2, true)
service.tick(0.1, true)
assert(applied == 1, 'Unchanged appearance reapplied')
members[1].text = 'updated'
service.tick(2, true)
service.tick(0.1, true)
assert(applied == 2 and restored == 1, 'Changed packet did not restore prior appearance')
members[1].text = 'invalid'
service.tick(2, true)
assert(next(service.peers) == nil and restored == 2, 'Malformed remote packet left appearance applied')
members[1].text = 'full'
service.tick(2, true)
service.tick(0.1, true)
service.tick(0.1, false)
assert(next(service.peers) == nil, 'Sharing off did not restore remote appearance immediately')
assert(service.close() and cleared)
peer['local'] = true
local local_only = S.new(deps)
local_only.tick(2, true)
local_only.tick(0.1, true)
assert(next(local_only.peers) == nil, 'Local player was treated as a remote target')
print(
    'PASS sharing lifecycle: exact peer ownership, packet updates, unchanged no-op, malformed restore, off and cleanup'
)
