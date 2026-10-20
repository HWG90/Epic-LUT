-- Capture the current assigned palettes for a named Armory preset.
-- Entries borrow certified session buffers; persistence must consume them before
-- controller cleanup. Destination keys and differing shared-resource values stay
-- intact, and optional provenance never prevents an ordinary palette save.
local buffers = m and m.float_buffer or require('src.core.float_buffer')
local C = {}
function C.new(modules, host)
    local self = {}
    function self.capture(save_kind)
        local explicit = type(save_kind) == 'table'
        local scope = {}
        if explicit then
            for kind, checked in pairs(save_kind) do
                assert(kind == 'armor' or kind == 'helmet' or kind == 'cape', 'Unknown Armory save target')
                assert(type(checked) == 'boolean', 'Armory save targets must be checked or unchecked')
            end
            for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
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
        assert(scope.armor or scope.helmet or scope.cape, 'Check at least one gear type to save')
        local labels = {}
        for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
            if scope[kind] then
                labels[#labels + 1] = modules.gear_catalog.label(kind)
            end
        end
        local scope_label = table.concat(labels, ' + ')
        assert(host.stop_identification(), 'Highlight restoration pending')
        assert(host.stop_pattern_flash(), 'Pattern highlight restoration pending')
        host.refresh(true)
        local entries, seen = {}, {}
        local counts = { armor = 0, helmet = 0, cape = 0 }
        local material_counts = { armor = 0, helmet = 0, cape = 0 }
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
                    .. ' total='
                    .. #entries
            )
        end
        return entries,
            scope_label,
            {
                available = not not resolver,
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
            d.saved_pixels = buffers.bytes(d.data, d.width * d.height * 4)
        end
    end
    return self
end
return C
