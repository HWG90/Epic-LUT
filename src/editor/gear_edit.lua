-- Scoped material/Basic gear editing. Plans, immutable copies and target proofs
-- belong here; active-session mutation and owned native writes stay in the host.
local buffers = m and m.float_buffer or require('src.core.float_buffer')
local G = {}
function G.new(modules, host)
    local self = {}
    local function redraw()
        local menu = host.menu()
        if menu then
            menu.redraw_revision = (menu.redraw_revision or 0) + 1
        end
    end
    function self.choices(container)
        local entries = {}
        for _, kind in ipairs(container == 'armor' and { 'armor', 'cape' } or { 'helmet' }) do
            local ordinal = 0
            for index, group in ipairs(host.groups()) do
                for _, b in ipairs(group.bindings) do
                    if b[kind] then
                        ordinal = ordinal + 1
                        entries[#entries + 1] = {
                            group = index,
                            kind = kind,
                            ordinal = ordinal,
                            label = (kind == 'cape' and 'Cape LUT ' or 'LUT ') .. ordinal,
                            key = kind .. ':' .. tostring(group.object),
                            binding = b,
                        }
                        break
                    end
                end
            end
        end
        return entries
    end
    function self.target(kind, index)
        local group = assert(host.groups()[index], 'Selected live LUT is unavailable')
        local proof = host.proof()
        local original = host.original(group.object)
        local target = {
            kind = kind,
            group = index,
            object = group.object,
            resource = original and original.resource,
            cape_proof = kind == 'cape' and proof and proof.cape or nil,
            kit_proof = proof and proof[kind],
            binding_keys = {},
        }
        for _, b in ipairs(group.bindings) do
            if b[kind] then
                target.binding_keys[host.key(b) .. ':' .. tostring(b.slot or modules.material_slot)] = b.save_key or ''
            end
        end
        assert(next(target.binding_keys), 'Selected live LUT has no matching binding')
        return target
    end
    function self.warm_worn()
        host.refresh()
        local selected, complete, total = {}, true, 0
        for _, container in ipairs({ 'armor', 'helmet' }) do
            for choice, entry in ipairs(self.choices(container)) do
                local b = entry.binding
                local source = b.current ~= b.original and host.applied_document(b) or host.original(b.original)
                total = total + 1
                if source then
                    host.seed_document(entry.key, source, 'Worn ' .. entry.kind)
                    if not selected[container] or choice == host.get('basic_' .. container .. '_lut') then
                        selected[container] = {
                            document = source,
                            group = entry.group,
                            object = b.original,
                            kind = entry.kind,
                            label = entry.label,
                        }
                    end
                else
                    complete = false
                end
            end
        end
        return complete and total > 0, selected
    end
    function self.populate_worn()
        local complete, selected = self.warm_worn()
        if not complete then
            return false
        end
        local container = host.editor_container() == 'helmet' and 'helmet' or 'armor'
        if not selected[container] then
            container = selected.armor and 'armor' or 'helmet'
        end
        local target = selected[container]
        if not target then
            return false
        end
        local document = modules.basic_state.clone(
            target.document,
            target.kind == 'cape' and target.label .. ' (worn)' or 'Worn ' .. target.kind
        )
        host.set_loaded(document)
        document.resource_object = target.object
        local original = host.original(target.object)
        host.commit_worn_target(document, {
            kind = target.kind,
            group = target.group,
            object = target.object,
            resource = original and original.resource,
            cape_proof = target.kind == 'cape' and host.cape_proof() or nil,
        })
        host.select_lut(target.group)
        host.preview(host.loaded(), 0)
        host.finish_worn_selection(target.kind)
        host.sync_palette(container)
        host.sync_import()
        local manual_request = host.consume_populate_request()
        host.message('Loaded every current Armor, Cape and Helmet LUT slot. Select a table to edit.')
        local prime = manual_request and host.get_pattern_prime()
        if prime then
            local ok, ready, why = pcall(prime, container)
            if not ok or ready == false then
                host.log('Material LUTs loaded; Pattern quick editor not ready: ' .. tostring(ok and why or ready))
            end
        end
        local request = manual_request and host.get_binding_request()
        if request then
            local ok, ready, why = pcall(request)
            local reason = ok and why or ready
            if (not ok or ready == false) and reason then
                host.log('Binding source request: ' .. tostring(reason))
            end
        end
        return true
    end
    function self.set_camo_row(row, container, checked, expected_rows)
        local panel = host.panels()[container]
        if
            not panel
            or not modules.basic_camo.available(panel.document)
            or host.busy()
            or type(row) ~= 'number'
            or row % 1 ~= 0
            or row < 1
            or row > panel.document.height
            or type(checked) ~= 'boolean'
            or not panel.camo_rows
            or (expected_rows and panel.camo_rows ~= expected_rows)
        then
            return false
        end
        panel.camo_rows[row] = checked
        redraw()
        return true
    end
    function self.check_target(target)
        assert(target, 'Load current gear again')
        if target.binding_keys then
            local proof = host.proof()
            assert(
                not target.kit_proof or proof and proof[target.kind] == target.kit_proof,
                'Worn kit changed; load current colors again'
            )
            host.refresh()
            for index, group in ipairs(host.groups()) do
                if group.object == target.object then
                    local actual = {}
                    for _, b in ipairs(group.bindings) do
                        if b[target.kind] then
                            actual[host.key(b) .. ':' .. tostring(b.slot or modules.material_slot)] = b.save_key or ''
                        end
                    end
                    local same = true
                    for key, value in pairs(target.binding_keys) do
                        if actual[key] ~= value then
                            same = false
                            break
                        end
                    end
                    if same then
                        target.group = index
                        return index
                    end
                end
            end
            error('Worn binding or slot changed; load current colors again')
        end
        if target.kind ~= 'cape' then
            host.refresh()
            for index, group in ipairs(host.groups()) do
                if
                    target.object and group.object == target.object
                    or not target.object and target.key == target.kind .. ':' .. tostring(group.object)
                then
                    for _, b in ipairs(group.bindings) do
                        if b[target.kind] then
                            local original = host.original(b.original)
                            assert(
                                not target.resource or original and original.resource == target.resource,
                                'Worn resource changed; load current colors again'
                            )
                            target.group = index
                            return index
                        end
                    end
                end
            end
            error('Worn gear changed; load current colors again')
        end
        local proof = host.proof()
        assert(proof and proof.cape == target.cape_proof, 'Cape kit changed; load current Cape colors again')
        assert(target.resource, 'Cape resource identity unavailable; load current colors again')
        host.refresh()
        for index, group in ipairs(host.groups()) do
            for _, b in ipairs(group.bindings) do
                local original = b.cape and host.original(b.original)
                if original and original.resource == target.resource then
                    target.group, target.object = index, group.object
                    return index
                end
            end
        end
        error('Cape material changed; load current Cape colors again')
    end
    function self.apply_camo(container, choice, mode, color)
        assert(host.stop_identification(), 'Highlight restoration pending')
        host.refresh()
        local panel = host.panels()[container]
        assert(
            panel and modules.basic_camo.available(panel.document),
            'Load a current Armor or Helmet material LUT first'
        )
        assert(panel.camo_count > 0, 'Select at least one Camo region')
        local target = self.target(panel.kind, panel.group)
        local index = self.check_target(target)
        local targets = {}
        for _, b in ipairs(host.groups()[index].bindings) do
            if modules.gear_catalog.kind(b) == panel.kind then
                targets[#targets + 1] = b
            end
        end
        assert(#targets > 0, 'Selected LUT has no current material bindings')
        local document = modules.basic_state.copier().copy(panel.document)
        local rows, label = modules.basic_camo.apply(document, choice, mode, color, panel.kind, panel.camo_rows)
        local ok, count = host.write_camo(document, targets, target)
        assert(ok, count)
        host.remember_document(panel.key, document)
        for _, b in ipairs(targets) do
            host.remember_document(modules.gear_catalog.kind(b) .. ':' .. tostring(b.original), document)
        end
        target.container, target.key = container, panel.key
        host.commit_camo(target, document)
        host.sync_palette()
        if mode == 'color' then
            -- The selector follows the committed checked-region RGB immediately.
            -- State synchronization suppresses callbacks, preserving the custom
            -- recipe instead of applying the old named colorway again.
            host.sync_import()
        end
        redraw()
        return host.message(
            'Applied '
                .. (label or modules.basic_camo.CHOICES[choice])
                .. ' to '
                .. rows
                .. ' checked regions in this '
                .. modules.gear_catalog.label(panel.kind)
                .. ' LUT ('
                .. count
                .. ' bindings).'
        )
    end
    function self.picker_guard(control, container)
        return function()
            local panel = host.panels()[container]
            if not panel or not modules.basic_camo.available(panel.document) then
                return false, 'Load a current material LUT first.'
            end
            if panel.camo_count == 0 then
                return false, 'Select at least one Camo region.'
            end
            local picker = host.menu() and host.menu().color_picker
            if picker and picker.control == control then
                if control.camo_key ~= panel.key then
                    return false, 'The selected LUT changed; reopen the camo color picker.'
                end
                self.check_target(control.camo_target)
            else
                control.camo_key = panel.key
                control.camo_target = self.target(panel.kind, panel.group)
                self.check_target(control.camo_target)
            end
            return true
        end
    end
    function self.load_target(container)
        assert(host.stop_identification(), 'Highlight restoration pending')
        host.refresh()
        local panel = host.panels()[container]
        local kind = panel and panel.kind or container
        local source
        local group = panel and panel.group and host.groups()[panel.group]
        if group then
            for _, b in ipairs(group.bindings) do
                if b[kind] then
                    source = host.applied_document(b) or (host.original(b.original))
                    if source then
                        break
                    end
                end
            end
        end
        if not source then
            return false
        end
        assert(source.width == 23, 'Expected a 23-column material LUT')
        local original = host.original(group.object)
        local proof = host.proof()
        if kind == 'cape' then
            assert(original and original.resource and proof and proof.cape, 'Current Cape identity unavailable')
        end
        local document = modules.basic_state.clone(
            source,
            kind == 'cape' and panel.label .. ' (worn)'
                or modules.gear_catalog.label(kind) .. ' LUT ' .. panel.ordinal .. ' (worn)'
        )
        host.set_loaded(document)
        document.resource, document.resource_object = host.resource_id(group.object), group.object
        local target = {
            kind = kind,
            group = panel.group,
            object = group.object,
            resource = original and original.resource,
            cape_proof = kind == 'cape' and proof.cape or nil,
        }
        host.commit_loaded_target(document, target, kind)
        host.select_lut(panel.group)
        host.preview(host.loaded(), 0, true)
        host.sync_palette(container)
        return host.message('Editor populated from ' .. host.loaded().source .. '. Edits affect this LUT only.')
    end
    function self.apply_target(container, all)
        assert(host.loaded(), 'Load current colors or send an imported LUT to the editor first')
        if all then
            assert(host.set('scope', container == 'armor' and 2 or container == 'helmet' and 3 or 4))
            return host.apply(host.loaded(), container)
        end
        local panel = host.panels()[container]
        assert(panel and panel.group, 'Selected LUT unavailable')
        local kind = panel.kind or container
        if kind == 'cape' then
            assert(host.stop_identification(), 'Highlight restoration pending')
            host.refresh()
            assert(host.loaded(), 'Cape changed; load current colors again')
            panel = host.panels()[container]
        end
        local group = host.groups()[panel.group]
        local original = host.original(group.object)
        local proof = host.proof()
        host.select_lut(panel.group)
        assert(host.set('scope', 1))
        host.set_editor_target({
            kind = kind,
            group = panel.group,
            object = group.object,
            resource = original and original.resource,
            cape_proof = kind == 'cape' and proof and proof.cape or nil,
        })
        return host.apply(host.loaded(), kind)
    end
    function self.apply_import(kind)
        assert(host.stop_identification(), 'Highlight restoration pending')
        host.refresh()
        local panel = host.panels()[kind]
        assert(panel and panel.group, 'Select a ' .. kind .. ' LUT first')
        kind = panel.kind or kind
        assert(host.imported(), 'Import a LUT file first')
        local group = host.groups()[panel.group]
        host.select_lut(panel.group)
        assert(host.set('scope', 1))
        host.clear_basic_selection()
        local result = host.apply(host.imported(), kind)
        for _, b in ipairs(group.bindings) do
            if b[kind] and b.document then
                host.remember_document(
                    kind .. ':' .. tostring(b.original),
                    modules.basic_state.clone(b.document, 'Applied ' .. kind .. ' LUT')
                )
            end
        end
        host.clear_import_selection()
        return result
    end
    function self.copy_palette(destination, source_kind)
        assert(host.stop_identification(), 'Highlight restoration pending')
        local panels = host.panels()
        local target, source = panels[destination], panels[source_kind]
        assert(target and target.document and source and source.document, 'Load both gear palettes before copying')
        local d, s = target.document, source.document
        assert(d.width == s.width, 'Palette columns differ')
        local proof = host.proof()
        local original = host.original(host.groups()[target.group].object)
        if target.kind == 'cape' then
            assert(
                proof and proof.cape and original and original.resource,
                'Current Cape identity is still loading; load current colors again'
            )
        end
        host.commit_copy_target(d, {
            kind = target.kind or destination,
            container = destination,
            key = target.key,
            group = target.group,
            cape_proof = target.kind == 'cape' and proof and proof.cape or nil,
            resource = original and original.resource,
        })
        host.sync_palette()
        local rows = modules.basic_state.copy(d, s)
        host.preview(d, d.revision - 1)
        host.sync_palette()
        return host.message(
            'Copied '
                .. rows
                .. ' rows from '
                .. source_kind
                .. ' to '
                .. destination
                .. '. Live colors update automatically.'
        )
    end
    function self.copy_helmet_all()
        assert(host.stop_identification(), 'Highlight restoration pending')
        host.refresh()
        local panel = host.panels().helmet
        local source = assert(panel and panel.document, 'Load Helmet colors first')
        local plans = {}
        for index, group in ipairs(host.groups()) do
            if group.armor then
                local targets = {}
                local original
                for _, b in ipairs(group.bindings) do
                    if b.armor then
                        targets[#targets + 1] = b
                        original = original
                            or host.basic_document('armor:' .. tostring(b.original))
                            or b.document
                            or (host.original(b.original))
                    end
                end
                assert(original, 'Armor LUT ' .. index .. ' colors unavailable; no palettes copied')
                assert(original.width == source.width, 'Armor LUT columns differ; no palettes copied')
                local data = buffers.new(original.width * original.height * 4)
                buffers.copy(data, original.data, original.width * original.height * 4)
                buffers.copy(data, source.data, math.min(original.height, source.height) * original.width * 4)
                plans[#plans + 1] = {
                    targets = targets,
                    document = {
                        data = data,
                        width = original.width,
                        height = original.height,
                        source = 'Copied Helmet',
                        revision = (original.revision or 0) + 1,
                    },
                }
            end
        end
        assert(#plans > 0, 'No worn Armor LUTs found')
        host.resume()
        for _, plan in ipairs(plans) do
            host.apply_bindings(plan.document, plan.targets)
            for _, b in ipairs(plan.targets) do
                host.remember_document('armor:' .. tostring(b.original), plan.document)
            end
        end
        host.commit_copied_armor()
        return host.message('Copied Helmet palette to all ' .. #plans .. ' Armor LUTs and applied live.')
    end
    return self
end
return G
