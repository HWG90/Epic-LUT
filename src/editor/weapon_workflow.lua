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
            })
        end
        return mapper.open(descriptors, options)
    end
    function self.save(targets)
        local descriptors = bridge().descriptors(targets)
        local _, validate = m.weapon_mapping.freeze(bridge().runtime(), descriptors)
        local mask = { weapon = true, weapon_slots = {} }
        for _, descriptor in ipairs(descriptors) do
            mask.weapon_slots[descriptor.weapon_slot] = true
        end
        local mod, menu = host.mod(), assert(host.menu(), 'Preset dialog unavailable')
        menu.outfit_dialog = {
            phase = 'name',
            save_kind = mask,
            mod = mod,
            control = mod.controls.outfit_name,
            names = host.outfits().names(),
            on_save = function(name)
                validate()
                local _, summary = presets().save(name, descriptors)
                menu.outfit_dialog, menu.text_edit = nil, nil
                return host.message('Saved ' .. name .. ' with ' .. summary.count .. ' weapon LUT bindings.')
            end,
        }
        menu.text_edit = { mod = mod, control = mod.controls.outfit_name, text = '', replace = true }
        return true
    end
    function self.export(targets)
        local entries = presets().capture(bridge().descriptors(targets))
        local name, format, naming = host.export_options()
        local preset = { name = name, entries = entries }
        local output, description, archive = host.exporter(preset).save(name, preset, format, 1, naming)
        return host.message('Exported weapons (' .. description .. ') to ' .. (archive or output))
    end
    function self.export_editor(target, document, name, entire)
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
                if entire or direct or companion then
                    chosen[#chosen + 1] = descriptor
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
    function self.plan(preset, options)
        options = options or {}
        local descriptors, choices, by_id, receipts = bridge().descriptors(), {}, {}, {}
        local _, validate_targets = m.weapon_mapping.freeze(bridge().runtime(), descriptors)
        local live = {}
        for _, descriptor in ipairs(descriptors) do
            for _, binding in ipairs(descriptor.bindings) do
                local key = (descriptor.family == 'pattern' and 'p:' or '') .. binding.save_key
                live[key] = descriptor
            end
        end
        for _, entry in ipairs(preset.entries) do
            if entry.kind == 'weapon' then
                local pattern = entry.key:sub(1, 2) == 'p:'
                local id = 'weapon:'
                    .. entry.weapon_slot
                    .. ':'
                    .. (pattern and 'pattern:' or 'material:')
                    .. (entry.original and entry.original.resource or entry.key)
                local choice = by_id[id]
                if not choice then
                    choice = {
                        id = id,
                        weapon_slot = entry.weapon_slot,
                        weapon_resource = entry.weapon_resource,
                        label = labels[entry.weapon_slot] .. (pattern and ' Pattern LUT ' or ' LUT ') .. (#choices + 1),
                        enabled = true,
                        entries = {},
                        pattern = pattern,
                    }
                    by_id[id], choices[#choices + 1] = choice, choice
                end
                choice.entries[#choice.entries + 1] = entry
                local descriptor = live[entry.key]
                choice.enabled = choice.enabled
                    and descriptor ~= nil
                    and descriptor.weapon_resource == entry.weapon_resource
                receipts[#receipts + 1] = {
                    entry = entry,
                    key = entry.key,
                    resource = entry.weapon_resource,
                    bytes = m.weapon_mapping.bytes(entry.document),
                }
            end
        end
        local chosen, selected_keys = {}, {}
        for _, choice in ipairs(choices) do
            local selected = not options.selected or options.selected[choice.id] == true
            local slot_selected = not options.slots or options.slots[choice.weapon_slot] == true
            if not choice.enabled then
                choice.detail = 'Requires the saved weapon configuration and LUT destinations'
            end
            if selected and slot_selected and not options.preview then
                assert(choice.enabled, 'Saved weapon differs from current slot; choose its matching weapon')
                for _, entry in ipairs(choice.entries) do
                    chosen[entry], selected_keys[entry.key:gsub('^p:', '')] = true, true
                end
            end
        end
        -- A selected material always includes its exact saved Pattern companions.
        for _, choice in ipairs(choices) do
            if choice.pattern then
                for _, entry in ipairs(choice.entries) do
                    if selected_keys[entry.key:gsub('^p:', '')] then
                        chosen[entry] = true
                    end
                end
            else
                for _, entry in ipairs(choice.entries) do
                    if live['p:' .. entry.key] then
                        choice.has_pattern = true
                    end
                end
            end
        end
        local selected_preset = { entries = {} }
        for _, entry in ipairs(preset.entries) do
            if chosen[entry] then
                selected_preset.entries[#selected_preset.entries + 1] = entry
            end
        end
        local plan = { choices = choices, count = #selected_preset.entries }
        local plans, context
        if not options.preview then
            assert(plan.count > 0, 'Choose at least one weapon LUT')
            local selected_descriptors = {}
            for _, descriptor in ipairs(descriptors) do
                local matches = false
                for _, entry in ipairs(selected_preset.entries) do
                    if
                        entry.weapon_slot == descriptor.weapon_slot
                        and entry.weapon_resource == descriptor.weapon_resource
                        and (entry.key:sub(1, 2) == 'p:') == (descriptor.family == 'pattern')
                    then
                        matches = matches or entry.original and entry.original.resource == descriptor.source_resource
                        for _, binding in ipairs(descriptor.bindings) do
                            matches = matches or entry.key:gsub('^p:', '') == binding.save_key
                        end
                    end
                end
                if matches then
                    selected_descriptors[#selected_descriptors + 1] = descriptor
                end
            end
            plans, context = presets().plan(selected_preset, selected_descriptors)
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
            if context then
                context.validate()
            end
            return true
        end
        function plan.apply()
            plan.validate()
            assert(plans, 'Choose weapon LUTs before applying')
            local results = bridge().runtime().apply_plan(plans)
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
