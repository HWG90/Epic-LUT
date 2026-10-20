-- Prevent stock appearance restoration at its private per-weapon source.
-- No code hooks, shared configuration writes, or per-frame material repair.
local S = {}
local ZERO = string.rep('\0', 4)
local function u32(bytes, offset)
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    assert(d, 'Short source configuration read')
    return a + b * 256 + c * 65536 + d * 16777216
end
function S.new(deps)
    local leases, self = {}, {}
    local function read(address, size)
        assert(type(address) == 'number' and address >= 65536 and address + size < 2 ^ 47)
        local value = deps.read(address, size)
        assert(type(value) == 'string' and #value == size, 'Weapon source memory unavailable')
        return value
    end
    local function pointer(address)
        local bytes = read(address, 8)
        local value = u32(bytes, 0) + u32(bytes, 4) * 4294967296
        assert(value >= 65536 and value < 2 ^ 47, 'Invalid weapon source pointer')
        return value
    end
    local function rows(address)
        local header = read(address, 16)
        local count, empty = u32(header, 8), u32(header, 12)
        assert(count > 0 and count <= 4096, 'Weapon source map bounds')
        return pointer(address), count, empty
    end
    local function lookup(address, entity)
        local data, count, empty = rows(address)
        -- Copy one bounded map per proof, rather than crossing the safe-read
        -- boundary for every empty hash bucket. Never cache across proofs.
        local entries = read(data, count * 8)
        local result
        for index = 0, count - 1 do
            local offset = index * 8
            if u32(entries, offset) == entity and entity ~= empty then
                assert(not result, 'Duplicate weapon source identity')
                result = u32(entries, offset + 4)
                assert(result < 4096, 'Weapon source index bounds')
            end
        end
        return result
    end
    local function locate(slot, binding)
        local identity, why
        if binding.remote then
            identity, why = deps.identity.snapshot_remote({
                player = binding.peer_player,
                unit = binding.peer_unit,
                peer_low = binding.peer_low,
                peer_high = binding.peer_high,
            }, slot)
        else
            identity, why = deps.identity.snapshot(slot)
        end
        assert(identity, why)
        local game = assert(deps.module('game.dll'))
        local manager = pointer(game + 0x3326a38)
        local entity = identity.weapon_entity
        local instance = assert(lookup(manager + 0x278, entity), 'Weapon source owner unavailable')
        local owner_at = pointer(pointer(manager + 0x290) + instance * 8)
        local owner = read(owner_at, 24)
        assert(u32(owner, 8) == entity, 'Weapon source owner changed')
        local index = lookup(manager + 0x2b8, entity)
        if index == nil then
            assert(deps.ensure_private, 'No private weapon appearance configuration')
            assert(deps.ensure_private(identity, manager, owner_at, owner), 'Private weapon allocation failed')
            assert(
                pointer(game + 0x3326a38) == manager and read(owner_at, 24) == owner,
                'Weapon changed during private source creation'
            )
            index = assert(lookup(manager + 0x2b8, entity), 'Private weapon source creation readback failed')
        end
        local data, count, empty = rows(manager + 0x2b8)
        local entries = read(data, count * 8)
        local aliases = 0
        for row = 0, count - 1 do
            local offset = row * 8
            if u32(entries, offset) ~= empty and u32(entries, offset + 4) == index then
                assert(u32(entries, offset) == entity, 'Weapon appearance configuration is shared')
                aliases = aliases + 1
            end
        end
        assert(aliases == 1, 'Weapon appearance ownership ambiguous')
        local base = pointer(manager + 0x2f8) + index * 0x1308
        local function current()
            if pointer(game + 0x3326a38) ~= manager then
                return false
            end
            local live_instance = lookup(manager + 0x278, entity)
            if live_instance == nil then
                return false
            end
            if pointer(pointer(manager + 0x290) + live_instance * 8) ~= owner_at or read(owner_at, 24) ~= owner then
                return false
            end
            local live_index = lookup(manager + 0x2b8, entity)
            if live_index == nil then
                return false
            end
            local data, count, empty = rows(manager + 0x2b8)
            local entries = read(data, count * 8)
            for row = 0, count - 1 do
                local offset = row * 8
                assert(
                    u32(entries, offset) == empty or u32(entries, offset + 4) ~= live_index
                        or u32(entries, offset) == entity,
                    'Weapon appearance configuration is shared'
                )
            end
            return true, pointer(manager + 0x2f8) + live_index * 0x1308
        end
        return base, current, identity.weapon_unit_ref
    end
    local function release(record)
        -- A dead/reused owner must never receive an old selector.
        local ok, valid = pcall(record.current)
        if not ok then
            return false
        end
        if not valid then
            return true
        end
        local now = read(record.address, 40)
        if now ~= record.masked then
            return now == record.bytes
        end
        assert(record.current(), 'Weapon source changed before restoration')
        deps.write(record.address, ZERO, record.bytes:sub(1, 4))
        return read(record.address, 40) == record.bytes
    end
    function self.sync(bindings)
        -- Resolve journals before considering a replacement weapon at a reused address.
        local resolved = {}
        for address, record in pairs(leases) do
            local valid, base = record.current()
            if valid then
                local at = record.offset and base and base + record.offset or address
                assert(not resolved[at], 'Weapon source journals overlap')
                resolved[at] = record
                record.address = at
            end
        end
        leases = resolved
        local wanted, additions = {}, {}
        local by_slot = {}
        for _, binding in ipairs(bindings) do
            local scope = binding.weapon_slot .. ':' .. tostring(binding.peer_player or 'local')
            by_slot[scope] = by_slot[scope] or {}
            table.insert(by_slot[scope], binding)
        end
        -- Validate the whole plan before touching a selector.
        for _, selected in pairs(by_slot) do
            local private, reason = deps.discovery.prove_private(selected)
            assert(private, reason or 'Weapon source privacy unavailable')
            local base, current, unit = locate(selected[1].weapon_slot, selected[1])
            local selected_roles = {}
            for _, binding in ipairs(selected) do
                local count = u32(read(binding.mesh + 0x58, 4), 0)
                assert(count > 0 and count <= 64 and binding.material_index >= 0 and binding.material_index < count)
                local role = u32(read(pointer(binding.mesh + 0x60) + binding.material_index * 4, 4), 0)
                selected_roles[role] = selected_roles[role] or {}
                selected_roles[role][binding.slot or 0x7e662968] = true
            end
            for _, binding in ipairs(selected) do
                assert(binding.unit == unit, 'Weapon source Unit differs from binding')
                assert(
                    deps.discovery.present(binding) and deps.discovery.binding(binding) == binding.current,
                    'Weapon changed before source acquisition'
                )
                local count = u32(read(binding.mesh + 0x58, 4), 0)
                assert(count > 0 and count <= 64 and binding.material_index >= 0 and binding.material_index < count)
                local role = u32(read(pointer(binding.mesh + 0x60) + binding.material_index * 4, 4), 0)
                assert(role ~= 0, 'Unnamed weapon material')
                local matched
                for row = 0, 9 do
                    local address = base + 0xc8 + row * 40
                    local held = leases[address]
                    local bytes = read(address, 40)
                    if u32(bytes, 0) == role or held and u32(held.bytes, 0) == role then
                        assert(not matched, 'Duplicate weapon appearance role')
                        matched = address
                        if held then
                            assert(held.current() and bytes == held.masked, 'Weapon source lease changed')
                        else
                            -- game.dll 6eb330 consumes +8 as material LUT and
                            -- +24 as Pattern LUT. Existing overrides in slots
                            -- explicitly replaced by this plan are intentional.
                            -- Keep all 36 payload bytes intact; refuse unrelated
                            -- decal/other overrides and unknown padding.
                            local slots = selected_roles[role]
                            assert(
                                bytes:sub(5, 8) == ZERO
                                    and (slots[0x7e662968] or bytes:sub(9, 16) == ZERO .. ZERO)
                                    and bytes:sub(17, 24) == ZERO .. ZERO
                                    and (slots[0x81d4c49d] or bytes:sub(25, 32) == ZERO .. ZERO)
                                    and bytes:sub(33, 40) == ZERO .. ZERO,
                                'Explicit weapon skin overrides must be preserved'
                            )
                            additions[address] = {
                                address = address,
                                offset = address - base,
                                bytes = bytes,
                                masked = ZERO .. bytes:sub(5),
                                current = current,
                            }
                        end
                    end
                end
                -- No matching selector means this material is untouched by the reset path.
                if matched then
                    wanted[matched] = true
                end
            end
        end
        local written = {}
        local ok, why = pcall(function()
            for address, record in pairs(additions) do
                assert(record.current() and read(address, 40) == record.bytes, 'Weapon source changed before write')
                leases[address], written[address] = record, record
                deps.write(address, record.bytes:sub(1, 4), ZERO)
                assert(read(address, 40) == record.masked, 'Weapon source suppression readback failed')
            end
        end)
        if not ok then
            for address, record in pairs(written) do
                if release(record) then
                    leases[address] = nil
                end
            end
            error(why, 0)
        end
        for address, record in pairs(leases) do
            if not wanted[address] then
                assert(release(record), 'Weapon source restoration pending')
                leases[address] = nil
            end
        end
        return true
    end
    function self.pending()
        return next(leases) ~= nil
    end
    return self
end
return S
