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
        lut.choices = modules.preset_export and modules.preset_export.lut_choices(selected)
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
            }
        end
        return entries, matched
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
