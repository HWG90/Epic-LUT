-- Startup snapshots carry named assignment proofs, never native pointers.
-- Palette persistence waits for exact sources; a user action cancels resume.
local S = { TIMEOUT = 120 }
function S.new(m, host)
    local P, M = assert(m.binding_provenance), assert(m.weapon_mapping)
    local self, job, unresolved = {}, nil, false
    local function bridge()
        return host.bridge()
    end
    local function signature(refs, original)
        local normalized = P.validate(refs, 'weapon', refs.key, original)
        -- Runtime enumeration may change. MeshID/Section/material slot and the
        -- entire effective source identity must still describe the same role.
        normalized.key = (normalized.texture_slot == P.PATTERN and 'p:' or '')
            .. '3:'
            .. normalized.weapon_slot
            .. ':0:0'
        return P.encode(normalized, 'weapon', normalized.key, original)
    end
    function self.cancel(discard)
        job = nil
        if discard then
            unresolved = false
        end
    end
    function self.pending()
        return job ~= nil
    end
    function self.capture()
        assert(not job and not unresolved, 'Saved weapon setup is awaiting recovery; previous setup retained')
        local editor, entries, receipts, copies = bridge(), {}, {}, {}
        local discovery = editor.discovery()
        for _, b in ipairs(editor.runtime().all_owned()) do
            if b.texture and b.current == b.texture.object then
                if discovery.present(b) then
                    if discovery.binding(b) == b.current then
                        local original =
                            assert(host.original(b), 'Original weapon pixels are still loading; retry Save')
                        local key = (b.slot == P.PATTERN and 'p:' or '') .. b.save_key
                        local _, refs = host.sources().capture(b, { kind = 'weapon', key = key, original = original })
                        assert(refs and refs.version == 4, 'Exact weapon startup assignment proof unavailable')
                        local bytes = M.bytes(b.texture)
                        copies[bytes] = copies[bytes] or M.copy(b.texture)
                        entries[#entries + 1] = {
                            kind = 'weapon',
                            key = key,
                            weapon_slot = b.weapon_slot,
                            weapon_resource = b.weapon_resource or b.weapon_resource64,
                            document = copies[bytes],
                            original = original,
                            binding_provenance = refs,
                        }
                        receipts[#receipts + 1] = { binding = b, current = b.current, bytes = bytes }
                    end
                else
                    error('Applied weapon setup is awaiting recovery; previous setup retained', 0)
                end
            end
        end
        assert(#entries <= 4096, 'Weapon startup binding budget exceeded')
        for _, receipt in ipairs(receipts) do
            local b = receipt.binding
            assert(
                discovery.present(b)
                    and discovery.binding(b) == receipt.current
                    and b.current == receipt.current
                    and b.texture
                    and M.bytes(b.texture) == receipt.bytes,
                'Weapon setup changed during capture; previous setup retained'
            )
        end
        return entries
    end
    function self.start(preset)
        assert(not job, 'Weapon startup already in progress')
        assert(
            type(preset) == 'table'
                and type(preset.entries) == 'table'
                and #preset.entries > 0
                and #preset.entries <= 4096,
            'Invalid weapon startup snapshot'
        )
        local saved, by_proof, slots, bytes_seen, total = {}, {}, {}, {}, 0
        for _, entry in ipairs(preset.entries) do
            assert(
                entry.kind == 'weapon' and entry.original and entry.binding_provenance,
                'Weapon startup requires an exact saved assignment'
            )
            local proof = signature(entry.binding_provenance, entry.original)
            local refs = entry.binding_provenance
            assert(
                refs.weapon_resource == entry.weapon_resource and refs.weapon_slot == entry.weapon_slot,
                'Weapon startup identity differs from assignment'
            )
            assert(not by_proof[proof], 'Duplicate weapon startup assignment')
            assert(
                not slots[entry.weapon_slot] or slots[entry.weapon_slot] == entry.weapon_resource,
                'Conflicting weapon startup configurations'
            )
            slots[entry.weapon_slot] = entry.weapon_resource
            local bytes = M.bytes(entry.document)
            if not bytes_seen[bytes] then
                total = total + #bytes
                assert(total <= 8 * 1024 * 1024, 'Weapon startup payload budget exceeded')
                bytes_seen[bytes] = M.copy(entry.document)
            end
            local copy = {}
            for key, value in pairs(entry) do
                copy[key] = value
            end
            copy.document = bytes_seen[bytes]
            copy.binding_provenance = P.validate(refs, 'weapon', entry.key, entry.original)
            saved[#saved + 1], by_proof[proof] = copy, copy
        end
        local started = host.time()
        unresolved = true
        job = coroutine.create(function()
            local runtime, discovery = bridge().runtime(), bridge().discovery()
            local applicable, skipped = {}, 0
            for slot, resource in pairs(slots) do
                local catalog
                repeat
                    catalog = runtime.refresh(slot)
                    if not catalog then
                        assert(host.time() - started < S.TIMEOUT, 'Saved weapons are not available; setup retained')
                        coroutine.yield()
                    end
                until catalog
                if (catalog.weapon_resource or catalog.weapon_resource64) == resource then
                    applicable[slot] = true
                else
                    skipped = skipped + 1
                end
            end
            local plans, variants, found, checked, selected_entries = {}, {}, {}, {}, {}
            for slot in pairs(applicable) do
                for _, kind in ipairs({ 'material', 'pattern' }) do
                    local needed = false
                    for _, entry in ipairs(saved) do
                        needed = needed
                            or entry.weapon_slot == slot and (entry.key:sub(1, 2) == 'p:') == (kind == 'pattern')
                    end
                    if needed then
                        for index, group in ipairs(runtime.groups(slot, kind)) do
                            for _, b in ipairs(group.bindings) do
                                assert(host.time() - started < S.TIMEOUT, 'Weapon startup timed out; setup retained')
                                local original, refs
                                repeat
                                    assert(
                                        discovery.present(b)
                                            and discovery.binding(b) == b.current
                                            and b.current == b.original,
                                        'Weapon changed during startup; setup retained'
                                    )
                                    original = host.original(b)
                                    if original then
                                        local ok, result, value = pcall(host.sources().capture, b, {
                                            kind = 'weapon',
                                            original = original,
                                            key = (kind == 'pattern' and 'p:' or '') .. b.save_key,
                                        })
                                        if ok then
                                            refs = value
                                        elseif not tostring(result):find(m.weapon_provenance.PENDING, 1, true) then
                                            error(result, 0)
                                        end
                                    end
                                    if not refs then
                                        assert(
                                            host.time() - started < S.TIMEOUT,
                                            'Exact weapon startup sources are not ready; setup retained'
                                        )
                                        coroutine.yield()
                                    end
                                until refs
                                local entry = by_proof[signature(refs, original)]
                                if entry then
                                    assert(not found[entry], 'Ambiguous current weapon startup assignment')
                                    assert(
                                        entry.document.width == original.width
                                            and entry.document.height == original.height,
                                        'Weapon startup LUT dimensions changed'
                                    )
                                    found[entry] = true
                                    selected_entries[#selected_entries + 1] = entry
                                    local variant = slot
                                        .. ':'
                                        .. kind
                                        .. ':'
                                        .. index
                                        .. ':'
                                        .. M.bytes(entry.document)
                                    local plan = variants[variant]
                                    if not plan then
                                        plan = {
                                            weapon_slot = slot,
                                            weapon_resource = slots[slot],
                                            source_resource = original.resource,
                                            family = kind,
                                            index = index,
                                            document = entry.document,
                                            targets = {},
                                        }
                                        variants[variant], plans[#plans + 1] = plan, plan
                                    end
                                    plan.targets[#plan.targets + 1] = b
                                    checked[#checked + 1] = { binding = b, current = b.current }
                                end
                                coroutine.yield()
                            end
                        end
                    end
                end
            end
            for _, entry in ipairs(saved) do
                assert(
                    not applicable[entry.weapon_slot] or found[entry],
                    'Saved weapon assignment no longer matches; setup retained'
                )
            end
            if #plans > 0 then
                -- Recheck the complete disk-source scope once immediately before
                -- writing, after cooperative captures have crossed frames.
                host.sources().with_export_batch(selected_entries, function(batch)
                    for _, entry in ipairs(selected_entries) do
                        batch.provenance(entry)
                    end
                end)
                for _, receipt in ipairs(checked) do
                    assert(
                        discovery.present(receipt.binding) and discovery.binding(receipt.binding) == receipt.current,
                        'Weapon changed before startup apply; setup retained'
                    )
                end
                local results, count = host.apply(plans), 0
                for _, result in ipairs(results) do
                    count = count + result.count
                end
                host.message(
                    'Saved weapon setup restored to '
                        .. count
                        .. ' bindings; '
                        .. skipped
                        .. ' different weapon slots skipped.'
                )
                unresolved = skipped > 0
            elseif skipped > 0 then
                host.message('Saved weapon setup skipped: current weapon configurations differ.')
            end
        end)
    end
    function self.tick()
        if not job then
            return
        end
        if host.busy and host.busy() then
            self.cancel()
            return
        end
        local now = host.time()
        if self.next_tick and now < self.next_tick then
            return
        end
        self.next_tick = now + 0.1
        local ok, why = coroutine.resume(job)
        if not ok then
            job = nil
            host.message('Saved weapon setup could not resume: ' .. tostring(why))
        elseif coroutine.status(job) == 'dead' then
            job = nil
        end
    end
    return self
end
return S
