local ffi = require('ffi')
local I = dofile('src/gear/unit_identity.lua')
local function unit(ref)
    return ffi.cast('void *', ref * 4)
end
local handle, other, portrait = unit(123), unit(124), unit(900)
local identity = { player = 7, unit = 8, avatar = 9, avatar_index = 0, units_at = 65536, peer_low = 10, peer_high = 11 }
local current_identity = identity
local garments = { { unit = 123, type = 0, slot = 1, preview = false } }
local current_worlds = { 'game', 'portrait' }
local current_main = 'game'
local world_units = { game = { handle, other }, portrait = { portrait } }
local alive, resources = true, '#ID[ABCDEF0123456789]'
local calls = { worlds = 0, units = 0, alive = 0, resource = 0 }
local excluded, world_changed, on_resource = false, false, nil
local E = {
    Application = {
        main_world = function()
            return current_main
        end,
        worlds = function()
            calls.worlds = calls.worlds + 1
            return current_worlds
        end,
    },
    World = {
        units = function(world)
            calls.units = calls.units + 1
            if world_changed then
                current_worlds = { 'portrait' }
                current_main = 'portrait'
            end
            return assert(world_units[world])
        end,
    },
    Unit = {
        alive = function(value)
            calls.alive = calls.alive + 1
            assert(type(value) == 'cdata' and value == handle, 'Numeric or unknown Unit argument reached alive')
            return alive
        end,
        resource_name = function(value)
            calls.resource = calls.resource + 1
            assert(type(value) == 'cdata' and value == handle, 'Numeric or unknown Unit argument reached resource_name')
            if on_resource then
                on_resource()
            end
            return resources
        end,
    },
}
local deps = {
    avatar = {
        resolve_live = function()
            return current_identity
        end,
        units = function(_, received, preview, first, last)
            assert(received == current_identity and preview == nil and first == 0 and last == 9)
            return garments
        end,
        resolve_remote = function()
            error('Remote avatar resolver called', 0)
        end,
    },
    excluded = function(value)
        return excluded or value == portrait
    end,
}
local helper = I.new(E, deps)
local function refuse(fn, needle, allowed_resource_calls)
    local before = calls.resource
    local ok, why = pcall(fn)
    assert(not ok and tostring(why):find(needle, 1, true), tostring(why))
    assert(calls.resource == before + (allowed_resource_calls or 0), 'Rejected target reached resource API')
    return tostring(why)
end
local hash, receipt = helper.resource(123, identity)
assert(hash == 'abcdef0123456789' and receipt.unit == handle and receipt.reference == 123 and receipt.world == 'game')
assert(helper.validate(receipt))
local selected, selected_receipt = helper.handle(123)
assert(selected == handle and helper.validate(selected_receipt))
local function id_string(text)
    local value = newproxy(true)
    getmetatable(value).__tostring = function()
        return text
    end
    return value
end
resources = id_string('[IdString64 "#ID[99bbb032f686274e]" 0x99bbb032f686274e]')
assert(helper.resource(123) == '99bbb032f686274e', 'Exact live IdString64 diagnostic failed to decode')
resources = id_string('[IdString64 "#ID[ABCDEF0123456789]" 0xabcdef0123456789]')
local wrapped_hash, wrapped_receipt = helper.resource(123)
assert(wrapped_hash == hash and helper.validate(wrapped_receipt), 'Observed IdString64 wrapper was not decoded exactly')
for _, text in ipairs({
    '[IdString64 "#ID[abcdef0123456789]" 0xabcdef0123456788]',
    '[IdString64 "#ID[abcdef012345678]" 0xabcdef0123456789]',
    '[IdString64 "#ID[abcdef0123456789]" 0xabcdef012345678]',
    '[IdString64 "#ID[abcdef0123456789]" 0xabcdef0123456789] extra',
    'prefix [IdString64 "#ID[abcdef0123456789]" 0xabcdef0123456789]',
    '#ID[abcdef0123456789]',
}) do
    resources = id_string(text)
    refuse(function()
        helper.resource(123)
    end, 'Stable Lua Unit resource ID unavailable', 1)
end
resources = '[IdString64 "#ID[abcdef0123456789]" 0xabcdef0123456789]'
refuse(function()
    helper.resource(123)
end, 'Stable Lua Unit resource ID unavailable', 1)
resources = setmetatable({}, {
    __tostring = function()
        return '#ID[abcdef0123456789]'
    end,
})
refuse(function()
    helper.resource(123)
end, 'Stable Lua Unit resource ID unavailable', 1)
resources = '#ID[ABCDEF0123456789]'
local plain_handle = handle
local tagged_receipt
for tag = 0, 3 do
    handle = ffi.cast('void *', 123 * 4 + tag)
    world_units.game = { handle, other }
    local tagged_hash
    tagged_hash, tagged_receipt = helper.resource(123)
    assert(
        tagged_hash == hash and tagged_receipt.unit == handle and helper.validate(tagged_receipt),
        'Tagged handle was discarded or replaced by a numeric reference'
    )
end
handle = ffi.cast('void *', 123 * 4 + 2)
world_units.game = { handle, other }
refuse(function()
    helper.validate(tagged_receipt)
end, 'handle or world changed')
handle, world_units.game = plain_handle, { plain_handle, other }
current_worlds = { 'portrait' }
local main_hash, main_receipt = helper.resource(123)
assert(main_hash == hash and main_receipt.world == 'game', 'Omitted main_world was not scanned')
current_worlds = { 'game', 'game', 'portrait' }
local scans = calls.units
helper.handle(123)
assert(calls.units == scans + 2, 'main_world/worlds duplicate entries caused repeated or ambiguous scans')
current_worlds = { 'game', 'portrait' }
local main_api = E.Application.main_world
E.Application.main_world = nil
assert(helper.resource(123) == hash, 'Enumerated-world fallback required main_world')
E.Application.main_world = main_api

local before_alive, before_worlds = calls.alive, calls.worlds
for _, ref in ipairs({ 0, -1, 1.25, 0xffffffff, math.huge, '123', handle }) do
    refuse(function()
        helper.resource(ref)
    end, 'Invalid native Unit reference')
end
assert(calls.alive == before_alive and calls.worlds == before_worlds, 'Invalid reference reached World/Unit APIs')
refuse(function()
    helper.resource(124)
end, 'not a current local garment')
refuse(function()
    helper.resource(900)
end, 'not a current local garment')
assert(
    calls.alive == before_alive and calls.worlds == before_worlds,
    'Unknown/portrait reference reached World/Unit APIs'
)

garments[1].preview = true
refuse(function()
    helper.resource(123)
end, 'not a current local garment')
garments[1].preview = nil
refuse(function()
    helper.resource(123)
end, 'not a current local garment')
garments[1].preview = false
world_units.game = { 123, 492, ffi.new('uint32_t', 492), ffi.cast('void *', 497), ffi.cast('void *', 3) }
refuse(function()
    helper.resource(123)
end, 'No live Lua Unit handle')
assert(calls.alive == before_alive, 'Numbers/scalar cdata/foreign or null handles reached Unit APIs')
world_units.game = { plain_handle, ffi.cast('void *', 123 * 4 + 1) }
refuse(function()
    helper.resource(123)
end, 'Ambiguous Unit reference')
world_units.game = { handle, other }
world_units.portrait = { portrait, handle }
refuse(function()
    helper.resource(123)
end, 'Ambiguous Unit reference')
world_units.portrait = { portrait }
excluded = true
refuse(function()
    helper.resource(123)
end, 'Preview-owned Unit refused')
excluded = false
assert(calls.alive == before_alive, 'Ambiguous/excluded handles reached Unit APIs')

world_changed = true
refuse(function()
    helper.resource(123)
end, 'Garment world disappeared')
world_changed = false
current_worlds = { 'game', 'portrait' }
current_main = 'game'
assert(calls.alive == before_alive, 'Freed world reached Unit APIs')
alive = false
refuse(function()
    helper.resource(123)
end, 'Unit disappeared')
alive = 0
refuse(function()
    helper.resource(123)
end, 'Unit disappeared')
alive = true

local bad = {}
refuse(function()
    helper.validate(bad)
end, 'Unknown or altered')
receipt.reference = 124
refuse(function()
    helper.validate(receipt)
end, 'Unknown or altered')
receipt.reference = 123
current_identity = {
    player = 7,
    unit = 8,
    avatar = 9,
    avatar_index = 0,
    units_at = 65536,
    peer_low = 12,
    peer_high = 11,
}
before_alive, before_worlds = calls.alive, calls.worlds
refuse(function()
    helper.validate(receipt)
end, 'Local avatar identity changed')
refuse(function()
    helper.resource(123, identity)
end, 'Local avatar identity changed')
assert(calls.alive == before_alive and calls.worlds == before_worlds, 'Changed identity reached World/Unit APIs')
current_identity['local'] = false
refuse(function()
    helper.resource(123)
end, 'Local avatar unavailable')
current_identity = identity
garments = {}
refuse(function()
    helper.validate(receipt)
end, 'not a current local garment')
garments = { { unit = 123, type = 0, slot = 1, preview = false } }

world_units.game = {}
refuse(function()
    helper.validate(receipt)
end, 'No live Lua Unit handle')
world_units.game = { handle, other }
world_units.portrait = { handle }
world_units.game = {}
refuse(function()
    helper.validate(receipt)
end, 'handle or world changed')
world_units.game, world_units.portrait = { handle, other }, { portrait }

resources = 'content/unknown'
local why = refuse(function()
    helper.resource(123)
end, 'Stable Lua Unit resource ID unavailable', 1)
assert(why:find('type=string', 1, true) and why:find('value="content/unknown"', 1, true))
resources = setmetatable({}, {
    __tostring = function()
        return ('a'):rep(4096) .. '\nprivate-tail'
    end,
})
why = refuse(function()
    helper.resource(123)
end, 'Stable Lua Unit resource ID unavailable', 1)
assert(
    #why < 256 and why:find('type=table', 1, true) and not why:find('private-tail', 1, true),
    'Resource failure diagnostic was not bounded'
)
resources = setmetatable({}, {
    __tostring = function()
        error('internal diagnostic should stay private', 0)
    end,
})
why = refuse(function()
    helper.resource(123)
end, 'Stable Lua Unit resource ID unavailable', 1)
assert(why:find('<tostring failed>', 1, true) and not why:find('stay private', 1, true))
resources = nil
why = refuse(function()
    helper.resource(123)
end, 'Stable Lua Unit resource ID unavailable', 1)
assert(why:find('type=nil', 1, true))
resources = '#ID[ABCDEF0123456789]'
on_resource = function()
    garments = {}
end
refuse(function()
    helper.resource(123)
end, 'not a current local garment', 1)
on_resource = nil
garments = { { unit = 123, type = 0, slot = 1, preview = false } }
local overflow = {}
for n = 1, I.MAX_WORLDS + 1 do
    overflow[n] = 'world' .. n
end
current_worlds = overflow
refuse(function()
    helper.resource(123)
end, 'World list bounds changed')
current_worlds = { 'game', 'portrait' }
overflow = {}
for n = 1, I.MAX_UNITS + 1 do
    overflow[n] = other
end
world_units.game = overflow
refuse(function()
    helper.resource(123)
end, 'World Unit list bounds changed')
world_units.game = { handle, other }
overflow = {}
for n = 1, I.MAX_GARMENTS + 1 do
    overflow[n] = garments[1]
end
garments = overflow
refuse(function()
    helper.resource(123)
end, 'Local garment list bounds changed')
print(
    'PASS Lua Unit identity: genuine tagged handles preserved, main-world plus deduplicated bounded worlds, local non-preview membership, immutable receipts and stale/freed/ambiguous rejection; read-only'
)
-- Receipt validation remains fresh but does not allocate the entire World.
garments = { { unit = 123, type = 0, slot = 1, preview = false } }
current_identity, current_worlds, current_main = identity, { 'game', 'portrait' }, 'game'
world_units.game, alive, excluded, world_changed = { handle, other }, true, false, false
local _, direct_receipt = helper.handle(123)
local direct_world = 'game'
E.Unit.world = function(value)
    assert(value == handle, 'Direct ownership query received a fabricated handle')
    return direct_world
end
local before_units = calls.units
for _ = 1, 1000 do assert(helper.validate(direct_receipt)) end
assert(calls.units == before_units, 'Receipt validation enumerated World Units')
direct_world = 'portrait'
refuse(function() helper.validate(direct_receipt) end, 'handle or world changed')
direct_world, garments = 'game', {}
refuse(function() helper.validate(direct_receipt) end, 'not a current local garment')
garments = { { unit = 123, type = 0, slot = 1, preview = false } }
excluded = true
refuse(function() helper.validate(direct_receipt) end, 'Preview-owned Unit refused')
excluded, resources = false, '#ID[ABCDEF0123456789]'
assert(helper.resource(123) == 'abcdef0123456789')
before_units = calls.units
for _ = 1, 1000 do assert(helper.resource(123) == 'abcdef0123456789') end
assert(calls.units == before_units, 'Known genuine garment handle was rediscovered from the entire World')
print('PASS direct garment receipt validation: no world enumeration, moved/removed/preview owners refused')
