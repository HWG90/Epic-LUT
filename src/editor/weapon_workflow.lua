-- UI orchestration for immutable import/preset plans. Native writes stay in the runtime.
local W = {}
local labels = { 'Primary', 'Secondary', 'Support' }
function W.new(m, host)
    local self, mapper, storage = {}, nil, nil
    local function bridge()
        return host.bridge()
    end
    local function presets()
        if not storage then
            storage = m.weapon_presets.new(m, {
                runtime = bridge().runtime(),
                groups = function()
                    return bridge().descriptors()
                end,
                original = host.original,
                provenance = host.provenance,
                outfits = host.outfits(),
                invalidate = host.invalidate,
            })
        end
        return storage
    end
    function self.map(targets, options)
        local descriptors = bridge().descriptors(targets)
        if host.prepare_imports and host.prepare_imports(descriptors, options) == false then
            return false
        end
        if not mapper then
            mapper = m.weapon_mapping.new({
                runtime = bridge().runtime(),
                menu = host.menu,
                imports = host.imports,
                message = host.message,
                mutate = host.mutate,
            })
        end
        return mapper.open(descriptors, options)
    end
    function self.map_prepared(descriptors, options)
        if not mapper then
            mapper = m.weapon_mapping.new({
                runtime = bridge().runtime(),
                menu = host.menu,
                imports = host.imports,
                message = host.message,
                mutate = host.mutate,
            })
        end
        return mapper.open(descriptors, options)
    end
    function self.map_preset(targets, preset)
        assert(
            preset and type(preset.entries) == 'table' and #preset.entries > 0 and #preset.entries <= 4096,
            'Choose an existing Armory preset first'
        )
        local paths, documents, resources, seen = {}, {}, {}, {}
        for index, entry in ipairs(preset.entries) do
            local document = m.weapon_mapping.copy(entry.document)
            local signature = document.width .. ':' .. document.height .. ':' .. m.weapon_mapping.bytes(document)
            if not seen[signature] then
                local path = (preset.name or 'Preset')
                    .. '/'
                    .. (document.width == 3 and 'PatternLUT' or 'LUT')
                    .. string.format('%03d', index - 1)
                    .. '.dds'
                paths[#paths + 1], documents[path], resources[path], seen[signature] =
                    path, document, entry.original and entry.original.resource, true
            end
        end
        local mapping = m.weapon_mapping.new({
            runtime = bridge().runtime(),
            menu = host.menu,
            message = host.message,
            mutate = host.mutate,
            imports = {
                palettes = function()
                    return paths
                end,
                document = function(path)
                    return documents[path]
                end,
                resource = function(path)
                    return resources[path]
                end,
                pending = function()
                    return false
                end,
                indexing = function()
                    return false
                end,
            },
        })
        return mapping.open(bridge().descriptors(targets), { auto = true, rollover = true })
    end
    function self.save(targets)
        local descriptors = bridge().descriptors(targets)
        local _, validate = m.weapon_mapping.freeze(bridge().runtime(), descriptors)
        local mask = { weapon = true, weapon_slots = {} }
        for _, descriptor in ipairs(descriptors) do
            mask.weapon_slots[descriptor.weapon_slot] = true
        end
        local mod, menu = host.mod(), assert(host.menu(), 'Preset dialog unavailable')
        local function save(name, existing)
            validate()
            local _, summary = presets().save(name, descriptors, existing)
            menu.outfit_dialog, menu.text_edit = nil, nil
            local text = 'Saved ' .. name .. ' with ' .. summary.count .. ' weapon LUT bindings.'
            if summary.provenance_incomplete then
                text = text
                    .. ' Patch assignment proof is pending or unavailable; retry Export with these weapons equipped.'
            end
            return host.message(text)
        end
        local function submit(name)
            local existing
            for _, stored_name in ipairs(host.outfits().names()) do
                if stored_name:lower() == name:lower() then
                    name, existing = stored_name, host.outfits().load(stored_name)
                    break
                end
            end
            if existing then
                local collision = false
                for _, entry in ipairs(existing.entries) do
                    if entry.kind == 'weapon' then
                        for _, descriptor in ipairs(descriptors) do
                            collision = collision
                                or (
                                    entry.weapon_resource:lower() == descriptor.weapon_resource:lower()
                                    and entry.weapon_slot == descriptor.weapon_slot
                                )
                        end
                    end
                end
                if collision then
                    menu.text_edit = nil
                    menu.outfit_dialog = {
                        phase = 'confirm',
                        title = 'Update Weapon Preset',
                        preset_name = name,
                        description = 'Replace this weapon in ' .. name .. '? Other saved gear is kept.',
                        on_confirm = function()
                            return save(name, existing)
                        end,
                    }
                    return false
                end
            end
            return save(name, existing)
        end
        local selected = host.selected_preset and host.selected_preset()
        if selected then
            return submit(selected.name)
        end
        menu.outfit_dialog = {
            phase = 'name',
            save_kind = mask,
            mod = mod,
            control = mod.controls.outfit_name,
            names = host.outfits().names(),
            on_save = submit,
        }
        menu.text_edit = { mod = mod, control = mod.controls.outfit_name, text = '', replace = true }
        return true
    end
    local export_job, export_elapsed
    local function finish_export(job)
        local ok, output, description, archive =
            pcall(job.exporter.save, job.name, job.preset, job.format, job.lut or 1, job.naming)
        if not ok then
            if host.export_pending and host.export_pending(output) then
                return false
            end
            error(output, 0)
        end
        export_job = nil
        return true,
            host.message(
                'Exported ' .. (job.label or 'weapons') .. ' (' .. description .. ') to ' .. (archive or output)
            )
    end
    function self.tick(dt)
        if not export_job then
            return
        end
        local elapsed = math.max(0, dt or 0)
        export_job.age = (export_job.age or 0) + elapsed
        if export_job.age > 120 then
            export_job = nil
            return host.message('Export timed out while waiting for source verification; saved preset retained.')
        end
        export_elapsed = (export_elapsed or 0) + elapsed
        if export_elapsed < 0.25 then
            return
        end
        export_elapsed = 0
        local ok, why = pcall(finish_export, export_job)
        if not ok then
            export_job = nil
            host.message('Weapon export stopped: ' .. tostring(why))
        end
    end
    function self.export_saved(preset, name, format, lut, naming, factory)
        assert(not export_job, 'An export is already being prepared')
        assert(
            type(preset.entries) == 'table' and #preset.entries > 0 and #preset.entries <= 4096,
            'Invalid export preset'
        )
        local memo, total = {}, 0
        local function freeze(value)
            if type(value) ~= 'table' then
                return value
            end
            if memo[value] then
                return memo[value]
            end
            local result = {}
            memo[value] = result
            if value.data and value.width and value.height then
                local copied = m.weapon_mapping.copy(value)
                total = total + value.width * value.height * 16
                assert(total <= 8 * 1024 * 1024, 'Queued preset export exceeds pixel budget')
                result.data = copied.data
            end
            for key, item in pairs(value) do
                if key ~= 'data' or result.data == nil then
                    result[key] = freeze(item)
                end
            end
            return result
        end
        local snapshot = freeze(preset)
        export_job = {
            preset = snapshot,
            name = name,
            format = format,
            lut = lut,
            naming = naming,
            label = snapshot.name or 'preset',
            exporter = (factory or host.exporter)(snapshot),
        }
        export_elapsed = 0
        local ok, done, result = pcall(finish_export, export_job)
        if not ok then
            export_job = nil
            error(done, 0)
        end
        if not done then
            return host.message('Preparing preset export; it will finish automatically when source checks are ready.')
        end
        return result
    end
    function self.export(targets)
        assert(not export_job, 'A weapon export is already being prepared')
        local entries = presets().capture(bridge().descriptors(targets))
        local name, format, naming = host.export_options()
        local preset = { name = name, entries = entries }
        export_job =
            { name = name, format = format, naming = naming, preset = preset, exporter = host.exporter(preset) }
        export_elapsed = 0
        local ok, done, result = pcall(finish_export, export_job)
        if not ok then
            export_job = nil
            error(done, 0)
        end
        if not done then
            return host.message('Preparing weapon export; it will finish automatically when source checks are ready.')
        end
        return result
    end
    local function export_editor_now(target, document, name, entire)
        bridge().check(target)
        local descriptors, selected_keys, chosen = bridge().descriptors(), {}, {}
        for _, binding in ipairs(target.bindings or { target }) do
            selected_keys[binding.save_key] = true
        end
        for _, descriptor in ipairs(descriptors) do
            if descriptor.weapon_slot == target.weapon_slot then
                local direct = descriptor.index == target.group_index
                    and descriptor.family == (target.family == 'pattern' and 'pattern' or 'material')
                local companion = false
                if target.family ~= 'pattern' and descriptor.family == 'pattern' then
                    for _, binding in ipairs(descriptor.bindings) do
                        companion = companion or selected_keys[binding.save_key]
                    end
                end
                if entire then
                    chosen[#chosen + 1] = descriptor
                elseif direct or companion then
                    -- Narrow before capture, not after: unrelated mixed Pattern
                    -- members must not block or inflate a selected-LUT export.
                    local subset = {}
                    for key, value in pairs(descriptor) do
                        subset[key] = value
                    end
                    subset.bindings = {}
                    for _, binding in ipairs(descriptor.bindings) do
                        if selected_keys[binding.save_key] then
                            subset.bindings[#subset.bindings + 1] = binding
                        end
                    end
                    if #subset.bindings > 0 then
                        chosen[#chosen + 1] = subset
                    end
                end
            end
        end
        local captured, entries = presets().capture(chosen), {}
        for _, entry in ipairs(captured) do
            local key, pattern = entry.key:gsub('^p:', ''), entry.key:sub(1, 2) == 'p:'
            if entire or selected_keys[key] then
                if selected_keys[key] and pattern == (target.family == 'pattern') then
                    assert(
                        document.width == entry.document.width and document.height == entry.document.height,
                        'Edited weapon LUT dimensions differ from destination'
                    )
                    entry.document = m.weapon_mapping.copy(document)
                end
                entries[#entries + 1] = entry
            end
        end
        local preset = { name = name, entries = entries }
        local output, description, archive = host.exporter(preset).save(name, preset, entire and 3 or 2, 1, 1)
        return host.message('Exported weapon (' .. description .. ') to ' .. (archive or output))
    end
    local editor_export
    function self.export_editor(target, document, name, entire)
        assert(not editor_export and not export_job, 'An export is already being prepared')
        bridge().check(target)
        local frozen = m.weapon_mapping.copy(document)
        local receipts = {}
        for _, descriptor in ipairs(bridge().descriptors()) do
            if descriptor.weapon_slot == target.weapon_slot then
                for _, b in ipairs(descriptor.bindings) do
                    receipts[#receipts + 1] = { binding = b, current = b.current, original = b.original,
                        unit = b.unit, material = b.material }
                end
            end
        end
        local job = { attempts = 0 }
        editor_export = job
        local function run()
            assert(editor_export == job, 'Weapon export was cancelled')
            bridge().check(target)
            for _, proof in ipairs(receipts) do
                local b = proof.binding
                assert(b.current == proof.current and b.original == proof.original
                    and b.unit == proof.unit and b.material == proof.material,
                    'Weapon changed while preparing export; export cancelled')
            end
            local ok, result = pcall(export_editor_now, target, frozen, name, entire)
            if ok then editor_export = nil; return result end
            if not (host.export_pending and host.export_pending(result) and host.when_sources_ready) then
                editor_export = nil
                error(result, 0)
            end
            job.attempts = job.attempts + 1
            assert(job.attempts <= 8, 'Weapon export source requests did not converge')
            host.when_sources_ready(function(ready, why)
                if editor_export ~= job then return end
                if not ready then
                    editor_export = nil
                    return host.message('Weapon export stopped: ' .. tostring(why))
                end
                local success, problem = pcall(run)
                if not success then
                    editor_export = nil
                    host.message('Weapon export stopped: ' .. tostring(problem))
                end
            end)
            return host.message('Preparing weapon export; it will finish automatically when sources are ready.')
        end
        local ok, result = pcall(run)
        if not ok then editor_export = nil; error(result, 0) end
        return result
    end
    function self.plan(preset, options)
        options = options or {}
        local editor, sources, seen, slots, receipts = bridge(), {}, {}, {}, {}
        for _, entry in ipairs(preset.entries) do
            if entry.kind == 'weapon' then
                local slot = entry.weapon_slot
                assert(slot == 1 or slot == 2 or slot == 3, 'Invalid saved weapon slot')
                local family = entry.key:sub(1, 2) == 'p:' and 'pattern' or 'material'
                sources[slot] = sources[slot] or { material = {}, pattern = {} }
                slots[slot] = entry.weapon_resource
                local bytes = m.weapon_mapping.bytes(entry.document)
                local id = slot
                    .. ':'
                    .. family
                    .. ':'
                    .. tostring(entry.original and entry.original.resource)
                    .. ':'
                    .. bytes
                if not seen[id] then
                    seen[id] = true
                    table.insert(sources[slot][family], m.weapon_mapping.copy(entry.document))
                end
                receipts[#receipts + 1] =
                    { entry = entry, key = entry.key, resource = entry.weapon_resource, bytes = bytes }
            end
        end
        local runtime = editor.runtime()
        if runtime.refresh then
            for slot in pairs(slots) do
                runtime.refresh(slot)
            end
        end
        local descriptors = {}
        for _, descriptor in ipairs(editor.descriptors(nil, slots, true)) do
            local family = descriptor.family == 'main' and 'material' or descriptor.family
            if sources[descriptor.weapon_slot] and #sources[descriptor.weapon_slot][family] > 0 then
                descriptors[#descriptors + 1] = descriptor
            end
        end
        table.sort(descriptors, function(a, b)
            if a.weapon_slot ~= b.weapon_slot then
                return a.weapon_slot < b.weapon_slot
            end
            if a.family ~= b.family then
                return a.family < b.family
            end
            return a.index < b.index
        end)
        local frozen, validate_targets = m.weapon_mapping.freeze(runtime, descriptors, { application_only = true })
        local plan, ordinal, selected_keys = { choices = {}, count = 0 }, {}, {}
        local entries, choices, pattern_keys = {}, {}, {}
        for index, target in ipairs(frozen) do
            local slot, family = target.weapon_slot, target.family
            local key = slot .. ':' .. family
            ordinal[key] = (ordinal[key] or 0) + 1
            local cycle = sources[slot][family]
            local source = cycle[(ordinal[key] - 1) % #cycle + 1]
            local document = m.weapon_mapping.fit(source, target.width, target.height)
            local choice = {
                id = target.id,
                weapon_slot = slot,
                weapon_resource = target.weapon_resource,
                saved_weapon_resource = slots[slot],
                pattern = family == 'pattern',
                enabled = true,
                label = labels[slot] .. (family == 'pattern' and ' Pattern LUT ' or ' LUT ') .. target.index,
                detail = 'Auto-mapped from saved ' .. labels[slot] .. ' LUT ' .. ((ordinal[key] - 1) % #cycle + 1),
            }
            choices[index], plan.choices[index] = choice, choice
            entries[index] = {
                weapon_slot = slot,
                weapon_resource = target.weapon_resource,
                source_resource = target.source_resource,
                family = family,
                index = target.index,
                document = document,
                targets = {},
            }
            for _, member in ipairs(target.members) do
                entries[index].targets[#entries[index].targets + 1] = member.binding
            end
            if family == 'pattern' then
                for _, member in ipairs(target.members) do
                    pattern_keys[slot .. ':' .. member.binding.save_key] = true
                end
            end
            local selected = (not options.slots or options.slots[slot])
                and (not options.selected or options.selected[choice.id] == true)
            choice.selected = selected
            if selected and family == 'material' then
                for _, member in ipairs(target.members) do
                    selected_keys[slot .. ':' .. member.binding.save_key] = true
                end
            end
        end
        local plans = {}
        for index, target in ipairs(frozen) do
            local choice, entry = choices[index], entries[index]
            if choice.pattern and not choice.selected then
                local subset = {}
                for _, member in ipairs(target.members) do
                    if selected_keys[target.weapon_slot .. ':' .. member.binding.save_key] then
                        subset[#subset + 1] = member.binding
                    end
                end
                if #subset > 0 then
                    entry.targets, choice.selected = subset, true
                end
            elseif not choice.pattern then
                for _, member in ipairs(target.members) do
                    if pattern_keys[target.weapon_slot .. ':' .. member.binding.save_key] then
                        choice.has_pattern = true
                    end
                end
            end
            if choice.selected and not options.preview then
                plans[#plans + 1] = entry
                plan.count = plan.count + #entry.targets
            end
        end
        if not options.preview then
            assert(plan.count > 0, 'Choose at least one available weapon LUT')
        end
        function plan.validate()
            validate_targets()
            for _, receipt in ipairs(receipts) do
                assert(
                    receipt.entry.key == receipt.key
                        and receipt.entry.weapon_resource == receipt.resource
                        and m.weapon_mapping.bytes(receipt.entry.document) == receipt.bytes,
                    'Saved weapon preset changed; reopen Apply Preset'
                )
            end
            return true
        end
        function plan.apply()
            plan.validate()
            assert(not options.preview and #plans > 0, 'Choose weapon LUTs before applying')
            local results = runtime.apply_plan(plans)
            if type(results) == 'number' then
                return results
            end
            local count = 0
            for _, result in ipairs(results) do
                count = count + result.count
            end
            return count
        end
        return plan
    end
    return self
end
return W
