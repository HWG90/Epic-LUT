-- Saved gear application and its per-LUT chooser. The controller owns session
-- mutation; this service owns planning, frozen receipts and stale-target checks.
local buffers = m and m.float_buffer or require('src.core.float_buffer')
local A = {}
function A.new(modules, host)
    local function apply_outfit(kind, selection)
        local selected_outfit = assert(host.selected(), 'Choose an outfit preset first')
        local combined = type(kind) == 'table'
        local scope, names = {}, {}
        for _, family in ipairs({ 'armor', 'helmet', 'cape' }) do
            local wanted = combined and kind[family] == true or not combined and kind == family
            if wanted then
                local available = not combined
                    or family == 'cape' and host.cape_available(selected_outfit)
                    or family ~= 'cape' and #(selected_outfit[family] or {}) > 0
                if available then
                    scope[family] = true
                    names[#names + 1] = modules.gear_catalog.label(family)
                end
            end
        end
        assert(next(scope), 'Check at least one available gear type to apply')
        local scope_label = table.concat(names, ' + ')
        assert(host.stop_identification(), 'Highlight restoration pending')
        if host.has_patterns() then
            assert(host.stop_patterns(), 'Pattern highlight restoration pending')
        end
        if scope.cape then
            for _, session in ipairs({ host.material_session(), host.pattern_session() or {} }) do
                for _, b in ipairs(session.owned or {}) do
                    assert(
                        not b.cape or not host.present(b) or host.binding(b) == b.current,
                        'Cape binding changed; load current gear again'
                    )
                end
            end
        end
        host.refresh()
        if host.has_patterns() then
            host.scan_patterns()
        end
        if selection then
            selection.validate(true)
        end
        local exact = host.documents(selected_outfit)
        local has_saved = {}
        for _, entry in ipairs(selected_outfit.entries) do
            if scope[entry.kind] then
                has_saved[entry.kind] = true
            end
            if scope.cape and entry.kind == 'armor' then
                has_saved.cape = true
            end
        end
        for family in pairs(scope) do
            assert(has_saved[family], 'This preset has no ' .. family .. ' palette')
        end
        local batches, skipped, matches = {}, 0, {}
        local family_matches = {}
        local selected_material, selected_pattern = {}, {}
        for _, group in ipairs(host.groups()) do
            for _, b in ipairs(group.bindings) do
                local family = modules.gear_catalog.kind(b)
                if scope[family] and (not selection or selection.material[family .. ':' .. host.key(b)]) then
                    assert(host.present(b) and host.binding(b) == b.current, 'Gear changed; load current gear again')
                    local d, match = host.document(exact, b, false)
                    if d then
                        assert(d.width == 23, 'Saved material LUT must have 23 columns')
                        assert(not b.cape or host.resource(b), 'Current Cape resource identity unavailable')
                        batches[d] = batches[d] or {}
                        table.insert(batches[d], b)
                        matches[b] = match or 'exact'
                        family_matches[family] = true
                        selected_material[family .. ':' .. host.key(b)] = true
                    else
                        skipped = skipped + 1
                        if host.log then
                            host.log(
                                'ARMORY_SKIP preset='
                                    .. selected_outfit.name
                                    .. ' kind='
                                    .. family
                                    .. ' unmatched_slot='
                                    .. b.save_key
                            )
                        end
                    end
                end
            end
        end
        local patterns = {}
        if host.has_patterns() then
            for _, group in ipairs(host.pattern_groups()) do
                for _, b in ipairs(group.bindings) do
                    local d, match
                    local family = modules.gear_catalog.kind(b)
                    if scope[family] and (not selection or selection.pattern[family .. ':' .. host.key(b)]) then
                        d, match = host.document(exact, b, true)
                    end
                    if d then
                        assert(d.width == 3 and d.height == 1, 'Saved Pattern LUT must be 3 x 1')
                        assert(not b.cape or host.resource(b), 'Current Cape resource identity unavailable')
                        assert(
                            host.present(b) and host.binding(b) == b.current,
                            'Pattern gear changed; load current gear again'
                        )
                        patterns[d] = patterns[d] or {}
                        patterns[d][#patterns[d] + 1] = b
                        matches[b] = match or 'exact'
                        family_matches[family] = true
                        selected_pattern[family .. ':' .. host.key(b)] = true
                    end
                end
            end
        end
        assert(
            next(batches) or next(patterns),
            'No saved LUT bindings match this gear; select a table and apply it manually to adapt the preset'
        )
        if selection then
            for key in pairs(selection.material) do
                assert(selected_material[key], 'Selected material LUT changed; reopen Apply Preset')
            end
            for key in pairs(selection.pattern) do
                assert(selected_pattern[key], 'Associated Pattern LUT changed; reopen Apply Preset')
            end
        end
        if combined then
            for family in pairs(scope) do
                assert(
                    family_matches[family],
                    'No saved ' .. family .. ' LUT bindings match this gear; apply a table manually to adapt the preset'
                )
            end
        end
        local cape_proof
        for _, plans in ipairs({ batches, patterns }) do
            for _, targets in pairs(plans) do
                for _, b in ipairs(targets) do
                    if b.cape then
                        local proof = host.proof()
                        cape_proof =
                            assert(proof and proof.cape, 'Current Cape identity unavailable; load current gear again')
                    end
                end
            end
        end
        local function apply_batch(document, targets, pattern)
            return host.apply_batch(document, targets, pattern, cape_proof, selection and selection.proofs or nil)
        end
        local function log_applied(targets, pattern)
            if not host.log then
                return
            end
            for _, b in ipairs(targets) do
                host.log(
                    'ARMORY_APPLY preset='
                        .. selected_outfit.name
                        .. ' kind='
                        .. modules.gear_catalog.kind(b)
                        .. ' slot='
                        .. (pattern and 'p:' or '')
                        .. b.save_key
                        .. ' resource='
                        .. host.resource_id(b.original)
                        .. ' match='
                        .. matches[b]
                        .. ' verified=true'
                )
            end
        end
        local before = combined and host.capture()
        local ok, count = pcall(function()
            -- Multi-LUT presets never become blanket overrides for unmatched pieces.
            for family in pairs(scope) do
                host.clear_default(family)
            end
            host.begin_application()
            local applied = 0
            for d, targets in pairs(batches) do
                applied = applied + apply_batch(d, targets, false)
                log_applied(targets, false)
                for _, b in ipairs(targets) do
                    host.remember_basic(b, d)
                end
            end
            for d, targets in pairs(patterns) do
                applied = applied + apply_batch(d, targets, true)
                log_applied(targets, true)
            end
            assert(applied > 0, 'No worn gear bindings available for this preset')
            host.finish_application()
            return applied
        end)
        if not ok then
            if before then
                local restored, reason = pcall(host.restore, before, host.capture())
                assert(
                    restored and reason ~= false,
                    tostring(count) .. '; preset rollback failed: ' .. tostring(reason)
                )
            end
            error(count, 0)
        end
        return host.message(
            'Applied '
                .. selected_outfit.name
                .. ' '
                .. scope_label
                .. ' palettes to '
                .. count
                .. ' matched bindings; '
                .. skipped
                .. ' unmatched left unchanged.'
        )
    end
    local function choose_outfit_luts()
        local preset = assert(host.selected(), 'Choose an outfit preset first')
        assert(host.menu(), 'Preset chooser requires the editor menu')
        assert(host.stop_identification(), 'Highlight restoration pending')
        if host.has_patterns() then
            assert(host.stop_patterns(), 'Pattern highlight restoration pending')
        end
        host.refresh()
        if host.has_patterns() then
            host.scan_patterns()
        end
        local proof = assert(host.proof(), 'Current gear identity unavailable; load current gear again')
        local exact = host.documents(preset)
        local columns = { { title = 'Armor / Cape', items = {} }, { title = 'Helmet', items = {} } }
        local records, saved, saved_pixels = {}, {}, {}
        local function bytes(d)
            return buffers.bytes(d.data, d.width * d.height * 4)
        end
        local function metadata(original)
            return original
                    and table.concat({
                        tostring(original.resource),
                        tostring(original.width),
                        tostring(original.height),
                        tostring(original.patch_source),
                    }, '|')
                or ''
        end
        for _, entry in ipairs(preset.entries) do
            saved_pixels[entry.document] = saved_pixels[entry.document] or bytes(entry.document)
            saved[#saved + 1] = {
                entry = entry,
                kind = entry.kind,
                key = entry.key,
                document = entry.document,
                width = entry.document.width,
                height = entry.document.height,
                bytes = saved_pixels[entry.document],
                original = entry.original,
                metadata = metadata(entry.original),
            }
        end
        local pattern_bindings = {}
        for _, group in ipairs(host.pattern_groups()) do
            for _, b in ipairs(group.bindings) do
                pattern_bindings[modules.gear_catalog.kind(b) .. ':' .. host.key(b)] = b
            end
        end
        local function receipt(b, pattern)
            local original = host.original(b.original)
            return {
                binding = b,
                kind = modules.gear_catalog.kind(b),
                unit = b.unit,
                mesh = b.mesh,
                material = b.material,
                slot = b.slot or (pattern and modules.pattern_slot or modules.material_slot),
                original = b.original,
                current = b.current,
                save_key = b.save_key,
                resource = original and original.resource,
                width = original and original.width,
                height = original and original.height,
                pattern = pattern,
            }
        end
        local function companion(material)
            local kind = modules.gear_catalog.kind(material)
            local key = kind .. ':' .. host.key(material)
            local b = pattern_bindings[key]
            -- Use the same live resolver as apply_outfit. A saved Pattern at
            -- another LOD does not create a slot or certify this destination.
            local d = b and host.document(exact, b, true)
            if not d then
                return
            end
            local original = b and host.original(b.original)
            assert(
                b
                    and d
                    and d.width == 3
                    and d.height == 1
                    and original
                    and original.width == 3
                    and original.height == 1
                    and b.slot == modules.pattern_slot
                    and host.present(b)
                    and host.binding(b) == b.current,
                'Associated Pattern LUT is unavailable or changed; load current Pattern LUTs again'
            )
            return receipt(b, true)
        end
        local represented = {}
        for column, container in ipairs({ 'armor', 'helmet' }) do
            for _, choice in ipairs(host.choices(container)) do
                local group = host.groups()[choice.group]
                local record =
                    { target = host.target(choice.kind, choice.group), material = {}, patterns = {}, members = {} }
                for _, b in ipairs(group.bindings) do
                    if modules.gear_catalog.kind(b) == choice.kind then
                        represented[choice.kind .. ':' .. host.key(b)] = true
                    end
                end
                local allowed, reason = pcall(function()
                    assert(proof[choice.kind], 'Current gear identity unavailable')
                    for _, b in ipairs(group.bindings) do
                        if modules.gear_catalog.kind(b) == choice.kind then
                            record.members[#record.members + 1] = receipt(b, false)
                            assert(host.present(b) and host.binding(b) == b.current, 'Current LUT binding changed')
                            local d = host.document(exact, b, false)
                            if d then
                                assert(d.width == 23, 'Saved material LUT must have 23 columns')
                                record.material[#record.material + 1] = receipt(b, false)
                            end
                            local paired = companion(b)
                            if paired then
                                record.patterns[#record.patterns + 1] = paired
                            end
                        end
                    end
                    assert(#record.material > 0 or #record.patterns > 0, 'No saved LUT matches this current LUT')
                end)
                record.enabled = allowed
                records[choice.key] = record
                local detail = #record.patterns > 0 and (#record.material > 0 and 'Pattern included' or 'Pattern only')
                    or nil
                if not allowed then
                    detail = tostring(reason):gsub('^.-%.lua:%d+:%s*', '')
                end
                columns[column].items[#columns[column].items + 1] = {
                    id = choice.key,
                    label = (choice.kind == 'cape' and 'Cape' or modules.gear_catalog.label(choice.kind))
                        .. ' LUT '
                        .. choice.ordinal,
                    kind = choice.kind,
                    enabled = allowed,
                    checked = allowed,
                    detail = detail,
                }
            end
        end
        -- Some materials expose only a Pattern slot. Armory already applies
        -- these; give Basic a frozen choice instead of silently dropping them.
        local pattern_ordinals = {}
        for _, group in ipairs(host.pattern_groups()) do
            for _, kind in ipairs({ 'armor', 'cape', 'helmet' }) do
                local record = {
                    target = { kind = kind, object = group.object, binding_keys = {}, pattern_only = true },
                    material = {},
                    patterns = {},
                    members = {},
                }
                local allowed, reason = pcall(function()
                    for _, b in ipairs(group.bindings) do
                        if modules.gear_catalog.kind(b) == kind and not represented[kind .. ':' .. host.key(b)] then
                            if host.document(exact, b, true) then
                                assert(proof[kind], 'Current gear identity unavailable')
                                local member = receipt(b, true)
                                record.members[#record.members + 1] = member
                                record.target.binding_keys[host.key(b) .. ':' .. member.slot] = b.save_key
                                local paired = assert(companion(b))
                                record.patterns[#record.patterns + 1] = paired
                            end
                        end
                    end
                end)
                if #record.members > 0 then
                    pattern_ordinals[kind] = (pattern_ordinals[kind] or 0) + 1
                    local id = 'pattern:' .. kind .. ':' .. pattern_ordinals[kind]
                    records[id] = record
                    record.enabled = allowed
                    local column = kind == 'helmet' and 2 or 1
                    columns[column].items[#columns[column].items + 1] = {
                        id = id,
                        kind = kind,
                        enabled = allowed,
                        checked = allowed,
                        label = modules.gear_catalog.label(kind) .. ' Pattern LUT ' .. pattern_ordinals[kind],
                        detail = allowed and 'Pattern only' or tostring(reason):gsub('^.-%.lua:%d+:%s*', ''),
                    }
                end
            end
        end
        local dialog = { title = 'Apply Preset', columns = columns }
        local function validate_record(r)
            local b = r.binding
            assert(
                b.unit == r.unit
                    and b.mesh == r.mesh
                    and b.material == r.material
                    and b.original == r.original
                    and b.save_key == r.save_key
                    and (b.slot or modules.material_slot) == r.slot
                    and host.present(b)
                    and host.binding(b) == r.current,
                'Current LUT target changed; reopen Apply Preset'
            )
            local original = host.original(r.original)
            assert(
                original
                    and original.resource == r.resource
                    and original.width == r.width
                    and original.height == r.height,
                'Current LUT resource changed; reopen Apply Preset'
            )
            if r.pattern then
                assert(original.width == 3 and original.height == 1, 'Associated Pattern LUT is unavailable or changed')
            end
        end
        dialog.on_apply = function(selected)
            assert(host.menu().lut_apply_dialog == dialog, 'Preset chooser changed; reopen Apply Preset')
            assert(type(selected) == 'table', 'Choose current LUTs to apply')
            local chosen, scope = {}, {}
            for id, checked in pairs(selected) do
                assert(records[id] and type(checked) == 'boolean', 'Preset LUT choices changed; reopen Apply Preset')
                if checked then
                    assert(records[id].enabled, 'This current LUT cannot use the selected preset')
                    chosen[#chosen + 1] = records[id]
                    scope[records[id].target.kind] = true
                end
            end
            assert(#chosen > 0, 'Select at least one current LUT')
            local selection = { material = {}, pattern = {}, proofs = proof }
            selection.validate = function(refreshed)
                assert(
                    host.selected() == preset and #preset.entries == #saved,
                    'Saved preset changed; reopen Apply Preset'
                )
                local checked_documents = {}
                for index, entry in ipairs(saved) do
                    local current = preset.entries[index]
                    assert(
                        current == entry.entry
                            and current.kind == entry.kind
                            and current.key == entry.key
                            and current.document == entry.document
                            and current.original == entry.original
                            and metadata(current.original) == entry.metadata
                            and current.document.width == entry.width
                            and current.document.height == entry.height,
                        'Saved preset changed; reopen Apply Preset'
                    )
                    if not checked_documents[current.document] then
                        assert(bytes(current.document) == entry.bytes, 'Saved preset changed; reopen Apply Preset')
                        checked_documents[current.document] = true
                    end
                end
                local current = host.proof()
                for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
                    assert(current and current[kind] == proof[kind], 'Worn gear changed; reopen Apply Preset')
                end
                for _, record in ipairs(chosen) do
                    for _, r in ipairs(record.members) do
                        validate_record(r)
                    end
                    for _, r in ipairs(record.patterns) do
                        validate_record(r)
                    end
                    if refreshed then
                        local actual, count = {}, 0
                        local collection = record.target.pattern_only and host.pattern_groups() or host.groups()
                        for _, group in ipairs(collection) do
                            if group.object == record.target.object then
                                for _, b in ipairs(group.bindings) do
                                    if
                                        modules.gear_catalog.kind(b) == record.target.kind
                                        and (
                                            not record.target.pattern_only
                                            or record.target.binding_keys[host.key(b) .. ':' .. tostring(b.slot)]
                                                ~= nil
                                        )
                                    then
                                        actual[host.key(b) .. ':' .. tostring(b.slot or modules.material_slot)] =
                                            b.save_key
                                        count = count + 1
                                    end
                                end
                            end
                        end
                        assert(count == #record.members, 'Current LUT members changed; reopen Apply Preset')
                        for key, value in pairs(record.target.binding_keys) do
                            assert(actual[key] == value, 'Current LUT members changed; reopen Apply Preset')
                        end
                    end
                end
            end
            selection.validate() -- Reject stale state before refresh/flash cleanup or any native write.
            for _, record in ipairs(chosen) do
                for _, r in ipairs(record.material) do
                    selection.material[r.kind .. ':' .. host.key(r.binding)] = true
                end
                for _, r in ipairs(record.patterns) do
                    selection.pattern[r.kind .. ':' .. host.key(r.binding)] = true
                end
            end
            local before = host.capture_history()
            local result = apply_outfit(scope, selection)
            if before then
                host.record_history(before)
            end
            host.menu().lut_apply_dialog = nil
            return true, result
        end
        host.menu().lut_apply_dialog = dialog
        return host.message('Choose current LUTs to apply. Associated Pattern LUTs are always included.')
    end
    return { apply = apply_outfit, choose_luts = choose_outfit_luts }
end
return A
