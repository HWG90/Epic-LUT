local Sharing = dofile('src/gear/shared_appearance.lua')
local resource = '5fecab819f96a3e8'
local peer = { peer_low = 12, peer_high = 0, player = 20, unit = 7 }
local members, players, configuration = {}, { peer }, resource
local sharing = Sharing.new({
    sync = {
        session = function()
            return {
                poll = function()
                    return members
                end,
                clear = function()
                    return true
                end,
            }
        end,
    },
    codec = {
        decode = function(text)
            assert(text == 'valid')
            return { weapons = { configuration } }
        end,
    },
    note = function() end,
    players = function()
        return players
    end,
})
assert(not sharing.authorized(peer, 1, resource))
sharing.enabled = true
members = { { peer_low = 12, peer_high = 0, text = 'valid' } }
assert(sharing.authorized(peer, 1, resource))
configuration = '1111111111111111'
assert(not sharing.authorized(peer, 1, resource))
configuration = resource
players = { { peer_low = 12, peer_high = 0, player = 20, unit = 8 } }
assert(not sharing.authorized(peer, 1, resource))
players, members = { peer }, {}
assert(not sharing.authorized(peer, 1, resource))
members = { { peer_low = 12, peer_high = 0, text = 'invalid' } }
assert(not sharing.authorized(peer, 1, resource))
sharing.enabled = false
assert(not sharing.authorized(peer, 1, resource))
local applied, restored, notes, refuse = 0, 0, {}, false
members = { { peer_low = 12, peer_high = 0, text = 'valid' } }
local appearance = { body = 1, armor = 2, helmet = 3, weapons = { resource } }
local doc = {}
local receiving = Sharing.new({
    sync = {
        session = function()
            return {
                poll = function()
                    return members
                end,
                clear = function()
                    return true
                end,
            }
        end,
    },
    codec = {
        decode = function()
            return appearance
        end,
    },
    note = function(value)
        notes[#notes + 1] = value
    end,
    players = function()
        return { peer }
    end,
    identity = function()
        return nil
    end,
    resolve = function()
        return { body = 4, armor = 5, helmet = 6, weapons = { resource } }
    end,
    targets = function()
        if refuse then
            error('Weapon ownership changed')
        end
        return { [doc] = { {} } }, 'same-weapon'
    end,
    bindings = function()
        return {
            apply = function()
                applied = applied + 1
            end,
            restore = function()
                restored = restored + 1
                return true
            end,
        }
    end,
})
receiving.tick(2, true)
receiving.tick(0.01, false)
assert(applied == 0 and restored == 1, 'Revoked sharing resumed a pending native write job')
receiving.tick(2, true)
receiving.tick(0.01, true)
assert(applied == 1)
refuse = true
assert(pcall(receiving.tick, 2, true) and restored == 2, 'Peer ownership refusal escaped into the editor')
local count = #notes
assert(pcall(receiving.tick, 2, true) and #notes == count, 'Unchanged peer refusal repeatedly logged')
assert(receiving.close())
print('PASS Shared LUT containment: cancelled jobs on revoke and quiet peer-target refusal with restoration')
print(
    'PASS Shared LUT weapon authorization: fresh lobby advertisement/configuration, live peer identity and local consent'
)
