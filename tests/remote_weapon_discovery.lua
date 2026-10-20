local fixture = dofile('tests/weapon_fixture.lua')
local D = dofile('src/weapons/weapon_discovery.lua')
local Sessions = dofile('src/gear/binding_session.lua')
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
local function remote_fixture()
    local f = fixture()
    f.peer = { player = 19, unit = 177, peer_low = 0x11223344, peer_high = 0x55667788 }
    f.authorized, f.member, f.authorization_calls = true, true, 0
    f.make_unit(400, 5, '5fecab819f96a3e8')
    f.remote_snapshots = {}
    for slot = 1, 3 do
        f.remote_snapshots[slot] = {
            game_base = 0x100000,
            player_entity = 19,
            avatar_entity = 30,
            avatar_native_ref = 177,
            weapon_slot = slot,
            weapon_entity = 1400,
            weapon_record = 0x200000 + 400 * 24,
            weapon_resource64 = '5fecab819f96a3e8',
            weapon_resource = '5fecab819f96a3e8',
            weapon_unit_ref = 400,
            weapon_native_ref = 900,
            weapon_object = 0x400000 + 400 * 128,
            remote = true,
            peer_player = 19,
            peer_unit = 177,
            peer_low = f.peer.peer_low,
            peer_high = f.peer.peer_high,
        }
    end
    f.identity.snapshot_remote = function(peer, slot)
        if not f.member then
            return nil, 'Remote peer is not a current player'
        end
        for _, field in ipairs({ 'player', 'unit', 'peer_low', 'peer_high' }) do
            if peer[field] ~= f.peer[field] then
                return nil, 'Remote peer membership changed'
            end
        end
        local saved = f.remote_snapshots[slot]
        if not saved then
            return nil, 'Weapon inventory slot is empty'
        end
        local copied = {}
        for key, value in pairs(saved) do
            copied[key] = value
        end
        return copied
    end
    f.identity.snapshot_remote_cleanup = function(peer, slot, captured)
        if f.row_reused then
            return nil, 'Remote cleanup peer row was cleared or reused'
        end
        for _, field in ipairs({ 'player', 'unit', 'peer_low', 'peer_high' }) do
            if peer[field] ~= f.peer[field] then
                return nil, 'Remote cleanup peer changed'
            end
        end
        local saved = f.remote_snapshots[slot]
        if not saved or saved.weapon_object ~= captured.weapon_object then
            return nil, 'Remote cleanup Unit was recycled'
        end
        local copy = {}
        for field, value in pairs(saved) do
            copy[field] = value
        end
        copy.cleanup_only = true
        return copy
    end
    f.discovery_deps.remote_authorized = function(peer, slot, resource)
        f.authorization_calls = f.authorization_calls + 1
        assert(
            peer.player == f.peer.player
                and peer.unit == f.peer.unit
                and peer.peer_low == f.peer.peer_low
                and peer.peer_high == f.peer.peer_high
                and slot >= 1
                and slot <= 3
                and #resource == 16
        )
        return f.authorized and f.member, 'Remote peer consent or current lobby membership changed'
    end
    return f
end
test('remote editing is disabled without an explicit authority callback', function()
    local f = remote_fixture()
    f.discovery_deps.remote_authorized = nil
    local missing, why = f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8')
    assert(not missing and why:find('Remote weapon editing is not authorized', 1, true))
    assert(f.discovery.capture(1), 'Remote availability blocked the local editor')
end)
test('explicit peer receipts retain resource slot and peer scope on every descriptor', function()
    local f = remote_fixture()
    local receipt, why = f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8')
    assert(receipt, why)
    local rows = f.discovery.materials(receipt)
    local b = assert(f.discovery.descriptor(receipt, rows[1], D.LUT))
    assert(b.kind == 'weapon' and b.type == 3 and b.remote and b.peer_player == 19 and b.peer_unit == 177)
    assert(b.peer_low == f.peer.peer_low and b.peer_high == f.peer.peer_high and b.weapon_slot == 1 and b.slot == D.LUT)
    assert(b.weapon_resource == '5fecab819f96a3e8' and f.discovery.write_guard(b))
    local missing = f.discovery.capture_remote({ player = '19' }, 1, '5fecab819f96a3e8')
    assert(not missing)
end)
test('resource and peer mismatches fail before any genuine Unit native reads', function()
    local f = remote_fixture()
    local calls = 0
    local alive = f.native.alive
    f.native.alive = function(ref)
        calls = calls + 1
        return alive(ref)
    end
    local missing, why = f.discovery.capture_remote(f.peer, 1, 'ffffffffffffffff')
    assert(not missing and why:find('expected resource changed', 1, true) and calls == 0)
    f.remote_snapshots[1].peer_player = 99
    missing, why = f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8')
    assert(not missing and why:find('identity scope', 1, true) and calls == 0)
end)
test('consent membership and generation revocation invalidate current remote receipts', function()
    local f = remote_fixture()
    local receipt = assert(f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8'))
    local b = f.discovery.descriptor(receipt, f.discovery.materials(receipt)[1], D.LUT)
    f.authorized = false
    assert(not f.discovery.present(b) and not f.discovery.write_guard(b))
    f.authorized = true
    f.member = false
    assert(not f.discovery.validate(receipt))
    f.member = true
    f.remote_snapshots[1].weapon_object = f.remote_snapshots[1].weapon_object + 1
    assert(not f.discovery.present(b))
    assert(f.discovery.capture(1), 'Remote revocation affected the local scope')
end)
test('remote pointer aliases to local or other peer units are refused', function()
    local f = remote_fixture()
    local receipt = assert(f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8'))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then
            targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT)
        end
    end
    assert(f.discovery.prove_private(targets))
    f.units[100].meshes[1].materials[1] = targets[1].material
    local private, why = f.discovery.prove_private(targets)
    assert(not private and why:find('aliases another destination', 1, true))
    assert(#f.writes == 0)
end)
test('peer-scoped session checks authorization immediately before every write', function()
    local f = remote_fixture()
    local receipt = assert(f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8'))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then
            targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT)
        end
    end
    local session = Sessions.new({
        retain = f.retain,
        cohort = f.cohort,
        key = function(b)
            return b.unit .. ':' .. b.mesh .. ':' .. b.material .. ':' .. b.slot
        end,
        present = f.discovery.present,
        binding = f.discovery.binding,
        create_texture = function()
            f.authorized = false
            return { object = 0x70001000 }
        end,
        bind = function(b, object)
            assert(f.discovery.write_guard(b), 'Remote write permission changed')
            f.writes[#f.writes + 1] = { binding = b, object = object }
        end,
    })
    local ok, why = pcall(session.apply, f.documents[f.A], targets)
    assert(not ok and (tostring(why):find('Remote write permission changed', 1, true)
        or tostring(why):find('LUT target changed after preparation', 1, true)))
    assert(#f.writes == 0 and f.authorization_calls > 1)
end)
test('revoked consent and departed membership permit only checked restoration of owned objects', function()
    local f = remote_fixture()
    local receipt = assert(f.discovery.capture_remote(f.peer, 1, '5fecab819f96a3e8'))
    local targets = {}
    for _, row in ipairs(f.discovery.materials(receipt)) do
        if row.material_index == 0 then
            targets[#targets + 1] = f.discovery.descriptor(receipt, row, D.LUT)
        end
    end
    local b = targets[1]
    b.current = 0x70001000
    f.textures[b.material][b.slot] = b.current
    f.authorized, f.member = false, false
    assert(not f.discovery.present(b) and not f.discovery.write_guard(b))
    assert(f.discovery.cleanup_present(b) and f.discovery.cleanup_binding(b) == b.current)
    assert(f.discovery.prove_cleanup_private(targets))
    assert(f.discovery.cleanup_write_guard(b, b.current, b.original))
    assert(not f.discovery.cleanup_write_guard(b, b.current, 0x70002000), 'Cleanup enabled recoloring')
    f.textures[b.material][b.slot] = 0xdead00
    assert(not f.discovery.cleanup_write_guard(b, b.current, b.original), 'Cleanup overwrote a foreign writer')
    f.row_reused = true
    assert(not f.discovery.cleanup_present(b))
end)
print('PASS remote weapon discovery: ' .. cases .. ' focused contracts')
