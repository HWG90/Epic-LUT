-- Complete-addon cleanup only. Certificates prove restored bindings; callbacks
-- own the existing renderer fence/disposal APIs. No active-history eviction.
local T = {}
local function handle(texture)
    local ok, n = pcall(tonumber, texture and texture.handle)
    return ok and n and n > 0 and n <= 4294967295 and n % 1 == 0 and n or nil
end
function T.new(deps)
    local retain, cohort = assert(deps.retain), assert(deps.cohort)
    local self = { state = 'new', freed_count = 0, freed_bytes = 0 }
    local records, textures, total
    local function finish(state, reason)
        self.state, self.reason = state, reason
        records, textures, total = nil, nil, nil
        cohort.sessions = nil -- Retained receipts must not pin old addon closures.
        return true
    end
    local function quarantine(reason)
        return finish('quarantined', tostring(reason or 'Texture retirement is not certified'))
    end
    local function prepare()
        records, textures, total = {}, {}, 0
        local handles = {}
        for _, record in ipairs(retain.records) do
            if record.cohort == cohort then
                local h = handle(record.texture)
                if
                    record.owned ~= true
                    or not h
                    or type(record.bytes) ~= 'number'
                    or record.bytes < 1
                    or record.bytes % 1 ~= 0
                    or record.bytes == math.huge
                then
                    return quarantine('Unknown texture creation receipt retained')
                end
                if handles[h] then
                    return quarantine('Duplicate texture handle receipt retained')
                end
                handles[h], textures[record.texture] = record.texture, true
                records[#records + 1], total = record, total + record.bytes
            end
        end
        if #records == 0 then
            return finish('closed')
        end
        for _, record in ipairs(retain.records) do
            local h = handle(record.texture)
            if record.cohort ~= cohort and h and handles[h] then
                return quarantine('Texture handle is shared with another retention cohort')
            end
        end
        for _, texture in pairs(retain.cache) do
            local h = handle(texture)
            if h and handles[h] and not textures[texture] then
                return quarantine('Texture cache has an unknown handle alias')
            end
        end
        if type(retain.bytes) ~= 'number' or retain.bytes < total then
            return quarantine('Texture retention byte accounting is inconsistent')
        end
        local ok, certified, why = pcall(deps.certified)
        if not ok or certified ~= true then
            return quarantine(ok and why or certified)
        end
        self.state = 'draining'
    end
    local function drain()
        local ok, receipt, why = pcall(deps.drain)
        if not ok then
            return quarantine('Render fence outcome is uncertain: ' .. tostring(receipt)), true
        end
        if not receipt then
            self.reason = tostring(why or 'Render fence pending')
            return false
        end
        if type(receipt) ~= 'table' then
            return quarantine('Render fence returned no retained receipt'), true
        end
        retain.fences = retain.fences or {}
        retain.fences[#retain.fences + 1] = receipt
        -- Each successful fence drains the destruction queued by its predecessor.
        while #retain.fences > 2 do
            table.remove(retain.fences, 1)
        end
        self.reason = nil
        return true
    end
    function self.close()
        cohort.closing = true -- No late session may reuse a certified cohort.
        if self.state == 'closed' or self.state == 'quarantined' then
            return true
        end
        if self.state == 'new' then
            local done = prepare()
            if done then
                return true
            end
        end
        if self.state == 'draining' then
            local done, quarantined = drain()
            if quarantined then
                return true
            end
            if not done then
                return false
            end
            self.state = 'destroying'
        end
        if self.state == 'destroying' then
            -- Quarantined partially destroyed cohorts must never be reused from
            -- the content cache. Backing buffers remain retained until a fence.
            for texture in pairs(textures) do
                texture.retiring = true
            end
            for _, record in ipairs(records) do
                local ok, done, why = pcall(deps.destroy, record.texture)
                if not ok or done == false then
                    return quarantine('Texture disposal outcome is uncertain: ' .. tostring(ok and why or done))
                end
            end
            self.state = 'retiring'
        end
        if self.state == 'retiring' then
            local done, quarantined = drain()
            if quarantined then
                return true
            end
            if not done then
                return false
            end
            local removed = {}
            for _, record in ipairs(records) do
                removed[record] = true
            end
            local remaining = {}
            for _, record in ipairs(retain.records) do
                if not removed[record] then
                    remaining[#remaining + 1] = record
                end
            end
            for key, texture in pairs(retain.cache) do
                if textures[texture] then
                    retain.cache[key] = nil
                end
            end
            retain.records, retain.bytes = remaining, retain.bytes - total
            self.freed_count, self.freed_bytes = #records, total
            return finish('closed')
        end
        return false
    end
    return self
end
return T
