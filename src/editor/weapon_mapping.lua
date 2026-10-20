-- Planning and frozen receipts only. The runtime owns all native writes and rollback.
local ffi = require('ffi')
local M = { MAX_BINDINGS = 4096, MAX_GROUPS = 3072 }
local roles = { 'primary', 'secondary', 'support' }
local labels = { 'Primary', 'Secondary', 'Support' }
local function dense(values, limit, label)
    assert(type(values) == 'table' and #values <= limit, 'Invalid ' .. label .. ' list')
    local count = 0
    for index in pairs(values) do
        assert(
            type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= #values,
            label .. ' must be a dense list'
        )
        count = count + 1
    end
    assert(count == #values, label .. ' must be a dense list')
end
local function family(value)
    value = value == 'main' and 'material' or value
    assert(value == 'material' or value == 'pattern', 'Invalid weapon LUT family')
    return value
end
local function resource(value)
    assert(
        type(value) == 'string' and #value == 16 and value:match('^%x+$') and value ~= string.rep('0', 16),
        'Invalid weapon configuration ID'
    )
    return value:lower()
end
-- Preserve every channel while adapting saved palettes to another weapon's rows.
function M.fit(document, width, height)
    M.bytes(document)
    assert(
        document.width == width and height >= 1 and height <= 64 and height % 1 == 0,
        'Incompatible weapon LUT family'
    )
    assert(width ~= 3 or height == 1, 'Invalid Pattern LUT shape')
    local data = ffi.new('float[?]', width * height * 4)
    for row = 0, height - 1 do
        ffi.copy(data + row * width * 4, document.data + (row % document.height) * width * 4, width * 16)
    end
    return { data = data, width = width, height = height }
end
function M.bytes(document)
    assert(
        type(document) == 'table'
            and type(document.height) == 'number'
            and document.height % 1 == 0
            and (
                (document.width == 23 and document.height >= 1 and document.height <= 64)
                or (document.width == 3 and document.height == 1)
            ),
        'Unsupported weapon LUT shape'
    )
    local size = document.width * document.height * 16
    assert(
        type(document.data) == 'cdata' and ffi.istype('float[?]', document.data) and ffi.sizeof(document.data) >= size,
        'Weapon LUT must own its complete float32 array'
    )
    for index = 0, size / 4 - 1 do
        local value = tonumber(document.data[index])
        assert(value == value and math.abs(value) <= 1e10, 'Invalid weapon LUT float')
    end
    return ffi.string(document.data, size)
end
function M.copy(document)
    local bytes, result = M.bytes(document), {}
    for key, value in pairs(document) do
        result[key] = value
    end
    result.data = ffi.new('float[?]', #bytes / 4)
    ffi.copy(result.data, bytes, #bytes)
    if document.original ~= nil then
        assert(
            type(document.original) == 'cdata'
                and ffi.istype('float[?]', document.original)
                and ffi.sizeof(document.original) >= #bytes,
            'Invalid original weapon LUT array'
        )
        result.original = ffi.new('float[?]', #bytes / 4)
        ffi.copy(result.original, document.original, #bytes)
    end
    return result
end
-- Runtime.target re-proves the local/configuration ownership and live bindings.
function M.freeze(runtime, descriptors, options)
    local application_only = options and options.application_only == true
    assert(
        type(runtime) == 'table' and type(runtime.target) == 'function' and type(runtime.load) == 'function',
        'Weapon runtime receipt operations unavailable'
    )
    dense(descriptors, M.MAX_GROUPS, 'Weapon groups')
    local frozen, seen, count = {}, {}, 0
    local fields = {
        'unit',
        'mesh',
        'material',
        'slot',
        'save_key',
        'original',
        'current',
        'weapon_slot',
        'weapon_resource',
        'weapon_resource64',
        'receipt',
        'mesh_index',
        'material_index',
    }
    for _, descriptor in ipairs(descriptors) do
        assert(type(descriptor) == 'table', 'Invalid weapon group descriptor')
        local slot, index, kind = descriptor.weapon_slot, descriptor.index, family(descriptor.family)
        assert(
            type(slot) == 'number'
                and slot % 1 == 0
                and slot >= 1
                and slot <= 3
                and type(index) == 'number'
                and index % 1 == 0
                and index >= 1,
            'Invalid weapon group locator'
        )
        local group = runtime.target(slot, index, kind)
        if application_only and runtime.shape then
            group = runtime.shape(slot, index, kind)
        elseif not group.source_document then
            runtime.load(slot, index, kind)
            group = runtime.target(slot, index, kind)
        end
        local id = resource(group.weapon_resource or group.weapon_resource64)
        assert(
            resource(descriptor.weapon_resource or descriptor.weapon_resource64) == id,
            'Weapon group configuration changed'
        )
        assert(
            descriptor.source_resource == nil or descriptor.source_resource == group.source_resource,
            'Weapon group source LUT changed'
        )
        local key = slot .. ':' .. kind .. ':' .. index
        assert(not seen[key], 'Duplicate weapon group locator')
        seen[key] = true
        local original = group.source_document
        assert(application_only or original, 'Original weapon LUT pixels unavailable')
        local width, height = group.width or original and original.width, group.height or original and original.height
        assert(width == (kind == 'pattern' and 3 or 23) and type(height) == 'number'
            and height >= 1 and height <= 64 and height % 1 == 0 and (kind ~= 'pattern' or height == 1),
            'Weapon group family differs from source shape')
        dense(group.bindings, M.MAX_BINDINGS, 'Weapon group bindings')
        assert(#group.bindings > 0, 'Weapon LUT group has no bindings')
        local wanted = {}
        local subset = descriptor.bindings or group.bindings
        dense(subset, M.MAX_BINDINGS, 'Weapon target subset')
        assert(#subset > 0, 'Choose at least one weapon binding')
        for _, binding in ipairs(subset) do
            assert(
                type(binding) == 'table' and type(binding.save_key) == 'string' and not wanted[binding.save_key],
                'Invalid or duplicate weapon subset'
            )
            wanted[binding.save_key] = binding
        end
        local saved = {
            id = 'weapon:' .. key,
            group = group,
            index = index,
            family = kind,
            weapon_slot = slot,
            weapon_resource = id,
            source_resource = group.source_resource,
            source_document = original,
            source_bytes = original and M.bytes(original),
            width = width,
            height = height,
            members = {},
            scope_members = {},
        }
        for _, binding in ipairs(group.bindings) do
            count = count + 1
            assert(count <= M.MAX_BINDINGS, 'Weapon binding budget exceeded')
            assert(
                type(binding) == 'table'
                    and binding.weapon_slot == slot
                    and resource(binding.weapon_resource or binding.weapon_resource64) == id,
                'Weapon binding configuration differs from group'
            )
            local member = { binding = binding, fields = {} }
            for _, field in ipairs(fields) do
                member.fields[field] = binding[field]
            end
            saved.scope_members[#saved.scope_members + 1] = member
            local requested = wanted[binding.save_key]
            if requested then
                for _, field in ipairs(fields) do
                    assert(requested[field] == binding[field], 'Weapon subset receipt changed: ' .. field)
                end
                local current = binding.document or group.applied_document or original
                member.document, member.bytes = current, current and M.bytes(current)
                saved.members[#saved.members + 1] = member
                wanted[binding.save_key] = nil
            end
        end
        assert(not next(wanted), 'Weapon subset contains an unknown destination')
        frozen[#frozen + 1] = saved
    end
    local function validate()
        for _, saved in ipairs(frozen) do
            local group = runtime.target(saved.weapon_slot, saved.index, saved.family)
            if application_only and runtime.shape then
                group = runtime.shape(saved.weapon_slot, saved.index, saved.family)
                assert(group.width == saved.width and group.height == saved.height,
                    'Loaded weapon shape changed; reopen the operation')
            end
            assert(
                group == saved.group
                    and resource(group.weapon_resource or group.weapon_resource64) == saved.weapon_resource
                    and group.source_resource == saved.source_resource
                    and group.source_document == saved.source_document
                    and (not saved.source_bytes or M.bytes(group.source_document) == saved.source_bytes)
                    and #group.bindings == #saved.scope_members,
                'Weapon/source LUT changed; reopen the operation'
            )
            for index, member in ipairs(saved.scope_members) do
                local binding = group.bindings[index]
                assert(binding == member.binding, 'Weapon group members changed; reopen the operation')
                for _, field in ipairs(fields) do
                    assert(binding[field] == member.fields[field], 'Weapon target receipt changed: ' .. field)
                end
                if member.bytes then
                    local current = binding.document or group.applied_document or group.source_document
                    assert(M.bytes(current) == member.bytes, 'Current weapon LUT pixels changed; reopen the operation')
                end
            end
        end
        return true
    end
    validate()
    return frozen, validate
end
function M.new(host)
    assert(
        type(host) == 'table'
            and type(host.menu) == 'function'
            and host.imports
            and host.runtime
            and type(host.runtime.apply_plan) == 'function',
        'Weapon mapping host unavailable'
    )
    local imports, runtime, self = host.imports, host.runtime, {}
    function self.open(descriptors, options)
        options = options or {}
        assert(
            options.auto == nil or type(options.auto) == 'boolean' or type(options.auto) == 'table',
            'Invalid auto-map option'
        )
        assert(options.rollover == nil or type(options.rollover) == 'boolean', 'Invalid auto-map rollover option')
        local menu = assert(host.menu(), 'Weapon mapping menu unavailable')
        assert(not imports.pending() and not imports.indexing(), 'Wait for imported LUTs to finish loading')
        local catalog = imports.palettes()
        dense(catalog, M.MAX_BINDINGS, 'Imported LUTs')
        assert(#catalog > 0, 'Import a DDS palette first')
        local columns = { { title = 'Imported LUTs', items = {} } }
        for slot = 1, 3 do
            columns[slot + 1] = {
                title = labels[slot],
                kind = roles[slot],
                weapon_slot = slot,
                items = {},
                enabled = false,
                checked = false,
            }
        end
        local sources, source_order, by_resource = {}, {}, {}
        for ordinal, path in ipairs(catalog) do
            assert(type(path) == 'string', 'Invalid imported DDS path')
            local document = assert(imports.document(path), 'Imported LUT pixels unavailable')
            local bytes = M.bytes(document)
            local name = path:gsub('\\', '/'):match('[^/]+$') or path
            local id = 'source:' .. ordinal
            local source = {
                id = id,
                path = path,
                ordinal = ordinal,
                document = document,
                bytes = bytes,
                copied = M.copy(document),
                resource = imports.resource(path, document),
                family = document.width == 3 and 'pattern' or 'material',
                number = tonumber(name:lower():match('lut(%d+)')),
            }
            sources[id], source_order[#source_order + 1] = source, source
            if source.resource then
                by_resource[source.resource] = by_resource[source.resource] or {}
                table.insert(by_resource[source.resource], source)
            end
            columns[1].items[#columns[1].items + 1] = {
                id = id,
                label = 'LUT ' .. ordinal .. ' / ' .. name,
                enabled = true,
                detail = source.family == 'pattern' and 'Pattern' or nil,
            }
        end
        local targets, target_order = {}, {}
        dense(descriptors, M.MAX_GROUPS, 'Weapon groups')
        for _, descriptor in ipairs(descriptors) do
            local frozen, validate = M.freeze(runtime, { descriptor })
            local target = frozen[1]
            assert(not targets[target.id], 'Duplicate mapping target')
            target.validate = validate
            target.item = {
                id = target.id,
                label = (target.family == 'pattern' and 'Pattern LUT ' or 'LUT ') .. target.index,
                enabled = true,
            }
            targets[target.id], target_order[#target_order + 1] = target, target
            local column = columns[target.weapon_slot + 1]
            column.items[#column.items + 1], column.enabled, column.checked = target.item, true, true
        end
        assert(#target_order > 0, 'Load weapon LUTs before mapping')
        table.sort(target_order, function(a, b)
            if a.weapon_slot ~= b.weapon_slot then
                return a.weapon_slot < b.weapon_slot
            end
            if a.family ~= b.family then
                return a.family == 'material'
            end
            return a.index < b.index
        end)
        local dialog = {
            mode = 'mapping',
            title = 'Map LUTs to Weapons',
            columns = columns,
            gear_columns = true,
            weapon_columns = true,
            source_id = source_order[1].id,
        }
        local function validate_sources()
            assert(
                host.menu() == menu
                    and menu.lut_apply_dialog == dialog
                    and not imports.pending()
                    and not imports.indexing(),
                'Weapon mapping dialog or import session changed'
            )
            local current = imports.palettes()
            assert(#current == #source_order, 'Imported DDS catalog changed')
            for index, source in ipairs(source_order) do
                local document = imports.document(source.path)
                assert(
                    current[index] == source.path
                        and document == source.document
                        and M.bytes(document) == source.bytes
                        and imports.resource(source.path, document) == source.resource,
                    'Imported DDS bytes/identity changed'
                )
            end
        end
        local function compatible(source, target)
            return source.family == target.family
                and source.copied.width == target.width
                and source.copied.height == target.height
        end
        local function companions(source, target)
            local paired = {}
            if source.family ~= 'material' then
                return paired
            end
            local keys = {}
            for _, member in ipairs(target.members) do
                keys[member.binding.save_key] = true
            end
            for _, pattern in ipairs(target_order) do
                if
                    pattern.family == 'pattern'
                    and pattern.weapon_slot == target.weapon_slot
                    and pattern.weapon_resource == target.weapon_resource
                then
                    local exact = {}
                    for _, member in ipairs(pattern.members) do
                        if keys[member.binding.save_key] then
                            exact[#exact + 1] = member.binding
                        end
                    end
                    if #exact > 0 then
                        local matched
                        if type(imports.companion) == 'function' then
                            local path = imports.companion(source.path, pattern.source_resource, target.group)
                            for _, candidate in ipairs(source_order) do
                                if path == candidate.path then
                                    matched = candidate
                                end
                            end
                        elseif
                            source.resource
                            and source.resource == target.source_resource
                            and #by_resource[source.resource] == 1
                        then
                            local candidates = pattern.source_resource and by_resource[pattern.source_resource]
                            if candidates and #candidates == 1 then
                                matched = candidates[1]
                            end
                        end
                        if matched then
                            assert(compatible(matched, pattern), 'Associated Pattern DDS dimensions differ')
                            paired[#paired + 1] = { source = matched, target = pattern, targets = exact }
                        end
                    end
                end
            end
            return paired
        end
        local function apply(assignments)
            assert(runtime.supports_target_subsets == true, 'Weapon runtime exact subset plans unavailable')
            assert(#assignments > 0, 'No compatible weapon LUTs selected')
            validate_sources()
            local plan, included, plan_groups, written = {}, {}, {}, {}
            local function include(assignment)
                local source, target = assignment.source, assignment.target
                assert(compatible(source, target), 'Imported DDS dimensions differ from selected weapon LUT')
                target.validate()
                local allowed, selected = {}, assignment.targets or {}
                for _, member in ipairs(target.members) do
                    allowed[member.binding] = true
                    if not assignment.targets then
                        selected[#selected + 1] = member.binding
                    end
                end
                dense(selected, M.MAX_BINDINGS, 'Mapping targets')
                assert(#selected > 0, 'No exact weapon bindings selected')
                plan_groups[target.id] = plan_groups[target.id] or {}
                local entry = plan_groups[target.id][source.bytes]
                if not entry then
                    entry = {
                        weapon_slot = target.weapon_slot,
                        family = target.family,
                        index = target.index,
                        weapon_resource = target.weapon_resource,
                        source_resource = target.source_resource,
                        document = M.copy(source.copied),
                        targets = {},
                    }
                    plan_groups[target.id][source.bytes] = entry
                end
                for _, binding in ipairs(selected) do
                    assert(allowed[binding], 'Unknown Pattern companion mapping target')
                    assert(
                        not included[binding] or included[binding] == source.bytes,
                        'Conflicting Pattern/material mapping'
                    )
                    if not included[binding] then
                        included[binding] = source.bytes
                        entry.targets[#entry.targets + 1] = binding
                    end
                end
                if #entry.targets > 0 and not written[target.id .. ':' .. source.id] then
                    local present = false
                    for _, current in ipairs(plan) do
                        present = present or current == entry
                    end
                    if not present then
                        plan[#plan + 1] = entry
                    end
                    written[target.id .. ':' .. source.id] = true
                end
            end
            for _, assignment in ipairs(assignments) do
                include(assignment)
                for _, paired in ipairs(companions(assignment.source, assignment.target)) do
                    include(paired)
                end
            end
            validate_sources()
            for _, target in ipairs(target_order) do
                if plan_groups[target.id] then
                    target.validate()
                end
            end
            local results = runtime.apply_plan(plan)
            assert(type(results) == 'table' and #results == #plan, 'Weapon runtime did not report applied plans')
            for _, target in ipairs(target_order) do
                if plan_groups[target.id] then
                    local refreshed, validate = M.freeze(runtime, { target.group })
                    target.members, target.source_bytes, target.validate =
                        refreshed[1].members, refreshed[1].source_bytes, validate
                    target.item.detail = 'Mapped'
                end
            end
            menu.redraw_revision = (menu.redraw_revision or 0) + 1
            return true, 'Mapped ' .. #plan .. ' weapon LUT tables.'
        end
        local function run(assignments)
            if host.mutate then
                assert(type(host.mutate) == 'function', 'Weapon mapping history service unavailable')
                return host.mutate(function()
                    return apply(assignments)
                end)
            end
            return apply(assignments)
        end
        dialog.on_map = function(source_id, target_id)
            local source, target = sources[source_id], targets[target_id]
            assert(source and target, 'Weapon mapping choices changed')
            return run({ { source = source, target = target } })
        end
        dialog.on_auto_map = function(mask)
            mask = mask or { primary = true, secondary = true, support = true }
            assert(type(mask) == 'table', 'Choose weapon columns to auto-map')
            for key, checked in pairs(mask) do
                assert(
                    (
                        key == 'primary'
                        or key == 'secondary'
                        or key == 'support'
                        or type(key) == 'number' and key % 1 == 0 and key >= 1 and key <= 3
                    ) and type(checked) == 'boolean',
                    'Invalid auto-map weapon selection'
                )
            end
            local selected = {}
            for slot, role in ipairs(roles) do
                selected[slot] = mask[role] == true or mask[slot] == true
            end
            local sorted = {}
            for _, source in ipairs(source_order) do
                sorted[#sorted + 1] = source
            end
            table.sort(sorted, function(a, b)
                if a.number and b.number and a.number ~= b.number then
                    return a.number < b.number
                end
                if (a.number ~= nil) ~= (b.number ~= nil) then
                    return a.number ~= nil
                end
                return a.ordinal < b.ordinal
            end)
            local assignments, ordinal, paired_bindings = {}, {}, {}
            for _, target in ipairs(target_order) do
                if selected[target.weapon_slot] then
                    local cycle = {}
                    for _, source in ipairs(sorted) do
                        if compatible(source, target) then
                            cycle[#cycle + 1] = source
                        end
                    end
                    if #cycle > 0 then
                        local key = target.weapon_slot .. ':' .. target.family .. ':' .. target.height
                        ordinal[key] = (ordinal[key] or 0) + 1
                        local selected_targets
                        if target.family == 'pattern' then
                            selected_targets = {}
                            for _, member in ipairs(target.members) do
                                if not paired_bindings[member.binding] then
                                    selected_targets[#selected_targets + 1] = member.binding
                                end
                            end
                        end
                        local assignment = {
                            source = cycle[(ordinal[key] - 1) % #cycle + 1],
                            target = target,
                            targets = selected_targets,
                        }
                        if not selected_targets or #selected_targets > 0 then
                            assert(
                                options.rollover ~= false or ordinal[key] <= #cycle,
                                'More weapon slots than imported LUTs; enable rollover'
                            )
                            assignments[#assignments + 1] = assignment
                            for _, companion in ipairs(companions(assignment.source, target)) do
                                for _, binding in ipairs(companion.targets) do
                                    paired_bindings[binding] = true
                                end
                            end
                        end
                    end
                end
            end
            return run(assignments)
        end
        menu.lut_apply_dialog = dialog
        if options.auto then
            dialog.on_auto_map(type(options.auto) == 'table' and options.auto or nil)
        end
        return dialog
    end
    return self
end
return M
