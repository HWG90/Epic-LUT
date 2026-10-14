-- Real receiver, binding sessions and destination discovery with independently
-- loaded armor/helmet Patterns, as during ship-to-mission material streaming.
local ffi = require('ffi')
local S = dofile('src/gear/shared_appearance.lua')
local B = dofile('src/gear/binding_session.lua')
local T = dofile('src/gear/shared_targets.lua')
local function fixture()
    local state = {
        ready = false,
        fail = false,
        restore_pending = false,
        reads = 0,
        writes = {},
        created = 0,
        bound = { [11] = 100, [22] = 200 },
        present = { [11] = true, [22] = true },
    }
    local armor = { width = 3, height = 1, data = ffi.new('float[12]') }
    armor.data[0] = 0.25
    local helmet = { width = 3, height = 1, data = ffi.new('float[12]') }
    helmet.data[0] = 0.75
    local appearance =
        { body = 1, armor = 2, helmet = 3, entries = { ['p:0:1:0:0'] = { document = armor }, ['p:0:0:0:0'] = {
            document = helmet,
        } } }
    local units = { { unit = 1, type = 0, slot = 1 }, { unit = 2, type = 0, slot = 0 } }
    local retain = { cache = {}, records = {}, bytes = 0 }
    local function materials(unit)
        if state.throw_targets then
            error('Material list not ready')
        end
        if unit == 2 and not state.ready then
            return {}
        end
        local m = unit == 1 and 11 or 22
        return { { mesh = unit * 10, material = m, mesh_index = 0, material_index = 0 } }
    end
    local function binding(b)
        return state.bound[b.material]
    end
    local function key(b)
        return b.unit .. ':' .. b.mesh .. ':' .. b.material
    end
    local roster = { { peer_low = 12, peer_high = 0, text = 'same-packet' } }
    local deps = {
        memory = {},
        game = 0,
        note = function() end,
        highlighting = function()
            return false
        end,
        identity = function()
            return appearance
        end,
        entries = function()
            return {}
        end,
        codec = {
            encode = function()
                return 'outgoing'
            end,
            decode = function()
                return appearance
            end,
        },
        sync = {
            session = function()
                return {
                    poll = function()
                        return roster
                    end,
                    clear = function()
                        return true
                    end,
                }
            end,
        },
        players = function()
            return { { peer_low = 12, peer_high = 0 } }
        end,
        resolve = function()
            return appearance
        end,
        targets = function()
            return T.garments(units, appearance, materials, binding, key, 1, 2)
        end,
        bindings = function()
            local session = B.new({
                retain = retain,
                key = function(b)
                    return key(b) .. ':' .. b.slot
                end,
                present = function(b)
                    return state.present[b.material]
                end,
                binding = binding,
                create_texture = function(_, _, data)
                    state.created = state.created + 1
                    return { object = 1000 + state.created, data = data }
                end,
                bind = function(b, object)
                    if
                        state.fail
                        or (object >= 1000 and state.fail_after and (state.forward_writes or 0) >= state.fail_after)
                    then
                        error('streaming rejected bind')
                    end
                    if state.restore_pending and object < 1000 then
                        error('restoration pending')
                    end
                    if object >= 1000 then
                        state.forward_writes = (state.forward_writes or 0) + 1
                    end
                    state.bound[b.material] = object
                    state.writes[b.material] = (state.writes[b.material] or 0) + 1
                end,
            })
            return session
        end,
    }
    local service = S.new(deps)
    local function drain()
        for i = 1, 8 do
            service.tick(0.01, true)
        end
    end
    return state, service, drain, deps, roster, units, appearance
end
do
    local state, s, drain, deps, roster, units, appearance = fixture()
    s.tick(2, true)
    drain()
    assert(state.bound[11] >= 1000 and state.bound[22] == 200)
    state.ready = true
    state.bound[22] = 0
    s.tick(2, true)
    drain()
    assert(state.bound[22] == 0, 'Unavailable texture slot was written')
    state.bound[22] = 200
    s.tick(2, true)
    drain()
    assert(
        state.bound[11] >= 1000 and state.bound[22] >= 1000 and state.bound[11] ~= state.bound[22],
        'Late helmet material was ignored on unchanged Units/packet'
    )
    local armor, helmet = state.bound[11], state.bound[22]
    local armor_writes = state.writes[11]
    local creates = state.created
    state.bound[22] = 200
    s.tick(2, true)
    drain()
    assert(
        state.bound[22] == helmet and state.bound[11] == armor,
        'Known stock reset did not restore the independent helmet camo'
    )
    assert(
        state.writes[11] == armor_writes and state.created == creates,
        'Repair rewrote healthy armor or allocated another texture'
    )
    local _, first = deps.targets(nil, appearance)
    units[1], units[2] = units[2], units[1]
    local _, second = deps.targets(nil, appearance)
    assert(first == second, 'Enumeration order changed a stable destination signature')
    state.bound[22] = 9999
    local before = state.writes[22]
    s.tick(2, true)
    drain()
    assert(state.bound[22] == 9999 and state.writes[22] == before, 'Repair overwrote a foreign binding')
    s.tick(0.01, false)
    assert(state.bound[11] == 100 and state.bound[22] == 9999, 'Sharing off touched foreign state or retained armor')
    assert(s.close())
end
do
    local state, s, drain = fixture()
    state.ready = true
    state.fail = true
    s.tick(2, true)
    drain()
    assert(state.bound[11] == 100 and state.bound[22] == 200)
    state.fail = false
    s.tick(2, true)
    drain()
    assert(state.bound[11] >= 1000 and state.bound[22] >= 1000, 'Failed apply never retried the unchanged peer packet')
    state.throw_targets = true
    s.tick(2, true)
    state.throw_targets = false
    s.tick(2, true)
    drain()
    assert(state.bound[11] >= 1000 and state.bound[22] >= 1000, 'Material read failure prevented later recovery')
    assert(s.close())
end
do
    local state, s, drain = fixture()
    state.ready = true
    state.fail_after = 1
    state.restore_pending = true
    s.tick(2, true)
    drain()
    assert(next(s.peers) ~= nil, 'Failed restoration discarded its ownership receipt')
    local creates = state.created
    state.fail_after = nil
    s.tick(2, true)
    drain()
    assert(state.created == creates, 'Retry allocated textures while old restoration was pending')
    state.restore_pending = false
    s.tick(2, true)
    drain()
    assert(
        state.bound[11] >= 1000 and state.bound[22] >= 1000,
        'Pending restoration prevented later retry of the same packet'
    )
    assert(s.close())
end
print(
    'PASS Shared LUT transition recovery: separate armor/helmet camos, late material readiness, stable order, exact reset repair, cached textures, foreign isolation, failed apply/target retries and off cleanup'
)
