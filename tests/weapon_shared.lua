local F = dofile('tests/weapon_services_fixture.lua')
local Mapping = dofile('src/editor/weapon_mapping.lua')
local S = dofile('src/weapons/weapon_shared.lua')
local Codec = dofile('src/gear/shared_lut_codec.lua')
local Session = dofile('src/gear/binding_session.lua')
local function fixture()
    local f = F.new()
    f.allowed, f.owner, f.auth_calls, f.writes, f.private_calls = true, true, 0, 0, 0
    f.peer = {
        ['local'] = false,
        player = 70,
        unit = 80,
        peer_low = 9,
        peer_high = 10,
        body = 1,
        armor = 2,
        helmet = 3,
    }
    local actual, descriptors = {}, {}
    local original = F.document(23, 8, 0, '0000000000000011')
    local pattern = F.document(3, 1, 0, '0000000000000022')
    local local_group = f.group(1, 'material', 1, original.resource, 0)
    local local_binding = local_group.bindings[1]
    f.set_document(local_binding, F.document(23, 8, 5.75))
    local_binding.texture = {
        object = local_binding.current,
        width = 23,
        height = 8,
        data = Mapping.copy(local_binding.document).data,
    }
    local receipt = { unit = 7000, unit_resource64 = f.config[1], weapon_resource64 = f.config[1] }
    local discovery = {}
    function discovery.capture(slot)
        return slot == 1 and { weapon_resource64 = f.config[1] } or nil
    end
    function discovery.capture_remote(peer, slot, expected)
        assert(peer.player == f.peer.player and peer.unit == f.peer.unit and expected == f.config[1] and slot == 1)
        return f.allowed and f.owner and receipt or nil, 'Remote owner/consent changed'
    end
    function discovery.materials(value)
        assert(value == receipt)
        return { { mesh_index = 0, material_index = 0, mesh = 100000, material = 200000 } }
    end
    function discovery.descriptor(value, row, slot)
        assert(value == receipt)
        local b = {
            kind = 'weapon',
            remote = true,
            peer_scope = 'remote',
            unit = receipt.unit,
            mesh = row.mesh,
            material = row.material,
            slot = slot,
            original = slot == 0x7e662968 and 50001 or 50002,
            save_key = '3:1:0:0',
            weapon_slot = 1,
            weapon_resource = f.config[1],
            receipt = receipt,
            peer_player = f.peer.player,
            peer_unit = f.peer.unit,
            peer_low = f.peer.peer_low,
            peer_high = f.peer.peer_high,
        }
        b.current = b.original
        actual[b], descriptors[#descriptors + 1] = b.current, b
        return b
    end
    function discovery.validate(value)
        return value == receipt and f.allowed and f.owner
    end
    function discovery.present(b)
        if b == local_binding then
            return f.owner
        end
        return f.allowed and f.owner and actual[b] ~= nil
    end
    function discovery.binding(b)
        assert(discovery.present(b))
        return b == local_binding and b.current or actual[b]
    end
    function discovery.dead()
        return f.dead == true
    end
    function discovery.prove_private(targets)
        f.private_calls = f.private_calls + 1
        return f.allowed and f.owner and not f.alias, 'Aliased or unauthorized material'
    end
    function discovery.write_guard(b)
        return discovery.present(b)
    end
    function discovery.cleanup_present(b)
        return f.owner and actual[b] ~= nil
    end
    function discovery.cleanup_binding(b)
        assert(discovery.cleanup_present(b))
        return actual[b]
    end
    function discovery.prove_cleanup_private()
        return f.owner and not f.alias
    end
    function discovery.cleanup_write_guard(b, owned, target)
        return discovery.cleanup_present(b)
            and actual[b] == owned
            and (owned == b.current or owned == b.previous)
            and target == b.original
    end
    local retain = { records = {}, cache = {}, bytes = 0 }
    local next_object = 80000
    f.deps = {
        runtime = {
            all_owned = function()
                return { local_binding }
            end,
        },
        discovery = discovery,
        weapon_mapping = Mapping,
        binding_session = Session,
        retain = retain,
        cohort = {},
        remote_snapshot = function(peer, slot)
            assert(peer.player == f.peer.player)
            return slot == 1
                    and {
                        remote = true,
                        peer_player = peer.player,
                        peer_unit = peer.unit,
                        peer_low = peer.peer_low,
                        peer_high = peer.peer_high,
                        weapon_slot = 1,
                        weapon_resource64 = f.config[1],
                    }
                or nil
        end,
        remote_authorized = function(peer, slot, resource)
            f.auth_calls = f.auth_calls + 1
            return f.allowed
                and f.owner
                and peer.player == f.peer.player
                and peer.unit == f.peer.unit
                and peer.peer_low == f.peer.peer_low
                and peer.peer_high == f.peer.peer_high
                and slot == 1
                and resource == f.config[1]
        end,
        original = function(_, b, family)
            return family == 'pattern' and pattern or original
        end,
        create_texture = function(width, height, data)
            next_object = next_object + 1
            if f.revoke_on_create then
                f.allowed = false
            end
            return { object = next_object, width = width, height = height, data = data }
        end,
        bind = function(b, object)
            f.writes = f.writes + 1
            actual[b] = object
        end,
    }
    f.local_binding, f.original = local_binding, original
    f.discovery, f.descriptors = discovery, descriptors
    f.actual = function(b)
        return actual[b]
    end
    f.provider = S.new(f.deps)
    return f
end
local f = fixture()
local local_identity = f.provider.local_identity({ body = 1, armor = 2, helmet = 3 })
local local_entries = f.provider.local_entries(local_identity)
assert(local_identity.weapons[1] == f.config[1] and local_identity.weapons[2] == nil and #local_entries == 1)
f.local_binding.document.data[0] = 99 -- A later dirty editor draft is not the uploaded texture.
assert(
    local_entries[1].document.data[0] == 5.75 and f.provider.local_entries(local_identity)[1].document.data[0] == 5.75
)
local codec = Codec.new(nil, function(resource)
    return resource == f.original.resource and f.original or nil
end)
local packet = codec.encode(local_identity, local_entries)
assert(packet:match('^6x?|'))
local appearance = codec.decode(packet)
local remote_identity = f.provider.remote_identity(f.peer)
local targets, signature = f.provider.targets(remote_identity, appearance)
assert(type(signature) == 'string' and signature ~= '' and targets[appearance.documents[1]][1].remote)
local binding = targets[appearance.documents[1]][1]
local session = f.provider.session()
session.apply(appearance.documents[1], targets[appearance.documents[1]])
assert(f.writes == 1 and f.actual(binding) ~= binding.original and f.private_calls == 1 and f.auth_calls > 3)
f.allowed = false
assert(
    not f.provider.present(binding)
        and not f.provider.write_guard(binding)
        and not pcall(f.provider.private, { binding }),
    'Revoked consent authorized a new recolor'
)
assert(
    session.restore() and f.writes == 2 and f.actual(binding) == binding.original,
    'Revoked new-write consent prevented exact owned-original restoration'
)
assert(session.retirement_certificate())
assert(
    f.deps.cohort.sessions[1] == session and f.deps.cohort.sessions[1].retirement_certificate(),
    'Cohort retirement reverted to a consent-gated forward session after restore'
)
-- A weapon-ID match cannot authorize garment destinations of another kit.
local incompatible = {
    body = 99,
    armor = 98,
    helmet = 97,
    weapons = remote_identity.weapons,
    player = f.peer.player,
    unit = f.peer.unit,
    peer_low = f.peer.peer_low,
    peer_high = f.peer.peer_high,
}
assert(not S.garment_compatible(incompatible, appearance) and S.garment_compatible(remote_identity, appearance))
f.allowed = true
appearance.entries['0:1:0:0'] = { document = appearance.documents[1] }
local weapon_only = f.provider.targets(incompatible, appearance)
local count = 0
for _, bindings in pairs(weapon_only) do
    for _, b in ipairs(bindings) do
        assert(b.kind == 'weapon')
        count = count + 1
    end
end
assert(count == 1, 'Weapon match remapped a garment target')
-- Mismatched config returns no weapon targets; malformed peer/config/shape or
-- topology never reaches texture creation or a native bind.
local wrong = {}
for key, value in pairs(remote_identity) do
    wrong[key] = value
end
wrong.weapons = { [1] = 'ffffffffffffffff' }
local wrong_targets = f.provider.targets(wrong, appearance)
assert(next(wrong_targets) == nil)
for _, alter in ipairs({
    function(f, identity, appearance)
        identity.player = 71
    end,
    function(f, identity, appearance)
        appearance.entries['3:1:0:0'].weapon_resource = 'ffffffffffffffff'
    end,
    function(f, identity, appearance)
        appearance.entries['3:1:0:0'].document = F.document(23, 7, 1)
    end,
    function(f, identity, appearance)
        appearance.entries['3:1:5:0'] = appearance.entries['3:1:0:0']
        appearance.entries['3:1:0:0'] = nil
    end,
}) do
    f = fixture()
    local identity = f.provider.remote_identity(f.peer)
    local appearance = codec.decode(
        codec.encode(f.provider.local_identity({}), f.provider.local_entries(f.provider.local_identity({})))
    )
    alter(f, identity, appearance)
    assert(not pcall(f.provider.targets, identity, appearance) and f.writes == 0)
end
f = fixture()
local identity = f.provider.remote_identity(f.peer)
appearance =
    codec.decode(codec.encode(f.provider.local_identity({}), f.provider.local_entries(f.provider.local_identity({}))))
targets = f.provider.targets(identity, appearance)
binding = targets[appearance.documents[1]][1]
session = f.provider.session()
f.alias = true
assert(
    not pcall(session.apply, appearance.documents[1], { binding }) and f.writes == 0,
    'Material alias privacy guard bypassed'
)
f.alias, f.revoke_on_create = false, true
assert(
    not pcall(session.apply, appearance.documents[1], { binding }) and f.writes == 0,
    'Consent revoked during texture creation still reached native bind'
)
assert(session.restore() and f.actual(binding) == binding.original)
f = fixture()
f.local_binding.current = f.local_binding.original
local no_weapons = f.provider.local_identity({ body = 1, armor = 2, helmet = 3 })
assert(
    next(no_weapons.weapons) == nil and #f.provider.local_entries(no_weapons) == 0,
    'Unedited weapons changed garment-only publication identity'
)
print(
    'PASS weapon sharing provider: exact local uploaded EL6 bytes, genuine-discovery peer/config targets, independent garment guard, consent/privacy/write checks and revoke-safe original cleanup'
)
dofile('tests/shared_weapon_lifecycle.lua')
