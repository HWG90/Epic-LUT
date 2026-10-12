-- Immutable weapon palette capture and exact apply plans; the host coordinates
-- persistence/cache, exports and any mixed garment/weapon transaction.
local W = { MAX_BINDINGS = 4096, MAX_PAYLOAD_BYTES = 8 * 1024 * 1024 }
function W.new(modules, host)
    local mapping = assert(modules.weapon_mapping, 'Weapon receipt helper unavailable')
    local targets = assert(modules.outfit_targets, 'Saved target resolver unavailable')
    local runtime = assert(host.runtime, 'Weapon runtime unavailable')
    local self = {}
    local function groups(descriptors)
        return descriptors or assert(host.groups(), 'Weapon LUT groups unavailable')
    end
    local function original(group, binding)
        local value = host.original and host.original(binding, group.group) or group.source_document
        assert(
            type(value) == 'table' and value.width == group.width and value.height == group.height,
            'Original weapon LUT shape changed'
        )
        return value
    end
    local function clones()
        local documents, total = {}, 0
        return function(document)
            local bytes = mapping.bytes(document)
            local signature = document.width .. ':' .. document.height .. ':' .. bytes
            if not documents[signature] then
                total = total + #bytes
                assert(total <= W.MAX_PAYLOAD_BYTES, 'Weapon preset payload budget exceeded')
                documents[signature] = mapping.copy(document)
            end
            return documents[signature], signature
        end
    end
    local function source_copy(source)
        if source.data then
            return mapping.copy(source)
        end
        local copy = {}
        for key, value in pairs(source) do
            copy[key] = value
        end
        return copy
    end
    function self.capture(descriptors)
        if host.prepare then
            assert(host.prepare() ~= false, 'Weapon capture preparation pending')
        end
        local frozen, validate = mapping.freeze(runtime, groups(descriptors))
        assert(#frozen > 0, 'Load weapon LUTs before saving')
        local clone, entries, seen, summary, originals = clones(), {}, {}, { count = 0, provenance_count = 0 }, {}
        for _, group in ipairs(frozen) do
            for _, member in ipairs(group.members) do
                local binding = member.binding
                local document = binding.document or group.group.applied_document or group.source_document
                local saved, signature = clone(document)
                assert(saved.width == group.width and saved.height == group.height, 'Current weapon LUT shape changed')
                local key = (group.family == 'pattern' and 'p:' or '') .. binding.save_key
                local prior = seen[key]
                assert(
                    not prior or prior.signature == signature and prior.weapon_resource == group.weapon_resource,
                    'Conflicting weapon preset destination'
                )
                if not prior then
                    local source = original(group, binding)
                    originals[source] = originals[source] or source_copy(source)
                    source = originals[source]
                    local refs
                    if host.provenance and source.resource and source.patch_source then
                        local ok, value, reason = pcall(host.provenance, binding, {
                            kind = 'weapon',
                            key = key,
                            original = source,
                            weapon_resource = group.weapon_resource,
                            weapon_slot = group.weapon_slot,
                        })
                        if ok and value then
                            local module = assert(modules.binding_provenance, 'Weapon provenance validator unavailable')
                            refs = module.validate(value, 'weapon', key, source)
                            assert(
                                refs.version == 4
                                    and refs.weapon_resource == group.weapon_resource
                                    and refs.weapon_slot == group.weapon_slot,
                                'Weapon assignment proof differs from captured target'
                            )
                            summary.provenance_count = summary.provenance_count + 1
                        else
                            summary.provenance_error = summary.provenance_error or tostring(ok and reason or value)
                        end
                    end
                    entries[#entries + 1] = {
                        kind = 'weapon',
                        key = key,
                        weapon_slot = group.weapon_slot,
                        weapon_resource = group.weapon_resource,
                        document = saved,
                        original = source,
                        binding_provenance = refs,
                    }
                    assert(#entries <= W.MAX_BINDINGS, 'Weapon preset binding budget exceeded')
                    seen[key] = { signature = signature, weapon_resource = group.weapon_resource }
                end
            end
        end
        validate()
        summary.count = #entries
        return entries, summary
    end
    function self.save(name, descriptors)
        assert(
            host.outfits
                and type(host.outfits.save) == 'function'
                and type(host.outfits.load) == 'function'
                and type(host.invalidate) == 'function',
            'Weapon preset persistence/cache operations unavailable'
        )
        local entries, summary = self.capture(descriptors)
        assert(host.outfits.save(name, entries) ~= false, 'Weapon preset was not saved')
        host.invalidate(name)
        return host.outfits.load(name), summary
    end
    function self.plan(preset, descriptors)
        assert(
            type(preset) == 'table' and type(preset.entries) == 'table' and #preset.entries <= W.MAX_BINDINGS,
            'Choose a valid saved weapon preset'
        )
        local frozen, validate_targets = mapping.freeze(runtime, groups(descriptors))
        local live_ids, live, garments, entries, copies, entry_receipts = {}, {}, {}, {}, clones(), {}
        for _, group in ipairs(frozen) do
            assert(
                not live_ids[group.weapon_slot] or live_ids[group.weapon_slot] == group.weapon_resource,
                'Current weapon configuration changed'
            )
            live_ids[group.weapon_slot] = group.weapon_resource
            for _, member in ipairs(group.members) do
                live[#live + 1] = {
                    kind = 'weapon',
                    binding = member.binding,
                    pattern = group.family == 'pattern',
                    original = original(group, member.binding),
                }
            end
        end
        local weapon_entries = 0
        for _, entry in ipairs(preset.entries) do
            assert(type(entry) == 'table', 'Invalid preset entry')
            local copy = {}
            for key, value in pairs(entry) do
                copy[key] = value
            end
            copy.document = copies(entry.document)
            copy.original = entry.original and source_copy(entry.original) or nil
            entries[#entries + 1] = copy
            entry_receipts[#entry_receipts + 1] = {
                entry = entry,
                document = entry.document,
                bytes = mapping.bytes(entry.document),
                kind = entry.kind,
                key = entry.key,
                weapon_slot = entry.weapon_slot,
                weapon_resource = entry.weapon_resource,
                original = entry.original,
                original_resource = entry.original and entry.original.resource,
                original_width = entry.original and entry.original.width,
                original_height = entry.original and entry.original.height,
                patch_source = entry.original and entry.original.patch_source,
            }
            if entry.kind == 'weapon' then
                weapon_entries = weapon_entries + 1
                assert(
                    type(entry.weapon_resource) == 'string'
                        and live_ids[entry.weapon_slot] == entry.weapon_resource:lower(),
                    'Saved weapon configuration differs from current weapon; load the intended weapon first'
                )
            else
                garments[#garments + 1] = copy
            end
        end
        assert(weapon_entries > 0, 'This preset contains no weapon LUTs')
        local resolver = targets.new({ entries = entries }, {
            document_bytes = function(document)
                return modules.dds.encode(document.data, document.width, document.height)
            end,
        })
        resolver.prepare(live)
        local plans = {}
        for _, group in ipairs(frozen) do
            local variants = {}
            for _, member in ipairs(group.members) do
                local document, why = resolver.resolve(
                    'weapon',
                    member.binding,
                    group.family == 'pattern',
                    original(group, member.binding)
                )
                assert(
                    document,
                    'No exact/certified saved weapon LUT for ' .. member.binding.save_key .. ': ' .. tostring(why)
                )
                assert(
                    document.width == group.width and document.height == group.height,
                    'Saved weapon LUT dimensions differ'
                )
                local bytes = mapping.bytes(document)
                local plan = variants[bytes]
                if not plan then
                    plan = {
                        weapon_slot = group.weapon_slot,
                        weapon_resource = group.weapon_resource,
                        family = group.family,
                        index = group.index,
                        source_resource = group.source_resource,
                        document = mapping.copy(document),
                        targets = {},
                    }
                    variants[bytes], plans[#plans + 1] = plan, plan
                end
                plan.targets[#plan.targets + 1] = member.binding
            end
        end
        assert(#plans > 0, 'No saved weapon destinations match current weapons')
        local context = { garment_entries = garments, weapon_resources = resolver.weapon_resources }
        function context.validate()
            validate_targets()
            assert(#preset.entries == #entry_receipts, 'Saved preset entries changed during apply')
            for index, receipt in ipairs(entry_receipts) do
                local entry = preset.entries[index]
                assert(
                    entry == receipt.entry
                        and entry.document == receipt.document
                        and mapping.bytes(entry.document) == receipt.bytes
                        and entry.kind == receipt.kind
                        and entry.key == receipt.key
                        and entry.weapon_slot == receipt.weapon_slot
                        and entry.weapon_resource == receipt.weapon_resource
                        and entry.original == receipt.original
                        and (
                            not entry.original
                            or entry.original.resource == receipt.original_resource
                                and entry.original.width == receipt.original_width
                                and entry.original.height == receipt.original_height
                                and entry.original.patch_source == receipt.patch_source
                        ),
                    'Saved preset bytes/identity changed during apply'
                )
            end
            return true
        end
        context.validate()
        return plans, context
    end
    function self.apply(preset, descriptors)
        assert(runtime.supports_target_subsets == true, 'Weapon runtime exact subset plans unavailable')
        local plans, context = self.plan(preset, descriptors)
        context.validate()
        if #context.garment_entries > 0 then
            assert(
                type(host.apply_mixed_plan) == 'function',
                'Mixed gear/weapon preset transaction coordinator unavailable'
            )
            return host.apply_mixed_plan(plans, context)
        end
        return runtime.apply_plan(plans)
    end
    function self.export(name, preset, format, index, naming)
        assert(host.exporter and type(host.exporter.save) == 'function', 'Weapon preset exporter unavailable')
        assert(type(preset) == 'table' and type(preset.entries) == 'table', 'Choose a saved weapon preset')
        -- The existing exporter validates schema4 identities and retains precise
        -- assignment sidecars; its provenance callback hydrates pristine sources.
        return host.exporter.save(name, preset, format, index, naming)
    end
    return self
end
return W
