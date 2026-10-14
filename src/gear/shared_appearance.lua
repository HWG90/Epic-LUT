-- Epic LUT appearance sharing. Lobby transport is derived from CowboyBingus v1.3.
-- Remote writes are scoped to that peer's live garment slots and matching equipped kits.
local S = {}
local function appearance_key(identity)
    local parts = { identity.body or 0, identity.armor or 0, identity.helmet or 0 }
    for slot = 1, 3 do
        parts[#parts + 1] = identity.weapons and identity.weapons[slot] or '0000000000000000'
    end
    return table.concat(parts, ':')
end
local function compatible(identity, appearance)
    if
        identity.body == appearance.body
        and identity.armor == appearance.armor
        and identity.helmet == appearance.helmet
    then
        return true
    end
    for slot = 1, 3 do
        local current = identity.weapons and identity.weapons[slot]
        if current and appearance.weapons and current == appearance.weapons[slot] then
            return true
        end
    end
    return false
end
function S.new(deps)
    local self = { status = 'Sharing: waiting for lobby', elapsed = 0, frame = 0, peers = {} }
    local text, signature, current_kit, packet_kit, publication_status
    local decode_failures = {}
    local target_failures = {}
    local function message(value)
        local line = tostring(value):match('^[^\r\n]*') or 'Appearance unavailable'
        for _ = 1, 4 do
            local clean, removed = line:gsub('^.-%.lua:%d+:%s*', '')
            if removed == 0 then
                break
            end
            line = clean
        end
        return line:gsub('%s+', ' '):sub(1, 240)
    end
    local session = deps.sync.session({
        memory = deps.memory,
        game = deps.game,
        natives = deps.sync.natives,
        note = function(message)
            self.status = publication_status or message
            deps.note(message)
        end,
    })
    local codec = deps.codec
    local function peer_key(p)
        return string.format('%08x%08x', p.peer_high, p.peer_low)
    end
    local function restore(key)
        local peer = self.peers[key]
        if not peer then
            return true
        end
        peer.job = nil
        local ok, done = pcall(peer.bindings.restore)
        if ok and done then
            self.peers[key] = nil
            return true
        end
        return false
    end
    local function publish(identity)
        local kit = appearance_key(identity)
        if current_kit ~= kit then
            current_kit, signature, publication_status = kit, nil, nil
            if packet_kit ~= kit then
                text, packet_kit = nil, nil
            end
        end
        if deps.highlighting() then
            if not text then
                publication_status = 'Sharing: waiting for region highlight to finish; receiving remains on'
                self.status = publication_status
            end
            return text
        end
        local entries = deps.entries()
        local marks = { identity.body or 0, identity.armor or 0, identity.helmet or 0 }
        marks[#marks + 1] = appearance_key(identity)
        for _, entry in ipairs(entries) do
            local d = entry.document
            local base = entry.original
            local baseline = base
                    and table.concat({
                        base.resource or '',
                        base.width or 0,
                        base.height or 0,
                        base.data and tostring(base.data) or 'pending',
                    }, ':')
                or ''
            marks[#marks + 1] = entry.key
                .. ':'
                .. d.width
                .. ':'
                .. d.height
                .. ':'
                .. baseline
                .. ':'
                .. require('ffi').string(d.data, d.width * d.height * 16)
        end
        local now = table.concat(marks, '|')
        if signature ~= now then
            local ok, packet = pcall(function()
                local encoded = codec.encode(identity, entries)
                assert(type(encoded) == 'string' and encoded ~= '', 'Shared LUT encoder returned no appearance')
                return encoded
            end)
            signature = now
            if ok then
                text, packet_kit = packet, kit
                publication_status = nil
                self.status = #entries == 0 and 'Sharing: enabled; no custom LUTs to publish'
                    or (
                        'Ready to share '
                        .. #entries
                        .. ' LUT bindings ('
                        .. #packet
                        .. ' bytes); waiting for stable lobby'
                    )
            else
                -- Keep a previously encoded packet only for this exact kit.
                -- Nil with enabled=true removes a stale-kit advertisement while
                -- the transport continues receiving the other peers' packets.
                if packet_kit ~= kit then
                    text, packet_kit = nil, nil
                end
                local reason = message(packet)
                publication_status = (reason:match('^Sharing:') and reason or 'Sharing: ' .. reason)
                    .. (text and '; keeping previous shareable appearance' or '; receiving remains on')
                self.status = publication_status
                deps.note(self.status)
            end
        end
        return text
    end
    local function receive(members)
        local players, seen, present = nil, {}, {}
        for _, member in ipairs(members or {}) do
            if member.text and not member['local'] then
                local key = peer_key(member)
                present[key] = true
                local old = self.peers[key]
                local ok, appearance
                if old and old.text == member.text then
                    ok, appearance = true, old.appearance
                else
                    ok, appearance = pcall(codec.decode, member.text)
                end
                if not ok then
                    local status = message(appearance)
                    local failed = decode_failures[key]
                    if not failed or failed.text ~= member.text or failed.status ~= status then
                        deps.note(status)
                    end
                    decode_failures[key] = { text = member.text, status = status }
                    self.status = publication_status or status
                end
                if ok then
                    local prior_failure = decode_failures[key]
                    decode_failures[key] = nil
                    if prior_failure and not publication_status and self.status == prior_failure.status then
                        self.status = 'Sharing: peer appearance ready'
                    end
                    players = players or deps.players()
                    for _, player in ipairs(players) do
                        if not player['local'] and peer_key(player) == key then
                            local identity = deps.resolve(player)
                            if identity and compatible(identity, appearance) then
                                local captured, targets, unit_signature = pcall(deps.targets, identity, appearance)
                                if captured then
                                    seen[key], target_failures[key] = true, nil
                                    if
                                        not old
                                        or old.retry
                                        or old.text ~= member.text
                                        or old.units ~= unit_signature
                                    then
                                        if restore(key) then
                                            -- Recapture originals after removing the prior packet.
                                            captured, targets, unit_signature =
                                                pcall(deps.targets, identity, appearance)
                                        else
                                            captured = false
                                            targets = 'Previous Shared LUT restoration is pending'
                                        end
                                        if captured then
                                            local peer = {
                                                text = member.text,
                                                appearance = appearance,
                                                units = unit_signature,
                                                bindings = deps.bindings(),
                                            }
                                            self.peers[key] = peer
                                            peer.job = coroutine.create(function()
                                                for document, bindings in pairs(targets) do
                                                    peer.bindings.apply(document, bindings)
                                                    coroutine.yield()
                                                end
                                            end)
                                        end
                                    elseif not old.job and old.bindings.reconcile then
                                        -- A map load can restore stock LUT pointers without replacing the Unit.
                                        -- Repair only the exact original bindings retained by this peer session.
                                        local repaired, why = pcall(old.bindings.reconcile)
                                        if not repaired then
                                            local refused = message(why)
                                            if old.repair_failure ~= refused then
                                                deps.note('Shared LUT repair deferred: ' .. refused)
                                            end
                                            old.repair_failure = refused
                                        else
                                            old.repair_failure = nil
                                        end
                                    end
                                end
                                if not captured then
                                    seen[key] = nil
                                    local refused = message(targets)
                                    if target_failures[key] ~= refused then
                                        deps.note('Shared LUT peer deferred: ' .. refused)
                                    end
                                    target_failures[key] = refused
                                    restore(key)
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
        for key in pairs(self.peers) do
            if not seen[key] then
                restore(key)
            end
        end
        for key in pairs(target_failures) do
            if not present[key] then
                target_failures[key] = nil
            end
        end
        for key in pairs(decode_failures) do
            if not present[key] then
                if not publication_status and self.status == decode_failures[key].status then
                    self.status = 'Sharing: waiting for peer appearance'
                end
                decode_failures[key] = nil
            end
        end
    end
    function self.authorized(peer, slot, resource)
        if not self.enabled then
            return false, 'Shared LUT is disabled'
        end
        -- Refresh the transport roster instead of granting writes from an old
        -- cached peer packet. The existing transport keeps publication throttled.
        local members = session.poll(math.floor(self.frame), text, false, { enabled = true })
        local wanted, found = peer_key(peer), nil
        for _, member in ipairs(members or {}) do
            if not member['local'] and peer_key(member) == wanted and member.text then
                found = member
                break
            end
        end
        if not found then
            return false, 'Peer no longer advertises Shared LUT in this lobby'
        end
        local prior = self.peers[wanted]
        local appearance
        if prior and prior.text == found.text then
            appearance = prior.appearance
        else
            local ok, decoded = pcall(codec.decode, found.text)
            if not ok then
                return false, 'Peer Shared LUT packet is invalid'
            end
            appearance = decoded
        end
        if not appearance.weapons or appearance.weapons[slot] ~= resource then
            return false, 'Peer weapon configuration or consent changed'
        end
        for _, player in ipairs(deps.players() or {}) do
            if
                not player['local']
                and peer_key(player) == wanted
                and player.player == peer.player
                and player.unit == peer.unit
            then
                return true
            end
        end
        return false, 'Peer live player identity changed'
    end
    function self.tick(dt, enabled)
        self.enabled = enabled == true
        self.frame = self.frame + math.max(0, dt or 0) * 60
        self.elapsed = self.elapsed + math.max(0, dt or 0)
        if not enabled then
            signature, current_kit, publication_status = nil, nil, nil
            self.status = 'Sharing: off'
            for key, peer in pairs(self.peers) do
                peer.job = nil
                restore(key)
            end
        end
        -- One texture job slice per tick, never a whole squad's textures at once.
        for key, peer in pairs(self.peers) do
            if peer.job then
                local ok, why = coroutine.resume(peer.job)
                if not ok then
                    peer.job = nil
                    peer.retry = true
                    restore(key)
                    deps.note('Shared appearance stopped safely: ' .. tostring(why))
                elseif coroutine.status(peer.job) == 'dead' then
                    peer.job = nil
                end
                break
            end
        end
        if self.elapsed < 2 then
            return
        end
        self.elapsed = 0
        local outgoing
        if enabled then
            local identity = deps.identity()
            if identity then
                outgoing = publish(identity)
            else
                text, signature, current_kit, packet_kit = nil, nil, nil, nil
                publication_status = 'Sharing: waiting for local Helldiver; receiving remains on'
                self.status = publication_status
            end
        end
        local members = session.poll(math.floor(self.frame), outgoing, false, { enabled = enabled })
        receive(enabled and members or nil)
        self.status = not enabled and 'Sharing: off' or publication_status or self.status
    end
    function self.close(allow_quarantine)
        self.enabled = false
        local complete = true
        for key in pairs(self.peers) do
            self.peers[key].job = nil
            if not restore(key) then
                complete = false
            end
        end
        if not self.cleared then
            local ok, done = pcall(session.clear)
            self.cleared = ok and done
        end
        if not complete and allow_quarantine == true then
            -- Full-addon retirement will refuse to destroy uncertified textures
            -- and retain their GPU backing. Ordinary sharing toggles and packet
            -- updates continue requiring exact restoration before proceeding.
            self.quarantined = true
            self.status = 'Sharing: remote texture restoration uncertified; backing retained'
            self.peers = {}
            return true
        end
        return complete
    end
    return self
end
return S
