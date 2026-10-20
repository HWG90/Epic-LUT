local cooperative=m and m.cooperative or require('src.core.cooperative')
local buffers=m and m.float_buffer or require('src.core.float_buffer')
-- Epic LUT appearance sharing. Lobby transport is derived from CowboyBingus v1.3.
-- Remote writes are scoped to that peer's live garment slots and matching equipped kits.
local S = {}
local function compatible(identity, appearance)
    return identity.body == appearance.body
        and identity.armor == appearance.armor
        and identity.helmet == appearance.helmet
end
function S.new(deps)
    local self = { status = 'Sharing: waiting for lobby', elapsed = 0, frame = 0, peers = {} }
    local text, signature, current_kit, packet_kit, publication_status, published_revision, identity_stamp
    local subscriptions = {}
    local publication_job
    local publication_epoch = 0
    function self.invalidate()
        publication_epoch = publication_epoch + 1
        published_revision = nil
    end
    local function subscribe()
        if #subscriptions > 0 then
            return
        end
        local ok, api = pcall(require, 'mods/skyeshade/hd2runtime')
        if ok and type(api) == 'table' and api.events and api.events.on then
            for _, name in ipairs({ 'player_spawned', 'player_died', 'mission_started', 'mission_ended' }) do
                local subscribed, token =
                    pcall(api.events.on, name, self.invalidate, { owner = 'epic_lut_shared_appearance', key = name })
                if subscribed and token then
                    subscriptions[#subscriptions + 1] = token
                end
            end
        end
    end
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
        if peer.bindings.restore() then
            self.peers[key] = nil
            return true
        end
        return false
    end
    local function publish(identity, checkpoint, current)
        local kit = table.concat({ identity.body or 0, identity.armor or 0, identity.helmet or 0 }, ':')
        if current_kit ~= kit then
            published_revision = nil
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
        -- Transport still receives peer packets, but an unchanged local
        -- assignment must not rescan every native gear/weapon binding.
        local revision = deps.revision and deps.revision()
        if revision ~= nil and published_revision == revision then
            return text
        end
        local entries = deps.entries(identity)
        if checkpoint then
            checkpoint(true)
        end
        local marks = { identity.body or 0, identity.armor or 0, identity.helmet or 0 }
        local documents, payload_ids, payloads = {}, {}, {}
        assert(#entries <= 4096, 'Too many LUT bindings to share')
        for index, entry in ipairs(entries) do
            if checkpoint and index % 64 == 0 then checkpoint() end
            local d = entry.document
            local payload = documents[d]
            if not payload then
                local bytes = buffers.bytes(d.data, d.width * d.height * 4, nil, checkpoint)
                local key = d.width .. ':' .. d.height .. ':' .. #bytes .. ':' .. bytes
                payload = payload_ids[key]
                if not payload then
                    payload = #payloads + 1
                    payload_ids[key], payloads[payload] = payload, key
                end
                documents[d] = payload
            end
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
                .. payload
        end
        -- Retain each immutable palette payload once, rather than once per binding.
        local now = table.concat(marks, '|') .. '|payloads:' .. #payloads .. '|' .. table.concat(payloads)
        if signature ~= now then
            local ok, packet = cooperative.call(function()
                local encoded = codec.encode(identity, entries, checkpoint)
                assert(type(encoded) == 'string' and encoded ~= '', 'Shared LUT encoder returned no appearance')
                return encoded
            end)
            -- A completed packet is accepted only for the captured assignment.
            if current and not current() then
                return text
            end
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
        if not current or current() then
            published_revision = revision
        end
        return text
    end
    local function advance_publication()
        local ok, why = coroutine.resume(publication_job)
        if not ok then
            publication_job = nil
            publication_status = 'Sharing: ' .. message(why)
            self.status = publication_status
            deps.note(self.status)
        elseif coroutine.status(publication_job) == 'dead' then
            publication_job = nil
        end
    end
    local function defer_publication(revision, stamp)
        local epoch = publication_epoch
        local clock = deps.publication_clock or os.clock
        local started = clock()
        local function checkpoint(force)
            if force or clock() - started >= 0.002 then
                coroutine.yield()
                started = clock()
            end
        end
        local function current()
            return self.enabled
                and publication_epoch == epoch
                and (not deps.revision or deps.revision() == revision)
                and (not deps.identity_key or deps.identity_key() == stamp)
        end
        publication_job = coroutine.create(function()
            local identity = deps.identity()
            checkpoint(true)
            if not current() then
                return
            end
            if identity then
                publish(identity, checkpoint, current)
                if current() then
                    identity_stamp = stamp
                end
            else
                text, signature, current_kit, packet_kit, identity_stamp = nil, nil, nil, nil, nil
                publication_status = 'Sharing: waiting for local Helldiver; receiving remains on'
                self.status = publication_status
            end
        end)
        advance_publication()
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
    function self.tick(dt, enabled)
        if enabled and not self.enabled then
            self.invalidate()
            subscribe()
            self.cleared = false
        end
        self.enabled = enabled == true
        if not enabled then
            publication_job = nil
        elseif publication_job then
            advance_publication()
        end
        self.frame = self.frame + math.max(0, dt or 0) * 60
        self.elapsed = self.elapsed + math.max(0, dt or 0)
        if not enabled then
            signature, current_kit, publication_status, published_revision = nil, nil, nil, nil
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
            local revision = deps.revision and deps.revision()
            local stamp = deps.identity_key and deps.identity_key()
            if revision ~= nil and stamp ~= nil and published_revision == revision and identity_stamp == stamp then
                outgoing = text
            else
                if identity_stamp ~= stamp then
                    published_revision = nil
                end
                if deps.defer_publication then
                    if not publication_job then
                        defer_publication(revision, stamp)
                    end
                    outgoing = text
                else
                    local identity = deps.identity()
                    if identity then
                        outgoing = publish(identity)
                        identity_stamp = stamp
                    else
                        text, signature, current_kit, packet_kit, identity_stamp = nil, nil, nil, nil, nil
                        publication_status = 'Sharing: waiting for local Helldiver; receiving remains on'
                        self.status = publication_status
                    end
                end
            end
        end
        local members = session.poll(math.floor(self.frame), outgoing, false, { enabled = enabled })
        receive(enabled and members or nil)
        self.status = not enabled and 'Sharing: off' or publication_status or self.status
    end
    function self.close()
        publication_job = nil
        for _, token in ipairs(subscriptions) do
            if token.unsubscribe then
                pcall(token.unsubscribe, token)
            end
        end
        subscriptions = {}
        self.invalidate()
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
        return complete
    end
    return self
end
return S
