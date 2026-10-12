-- EL6 weapon publication and authorized peer targets. Genuine Lua Unit handles
-- and native lifetime/ownership checks stay inside weapon_discovery.
local S = { MAX_BINDINGS = 4096 }
local peer_fields = { 'player', 'unit', 'peer_low', 'peer_high' }
local function id(value)
    assert(
        type(value) == 'string' and #value == 16 and value:match('^%x+$') and value ~= string.rep('0', 16),
        'Invalid shared weapon configuration'
    )
    return value:lower()
end
local function peer(identity)
    assert(type(identity) == 'table' and identity['local'] ~= true, 'Remote weapon identity required')
    local result = { ['local'] = false }
    for _, field in ipairs(peer_fields) do
        local value = identity[field]
        assert(
            type(value) == 'number' and value % 1 == 0 and value >= 0 and value <= 0xffffffff,
            'Invalid remote weapon peer field'
        )
        result[field] = value
    end
    assert(
        result.player > 0
            and result.player < 0xffffffff
            and result.unit > 0
            and result.unit < 0xffffffff
            and result.unit ~= 0x7fff
            and (result.peer_low ~= 0 or result.peer_high ~= 0),
        'Remote weapon peer unavailable'
    )
    return result
end
local function key(binding)
    return binding.unit .. ':' .. binding.mesh .. ':' .. binding.material .. ':' .. binding.slot
end
function S.garment_compatible(identity, appearance)
    if type(identity) ~= 'table' or type(appearance) ~= 'table' then
        return false
    end
    for _, field in ipairs({ 'body', 'armor', 'helmet' }) do
        local current = identity[field]
        if
            type(current) ~= 'number'
            or current % 1 ~= 0
            or current < 0
            or current > 0xffffffff
            or current ~= appearance[field]
        then
            return false
        end
    end
    return true
end
function S.new(deps)
    local runtime, discovery, mapping = assert(deps.runtime), assert(deps.discovery), assert(deps.weapon_mapping)
    assert(
        type(deps.remote_snapshot) == 'function'
            and type(deps.remote_authorized) == 'function'
            and type(deps.original) == 'function',
        'Shared weapon identity/source operations unavailable'
    )
    local self, known = {}, {}
    local function authorize(binding)
        local allowed, why = deps.remote_authorized(
            peer({
                player = binding.peer_player,
                unit = binding.peer_unit,
                peer_low = binding.peer_low,
                peer_high = binding.peer_high,
            }),
            binding.weapon_slot,
            id(binding.weapon_resource or binding.weapon_resource64)
        )
        assert(allowed == true, why or 'Shared weapon consent or peer membership changed')
        return true
    end
    local function remember(binding)
        assert(
            binding.kind == 'weapon' and binding.remote == true and binding.peer_scope == 'remote',
            'Only certified remote weapon descriptors may be shared'
        )
        known[key(binding)] = binding
        return binding
    end
    local function captured(binding, registry)
        local value = registry[key(binding)]
        assert(
            value
                and binding.unit == value.unit
                and binding.mesh == value.mesh
                and binding.material == value.material
                and binding.slot == value.slot
                and binding.original == value.original,
            'Unknown shared weapon target'
        )
        return value
    end
    function self.local_identity(base)
        if not base then
            return nil
        end
        local result = {}
        for field, value in pairs(base) do
            result[field] = value
        end
        result.weapons = {}
        local edited = {}
        for _, binding in ipairs(runtime.all_owned()) do
            if
                binding.remote ~= true
                and binding.current ~= binding.original
                and discovery.present(binding)
                and discovery.binding(binding) == binding.current
            then
                edited[binding.weapon_slot] = true
            end
        end
        for slot = 1, 3 do
            if edited[slot] then
                local receipt = discovery.capture(slot)
                if receipt then
                    result.weapons[slot] = id(receipt.weapon_resource or receipt.weapon_resource64)
                end
            end
        end
        return result
    end
    function self.local_entries(identity)
        assert(identity and type(identity.weapons) == 'table', 'Current shared weapon identities unavailable')
        local entries, seen = {}, {}
        for _, binding in ipairs(runtime.all_owned()) do
            if
                binding.remote ~= true
                and binding.current ~= binding.original
                and discovery.present(binding)
                and discovery.binding(binding) == binding.current
            then
                local slot, resource = binding.weapon_slot, id(binding.weapon_resource or binding.weapon_resource64)
                assert(identity.weapons[slot] == resource, 'Local shared weapon configuration changed')
                local document = binding.texture and binding.texture.object == binding.current and binding.texture
                    or binding.document
                assert(document, 'Owned shared weapon LUT pixels unavailable')
                local pattern = binding.slot == 0x81d4c49d
                assert(binding.slot == 0x7e662968 or pattern, 'Unsupported shared weapon texture slot')
                local destination = (pattern and 'p:' or '') .. binding.save_key
                local bytes = mapping.bytes(document)
                assert(document.width == (pattern and 3 or 23), 'Shared weapon role/shape differs')
                assert(
                    not seen[destination] or seen[destination] == bytes,
                    'Conflicting local shared weapon destination'
                )
                if not seen[destination] then
                    local original = deps.original(binding.original, binding, pattern and 'pattern' or 'material')
                    original = original and original.data and mapping.copy(original) or nil
                    entries[#entries + 1] = {
                        kind = 'weapon',
                        key = destination,
                        weapon_slot = slot,
                        weapon_resource = resource,
                        document = mapping.copy(document),
                        original = original,
                    }
                    assert(#entries <= S.MAX_BINDINGS, 'Shared weapon binding budget exceeded')
                    seen[destination] = bytes
                end
            end
        end
        return entries
    end
    function self.remote_identity(base)
        if not base then
            return nil
        end
        local member, result = peer(base), {}
        for field, value in pairs(base) do
            result[field] = value
        end
        result.weapons = {}
        for slot = 1, 3 do
            local snapshot = deps.remote_snapshot(member, slot)
            if snapshot then
                assert(
                    snapshot.remote == true
                        and snapshot.peer_player == member.player
                        and snapshot.peer_unit == member.unit
                        and snapshot.peer_low == member.peer_low
                        and snapshot.peer_high == member.peer_high
                        and snapshot.weapon_slot == slot,
                    'Remote weapon snapshot belongs to another peer'
                )
                result.weapons[slot] = id(snapshot.weapon_resource or snapshot.weapon_resource64)
            end
        end
        return result
    end
    function self.targets(identity, appearance)
        local member = peer(identity)
        assert(type(appearance) == 'table' and type(appearance.entries) == 'table', 'Shared appearance unavailable')
        local wanted, targets, marks, count = {}, {}, {}, 0
        for destination, entry in pairs(appearance.entries) do
            local pattern = destination:sub(1, 2) == 'p:'
            local bare = pattern and destination:sub(3) or destination
            if bare:match('^3:') or entry.kind == 'weapon' then
                local slot, mesh, material = bare:match('^3:(%d+):(%d+):(%d+)$')
                slot, mesh, material = tonumber(slot), tonumber(mesh), tonumber(material)
                assert(
                    slot and slot >= 1 and slot <= 3 and mesh and mesh < 64 and material and material < 64,
                    'Malformed shared weapon destination'
                )
                local expected = appearance.weapons and appearance.weapons[slot]
                assert(
                    entry.kind == 'weapon' and entry.weapon_slot == slot and id(entry.weapon_resource) == id(expected),
                    'Shared weapon entry identity disagrees with packet'
                )
                mapping.bytes(entry.document)
                assert(entry.document.width == (pattern and 3 or 23), 'Shared weapon entry role/shape differs')
                wanted[slot] = wanted[slot] or {}
                wanted[slot][destination] = entry
            end
        end
        for slot = 1, 3 do
            if wanted[slot] then
                local expected = id(appearance.weapons[slot])
                local current = identity.weapons and identity.weapons[slot]
                marks[#marks + 1] = slot .. ':' .. tostring(current or 'unavailable')
                if current == expected then
                    local allowed, why = deps.remote_authorized(member, slot, expected)
                    assert(allowed == true, why or 'Remote weapon sharing is not authorized')
                    local receipt, reason = discovery.capture_remote(member, slot, expected)
                    assert(receipt, reason)
                    marks[#marks + 1] =
                        table.concat({ receipt.unit, receipt.unit_resource64 or '', receipt.weapon_object or '' }, ':')
                    local found = {}
                    for _, row in ipairs(discovery.materials(receipt)) do
                        for _, pattern in ipairs({ false, true }) do
                            local destination = (pattern and 'p:' or '')
                                .. '3:'
                                .. slot
                                .. ':'
                                .. row.mesh_index
                                .. ':'
                                .. row.material_index
                            local entry = wanted[slot][destination]
                            if entry then
                                local binding = assert(
                                    discovery.descriptor(receipt, row, pattern and 0x81d4c49d or 0x7e662968),
                                    'Remote weapon texture role is unbound'
                                )
                                authorize(binding)
                                local original = assert(
                                    deps.original(binding.original, binding, pattern and 'pattern' or 'material'),
                                    'Remote weapon original LUT source is not ready'
                                )
                                assert(
                                    original.width == entry.document.width and original.height == entry.document.height,
                                    'Remote weapon LUT dimensions differ from sender'
                                )
                                assert(
                                    discovery.present(binding) and discovery.binding(binding) == binding.current,
                                    'Remote weapon changed while matching shared appearance'
                                )
                                count = count + 1
                                assert(count <= S.MAX_BINDINGS, 'Remote shared weapon target budget exceeded')
                                remember(binding)
                                targets[entry.document] = targets[entry.document] or {}
                                targets[entry.document][#targets[entry.document] + 1] = binding
                                marks[#marks + 1] = key(binding) .. ':' .. binding.original
                                found[destination] = true
                            end
                        end
                    end
                    for destination in pairs(wanted[slot]) do
                        assert(
                            found[destination],
                            'Sender weapon topology is not present on this peer: ' .. destination
                        )
                    end
                    assert(discovery.validate(receipt), 'Remote weapon changed during target matching')
                end
            end
        end
        return targets, table.concat(marks, '|')
    end
    function self.owns(binding)
        local ok = pcall(captured, binding, known)
        return ok
    end
    function self.present(binding)
        local ok, why = pcall(function()
            local value = captured(binding, known)
            authorize(value)
            assert(discovery.present(value))
        end)
        return ok, not ok and tostring(why) or nil
    end
    function self.binding(binding)
        local value = captured(binding, known)
        authorize(value)
        return discovery.binding(value)
    end
    function self.dead(binding)
        local ok, value = pcall(captured, binding, known)
        return ok and discovery.dead(value) == true or false
    end
    function self.write_guard(binding)
        local ok, why = pcall(function()
            local value = captured(binding, known)
            authorize(value)
            local allowed, reason = discovery.write_guard(value)
            assert(allowed == true, reason)
        end)
        return ok, not ok and tostring(why) or nil
    end
    function self.private(bindings)
        for _, binding in ipairs(bindings) do
            assert(self.present(binding))
        end
        return discovery.prove_private(bindings)
    end
    -- A per-session ledger retains original descriptor receipts even after a
    -- later packet creates fresh descriptors for the same native locations.
    function self.session()
        assert(
            deps.binding_session
                and deps.retain
                and deps.cohort
                and type(deps.bind) == 'function'
                and type(deps.create_texture) == 'function',
            'Remote weapon binding session dependencies unavailable'
        )
        for _, name in ipairs({ 'cleanup_present', 'cleanup_binding', 'cleanup_write_guard', 'prove_cleanup_private' }) do
            assert(type(discovery[name]) == 'function', 'Remote weapon restore proof unavailable: ' .. name)
        end
        local registry, active = {}, nil
        local function owned_object(object)
            for _, keep in ipairs(deps.retain.records or {}) do
                if
                    keep.cohort == deps.cohort
                    and keep.owned == true
                    and keep.texture
                    and keep.texture.object == object
                then
                    return true
                end
            end
            return false
        end
        local function kept(binding)
            return captured(binding, registry)
        end
        local function present(binding)
            local value = kept(binding)
            if active and active.cleanup then
                return discovery.cleanup_present(value)
            end
            authorize(value)
            return discovery.present(value)
        end
        local function bound(binding)
            local value = kept(binding)
            if active and active.cleanup then
                return discovery.cleanup_binding(value)
            end
            authorize(value)
            return discovery.binding(value)
        end
        local base = deps.binding_session.new({
            retain = deps.retain,
            cohort = deps.cohort,
            key = key,
            present = present,
            binding = bound,
            dead = function(binding)
                return discovery.dead(kept(binding))
            end,
            create_texture = deps.create_texture,
            bind = function(binding, object)
                local value = kept(binding)
                assert(active and active.keys[key(value)], 'Remote weapon write has no current private operation')
                local allowed, why
                if active.cleanup then
                    assert(object == value.original, 'Remote cleanup cannot recolor a weapon')
                    local current = discovery.cleanup_binding(value)
                    assert(owned_object(current), 'Remote cleanup object is not owned by this texture cohort')
                    allowed, why = discovery.cleanup_write_guard(value, current, object)
                else
                    authorize(value)
                    allowed, why = discovery.write_guard(value)
                end
                assert(allowed == true, why)
                deps.bind(value, object)
            end,
        })
        local session = { owned = base.owned }
        -- The cohort must certify through the cleanup-aware wrapper after a
        -- sharing toggle revokes new-write authorization.
        for index, registered in ipairs(deps.cohort.sessions or {}) do
            if registered == base then
                deps.cohort.sessions[index] = session
            end
        end
        local function operation(bindings, cleanup, callback)
            assert(not active, 'Nested shared weapon operation refused')
            local allowed, why
            if cleanup then
                allowed, why = discovery.prove_cleanup_private(bindings)
            else
                for _, binding in ipairs(bindings) do
                    authorize(binding)
                end
                allowed, why = discovery.prove_private(bindings)
            end
            assert(allowed == true, why)
            active = { cleanup = cleanup, keys = {} }
            for _, binding in ipairs(bindings) do
                active.keys[key(binding)] = true
            end
            local ok, a, b = pcall(callback)
            active = nil
            session.owned = base.owned
            if not ok then
                error(a, 0)
            end
            return a, b
        end
        function session.apply(document, bindings)
            for _, binding in ipairs(bindings) do
                local value = captured(binding, known)
                assert(value == binding, 'Remote weapon descriptor is not the current packet target')
                registry[key(binding)] = binding
            end
            return operation(bindings, false, function()
                return base.apply(document, bindings)
            end)
        end
        function session.restore()
            local live = {}
            for _, binding in ipairs(base.owned) do
                if not discovery.dead(kept(binding)) then
                    local allowed = discovery.cleanup_present(kept(binding))
                    if not allowed then
                        return false
                    end
                    live[#live + 1] = kept(binding)
                end
            end
            local function restore()
                local done = base.restore()
                local certified = base.retirement_certificate()
                return done and certified
            end
            if #live > 0 then
                return operation(live, true, restore)
            end
            active = { cleanup = true, keys = {} }
            local ok, done = pcall(restore)
            active, session.owned = nil, base.owned
            return ok and done or false
        end
        function session.retirement_certificate()
            active = { cleanup = true, keys = {} }
            local ok, done, why = pcall(base.retirement_certificate)
            active = nil
            return ok and done, not ok and tostring(done) or why
        end
        return session
    end
    return self
end
return S
