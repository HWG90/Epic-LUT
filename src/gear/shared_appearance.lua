-- Epic LUT appearance sharing. Lobby transport is derived from CowboyBingus v1.3.
-- Remote writes are scoped to that peer's live garment slots and matching equipped kits.
local S = {}
function S.new(deps)
    local self = { status = 'Sharing: waiting for lobby', elapsed = 0, frame = 0, peers = {} }
    local session = deps.sync.session({
        memory = deps.memory,
        game = deps.game,
        natives = deps.sync.natives,
        note = function(message)
            self.status = message
            deps.note(message)
        end,
    })
    local codec = deps.codec
    local text, signature
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
    local function publish(identity)
        if deps.highlighting() then
            return text
        end
        local entries = deps.entries()
        local marks = { identity.body or 0, identity.armor or 0, identity.helmet or 0 }
        for _, entry in ipairs(entries) do
            local d = entry.document
            marks[#marks + 1] = entry.key
                .. ':'
                .. d.width
                .. ':'
                .. d.height
                .. ':'
                .. require('ffi').string(d.data, d.width * d.height * 16)
        end
        local now = table.concat(marks, '|')
        if signature ~= now then
            local ok, packet = pcall(codec.encode, identity, entries)
            signature = now
            text = ok and packet or nil
            self.status = ok and ('Ready to share ' .. #entries .. ' full LUT bindings; waiting for stable lobby')
                or tostring(packet)
            if not ok then
                deps.note(self.status)
            end
        end
        return text
    end
    local function receive(members)
        local players, seen = nil, {}
        for _, member in ipairs(members or {}) do
            if member.text and not member['local'] then
                local key = peer_key(member)
                local old = self.peers[key]
                local ok, appearance
                if old and old.text == member.text then
                    ok, appearance = true, old.appearance
                else
                    ok, appearance = pcall(codec.decode, member.text)
                end
                if ok then
                    players = players or deps.players()
                    for _, player in ipairs(players) do
                        if not player['local'] and peer_key(player) == key then
                            local identity = deps.resolve(player)
                            if
                                identity
                                and identity.body == appearance.body
                                and identity.armor == appearance.armor
                                and identity.helmet == appearance.helmet
                            then
                                seen[key] = true
                                local targets, unit_signature = deps.targets(identity, appearance)
                                if not old or old.text ~= member.text or old.units ~= unit_signature then
                                    if restore(key) then
                                        targets = deps.targets(identity, appearance) -- recapture originals after restoring our prior packet
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
    end
    function self.tick(dt, enabled)
        self.frame = self.frame + math.max(0, dt or 0) * 60
        self.elapsed = self.elapsed + math.max(0, dt or 0)
        if not enabled then
            for key, peer in pairs(self.peers) do
                peer.job = nil
                restore(key)
            end
        end
        -- One texture job slice per tick, never a whole squad's textures at once.
        for _, peer in pairs(self.peers) do
            if peer.job then
                local ok, why = coroutine.resume(peer.job)
                if not ok then
                    peer.job = nil
                    peer.bindings.restore()
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
        local identity = deps.identity()
        if not identity then
            receive(nil)
            self.status = 'Sharing: waiting for local Helldiver'
            return
        end
        local outgoing = enabled and publish(identity) or nil
        local members = session.poll(math.floor(self.frame), outgoing, false)
        receive(enabled and members or nil)
        if not enabled then
            self.status = 'Sharing: off'
        end
    end
    function self.close()
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
