-- Imported-to-current LUT mapping. Dialogs freeze exact source bytes and native
-- destination receipts; getters resolve the controller's current session after
-- refresh, rollback or activation. The controller retains indexing and owned writes.
local M = {}
function M.new(deps)
    local imports, gear, patterns = deps.imports, deps.gear, deps.patterns
    local application, history = deps.application, deps.history
    local gear_catalog, slots = deps.gear_catalog, deps.slots
    local self = {}
    function self.open(kind, prepared)
        assert(kind == 'gear' or kind == 'armor' or kind == 'helmet' or kind == 'cape', 'Choose gear to map')
        assert(deps.menu() and #imports.palettes() > 0, 'Import a LUT file first')
        assert(not imports.pending(), 'Wait for the current import to finish')
        local missing = false
        for _, path in ipairs(imports.palettes()) do
            missing = missing or imports.document(path) == nil
        end
        if not prepared and (imports.indexing() or missing) then
            imports.defer(kind, imports.palettes())
            return deps.message('Reading imported LUTs; the mapping chooser will open when ready.')
        end
        assert(application.stop_identification(), 'Highlight restoration pending')
        assert(patterns.stop_flash(), 'Pattern highlight restoration pending')
        gear.refresh()
        patterns.scan()
        local proof = assert(gear.proof(), 'Current gear identity unavailable; load current gear again')
        local catalog = imports.palettes()
        local kinds = kind == 'gear' and { 'armor', 'helmet', 'cape' } or { kind }
        local columns = { { title = 'Imported LUTs', items = {} } }
        for _, k in ipairs(kinds) do
            local label = k == 'cape' and 'Cape' or gear_catalog.label(k)
            columns[#columns + 1] = {
                title = kind == 'gear' and label or 'Current ' .. label .. ' LUTs',
                kind = k,
                items = {},
                enabled = false,
                checked = false,
            }
        end
        local sources, source_order, resources = {}, {}, {}
        local pixels, resource = deps.pixels, imports.resource
        for index, path in ipairs(catalog) do
            local d = imports.document(path)
            local id = 'source:' .. path
            local name = path:gsub('\\', '/'):match('[^/]+$') or 'DDS'
            local valid = d and d.data and d.width == 23 and d.height >= 1 and d.height <= 64
            local r = {
                id = id,
                path = path,
                document = d,
                width = d and d.width,
                height = d and d.height,
                bytes = pixels(d),
                resource = resource(path, d),
                ordinal = index,
                number = tonumber(name:lower():match('lut(%d+)')),
                enabled = valid == true,
            }
            sources[id], source_order[#source_order + 1] = r, r
            if r.resource and d then
                resources[r.resource] = resources[r.resource] or {}
                resources[r.resource][#resources[r.resource] + 1] = r
            end
            columns[1].items[#columns[1].items + 1] = {
                id = id,
                label = (kind == 'gear' and 'LUT ' or 'Imported LUT ') .. index .. ' / ' .. name,
                enabled = r.enabled,
                detail = d and d.width ~= 23 and 'Pattern LUT' or not d and 'Unavailable LUT' or nil,
            }
        end
        local function receipt(b)
            local original = gear.original(b.original)
            return {
                binding = b,
                unit = b.unit,
                mesh = b.mesh,
                material = b.material,
                slot = b.slot or slots.material,
                save_key = b.save_key,
                original = b.original,
                current = b.current,
                resource = original and original.resource,
                width = original and original.width,
                height = original and original.height,
            }
        end
        local function validate_receipt(r)
            local b, original = r.binding, gear.original(r.original)
            assert(
                b.unit == r.unit
                    and b.mesh == r.mesh
                    and b.material == r.material
                    and b.original == r.original
                    and b.save_key == r.save_key
                    and (b.slot or slots.material) == r.slot
                    and gear.present(b)
                    and gear.binding(b) == r.current,
                'Current mapping target changed; reopen Map LUTs'
            )
            assert(
                original
                    and original.resource == r.resource
                    and original.width == r.width
                    and original.height == r.height,
                'Original mapping target changed; load current gear again'
            )
        end
        local targets, target_order = {}, {}
        for column_index, target_kind in ipairs(kinds) do
            local column = columns[column_index + 1]
            local container = target_kind == 'helmet' and 'helmet' or 'armor'
            for _, choice in ipairs(gear.choices(container)) do
                if choice.kind == target_kind then
                    local target = { target = gear.target(target_kind, choice.group), members = {}, patterns = {} }
                    local enabled, why = pcall(function()
                        assert(proof[target_kind], 'Current gear identity unavailable')
                        for _, b in ipairs(gear.groups()[choice.group].bindings) do
                            if gear_catalog.kind(b) == target_kind then
                                local r = receipt(b)
                                validate_receipt(r)
                                assert(r.width == 23, 'Current material LUT is not ready')
                                target.members[#target.members + 1] = r
                                for _, group in ipairs(patterns.groups()) do
                                    for _, p in ipairs(group.bindings) do
                                        if
                                            gear_catalog.kind(p) == target_kind
                                            and gear.material_key(p) == gear.material_key(b)
                                        then
                                            target.patterns[gear.material_key(b)] = receipt(p)
                                        end
                                    end
                                end
                            end
                        end
                        assert(#target.members > 0, 'Current LUT has no material bindings')
                    end)
                    target.enabled = enabled
                    target.item = {
                        id = choice.key,
                        label = kind == 'gear' and ('LUT ' .. choice.ordinal)
                            or (target_kind == 'cape' and 'Cape' or gear_catalog.label(target_kind))
                                .. ' LUT '
                                .. choice.ordinal,
                        enabled = enabled,
                        detail = not enabled and tostring(why):gsub('^.-%.lua:%d+:%s*', '') or nil,
                    }
                    targets[choice.key], target_order[#target_order + 1] = target, target
                    column.items[#column.items + 1] = target.item
                    column.enabled = column.enabled or enabled
                    column.checked = column.enabled
                end
            end
        end
        local dialog = {
            mode = 'mapping',
            title = 'Map LUTs to '
                .. (kind == 'gear' and 'Gear' or kind == 'cape' and 'Cape' or gear_catalog.label(kind)),
            columns = columns,
            gear_columns = kind == 'gear',
        }
        local current_source = catalog[imports.selected()]
        dialog.source_id = current_source
                and sources['source:' .. current_source].enabled
                and 'source:' .. current_source
            or nil
        if not dialog.source_id then
            for _, r in ipairs(source_order) do
                if r.enabled then
                    dialog.source_id = r.id
                    break
                end
            end
        end
        local function validate_catalog()
            assert(
                deps.menu().lut_apply_dialog == dialog
                    and imports.palettes() == catalog
                    and #imports.palettes() == #source_order
                    and not imports.pending()
                    and not imports.indexing(),
                'Imported palette changed; reopen Map LUTs'
            )
            for index, r in ipairs(source_order) do
                local d = imports.document(r.path)
                assert(
                    imports.palettes()[index] == r.path
                        and d == r.document
                        and resource(r.path, d) == r.resource
                        and (not d or d.width == r.width and d.height == r.height and pixels(d) == r.bytes),
                    'Imported LUT data changed; reopen Map LUTs'
                )
            end
            local current = gear.proof()
            for _, k in ipairs({ 'armor', 'helmet', 'cape' }) do
                assert(current and current[k] == proof[k], 'Worn gear changed; reopen Map LUTs')
            end
        end
        local function run(assignments)
            assert(#assignments > 0, 'No material LUTs available to map')
            validate_catalog()
            for _, assignment in ipairs(assignments) do
                assert(
                    assignment.source.enabled and assignment.target.enabled,
                    'Imported source or current mapping target is not ready'
                )
                for _, r in ipairs(assignment.target.members) do
                    validate_receipt(r)
                end
            end
            assert(application.stop_identification(), 'Highlight restoration pending')
            assert(patterns.stop_flash(), 'Pattern highlight restoration pending')
            gear.refresh()
            patterns.scan()
            validate_catalog()
            local plans, included = {}, {}
            for _, assignment in ipairs(assignments) do
                local source, target = assignment.source, assignment.target
                local target_kind = target.target.kind
                local actual, members = {}, {}
                for _, group in ipairs(gear.groups()) do
                    if group.object == target.target.object then
                        for _, b in ipairs(group.bindings) do
                            if gear_catalog.kind(b) == target_kind then
                                actual[gear.material_key(b) .. ':' .. tostring(b.slot or slots.material)] = b.save_key
                                members[#members + 1] = b
                            end
                        end
                    end
                end
                assert(#members == #target.members, 'Current LUT members changed; reopen Map LUTs')
                for key, value in pairs(target.target.binding_keys) do
                    assert(actual[key] == value, 'Current LUT members changed; reopen Map LUTs')
                end
                assignment.members, assignment.paired = members, {}
                local variants = {}
                for _, b in ipairs(members) do
                    local original = gear.original(b.original)
                    local d = source.document
                    if application.preserve_emissives() then
                        assert(gear.originals_ready(), 'Original game LUT snapshots are not ready')
                        variants[b.original] = variants[b.original]
                            or { document = application.preserve(d, original, d.height > 8), targets = {} }
                    else
                        variants[b.original] = variants[b.original] or { document = d, targets = {} }
                    end
                    variants[b.original].targets[#variants[b.original].targets + 1] = b
                    -- Only unique, metadata-certified resources at this exact native
                    -- material can establish an imported material/Pattern pair.
                    if
                        source.resource
                        and original.resource == source.resource
                        and #resources[source.resource] == 1
                    then
                        local p = target.patterns[gear.material_key(b)]
                        local candidates = p and p.resource and resources[p.resource]
                        if
                            candidates
                            and #candidates == 1
                            and candidates[1].document.width == 3
                            and candidates[1].document.height == 1
                        then
                            validate_receipt(p)
                            assert(
                                p.width == 3 and p.height == 1 and p.slot == slots.pattern,
                                'Associated Pattern LUT is not ready'
                            )
                            local fresh
                            for _, group in ipairs(patterns.groups()) do
                                for _, current in ipairs(group.bindings) do
                                    if
                                        gear_catalog.kind(current) == target_kind
                                        and gear.material_key(current) == gear.material_key(b)
                                    then
                                        fresh = current
                                    end
                                end
                            end
                            assert(
                                fresh and fresh.original == p.original and fresh.current == p.current,
                                'Associated Pattern target changed; reopen Map LUTs'
                            )
                            assignment.paired[gear.material_key(b)] = fresh
                            if not included[fresh] then
                                plans[#plans + 1] =
                                    { document = candidates[1].document, targets = { fresh }, pattern = true }
                                included[fresh] = true
                            end
                        end
                    end
                end
                for _, variant in pairs(variants) do
                    plans[#plans + 1] = variant
                end
            end
            local before = history.capture()
            local applied_kinds = {}
            for _, assignment in ipairs(assignments) do
                applied_kinds[assignment.target.target.kind] = true
            end
            local ok, count = application.with_proofs(proof, applied_kinds.cape and proof.cape or nil, function()
                local applied = 0
                for k in pairs(applied_kinds) do
                    application.set_default(k, nil)
                end
                for _, plan in ipairs(plans) do
                    if plan.pattern then
                        applied = applied + patterns.apply(plan.document, plan.targets)
                        application.remember_appearance(plan.targets, true)
                    else
                        applied = applied + application.apply(plan.document, plan.targets)
                        for _, b in ipairs(plan.targets) do
                            application.remember_document(gear_catalog.kind(b), b.original, plan.document)
                        end
                    end
                end
                application.finish()
                return applied
            end)
            if not ok then
                if before then
                    local restored, why = pcall(history.restore, before, history.current())
                    assert(restored and why ~= false, tostring(count) .. '; mapping rollback failed: ' .. tostring(why))
                    -- History restoration clones palette lists and edited source
                    -- documents. Reuse this dialog only when every frozen byte
                    -- and resource still agrees with those restored copies.
                    local same = #imports.palettes() == #source_order
                    for index, r in ipairs(source_order) do
                        local d = imports.document(r.path)
                        same = same
                            and imports.palettes()[index] == r.path
                            and resource(r.path, d) == r.resource
                            and (
                                not d and not r.document
                                or d and d.width == r.width and d.height == r.height and pixels(d) == r.bytes
                            )
                    end
                    if same then
                        catalog = imports.palettes()
                        for _, r in ipairs(source_order) do
                            r.document = imports.document(r.path)
                        end
                    end
                end
                error(count, 0)
            end
            if before then
                history.record(before, history.capture())
            end
            for _, assignment in ipairs(assignments) do
                local target = assignment.target
                target.item.mapped_source, target.item.detail =
                    assignment.source.id, columns[1].items[assignment.source.ordinal].label
                -- Rebase only destinations we actually wrote. An unrelated foreign
                -- write must not become a newly accepted mapping receipt.
                target.members = {}
                for _, b in ipairs(assignment.members) do
                    target.members[#target.members + 1] = receipt(b)
                end
                for key, b in pairs(assignment.paired) do
                    target.patterns[key] = receipt(b)
                end
            end
            if deps.menu() then
                deps.menu().redraw_revision = (deps.menu().redraw_revision or 0) + 1
            end
            return true,
                deps.message(
                    'Mapped ' .. #assignments .. ' imported LUTs to ' .. count .. ' exact ' .. kind .. ' bindings.'
                )
        end
        dialog.on_map = function(source_id, target_id)
            local source, target = sources[source_id], targets[target_id]
            assert(source and target, 'Mapping choices changed; reopen Map LUTs')
            return run({ { source = source, target = target } })
        end
        dialog.on_auto_map = function(gear_mask)
            local selected_kinds = {}
            if kind == 'gear' then
                assert(type(gear_mask) == 'table', 'Choose Armor, Helmet and/or Cape to auto-map')
                for k, checked in pairs(gear_mask) do
                    assert(
                        (k == 'armor' or k == 'helmet' or k == 'cape') and type(checked) == 'boolean',
                        'Invalid auto-map gear selection'
                    )
                end
                for column_index, k in ipairs(kinds) do
                    if gear_mask[k] then
                        assert(columns[column_index + 1].enabled, 'Selected auto-map gear is not ready')
                        selected_kinds[k] = true
                    end
                end
                assert(next(selected_kinds), 'Choose Armor, Helmet and/or Cape to auto-map')
            else
                selected_kinds[kind] = true
            end
            local cycle = {}
            for _, source in ipairs(source_order) do
                if source.enabled then
                    cycle[#cycle + 1] = source
                end
            end
            table.sort(cycle, function(a, b)
                if a.number and b.number and a.number ~= b.number then
                    return a.number < b.number
                end
                if (a.number ~= nil) ~= (b.number ~= nil) then
                    return a.number ~= nil
                end
                return a.ordinal < b.ordinal
            end)
            assert(#cycle > 0, 'No material LUTs available to auto-map')
            local assignments = {}
            local ordinals = {}
            for _, target in ipairs(target_order) do
                local k = target.target.kind
                if selected_kinds[k] then
                    ordinals[k] = (ordinals[k] or 0) + 1
                    assignments[#assignments + 1] = { source = cycle[(ordinals[k] - 1) % #cycle + 1], target = target }
                end
            end
            return run(assignments)
        end
        deps.menu().lut_apply_dialog = dialog
        return deps.message('Choose an imported LUT, then click the current LUT to map it.')
    end
    return self
end
return M
