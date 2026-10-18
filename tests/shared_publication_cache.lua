local S = dofile('src/gear/shared_appearance.lua')
local revision, entries, encodes, polls, removals, identities = 1, 0, 0, 0, 0, 0
local identity = { body = 1, armor = 2, helmet = 3 }
local events = {}
package.preload['mods/skyeshade/hd2runtime'] = function()
    return {
        events = {
            on = function(name, callback)
                events[name] = callback
                return {
                    unsubscribe = function()
                        removals = removals + 1
                    end,
                }
            end,
        },
    }
end
local sharing = S.new({
    memory = {},
    game = 0,
    note = function() end,
    sync = {
        session = function()
            return {
                poll = function()
                    polls = polls + 1
                    return {}
                end,
                clear = function()
                    return true
                end,
            }
        end,
    },
    codec = {
        encode = function()
            encodes = encodes + 1
            return 'packet'
        end,
    },
    identity = function()
        identities = identities + 1
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
    entries = function()
        entries = entries + 1
        return {}
    end,
})
sharing.tick(2, true)
for _ = 1, 100 do
    sharing.tick(2, true)
end
assert(
    entries == 1 and encodes == 1 and polls == 101,
    'Unchanged publication rescanned local bindings or stopped receiving'
)
assert(identities == 1, 'Unchanged publication repeated native identity validation')
revision = 2
sharing.tick(2, true)
assert(entries == 2, 'Assignment change did not validate local appearance')
for _, name in ipairs({ 'player_died', 'player_spawned', 'mission_started', 'mission_ended' }) do
    assert(events[name])
    events[name]()
    sharing.tick(2, true)
end
assert(entries == 6 and encodes == 1, 'Lifecycle refresh did not validate or redundantly encoded unchanged pixels')
identity.armor = 4
sharing.tick(2, true)
assert(entries == 7 and encodes == 2, 'Changed equipment reused a stale packet')
sharing.close()
assert(removals == 4)
sharing.tick(2, true)
assert(entries == 8, 'Re-enabling sharing did not acquire fresh lifecycle subscriptions')
sharing.close()
assert(removals == 8)
print(
    'PASS Shared LUT publication: cached unchanged packet, continuous receive, assignment/lifecycle invalidation and subscription cleanup'
)
