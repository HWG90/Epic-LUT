-- Capture the current assigned palettes for a named Armory preset.
-- Entries borrow certified session buffers; persistence must consume them before
-- controller cleanup. Destination keys and differing shared-resource values stay
-- intact, and optional provenance never prevents an ordinary palette save.
local ffi = require('ffi')
local C = {
    save_options = {
        { kind = 'armor', label = 'Armor', default = true },
        { kind = 'helmet', label = 'Helmet', default = true },
        { kind = 'cape', label = 'Cape', default = true },
        { kind = 'weapon', label = 'Weapons', default = false, slots = { 'Primary', 'Secondary', 'Support' } },
    },
}
function C.new(modules, host)
    local self = {}
    function self.capture(save_kind)
        local explicit = type(save_kind) == 'table'
        local scope, weapon_slots = {}, nil
        if explicit then
            for kind, checked in pairs(save_kind) do
                assert(
                    kind == 'armor' or kind == 'helmet' or kind == 'cape' or kind == 'weapon' or kind == 'weapon_slots',
                    'Unknown Armory save target'
                )
                if kind == 'weapon_slots' then
                    assert(type(checked) == 'table', 'Weapon save slots must be a table')
                    weapon_slots = {}
                    for slot, selected in pairs(checked) do
                        assert(
                            type(slot) == 'number'
                                and slot % 1 == 0
                                and slot >= 1
                                and slot <= 3
                                and type(selected) == 'boolean',
                            'Invalid weapon save slot'
                        )
                        weapon_slots[slot] = selected
                    end
                else
                    assert(type(checked) == 'boolean', 'Armory save targets must be checked or unchecked')
                end
            end
            for _, kind in ipairs({ 'armor', 'helmet', 'cape', 'weapon' }) do
                scope[kind] = save_kind[kind] == true
            end
        else
            assert(
                save_kind == nil or save_kind == 'armor' or save_kind == 'helmet' or save_kind == 'both',
                'Choose Armor, Helmet or Cape to save'
            )
            -- Historical programmatic Armor saves include capes. The explicit
            -- UI mask selects all three families independently.
            scope.armor = save_kind ~= 'helmet'
            scope.helmet = save_kind ~= 'armor'
            scope.cape = save_kind ~= 'helmet'
        end
        assert(scope.armor or scope.helmet or scope.cape or scope.weapon, 'Check at least one gear type to save')
        local labels = {}
        for _, kind in ipairs({ 'armor', 'helmet', 'cape', 'weapon' }) do
            if scope[kind] then
                labels[#labels + 1] = kind == 'weapon' and 'Weapons' or modules.gear_catalog.label(kind)
            end
        end
        local scope_label = table.concat(labels, ' + ')
        assert(host.stop_identification(), 'Highlight restoration pending')
        assert(host.stop_pattern_flash(), 'Pattern highlight restoration pending')
        host.refresh(true)
        local entries, seen = {}, {}
        local counts = { armor = 0, helmet = 0, cape = 0, weapon = 0 }
        local material_counts = { armor = 0, helmet = 0, cape = 0, weapon = 0 }
        local resolver = host.ensure_provenance()
        if resolver and host.provenance_state() == 'ready' then
            host.validate_provenance_scope()
        end
        local provenance_count, provenance_error = 0, nil
        local function collect(targets, pattern)
            for _, group in ipairs(targets) do
                for _, b in ipairs(group.bindings) do
                    local kind = modules.gear_catalog.kind(b)
                    local saved_key = (pattern and 'p:' or '') .. b.save_key
                    local key = kind .. ':' .. saved_key
                    if not seen[key] and scope[kind] then
                        local original = host.original(b.original)
                        local source = host.applied_document(b) or original
                        if not pattern or (source and source.width == 3 and source.height == 1) then
                            assert(source, 'Current ' .. kind .. ' LUT unavailable; load current gear before saving')
                            local provenance
                            if
                                resolver
                                and original
                                and original.patch_source
                                and host.provenance_state() == 'ready'
                            then
                                local ok, _, refs =
                                    pcall(resolver.capture, b, { kind = kind, key = saved_key, original = original })
                                if ok then
                                    provenance = refs
                                    provenance_count = provenance_count + 1
                                else
                                    provenance_error = provenance_error or tostring(_)
                                end
                            end
                            entries[#entries + 1] = {
                                kind = kind,
                                key = saved_key,
                                document = source,
                                original = original,
                                binding_provenance = provenance,
                            }
                            counts[kind] = counts[kind] + 1
                            if not pattern then
                                material_counts[kind] = material_counts[kind] + 1
                            end
                            seen[key] = true
                        end
                    end
                end
            end
        end
        collect(host.groups(), false)
        local pattern_groups = host.current_patterns()
        if pattern_groups then
            collect(pattern_groups, true)
        end
        if scope.weapon then
            assert(
                type(host.weapon_groups) == 'function'
                    and type(host.weapon_original) == 'function'
                    and type(host.weapon_applied_document) == 'function'
                    and type(host.weapon_proof) == 'function',
                'Weapon capture host unavailable'
            )
            local groups = host.weapon_groups()
            assert(type(groups) == 'table' and #groups <= 192, 'Weapon capture group bounds changed')
            local resources, slot_counts = {}, {}
            for _, group in ipairs(groups) do
                local pattern = group.family == 'pattern' or group.pattern == true
                assert(
                    type(group.bindings) == 'table' and #group.bindings <= 512,
                    'Weapon capture binding bounds changed'
                )
                for _, b in ipairs(group.bindings) do
                    local slot, mesh, material = tostring(b.save_key):match('^3:(%d+):(%d+):(%d+)$')
                    slot, mesh, material = tonumber(slot), tonumber(mesh), tonumber(material)
                    assert(
                        b.kind == 'weapon'
                            and slot
                            and slot >= 1
                            and slot <= 3
                            and b.weapon_slot == slot
                            and mesh <= 63
                            and material <= 63,
                        'Invalid weapon capture destination'
                    )
                    local resource = b.weapon_resource
                    assert(
                        type(resource) == 'string'
                            and #resource == 16
                            and resource:match('^%x+$')
                            and resource ~= string.rep('0', 16),
                        'Weapon resource identity unavailable'
                    )
                    assert(
                        not resources[slot] or resources[slot] == resource:lower(),
                        'Conflicting equipped weapon identities'
                    )
                    resources[slot] = resource:lower()
                    if not weapon_slots or weapon_slots[slot] == true then
                        local key = (pattern and 'p:' or '') .. b.save_key
                        local unique = 'weapon:' .. key
                        if not seen[unique] then
                            local receipt = {
                                unit = b.unit,
                                mesh = b.mesh,
                                material = b.material,
                                original = b.original,
                                current = b.current,
                                save_key = b.save_key,
                            }
                            local proof = assert(host.weapon_proof(b), 'Current weapon identity unavailable')
                            assert(
                                proof.weapon_slot == slot
                                    and proof.weapon_resource
                                    and proof.weapon_resource:lower() == resource:lower(),
                                'Current weapon identity differs from save target'
                            )
                            if proof.validate then
                                assert(proof.validate() == true, 'Current weapon proof is stale')
                            end
                            local original = host.weapon_original(b)
                            local source = host.weapon_applied_document(b) or original
                            assert(
                                source
                                    and source.data
                                    and (
                                        pattern and source.width == 3 and source.height == 1
                                        or not pattern
                                            and source.width == 23
                                            and source.height >= 1
                                            and source.height <= 64
                                            and source.height % 1 == 0
                                    ),
                                'Current weapon LUT unavailable or unsupported'
                            )
                            local provenance
                            if host.capture_weapon_provenance and original then
                                local ok, refs = pcall(host.capture_weapon_provenance, b, {
                                    kind = 'weapon',
                                    key = key,
                                    original = original,
                                    weapon_slot = slot,
                                    weapon_resource = resource:lower(),
                                })
                                if ok then
                                    provenance = refs
                                    if refs then
                                        provenance_count = provenance_count + 1
                                    end
                                else
                                    provenance_error = provenance_error or tostring(refs)
                                end
                            end
                            local after = assert(host.weapon_proof(b), 'Weapon changed during preset capture')
                            assert(
                                b.unit == receipt.unit
                                    and b.mesh == receipt.mesh
                                    and b.material == receipt.material
                                    and b.original == receipt.original
                                    and b.current == receipt.current
                                    and b.save_key == receipt.save_key
                                    and b.weapon_slot == slot
                                    and b.weapon_resource:lower() == resource:lower(),
                                'Weapon binding changed during preset capture'
                            )
                            assert(
                                after.weapon_slot == slot
                                    and after.weapon_resource
                                    and after.weapon_resource:lower() == resource:lower(),
                                'Weapon changed during preset capture'
                            )
                            if after.validate then
                                assert(after.validate() == true, 'Weapon changed during preset capture')
                            end
                            entries[#entries + 1] = {
                                kind = 'weapon',
                                key = key,
                                document = source,
                                original = original,
                                weapon_slot = slot,
                                weapon_resource = resource:lower(),
                                binding_provenance = provenance,
                            }
                            seen[unique], counts.weapon = true, counts.weapon + 1
                            if not pattern then
                                material_counts.weapon = material_counts.weapon + 1
                                slot_counts[slot] = (slot_counts[slot] or 0) + 1
                            end
                        end
                    end
                end
            end
            assert(
                material_counts.weapon > 0,
                'Current weapon material LUTs are unavailable or still loading. Load Current Weapons, then try saving again.'
            )
            if weapon_slots then
                for slot, selected in pairs(weapon_slots) do
                    assert(
                        not selected or (slot_counts[slot] or 0) > 0,
                        'Selected weapon slot is unavailable or still loading: ' .. slot
                    )
                end
            end
        end
        if explicit then
            for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
                assert(
                    not scope[kind] or material_counts[kind] > 0,
                    'Current '
                        .. modules.gear_catalog.label(kind)
                        .. ' material LUTs are unavailable or still loading. Load Current Gear, then try saving again.'
                )
            end
        else
            assert(
                not scope.armor or counts.armor + counts.cape > 0,
                'Current Armor/Cape LUTs are unavailable or still loading. Load Current Gear, then try saving again.'
            )
            assert(
                not scope.helmet or counts.helmet > 0,
                'Current Helmet LUTs are unavailable or still loading. Load Current Gear, then try saving again.'
            )
        end
        if host.log then
            host.log(
                'ARMORY_SAVE scope='
                    .. scope_label
                    .. ' armor='
                    .. counts.armor
                    .. ' cape='
                    .. counts.cape
                    .. ' helmet='
                    .. counts.helmet
                    .. (scope.weapon and (' weapons=' .. counts.weapon) or '')
                    .. ' total='
                    .. #entries
            )
        end
        return entries,
            scope_label,
            {
                available = not not (resolver or scope.weapon and type(host.capture_weapon_provenance) == 'function'),
                count = provenance_count,
                error = provenance_error,
            }
    end
    function self.report_saved(summary, total)
        if summary.available and host.log then
            host.log(
                'ARMORY_PROVENANCE captured='
                    .. summary.count
                    .. ' total='
                    .. total
                    .. ' cache='
                    .. host.provenance_state()
                    .. (summary.error and ' reason=' .. summary.error:sub(1, 512) or '')
            )
        end
    end
    function self.mark_saved(entries)
        for _, entry in ipairs(entries) do
            local d = entry.document
            d.saved_pixels = ffi.string(d.data, d.width * d.height * 16)
        end
    end
    return self
end
return C
