-- Explicit local/authorized-peer Unit/material receipts and pointer-alias proof.
-- Native callbacks are the existing verified Engine adapter, never new bindings.
local D = {
    MAX_WORLDS = 64,
    MAX_UNITS = 131072,
    MAX_MESHES = 64,
    MAX_MATERIALS = 512,
    MAX_CENSUS_UNITS = 8192,
    MAX_CENSUS_MATERIALS = 32768,
    LUT = 0x7e662968,
    PATTERN = 0x81d4c49d,
}
local identity_fields = {
    'game_base',
    'player_entity',
    'avatar_entity',
    'avatar_native_ref',
    'weapon_slot',
    'weapon_entity',
    'weapon_record',
    'weapon_resource64',
    'weapon_unit_ref',
    'weapon_native_ref',
    'weapon_object',
    'remote',
    'peer_player',
    'peer_unit',
    'peer_low',
    'peer_high',
}
local function pointer(value)
    return type(value) == 'number' and value % 1 == 0 and value >= 65536 and value < 2 ^ 47
end
local function index(value, maximum)
    return type(value) == 'number' and value % 1 == 0 and value >= 0 and value < maximum
end
local function same(left, right)
    for _, field in ipairs(identity_fields) do
        if left[field] ~= right[field] then
            return false
        end
    end
    return true
end
local function clone(value)
    local copy = {}
    for _, field in ipairs(identity_fields) do
        copy[field] = value[field]
    end
    return copy
end
function D.new(E, deps)
    local ffi = require('ffi')
    local A, W, U, N = E.Application, E.World, E.Unit, assert(deps.native, 'Verified native adapter unavailable')
    assert(
        A
            and W
            and U
            and type(A.worlds) == 'function'
            and type(W.units) == 'function'
            and type(U.alive) == 'function'
            and type(U.mesh) == 'function'
            and type(U.num_meshes) == 'function'
            and type(U.resource_name) == 'function'
            and deps.identity
            and type(deps.identity.snapshot) == 'function'
            and type(deps.read) == 'function',
        'Weapon discovery APIs unavailable'
    )
    for _, name in ipairs({ 'alive', 'meshes', 'mesh', 'materials', 'material' }) do
        assert(type(N[name]) == 'function' or type(N[name]) == 'cdata', 'Verified native adapter is incomplete')
    end
    local receipts, members = setmetatable({}, { __mode = 'k' }), setmetatable({}, { __mode = 'k' })
    local self = {}
    local function peer_copy(peer)
        assert(type(peer) == 'table' and peer['local'] ~= true, 'Invalid remote weapon peer')
        local copy = {}
        for _, field in ipairs({ 'player', 'unit', 'peer_low', 'peer_high' }) do
            local value = peer[field]
            assert(
                type(value) == 'number' and value % 1 == 0 and value >= 0 and value <= 0xffffffff,
                'Malformed remote weapon peer'
            )
            copy[field] = value
        end
        assert(
            copy.player > 0
                and copy.player < 0xffffffff
                and copy.unit > 0
                and copy.unit < 0xffffffff
                and copy.unit ~= 0x7fff
                and (copy.peer_low ~= 0 or copy.peer_high ~= 0),
            'Invalid remote weapon peer'
        )
        return copy
    end
    local function authorized(peer, slot, resource)
        assert(type(deps.remote_authorized) == 'function', 'Remote weapon editing is not authorized')
        local allowed, why = deps.remote_authorized(peer_copy(peer), slot, resource)
        assert(allowed == true, why or 'Remote weapon peer consent or lobby membership changed')
    end
    local function address(value)
        local kind = type(value)
        if kind ~= 'userdata' and kind ~= 'cdata' then
            return nil
        end
        if kind == 'cdata' and not tostring(ffi.typeof(value)):match('%*%s*>$') then
            return nil
        end
        local ok, result = pcall(function()
            return tonumber(ffi.cast('uintptr_t', value))
        end)
        return ok and result or nil
    end
    local function reference(value)
        local value_address = address(value)
        local ref = value_address and math.floor(value_address / 4)
        return ref and ref >= 1 and ref < 0xffffffff and ref or nil
    end
    local function worlds()
        local listed = A.worlds()
        assert(type(listed) == 'table' and #listed <= D.MAX_WORLDS, 'Weapon World list bounds changed')
        local all, seen = {}, {}
        local function add(world)
            if world ~= nil and not seen[world] then
                assert(#all < D.MAX_WORLDS, 'Weapon World list bounds changed')
                all[#all + 1], seen[world] = world, true
            end
        end
        if type(A.main_world) == 'function' then
            add(A.main_world())
        end
        for _, world in ipairs(listed) do
            add(world)
        end
        return all
    end
    local function units(world)
        local listed = W.units(world)
        assert(type(listed) == 'table' and #listed <= D.MAX_UNITS, 'Weapon World Unit bounds changed')
        return listed
    end
    local function resource(handle)
        local returned = U.resource_name(handle)
        local value, kind = tostring(returned), type(returned)
        local hash
        if kind == 'string' then
            hash = value:match('^#ID%[(%x+)%]$')
        elseif kind == 'userdata' then
            local named, raw = value:match('^%[IdString64 "#ID%[(%x+)%]" 0x(%x+)%]$')
            if named and raw and named:lower() == raw:lower() then
                hash = named
            end
        end
        assert(hash and #hash == 16, 'Stable weapon Unit resource ID unavailable')
        return hash:lower()
    end
    local validation_batch
    local function validate(receipt, cleanup)
        local kept = assert(receipts[receipt], 'Unknown weapon Unit receipt')
        assert(
            receipt.unit == kept.unit
                and receipt.lua_unit == kept.lua_unit
                and receipt.world == kept.world
                and receipt.weapon_slot == kept.identity.weapon_slot
                and receipt.weapon_resource64 == kept.identity.weapon_resource64
                and receipt.weapon_resource == kept.identity.weapon_resource64
                and receipt.unit_resource64 == kept.resource
                and receipt.remote == (kept.peer ~= nil)
                and receipt.peer_scope == (kept.peer and 'remote' or 'local')
                and receipt.peer_player == (kept.peer and kept.peer.player or nil)
                and receipt.peer_unit == (kept.peer and kept.peer.unit or nil)
                and receipt.peer_low == (kept.peer and kept.peer.peer_low or nil)
                and receipt.peer_high == (kept.peer and kept.peer.peer_high or nil),
            'Weapon Unit receipt was altered'
        )
        if validation_batch and not kept.peer and not cleanup and validation_batch[receipt] then
            return kept
        end
        local fresh, why
        if kept.peer then
            if cleanup then
                assert(
                    type(deps.identity.snapshot_remote_cleanup) == 'function',
                    'Remote cleanup identity proof unavailable'
                )
                fresh, why = deps.identity.snapshot_remote_cleanup(
                    peer_copy(kept.peer),
                    kept.identity.weapon_slot,
                    kept.raw_snapshot
                )
                assert(fresh and fresh.cleanup_only == true, why or 'Remote cleanup proof is not restoration-only')
            else
                authorized(kept.peer, kept.identity.weapon_slot, kept.identity.weapon_resource64)
                fresh, why = deps.identity.snapshot_remote(peer_copy(kept.peer), kept.identity.weapon_slot)
            end
        else
            fresh, why = deps.identity.snapshot(kept.identity.weapon_slot)
        end
        assert(fresh, why)
        assert(same(fresh, kept.identity), 'Current weapon identity changed')
        local world_present, matches = false, 0
        for _, world in ipairs(worlds()) do
            world_present = world_present or world == kept.world
        end
        assert(world_present, 'Weapon World disappeared')
        for _, handle in ipairs(units(kept.world)) do
            if reference(handle) == kept.unit then
                assert(handle == kept.lua_unit, 'Weapon Lua handle changed')
                matches = matches + 1
            end
        end
        assert(
            matches == 1 and U.alive(kept.lua_unit) == true and N.alive(kept.unit) ~= 0,
            'Weapon Unit disappeared or became ambiguous'
        )
        assert(resource(kept.lua_unit) == kept.resource, 'Weapon Unit resource changed')
        if validation_batch and not kept.peer and not cleanup then
            validation_batch[receipt] = kept
        end
        return kept
    end
    function self.with_validation_batch(fn)
        assert(not validation_batch, 'Nested weapon validation batches are unsupported')
        local batch = {}
        validation_batch = batch
        local function pack(...)
            return { n = select('#', ...), ... }
        end
        local task = coroutine.create(fn)
        local result = pack(coroutine.resume(task))
        validation_batch = nil
        assert(coroutine.status(task) == 'dead', 'Weapon validation batches cannot yield')
        if not result[1] then
            error(result[2], 0)
        end
        -- No cached identity escapes this synchronous read-only polling scope.
        for receipt in pairs(batch) do
            validate(receipt)
        end
        return unpack(result, 2, result.n)
    end
    local function capture(slot, requested_peer, expected_resource)
        local ok, value = pcall(function()
            local peer, snapshot, why
            if requested_peer then
                peer = peer_copy(requested_peer)
                assert(
                    type(expected_resource) == 'string'
                        and #expected_resource == 16
                        and expected_resource:match('^%x+$'),
                    'Expected remote weapon resource is required'
                )
                expected_resource = expected_resource:lower()
                authorized(peer, slot, expected_resource)
                assert(type(deps.identity.snapshot_remote) == 'function', 'Remote weapon identity adapter unavailable')
                snapshot, why = deps.identity.snapshot_remote(peer_copy(peer), slot)
            else
                snapshot, why = deps.identity.snapshot(slot)
            end
            assert(snapshot, why)
            assert(
                peer
                        and snapshot.remote == true
                        and snapshot.peer_player == peer.player
                        and snapshot.peer_unit == peer.unit
                        and snapshot.peer_low == peer.peer_low
                        and snapshot.peer_high == peer.peer_high
                        and snapshot.weapon_resource64 == expected_resource
                    or not peer and snapshot.remote ~= true,
                'Weapon identity scope or expected resource changed'
            )
            assert(
                snapshot.weapon_slot == slot
                    and type(snapshot.weapon_resource64) == 'string'
                    and #snapshot.weapon_resource64 == 16
                    and snapshot.weapon_resource64:match('^%x+$'),
                'Invalid weapon identity snapshot'
            )
            local handle, owner
            for _, world in ipairs(worlds()) do
                for _, candidate in ipairs(units(world)) do
                    if reference(candidate) == snapshot.weapon_unit_ref then
                        assert(not handle, 'Ambiguous weapon Unit reference across Worlds')
                        handle, owner = candidate, world
                    end
                end
            end
            assert(
                handle and U.alive(handle) == true and N.alive(snapshot.weapon_unit_ref) ~= 0,
                'No genuine live Lua Unit matches the local weapon'
            )
            local hash = resource(handle)
            local receipt = {
                unit = snapshot.weapon_unit_ref,
                lua_unit = handle,
                world = owner,
                weapon_slot = slot,
                weapon_resource64 = snapshot.weapon_resource64:lower(),
                weapon_resource = snapshot.weapon_resource64:lower(),
                unit_resource64 = hash,
                remote = peer ~= nil,
                peer_scope = peer and 'remote' or 'local',
                peer_player = peer and peer.player or nil,
                peer_unit = peer and peer.unit or nil,
                peer_low = peer and peer.peer_low or nil,
                peer_high = peer and peer.peer_high or nil,
            }
            receipts[receipt] = {
                unit = receipt.unit,
                lua_unit = handle,
                world = owner,
                resource = hash,
                identity = clone(snapshot),
                peer = peer,
                raw_snapshot = snapshot,
            }
            validate(receipt)
            return receipt
        end)
        if not ok then
            return nil, tostring(value)
        end
        return value
    end
    function self.capture(slot)
        return capture(slot)
    end
    function self.capture_remote(peer, slot, expected_resource)
        return capture(slot, peer, expected_resource)
    end
    function self.validate(receipt)
        local ok, why = pcall(validate, receipt)
        return ok, not ok and tostring(why) or nil
    end
    local function materials(handle, ref)
        assert(U.alive(handle) == true and N.alive(ref) ~= 0, 'Weapon material Unit is dead')
        local count = tonumber(N.meshes(ref))
        assert(
            index(count, D.MAX_MESHES + 1) and tonumber(U.num_meshes(handle)) == count,
            'Lua and native weapon mesh counts differ'
        )
        local found = {}
        for mesh_index = 0, count - 1 do
            local mesh = tonumber(N.mesh(ref, mesh_index))
            local lua_mesh = U.mesh(handle, mesh_index + 1)
            assert(pointer(mesh) and address(lua_mesh) == mesh, 'Lua and native weapon Mesh pointers differ')
            local total = tonumber(N.materials(mesh))
            assert(index(total, 65), 'Weapon material count bounds changed')
            for material_index = 0, total - 1 do
                assert(#found < D.MAX_MATERIALS, 'Weapon total material bounds changed')
                local material = tonumber(N.material(mesh, material_index))
                assert(pointer(material), 'Invalid weapon Material pointer')
                found[#found + 1] = {
                    mesh = mesh,
                    material = material,
                    mesh_index = mesh_index,
                    material_index = material_index,
                }
            end
        end
        return found
    end
    function self.materials(receipt)
        local kept = validate(receipt)
        local found = materials(kept.lua_unit, kept.unit)
        validate(receipt)
        return found
    end
    local function read(address_value, size)
        assert(pointer(address_value) and size >= 1 and size <= 4096, 'Weapon material read bounds')
        local bytes = deps.read(address_value, size)
        assert(type(bytes) == 'string' and #bytes == size, 'Weapon material binding data unavailable')
        return bytes
    end
    local function u32(bytes, offset)
        local a, b, c, d = bytes:byte(offset + 1, offset + 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end
    local function binding_bytes(material)
        local header = read(material + 24, 16)
        local count = u32(header, 0)
        assert(index(count, 65), 'Weapon texture slot count bounds changed')
        local array = u32(header, 8) + u32(header, 12) * 4294967296
        if count > 0 then
            assert(pointer(array), 'Invalid weapon binding array')
            return header, read(array, count * 16), count
        end
        return header, '', count
    end
    local function decode_bindings(bytes, count)
        local result = {}
        if count > 0 then
            for entry = 0, count - 1 do
                local at, slot = entry * 16, u32(bytes, entry * 16)
                assert(result[slot] == nil, 'Repeated weapon texture slot is ambiguous')
                local value = u32(bytes, at + 8) + u32(bytes, at + 12) * 4294967296
                assert(value == 0 or pointer(value), 'Invalid weapon texture object')
                result[slot] = value
            end
        end
        return result
    end
    local function bindings(material)
        local _, bytes, count = binding_bytes(material)
        return decode_bindings(bytes, count)
    end
    function self.descriptor(receipt, row, slot)
        local kept = validate(receipt)
        assert(slot == D.LUT or slot == D.PATTERN, 'Unsupported weapon texture slot')
        assert(
            index(row.mesh_index, D.MAX_MESHES)
                and index(row.material_index, 64)
                and pointer(row.mesh)
                and pointer(row.material),
            'Invalid weapon material locator'
        )
        local b = {
            kind = 'weapon',
            weapon = true,
            type = 3,
            unit = kept.unit,
            mesh = row.mesh,
            material = row.material,
            mesh_index = row.mesh_index,
            material_index = row.material_index,
            weapon_slot = kept.identity.weapon_slot,
            weapon_resource64 = kept.identity.weapon_resource64,
            weapon_resource = kept.identity.weapon_resource64,
            unit_resource64 = kept.resource,
            remote = kept.peer ~= nil,
            peer_scope = kept.peer and 'remote' or 'local',
            peer_player = kept.peer and kept.peer.player or nil,
            peer_unit = kept.peer and kept.peer.unit or nil,
            peer_low = kept.peer and kept.peer.peer_low or nil,
            peer_high = kept.peer and kept.peer.peer_high or nil,
            slot = slot,
            receipt = receipt,
            save_key = '3:' .. kept.identity.weapon_slot .. ':' .. row.mesh_index .. ':' .. row.material_index,
        }
        local expected = {}
        for key, value in pairs(b) do
            expected[key] = value
        end
        members[b] = expected
        assert(self.present(b), 'Weapon material locator changed')
        local object = bindings(b.material)[slot]
        if not object or object == 0 then
            members[b] = nil
            return nil
        end
        b.original, b.current = object, object
        members[b].original = object
        return b
    end
    local function present(b, cleanup)
        local expected = assert(members[b], 'Unknown weapon binding descriptor')
        for key, value in pairs(expected) do
            assert(b[key] == value, 'Weapon binding descriptor was altered')
        end
        local kept = validate(b.receipt, cleanup)
        assert(b.mesh_index < tonumber(N.meshes(kept.unit)), 'Weapon Mesh index changed')
        local mesh = tonumber(N.mesh(kept.unit, b.mesh_index))
        assert(
            mesh == b.mesh and address(U.mesh(kept.lua_unit, b.mesh_index + 1)) == mesh,
            'Weapon Mesh pointer changed'
        )
        assert(
            b.material_index < tonumber(N.materials(mesh))
                and tonumber(N.material(mesh, b.material_index)) == b.material,
            'Weapon Material pointer changed'
        )
        return true
    end
    function self.present(b)
        local ok, why = pcall(present, b)
        return ok, not ok and tostring(why) or nil
    end
    function self.binding(b)
        assert(present(b))
        local value = bindings(b.material)[b.slot]
        return value ~= 0 and value or nil
    end
    -- Negative-only frame gate: safe byte reads, never native Unit/Mesh calls.
    -- A mismatch is only a request for fresh ownership validation, not write permission.
    -- Only immutable decoded bytes are reused, never ownership/write proof.
    -- Weak keys release the probe when the assigned binding is retired.
    local probe_cache = setmetatable({}, { __mode = 'k' })
    function self.bindings_unchanged(targets)
        local decoded = {}
        for _, b in ipairs(targets) do
            assert(pointer(b.material), 'Invalid assigned Material pointer')
            local slots = decoded[b.material]
            if not slots then
                local header, bytes, count = binding_bytes(b.material)
                local prior = probe_cache[b]
                if prior and prior.material == b.material and prior.header == header and prior.bytes == bytes then
                    slots = prior.slots
                else
                    slots = decode_bindings(bytes, count)
                    probe_cache[b] = { material = b.material, header = header, bytes = bytes, slots = slots }
                end
                decoded[b.material] = slots
            end
            if slots[b.slot] ~= b.current then
                return false
            end
        end
        return true
    end
    function self.write_guard(b)
        -- Peer consent/current lobby membership is rechecked by present(), along
        -- with the exact Unit/material receipt. Call immediately before each bind.
        return self.present(b)
    end
    function self.cleanup_present(b)
        local ok, why = pcall(present, b, true)
        return ok, not ok and tostring(why) or nil
    end
    function self.cleanup_binding(b)
        assert(present(b, true))
        local value = bindings(b.material)[b.slot]
        return value ~= 0 and value or nil
    end
    function self.cleanup_write_guard(b, owned_object, restore_object)
        local ok, why = pcall(function()
            assert(present(b, true))
            assert(
                restore_object == b.original
                    and owned_object ~= b.original
                    and pointer(owned_object)
                    and (owned_object == b.current or owned_object == b.previous),
                'Remote cleanup can only restore an owned binding to its immutable original'
            )
            assert(self.cleanup_binding(b) == owned_object, 'Remote cleanup target was changed by another writer')
        end)
        return ok, not ok and tostring(why) or nil
    end
    function self.dead(b)
        local expected = members[b]
        local kept = expected and receipts[expected.receipt]
        if not kept then
            return false
        end
        local ok, gone = pcall(function()
            return U.alive(kept.lua_unit) == false and N.alive(kept.unit) == 0
        end)
        return ok and gone or false
    end
    -- This census has no yield. A proof is used only inside one synchronous write
    -- operation, never cached across frames or inferred from shared texture IDs.
    local function prove_private(targets, cleanup)
        local ok, why = pcall(function()
            assert(
                type(targets) == 'table' and #targets > 0 and #targets <= D.MAX_MATERIALS * 6,
                'Weapon privacy target bounds'
            )
            local wanted, destinations = {}, {}
            for _, b in ipairs(targets) do
                assert(present(b, cleanup))
                wanted[b.material] = true
                local key = b.unit .. ':' .. b.mesh_index .. ':' .. b.material_index
                assert(destinations[key] == nil or destinations[key] == b.material, 'Ambiguous weapon destination')
                destinations[key] = b.material
            end
            local total_units, total_materials, found, captured = 0, 0, {}, {}
            for _, world in ipairs(worlds()) do
                local listed = units(world)
                assert(total_units + #listed <= D.MAX_CENSUS_UNITS, 'Weapon material privacy census Unit bounds')
                local copy = {}
                for position, handle in ipairs(listed) do
                    copy[position] = handle
                    total_units = total_units + 1
                    if U.alive(handle) == true then
                        local ref = assert(reference(handle), 'Unknown genuine Unit handle representation')
                        for _, row in ipairs(materials(handle, ref)) do
                            total_materials = total_materials + 1
                            assert(total_materials <= D.MAX_CENSUS_MATERIALS, 'Weapon material privacy census bounds')
                            if wanted[row.material] then
                                local key = ref .. ':' .. row.mesh_index .. ':' .. row.material_index
                                assert(
                                    destinations[key] == row.material,
                                    'Weapon material pointer aliases another destination'
                                )
                                assert(not found[key], 'Ambiguous weapon material destination across Worlds')
                                found[key] = true
                            end
                        end
                    end
                end
                captured[world] = copy
            end
            for key in pairs(destinations) do
                assert(found[key], 'Weapon material missing from privacy census')
            end
            local remaining = {}
            for world in pairs(captured) do
                remaining[world] = true
            end
            for _, world in ipairs(worlds()) do
                local prior = assert(captured[world], 'Weapon World list changed during privacy census')
                local fresh = units(world)
                assert(#prior == #fresh, 'World Unit list changed during weapon privacy census')
                for position, handle in ipairs(prior) do
                    assert(fresh[position] == handle, 'World Unit identity changed during weapon privacy census')
                end
                remaining[world] = nil
            end
            assert(not next(remaining), 'Weapon World disappeared during privacy census')
            for _, b in ipairs(targets) do
                assert(present(b, cleanup))
            end
        end)
        return ok, not ok and tostring(why) or nil
    end
    function self.prove_private(targets)
        return prove_private(targets, false)
    end
    function self.prove_cleanup_private(targets)
        return prove_private(targets, true)
    end
    return self
end
return D
