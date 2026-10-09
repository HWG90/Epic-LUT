-- Reversible appearance intent, keyed by verified gear/slot/resource identity.
-- Documents are immutable cached textures; this service never edits or binds them.
local S = { MAX_RECORDS = 512, MAX_PROFILE = 128 }
local function token(value)
    return type(value) == 'string' and value ~= '' and #value <= 192 and not value:find('%z') and value or nil
end
local function kind(binding)
    if binding.kind == 'armor' or binding.kind == 'helmet' then
        return binding.kind
    end
    if binding.armor and not binding.helmet then
        return 'armor'
    end
    if binding.helmet and not binding.armor then
        return 'helmet'
    end
end
local function part(value)
    return #value .. ':' .. value
end
local function identity(b, pattern, proof, resource)
    local target = kind(b)
    local gear = target and proof and token(proof[target])
    local slot = token(b.save_key)
    if not target or not gear or not slot then
        return
    end
    local called, value = pcall(resource, b)
    if not called or type(value) ~= 'string' or #value ~= 16 or not value:match('^%x+$') then
        return
    end
    value = value:lower()
    local profile = part(target) .. (pattern and 'P' or 'M') .. part(gear)
    return profile .. part(slot) .. value, profile, target, gear, value
end
local function snapshot(b, pattern, proof)
    local target = kind(b)
    local gear = target and proof and token(proof[target])
    if not target or not gear or not token(b.save_key) then
        return
    end
    return {
        binding = b,
        texture = b.texture,
        original = b.original,
        save_key = b.save_key,
        kind = target,
        armor = target == 'armor',
        helmet = target == 'helmet',
        pattern = pattern,
        proof = gear,
    }
end
local function record_copy(record)
    return {
        save_key = record.save_key,
        kind = record.kind,
        pattern = record.pattern,
        proof = record.proof,
        resource = record.resource,
        texture = record.texture,
    }
end
function S.new()
    local records, total = {}, 0
    local self = {}
    function self.remember(bindings, pattern, proof, resource)
        assert(type(resource) == 'function', 'Appearance resource resolver unavailable')
        pattern = not not pattern
        local staged, pending, profiles, added = {}, {}, {}, 0
        for _, record in pairs(records) do
            profiles[record.profile] = (profiles[record.profile] or 0) + 1
        end
        for _, b in ipairs(bindings or {}) do
            local texture = b.texture
            if
                texture
                and texture.object
                and texture.object ~= 0
                and texture.data
                and texture.width
                and texture.height
            then
                local key, profile, target, gear, hash = identity(b, pattern, proof, resource)
                if key then
                    assert(
                        not staged[key] or staged[key].texture == texture,
                        'Conflicting appearance intent for one LUT slot'
                    )
                    if not staged[key] and not records[key] then
                        added = added + 1
                        profiles[profile] = (profiles[profile] or 0) + 1
                        assert(
                            profiles[profile] <= S.MAX_PROFILE,
                            'Appearance profile exceeds 128 LUT slots; restore or clear a profile'
                        )
                    end
                    staged[key] = {
                        save_key = b.save_key,
                        kind = target,
                        pattern = pattern,
                        proof = gear,
                        resource = hash,
                        texture = texture,
                        profile = profile,
                    }
                else
                    local captured = snapshot(b, pattern, proof)
                    if captured then
                        pending[#pending + 1] = captured
                    end
                end
            end
        end
        assert(
            total + added <= S.MAX_RECORDS,
            'Appearance history exceeds 512 LUT slots; restore or clear saved appearance intent'
        )
        local remembered = 0
        for key, record in pairs(staged) do
            records[key] = record
            remembered = remembered + 1
        end
        total = total + added
        return remembered, pending
    end
    function self.batches(bindings, pattern, proof, resource, current)
        assert(type(resource) == 'function' and type(current) == 'function', 'Appearance binding resolvers unavailable')
        local grouped, batches, seen = {}, {}, {}
        for _, b in ipairs(bindings or {}) do
            local key = identity(b, not not pattern, proof, resource)
            local record = key and records[key]
            if record and b.original and b.original ~= 0 and not seen[b] then
                local called, object = pcall(current, b)
                -- Already-owned objects are no-ops. Foreign bindings and unknown
                -- originals are deliberately left to their current owner.
                if called and object ~= nil and object == b.original and object ~= record.texture.object then
                    local batch = grouped[record.texture]
                    if not batch then
                        batch = { document = record.texture, targets = {} }
                        grouped[record.texture] = batch
                        batches[#batches + 1] = batch
                    end
                    batch.targets[#batch.targets + 1] = b
                    seen[b] = true
                end
            end
        end
        return batches
    end
    function self.clear(target, pattern)
        assert(target == nil or target == 'armor' or target == 'helmet', 'Invalid appearance target')
        assert(pattern == nil or type(pattern) == 'boolean', 'Invalid appearance type')
        local removed = 0
        for key, record in pairs(records) do
            if (not target or record.kind == target) and (pattern == nil or record.pattern == pattern) then
                records[key] = nil
                removed = removed + 1
            end
        end
        total = total - removed
        return removed
    end
    function self.entries()
        local keys = {}
        for key in pairs(records) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        local entries = {}
        for _, key in ipairs(keys) do
            entries[#entries + 1] = record_copy(records[key])
        end
        return entries
    end
    function self.replace(entries)
        assert(type(entries) == 'table' and #entries <= S.MAX_RECORDS, 'Invalid appearance history snapshot')
        local size = #entries
        local fields = 0
        for index in pairs(entries) do
            assert(
                type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= size,
                'Appearance history snapshot must be a dense list'
            )
            fields = fields + 1
        end
        assert(fields == size, 'Appearance history snapshot must be a dense list')
        local staged, profiles = {}, {}
        local function resource(entry)
            return entry.resource
        end
        for _, entry in ipairs(entries) do
            assert(
                type(entry) == 'table'
                    and (entry.kind == 'armor' or entry.kind == 'helmet')
                    and type(entry.pattern) == 'boolean',
                'Invalid appearance history identity'
            )
            local texture = entry.texture
            assert(
                type(texture) == 'table'
                    and texture.object
                    and texture.object ~= 0
                    and texture.data
                    and texture.width
                    and texture.height,
                'Appearance history texture is unavailable'
            )
            local key, profile, target, gear, hash =
                identity(entry, entry.pattern, { [entry.kind] = entry.proof }, resource)
            assert(key, 'Appearance history requires verified gear, slot and resource IDs')
            assert(not staged[key], 'Duplicate appearance history identity')
            profiles[profile] = (profiles[profile] or 0) + 1
            assert(profiles[profile] <= S.MAX_PROFILE, 'Appearance history profile exceeds 128 LUT slots')
            staged[key] = {
                save_key = entry.save_key,
                kind = target,
                pattern = entry.pattern,
                proof = gear,
                resource = hash,
                texture = texture,
                profile = profile,
            }
        end
        -- Commit only after the entire replacement validates. Texture buffers
        -- stay immutable references shared with the session cache.
        records, total = staged, size
        return total
    end
    function self.count()
        return total
    end
    return self
end
return S
