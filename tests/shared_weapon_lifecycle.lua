-- Real discovery -> provider -> receive -> binding sessions -> lifetime, over
-- bounded fake engine/memory ports. No constant target signatures or game calls.
local Fixture = dofile('tests/weapon_fixture.lua')
local Provider = dofile('src/weapons/weapon_shared.lua')
local Sharing = dofile('src/gear/shared_appearance.lua')
local Mapping = dofile('src/editor/weapon_mapping.lua')
local Codec = dofile('src/gear/shared_lut_codec.lua')
local Session = dofile('src/gear/binding_session.lua')
local Lifetime = dofile('src/gear/texture_lifetime.lua')
local D = dofile('src/weapons/weapon_discovery.lua')

local function fixture(previous)
    local f = Fixture()
    if previous then
        f.retain, f.next_texture = previous.retain, previous.next_texture
    end
    local resource = '5fecab819f96a3e8'
    f.peer = { player = 19, unit = 177, peer_low = 0x11223344, peer_high = 0x55667788, body = 1, armor = 2, helmet = 3 }
    f.member, f.row_valid = true, true
    local ref = previous and 500 or 400
    f.make_unit(ref, 5, resource)
    f.remote = {}
    for key, value in pairs(f.snapshots[1]) do
        f.remote[key] = value
    end
    f.remote.player_entity, f.remote.avatar_entity, f.remote.avatar_native_ref = 19, 30, 177
    f.remote.weapon_entity, f.remote.weapon_record = 1000 + ref, 0x200000 + ref * 24
    f.remote.weapon_unit_ref, f.remote.weapon_native_ref = ref, ref + 500
    f.remote.weapon_object, f.remote.weapon_resource = 0x400000 + ref * 128, resource
    f.remote.remote = true
    for _, name in ipairs({ 'player', 'unit', 'peer_low', 'peer_high' }) do
        f.remote['peer_' .. (name == 'peer_low' and 'low' or name == 'peer_high' and 'high' or name)] = f.peer[name]
    end
    local function copy(value)
        local out = {}
        for k, v in pairs(value) do
            out[k] = v
        end
        return out
    end
    f.identity.snapshot_remote = function(peer, slot)
        if not f.member then
            return nil, 'Peer left'
        end
        if slot ~= 1 then
            return nil, 'Weapon inventory slot is empty'
        end
        for _, name in ipairs({ 'player', 'unit', 'peer_low', 'peer_high' }) do
            assert(peer[name] == f.peer[name])
        end
        return copy(f.remote)
    end
    f.identity.snapshot_remote_cleanup = function(_, _, saved)
        if not f.row_valid or saved.weapon_object ~= f.remote.weapon_object then
            return nil, 'Remote cleanup peer row was cleared or reused'
        end
        local out = copy(saved)
        out.cleanup_only = true
        return out
    end
    local service, provider
    local codec = Codec.new(nil, function(resource_id)
        for _, document in pairs(f.documents) do
            if document.resource == resource_id then
                return document
            end
        end
    end)
    local document = Mapping.copy(f.documents[f.A])
    document.data[0] = 0.75
    local entries = {}
    for mesh = 0, 4 do
        entries[#entries + 1] = {
            kind = 'weapon',
            key = '3:1:' .. mesh .. ':0',
            weapon_slot = 1,
            weapon_resource = resource,
            document = document,
            original = f.documents[f.A],
        }
    end
    f.packet = codec.encode({ body = 1, armor = 2, helmet = 3, weapons = { resource } }, entries)
    f.discovery_deps.remote_authorized = function(peer, slot, config)
        return service and service.authorized(peer, slot, config)
    end
    provider = Provider.new({
        runtime = f.runtime,
        discovery = f.discovery,
        weapon_mapping = Mapping,
        binding_session = Session,
        retain = f.retain,
        cohort = f.cohort,
        remote_snapshot = f.identity.snapshot_remote,
        remote_authorized = f.discovery_deps.remote_authorized,
        original = function(object)
            -- Uploaded objects deliberately have no disk-original cache entry.
            return f.documents[object]
        end,
        create_texture = function(w, h, data)
            f.allocations = f.allocations + 1
            local object = f.next_texture
            f.next_texture = object + 0x1000
            return { object = object, handle = object, width = w, height = h, data = data }
        end,
        bind = function(binding, object)
            f.writes[#f.writes + 1] = { binding = binding, object = object }
            f.textures[binding.material][binding.slot] = object
        end,
    })
    f.notes = {}
    service = Sharing.new({
        sync = {
            session = function()
                return {
                    poll = function()
                        return f.member
                                and { { peer_low = f.peer.peer_low, peer_high = f.peer.peer_high, text = f.packet } }
                            or {}
                    end,
                    clear = function()
                        f.cleared = not f.no_lobby
                        return f.cleared
                    end,
                }
            end,
        },
        codec = codec,
        note = function(message)
            f.notes[#f.notes + 1] = message
        end,
        identity = function()
            return nil
        end,
        players = function()
            return f.member and { f.peer } or {}
        end,
        resolve = provider.remote_identity,
        targets = provider.targets,
        bindings = provider.session,
    })
    f.provider, f.service, f.document, f.entries, f.codec, f.resource =
        provider, service, document, entries, codec, resource
    function f.receive()
        service.tick(2, true)
        service.tick(0.01, true)
    end
    return f
end

local f = fixture()
f.receive()
assert(#f.writes == 5 and f.allocations == 1 and next(f.service.peers))
local initial = #f.writes
for _ = 1, 5 do
    f.receive()
end
assert(
    #f.writes == initial and f.allocations == 1,
    'Unchanged real remote binding signatures reapplied or lost their original source'
)
assert(#f.notes == 0, 'Owned uploaded texture was incorrectly requested as a disk original')
f.document.data[0] = 0.25
f.packet = f.codec.encode({ body = 1, armor = 2, helmet = 3, weapons = { f.resource } }, f.entries)
f.receive()
assert(#f.writes == initial + 10 and f.allocations == 2, 'Changed packet did not restore then apply all five LODs')
initial = #f.writes
for _ = 1, 4 do
    f.receive()
end
assert(#f.writes == initial, 'Post-restore recapture discarded its stable signature')
assert(f.service.close() and f.cleared)
for _, mesh in ipairs(f.units[400].meshes) do
    assert(f.textures[mesh.materials[1]][D.LUT] == f.A)
end
print(
    'PASS real weapon receive: stable uploaded-source signatures, unchanged packet no-op and exact changed-packet all-LOD restoration'
)

f = fixture()
f.receive()
local material = f.units[400].meshes[1].materials[1]
local before = #f.writes
f.textures[material][D.LUT] = 0xdead00
f.receive()
assert(f.textures[material][D.LUT] == 0xdead00, 'Stable signature normalization concealed a foreign pointer')
for index = before + 1, #f.writes do
    assert(f.writes[index].binding.material ~= material, 'Foreign texture ownership was overwritten')
end
assert(not f.service.close(), 'Foreign binding drift falsely certified exact restoration')
print('PASS real weapon receive: foreign binding drift remains visible and never overwritten')

f = fixture()
f.receive()
material = f.units[400].meshes[1].materials[1]
before = #f.writes
f.textures[material][D.LUT] = f.A
f.receive()
assert(
    #f.writes == before + 9 and f.textures[material][D.LUT] ~= f.A,
    'Foreign restoration to the stock object was concealed by stable source normalization'
)
before = #f.writes
f.receive()
assert(#f.writes == before and f.service.close(), 'Stock-drift recapture did not become a stable owned appearance')
print('PASS real weapon receive: restoring stock externally invalidates the owned replacement without repeated updates')

f = fixture()
f.receive()
before = #f.writes
f.remote.weapon_object = f.remote.weapon_object + 0x1000
f.receive()
assert(#f.writes == before and not f.service.close(), 'Recycled remote receipt was normalized into a current target')
print('PASS real weapon receive: changed native identity refuses writes and retains unresolved restoration')

f = fixture()
f.receive()
before = #f.writes
f.member, f.row_valid = false, false
assert(not f.service.close(), 'Ordinary Shared LUT close discarded a live unprovable peer')
assert(#f.writes == before and next(f.service.peers), 'Peer-row loss wrote native state or discarded retry receipts')
assert(
    f.service.close(true) and f.service.quarantined and f.cleared,
    'Addon shutdown did not allow retained-closure quarantine'
)
local destroyed = 0
local lifetime = Lifetime.new({
    retain = f.retain,
    cohort = f.cohort,
    certified = function()
        for _, session in ipairs(f.cohort.sessions) do
            local ok, why = session.retirement_certificate()
            if not ok then
                return false, why
            end
        end
        return true
    end,
    drain = function()
        error('Uncertified remote work reached a render fence')
    end,
    destroy = function()
        destroyed = destroyed + 1
    end,
})
assert(
    lifetime.close() and lifetime.state == 'quarantined' and destroyed == 0,
    'Reload cleanup destroyed an uncertified remote texture'
)
assert(
    #f.writes == before and #f.retain.records == 1 and f.retain.records[1].data,
    'Reload cleanup lost live GPU backing or changed foreign ownership'
)
assert(f.cohort.sessions == nil and next(f.service.peers) == nil, 'Finished quarantine pinned old addon closures')
print(
    'PASS real sharing/lifetime shutdown: strict peer cleanup, complete quarantine, retained buffers and no native writes/destroy'
)

-- The old live-but-unprovable peer keeps its uploaded object and backing after
-- addon cleanup. A returning peer owns fresh Unit receipts in the new cohort;
-- identical pixels must allocate again, not borrow the quarantined cohort.
local quarantined, old_record = f, f.retain.records[1]
local old_texture, old_cohort, kept_bytes = old_record.texture, old_record.cohort, old_record.bytes
local reloaded = fixture(quarantined)
assert(reloaded.cohort ~= old_cohort and reloaded.retain.cache == quarantined.retain.cache)
reloaded.receive()
assert(
    reloaded.allocations == 1 and #reloaded.retain.records == 2,
    'New sharing cohort borrowed a quarantined content-cache texture'
)
local new_record = reloaded.retain.records[2]
assert(
    new_record.texture.object ~= old_texture.object
        and new_record.texture.cohort == reloaded.cohort
        and new_record.cohort == reloaded.cohort,
    'Fresh uploaded texture lost its current cohort creation receipt'
)
local fresh_writes = #reloaded.writes
for _ = 1, 3 do
    reloaded.receive()
end
assert(
    #reloaded.writes == fresh_writes and #reloaded.notes == 0,
    'New-cohort sharing could not normalize its own uploaded original'
)
assert(reloaded.service.close(), 'New-cohort uploaded object could not restore exact originals')
for _, mesh in ipairs(reloaded.units[500].meshes) do
    assert(reloaded.textures[mesh.materials[1]][D.LUT] == reloaded.A)
end
assert(
    old_record.cohort == old_cohort
        and old_record.bytes == kept_bytes
        and old_record.data
        and quarantined.textures[quarantined.units[400].meshes[1].materials[1]][D.LUT] == old_texture.object,
    'Reload migrated, destroyed or restored an uncertified old-cohort object'
)
print(
    'PASS real sharing after quarantined reload: fresh cohort allocation, stable normalized sources and exact cleanup without migrating old GPU backing'
)

f = fixture()
f.receive()
f.member, f.row_valid, f.no_lobby = false, false, true
assert(
    f.service.close(true) and f.service.quarantined and not f.cleared,
    'An unavailable lobby trapped full-addon retained-buffer cleanup'
)
print('PASS full-addon Shared LUT quarantine remains available after lobby disappearance')

local legacy_retain = { records = {}, cache = {}, bytes = 0 }
local legacy_creates, legacy_bound = 0, 10
local function legacy_session()
    local binding = { unit = 1, mesh = 2, material = 3, slot = D.LUT, original = 10, current = legacy_bound }
    local session = Session.new({
        retain = legacy_retain,
        key = function()
            return 'legacy'
        end,
        present = function()
            return true
        end,
        binding = function()
            return legacy_bound
        end,
        create_texture = function(w, h, data)
            legacy_creates = legacy_creates + 1
            return { object = 20, width = w, height = h, data = data }
        end,
        bind = function(_, object)
            legacy_bound = object
        end,
    })
    return session, binding
end
local legacy, legacy_target = legacy_session()
legacy.apply(f.documents[f.A], { legacy_target })
local next_legacy, next_legacy_target = legacy_session()
next_legacy.apply(f.documents[f.A], { next_legacy_target })
assert(
    legacy_creates == 1 and legacy_retain.records[1].cohort == nil,
    'The current-cohort guard rejected compatible legacy nil/nil cache ownership'
)
print('PASS legacy nil-cohort sessions retain compatible content-cache reuse')
