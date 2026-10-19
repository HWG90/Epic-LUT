-- Prepare exact current-gear export entries and their optional Pattern companions.
-- The controller owns selection transitions and dialogs; existing exporters own
-- encoding, shared-resource byte deduplication and transactional filesystem IO.
local E = {}
function E.new(modules, host)
    local self = {}
    function self.sync_armory_options()
        local options = host.armory_options()
        if not options then
            return
        end
        local selected = options.selected
        host.sync_armory_cape()
        options.export.disabled = not selected
        local lut = options.lut
        lut.choices = modules.preset_export and modules.preset_export.lut_choices(selected, host.label)
            or { 'Choose a saved preset first' }
        local disabled = not selected or (host.armory_format() ~= 2 and host.armory_format() ~= 4)
        lut.disabled = false
        assert(host.set_armory_lut(math.min(host.armory_lut(), #lut.choices)))
        lut.disabled = disabled
    end
    function self.include_capes()
        local value, exists = host.export_preference('include_capes_in_armor_exports')
        if exists then
            return value ~= false
        end
        local value, exists = host.export_control('include_capes_in_armor_exports')
        return not exists or value ~= false
    end
    function self.include_patterns()
        local value, exists = host.export_preference('include_patterns_in_exports')
        if exists then
            return value ~= false
        end
        local value, exists = host.export_control('include_patterns_in_exports')
        return not exists or value ~= false
    end
    function self.selected_bindings(required)
        local selected = host.selected()
        if not selected and not required then
            return {}
        end
        host.refresh(true)
        local index = selected and host.checked_target(selected) or host.current_lut()
        local group = assert(host.groups()[index], 'Select a Live LUT destination first')
        local targets = {}
        for _, b in ipairs(group.bindings) do
            if
                (not selected or not selected.kind or modules.gear_catalog.kind(b) == selected.kind)
                and (not b.cape or selected and selected.kind == 'cape' or self.include_capes())
            then
                assert(
                    host.present(b) and host.binding(b) == b.current,
                    'Gear changed; load current gear before exporting'
                )
                targets[#targets + 1] = b
            end
        end
        assert(#targets > 0, 'Selected LUT has no live export destination')
        return targets
    end
    function self.original_patch(entry)
        local original = assert(entry.original, 'Original texture metadata unavailable')
        local baseline = original.data and original or host.original_resource(original.resource)
        assert(
            baseline
                and baseline.data
                and baseline.resource == original.resource
                and baseline.width == original.width
                and baseline.height == original.height,
            'Original texture palette is not ready; load current gear before exporting'
        )
        return modules.patch_export.encode(modules.dds, baseline, original)
    end
    function self.pattern_entries(targets, pattern_groups)
        if
            not self.include_patterns()
            or not host.has_patterns()
            or not modules.engine.PATTERN_SLOT
            or #targets == 0
        then
            return {}
        end
        pattern_groups = pattern_groups or host.scan_patterns(true)
        local matched = assert(modules.export_pairing, 'Export pairing unavailable').live(targets, pattern_groups, {
            key = host.material_key,
            kind = modules.gear_catalog.kind,
        })
        local entries, counts = {}, {}
        for _, b in ipairs(matched) do
            assert(
                host.present(b) and host.binding(b) == b.current,
                'Pattern gear changed; load current gear before exporting'
            )
            local original = host.original(b.original)
            local document = original
            if b.current ~= b.original then
                document = host.applied_document(b)
            end
            assert(document, 'Matching Pattern LUT snapshot is not ready; load current patterns before exporting')
            assert(document.width == 3 and document.height == 1, 'Matching Pattern snapshot is not a 3x1 LUT')
            local kind = modules.gear_catalog.kind(b)
            counts[kind] = (counts[kind] or 0) + 1
            entries[#entries + 1] = {
                document = document,
                original = original,
                kind = kind,
                ordinal = counts[kind],
                key = 'p:' .. b.save_key,
                label = host.label and host.label(original and original.resource),
            }
        end
        return entries, matched
    end
    -- Capture the displayed binding receipts once; unchanged menus do no discovery work.
    function self.choose_patches(name)
        assert(host.stop_identification(), 'Highlight restoration pending')
        host.refresh(true)
        local menu = assert(host.menu(), 'Export menu unavailable')
        local rows, columns, counts = {}, { { title = 'Armor / Cape', items = {} }, { title = 'Helmet', items = {} } }, {}
        local selected = host.selected()
        local current = selected and host.checked_target(selected) or host.current_lut()
        for index, group in ipairs(host.groups()) do
            local kinds = {}
            for _, b in ipairs(group.bindings) do
                local kind = modules.gear_catalog.kind(b)
                if not b.cape or self.include_capes() then
                    local row = kinds[kind]
                    if not row then
                        counts[kind] = (counts[kind] or 0) + 1
                        local original = host.original(b.original)
                        local custom = host.label(original and original.resource)
                        local label = custom or (kind:gsub('^%l', string.upper) .. ' LUT ' .. counts[kind])
                        row = { id = #rows + 1, label = label, checked = index == current,
                            bindings = {}, index = index, kind = kind, custom_name = custom }
                        rows[#rows + 1], kinds[kind] = row, row
                        local column = columns[kind == 'helmet' and 2 or 1]
                        column.items[#column.items + 1] = row
                    end
                    row.bindings[#row.bindings + 1] = { binding = b, current = b.current, original = b.original }
                end
            end
        end
        assert(#rows > 0, 'Load current gear before choosing LUT patches')
        local dialog = { title = 'Export LUT Patches', action_label = 'Export', columns = columns,
            hint = 'Choose LUTs to export. Matching Patterns follow your export settings.',
            allow_combine = true, combine = true }
        dialog.on_apply = function(mask)
            assert(menu.lut_apply_dialog == dialog, 'Export selection changed; reopen the chooser')
            assert(host.stop_identification(), 'Highlight restoration pending')
            local batches, combined = {}, {}
            local pattern_groups = self.include_patterns() and host.has_patterns() and modules.engine.PATTERN_SLOT
                and host.scan_patterns(true) or nil
            -- Validate every selection before starting filesystem writes.
            for _, row in ipairs(rows) do
                if mask[row.id] then
                    local entries, targets = {}, {}
                    for _, receipt in ipairs(row.bindings) do
                        local b = receipt.binding
                        assert(b.current == receipt.current and b.original == receipt.original
                            and host.present(b) and host.binding(b) == receipt.current,
                            'Gear changed; reopen the export chooser')
                        local original = assert(host.original(b.original), 'Original LUT snapshot is not ready')
                        local document = b.current ~= b.original and host.applied_document(b) or original
                        document = host.draft(row.index, row.kind) or document
                        assert(document, 'LUT data is not ready')
                        entries[#entries + 1] = { document = document, original = original,
                            kind = row.kind, key = b.save_key }
                        targets[#targets + 1] = b
                    end
                    for _, entry in ipairs(self.pattern_entries(targets, pattern_groups)) do
                        entries[#entries + 1] = entry
                    end
                    local filename = row.custom_name or (name:sub(1, math.max(1, 47 - #row.label)) .. ' ' .. row.label)
                    batches[#batches + 1] = { name = filename, entries = entries }
                    for _, entry in ipairs(entries) do combined[#combined + 1] = entry end
                end
            end
            assert(#batches > 0, 'Choose at least one LUT')
            if dialog.combine then
                local output, count, zip = host.write_patch(name, combined)
                return true, 'Exported ' .. count .. ' LUTs to ' .. (zip or output)
            end
            -- The assignment-aware writer owns each independently published patch.
            for _, batch in ipairs(batches) do host.write_patch(batch.name, batch.entries) end
            return true, 'Exported ' .. #batches .. ' separate LUT patches'
        end
        menu.lut_apply_dialog = dialog
        return true
    end
    function self.custom_dds(name, naming)
        assert(host.stop_identification(), 'Highlight restoration pending')
        host.refresh(true)
        local entries, material_targets = {}, {}
        local function collect(collection, companion_targets)
            local counts = { armor = 0, helmet = 0, cape = 0 }
            for _, group in ipairs(collection) do
                local ordinals = {}
                for _, b in ipairs(group.bindings) do
                    local kind = modules.gear_catalog.kind(b)
                    if (not b.cape or self.include_capes()) and not ordinals[kind] then
                        counts[kind] = counts[kind] + 1
                        ordinals[kind] = counts[kind]
                    end
                    if
                        (not b.cape or self.include_capes())
                        and (
                            b.current ~= b.original
                            or companion_targets and companion_targets[kind .. ':' .. host.material_key(b)]
                        )
                    then
                        assert(
                            host.present(b) and host.binding(b) == b.current,
                            'Gear changed; load current gear before exporting'
                        )
                        local original = host.original(b.original)
                        local document = original
                        if b.current ~= b.original then
                            document = host.applied_document(b)
                        end
                        assert(document, 'LUT data is unavailable; load current patterns before exporting')
                        entries[#entries + 1] = {
                            document = document,
                            original = original,
                            kind = kind,
                            ordinal = ordinals[kind],
                            label = host.label(original and original.resource),
                        }
                        if not companion_targets then
                            material_targets[#material_targets + 1] = b
                        end
                    end
                end
            end
        end
        collect(host.groups())
        if host.has_patterns() and self.include_patterns() then
            local pattern_groups = host.scan_patterns(true)
            local _, matched = self.pattern_entries(material_targets, pattern_groups)
            local companions = {}
            for _, b in ipairs(matched or {}) do
                companions[modules.gear_catalog.kind(b) .. ':' .. host.material_key(b)] = true
            end
            collect(pattern_groups, companions)
        end
        assert(#entries > 0, 'No custom LUTs available for the selected export settings')
        return modules.bulk_dds_export
            .new({
                lut_files = modules.lut_files,
                dds = modules.dds,
                resource_ids = modules.resource_ids,
                file_io = modules.file_io,
            }, host.paths)
            .save(name, entries, naming)
    end
    return self
end
return E
