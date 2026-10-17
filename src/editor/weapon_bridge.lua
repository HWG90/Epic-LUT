-- Connect the weapon runtime to the shared editor and the Weapons workspace.
-- Controller callbacks own UI/persistence; runtime owns validated native writes.
local B = {}
local names = { 'Primary', 'Secondary', 'Support' }
local function family(value)
    return value == 'pattern' and 'pattern' or 'material'
end
function B.new(m, host)
    assert(
        m.weapon_runtime and m.weapon_discovery and m.primary_identity and m.weapon_controller,
        'Weapon editor modules unavailable'
    )
    local self, runtime, discovery, controller, identity = {}, nil, nil, nil, nil
    local status, elapsed, recovery = 'Load current weapons to begin.', 0, {}
    local function get_runtime()
        if runtime then
            return runtime
        end
        local memory, native = host.memory(), host.native()
        identity = m.primary_identity.new({
            avatar = m.avatar,
            module = function(name)
                local module = memory.module(name)
                return module and memory.address(module)
            end,
            read = function(address, size)
                return memory.read(require('ffi').cast('const uint8_t *', address), size)
            end,
            verify_build = memory.verify_build,
        })
        discovery = m.weapon_discovery.new(assert(host.engine()), {
            identity = identity,
            native = native,
            remote_authorized = host.remote_authorized,
            read = function(address, size)
                return memory.read(require('ffi').cast('const uint8_t *', address), size)
            end,
        })
        runtime = m.weapon_runtime.new({
            discovery = discovery,
            binding_session = m.binding_session,
            retain = host.retain(),
            cohort = host.cohort(),
            document = function(object, binding, kind)
                return host.original(object, binding, kind)
            end,
            bind = host.bind,
            create_texture = host.create_texture,
            validate_document = host.validate_document,
        })
        return runtime
    end
    local function source_group(target)
        assert(type(target) == 'table' and target.kind == 'weapon', 'Choose a weapon LUT')
        local active = get_runtime()
        local kind, index = family(target.family), assert(target.group_index, 'Weapon group unavailable')
        local group = assert(active.groups(target.weapon_slot, kind)[index], 'Weapon LUT disappeared')
        assert(
            group.weapon_resource == target.weapon_resource and group.object == target.object,
            'Weapon LUT identity changed; load current weapons again'
        )
        local expected, chosen, wanted = {}, {}, {}
        local scope = target.group_bindings or target.bindings or { target }
        assert(type(scope) == 'table' and #scope == #group.bindings, 'Weapon group scope changed')
        for _, binding in ipairs(scope) do
            assert(not expected[binding.save_key], 'Duplicate weapon group destination')
            expected[binding.save_key] = binding
        end
        for _, binding in ipairs(target.bindings or { target }) do
            assert(expected[binding.save_key] and not wanted[binding.save_key], 'Invalid weapon target subset')
            local full = expected[binding.save_key]
            for _, field in ipairs({ 'unit', 'mesh', 'material', 'original', 'slot' }) do
                assert(binding[field] == full[field], 'Weapon target subset identity changed')
            end
            wanted[binding.save_key] = true
        end
        assert(next(wanted), 'Choose a weapon destination')
        for _, binding in ipairs(group.bindings) do
            local saved = assert(expected[binding.save_key], 'Weapon destination changed')
            assert(
                saved.unit == binding.unit
                    and saved.mesh == binding.mesh
                    and saved.material == binding.material
                    and saved.original == binding.original
                    and saved.slot == binding.slot,
                'Weapon binding changed; load current weapons again'
            )
            assert(
                discovery.present(binding) and discovery.binding(binding) == binding.current,
                'Weapon LUT binding changed'
            )
            if wanted[binding.save_key] then
                chosen[#chosen + 1] = binding
            end
        end
        return active, group, index, kind, chosen
    end
    function self.check(target)
        source_group(target)
        return true
    end
    local highlight
    function self.highlighting()
        return highlight ~= nil
    end
    function self.stop_highlight()
        if not highlight then
            return true
        end
        local remaining = {}
        for _, item in ipairs(highlight.items) do
            local b = item.binding
            if discovery.present(b) then
                local current = discovery.binding(b)
                if current == item.object or current == item.flash then
                    local ok = pcall(function()
                        host.bind(b, item.object)
                        assert(discovery.binding(b) == item.object, 'Weapon highlight restoration pending')
                        b.current, b.texture, b.document = item.object, item.texture, item.document
                    end)
                    if not ok then
                        remaining[#remaining + 1] = item
                    end
                end
            end
        end
        highlight.items = remaining
        highlight = #remaining > 0 and highlight or nil
        return highlight == nil
    end
    function self.identify(target, row)
        assert(self.stop_highlight(), 'Previous weapon highlight restoration pending')
        local active, group, index, kind, chosen = source_group(target)
        local loaded = active.load(target.weapon_slot, index, kind)
        assert(type(row) == 'number' and row % 1 == 0 and row >= 1 and row <= loaded.height, 'Invalid weapon region')
        local ffi, plans, variants, items = require('ffi'), {}, {}, {}
        local cache = {
            document = group.document,
            preview = group.preview_document,
            bindings = group.binding_documents,
            mixed = group.mixed,
        }
        for _, b in ipairs(chosen) do
            local source = assert(b.document or group.source_document, 'Original weapon colors unavailable')
            local bytes = ffi.string(source.data, source.width * source.height * 16)
            local plan = variants[bytes]
            if not plan then
                local data = ffi.new('float[?]', source.width * source.height * 4)
                ffi.copy(data, source.data, source.width * source.height * 16)
                for _, column in ipairs(source.width == 23 and { 1, 3, 6, 7, 13, 17, 18, 19, 20 } or { 1 }) do
                    local at = ((row - 1) * source.width + column - 1) * 4
                    data[at], data[at + 1], data[at + 2] = 1, 0, 1
                end
                plan = {
                    weapon_slot = target.weapon_slot,
                    weapon_resource = target.weapon_resource,
                    index = index,
                    family = kind,
                    document = { data = data, width = source.width, height = source.height },
                    targets = {},
                }
                variants[bytes], plans[#plans + 1] = plan, plan
            end
            plan.targets[#plan.targets + 1] = b
            items[#items + 1] = { binding = b, object = b.current, texture = b.texture, document = b.document }
        end
        -- One atomic plan validates all LODs and material privacy before allocation.
        -- Temporary appearance must never enter history, presets or shared pixels.
        active.apply_plan(plans, nil, true)
        for _, item in ipairs(items) do
            local b = item.binding
            item.flash = b.current
            b.texture, b.document = item.texture, item.document
        end
        group.document, group.preview_document, group.binding_documents, group.mixed =
            cache.document, cache.preview, cache.bindings, cache.mixed
        highlight = { items = items, remaining = 4, elapsed = 0, on = true, context = host.context and host.context() }
        return host.message('Flashing weapon region ' .. row .. ' for 4 seconds; prior bindings restore automatically.')
    end
    function self.tick_highlight(dt, visible)
        local job = highlight
        if not job then
            return
        end
        local delta = math.max(0, tonumber(dt) or 0)
        job.remaining, job.elapsed = job.remaining - delta, job.elapsed + delta
        if job.remaining <= 0 or visible == false or host.context and host.context() ~= job.context then
            return self.stop_highlight()
        end
        local on = math.floor(job.elapsed * 4) % 2 == 0
        if on == job.on then
            return
        end
        local ok = pcall(discovery.with_validation_batch or function(fn)
            return fn()
        end, function()
            for _, item in ipairs(job.items) do
                local b = item.binding
                local expected = job.on and item.flash or item.object
                assert(discovery.present(b) and discovery.binding(b) == expected, 'Weapon highlight target changed')
                local object = on and item.flash or item.object
                host.bind(b, object)
                assert(discovery.binding(b) == object, 'Weapon highlight binding failed')
                b.current = object
            end
        end)
        job.on = on
        if not ok then
            self.stop_highlight()
        end
    end
    function self.snapshot()
        local out = {
            weapons = {},
            status = status,
            busy = host.busy and host.busy() or false,
            imports = host.imports and host.imports(),
            presets = host.presets and host.presets(),
            shared = host.shared and host.shared(),
        }
        if not runtime then
            return out
        end
        for slot = 1, 3 do
            local catalog = runtime.catalog(slot)
            if catalog then
                local resource = catalog.weapon_resource or catalog.weapon_resource64
                local weapon = {
                    resource = resource,
                    name = host.weapon_name and host.weapon_name(slot, resource) or names[slot],
                    main = {},
                    pattern = {},
                    status = catalog.available and 'ready' or 'loading',
                    reason = catalog.reason,
                }
                if not catalog.available and tostring(catalog.reason):find('slot is empty', 1, true) then
                    weapon.status = 'absent'
                end
                for _, kind in ipairs({ 'material', 'pattern' }) do
                    for index, group in ipairs(runtime.groups(slot, kind)) do
                        local document, load_error = group.preview_document or group.document, nil
                        if not document then
                            local ok, value = pcall(runtime.load, slot, index, kind)
                            if ok then
                                document = value
                            else
                                load_error = tostring(value)
                            end
                        end
                        local targets = {}
                        for _, binding in ipairs(group.bindings) do
                            local target = {}
                            for key, value in pairs(binding) do
                                target[key] = value
                            end
                            target.weapon_resource = resource
                            target.index, target.group_index, target.object = index, index, group.object
                            targets[#targets + 1] = target
                        end
                        local label = kind == 'pattern' and ('Pattern LUT ' .. index) or ('Material LUT ' .. index)
                        local item = {
                            id = slot .. ':' .. kind .. ':' .. index .. ':' .. tostring(group.object),
                            label = label,
                            document = document,
                            binding_documents = document and document.binding_documents or group.binding_documents,
                            reason = load_error,
                            targets = targets,
                            group_index = index,
                            verified_shape = document
                                and document.data ~= nil
                                and document.width == (kind == 'pattern' and 3 or 23)
                                and (kind ~= 'pattern' or document.height == 1),
                        }
                        local list = kind == 'pattern' and weapon.pattern or weapon.main
                        list[#list + 1] = item
                    end
                end
                out.weapons[slot] = weapon
            end
        end
        return out
    end
    function self.load_current()
        assert(self.stop_highlight(), 'Weapon highlight restoration pending')
        local active, count = get_runtime(), 0
        for slot = 1, 3 do
            local catalog = active.refresh(slot)
            if catalog then
                count = count + #catalog.material + #catalog.pattern
            end
        end
        status = count > 0 and ('Found ' .. count .. ' weapon LUT tables.') or 'Weapons are not ready yet.'
        if controller then
            controller.sync()
        end
        host.message(status)
        return count > 0
    end
    function self.apply(target, document)
        assert(self.stop_highlight(), 'Weapon highlight restoration pending')
        local function apply()
            local active, group, index, kind, chosen = source_group(target)
            local count, texture
            if #chosen == #group.bindings then
                count, texture = active.apply(document, target.weapon_slot, index, kind)
            else
                local result = active.apply_plan({
                    {
                        weapon_slot = target.weapon_slot,
                        weapon_resource = target.weapon_resource,
                        index = index,
                        family = kind,
                        document = document,
                        targets = chosen,
                    },
                })
                assert(result and #result == 1, 'Weapon runtime did not report the selected subset')
                count, texture = result[1].count, result[1].texture
            end
            status = 'Applied ' .. names[target.weapon_slot] .. ' LUT to ' .. count .. ' bindings.'
            if controller then
                controller.sync()
            end
            host.message(status)
            return count, texture
        end
        return (host.mutate or function(fn)
            return fn()
        end)(apply)
    end
    function self.restore(target)
        assert(self.stop_highlight(), 'Weapon highlight restoration pending')
        local function restore()
            local active, restored = get_runtime()
            if target and active.apply_plan and active.all_owned then
                local _, _, _, _, chosen = source_group(target)
                local owned, changed = {}, {}
                for _, binding in ipairs(active.all_owned()) do
                    owned[binding] = true
                end
                for _, binding in ipairs(chosen) do
                    if owned[binding] and binding.current ~= binding.original then
                        changed[#changed + 1] = binding
                    end
                end
                active.apply_plan({}, changed)
                restored = true
            else
                if target then
                    source_group(target)
                end
                restored = active.restore(target and target.weapon_slot)
            end
            assert(restored, 'Weapon restoration is pending')
            if target then
                recovery[target.weapon_slot] = nil
            else
                recovery = {}
            end
            status = 'Restored original weapon LUTs.'
            host.message(status)
            if controller then
                controller.sync()
            end
            return true
        end
        return (host.mutate or function(fn)
            return fn()
        end)(restore)
    end
    function self.open(document, target, cell)
        assert(self.stop_highlight(), 'Weapon highlight restoration pending')
        source_group(target)
        assert(document and document.data, 'Weapon LUT pixels are loading')
        local active, group, index, kind, chosen = source_group(target)
        local copy = active.load(target.weapon_slot, index, kind, #chosen < #group.bindings and chosen or nil)
        host.load_editor(copy, target)
        return host.open_editor(cell or { target = target })
    end
    local poll_slot = 1
    function self.update(dt)
        if not runtime then
            return
        end
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.2 / 3 then
            return
        end
        elapsed = 0
        local prior = {}
        for slot = poll_slot, poll_slot do
            local catalog = runtime.catalog(slot)
            if catalog and catalog.available then
                local candidate = {
                    resource = catalog.weapon_resource or catalog.weapon_resource64,
                    bindings = {},
                    applied = false,
                }
                for _, kind in ipairs({ 'material', 'pattern' }) do
                    for _, group in ipairs(catalog[kind]) do
                        for _, binding in ipairs(group.bindings) do
                            candidate.bindings[#candidate.bindings + 1] = binding
                            candidate.applied = candidate.applied
                                or binding.current ~= binding.original and binding.document ~= nil
                        end
                    end
                end
                prior[slot] = candidate
            end
        end
        -- Spread the three native identity/material scans over separate frames.
        -- Each equipped slot retains the same polling cadence.
        local changed = runtime.update(poll_slot)
        poll_slot = poll_slot % 3 + 1
        if #changed > 0 then
            status = 'Weapon changed; load current weapons again.'
            host.invalidate(changed)
            for _, slot in ipairs(changed) do
                local candidate = prior[slot]
                if candidate and candidate.applied and not recovery[slot] then
                    recovery[slot] = candidate
                end
            end
        end
        for slot, candidate in pairs(recovery) do
            local dead, foreign, present, all_present, reset = true, false, false, true, false
            for _, binding in ipairs(candidate.bindings) do
                dead = discovery.dead(binding) == true and dead
                local live = discovery.present(binding)
                present, all_present = present or live, all_present and live
                if live then
                    local current = discovery.binding(binding)
                    foreign = foreign or (current ~= binding.current and current ~= binding.original)
                    reset = reset or (binding.current ~= binding.original and current == binding.original)
                end
            end
            if foreign then
                -- An external writer owns this change. A later death must not
                -- turn it into permission to restore our earlier draft.
                recovery[slot] = nil
            elseif dead or (all_present and reset) or not present then
                local current = identity.snapshot(slot)
                local resource = current and (current.weapon_resource or current.weapon_resource64)
                if resource and resource ~= candidate.resource then
                    recovery[slot] = nil
                elseif resource then
                    local ok, catalog, count = pcall(runtime.recovery, slot, true)
                    if ok and catalog then
                        recovery[slot] = nil
                        if count > 0 then
                            status = 'Recovered ' .. names[slot] .. ' LUTs after weapon reload.'
                            host.message(status)
                        end
                        if controller then
                            controller.sync()
                        end
                    elseif not ok and not tostring(catalog):find('Original weapon LUT pixels unavailable', 1, true) then
                        recovery[slot] = nil
                        error(catalog, 0)
                    end
                end
            end
        end
    end
    function self.runtime()
        return get_runtime()
    end
    function self.recovery_pending(slot)
        return recovery[slot] ~= nil
    end
    function self.discovery()
        get_runtime()
        return discovery
    end
    function self.remote_snapshot(peer, slot)
        get_runtime()
        return identity.snapshot_remote(peer, slot)
    end
    function self.descriptors(targets)
        local active, out, selected = get_runtime(), {}, {}
        if targets then
            for _, target in ipairs(targets) do
                source_group(target)
                selected[target.weapon_slot .. ':' .. family(target.family) .. ':' .. target.group_index] = true
            end
        end
        for slot = 1, 3 do
            for _, kind in ipairs({ 'material', 'pattern' }) do
                for index, group in ipairs(active.groups(slot, kind)) do
                    if not targets or selected[slot .. ':' .. kind .. ':' .. index] then
                        active.load(slot, index, kind)
                        out[#out + 1] = {
                            index = index,
                            family = kind,
                            weapon_slot = slot,
                            weapon_resource = group.weapon_resource or group.weapon_resource64,
                            source_resource = group.source_resource,
                            bindings = group.bindings,
                        }
                    end
                end
            end
        end
        return out
    end
    function self.close(allow_quarantine)
        local flash_restored = self.stop_highlight()
        recovery = {}
        if not runtime then
            return true
        end
        local ok, restored = pcall(runtime.restore)
        if not ok or not restored then
            status = 'Weapon restoration could not be certified; its texture allocations remain retained.'
        end
        return allow_quarantine == true or flash_restored and ok and restored
    end
    function self.controller()
        if controller then
            return controller
        end
        local actions = {
            snapshot = self.snapshot,
            selection_changed = function(state)
                if host.follow_selection and host.follow_selection() then
                    if state.target and state.document then
                        return self.open(state.document, state.target)
                    end
                    if host.selection_unavailable then
                        host.selection_unavailable()
                    end
                end
                return true
            end,
            load_current = self.load_current,
            apply = self.apply,
            restore = self.restore,
            load_editor = function(document, target)
                source_group(target)
                host.load_editor(document, target)
                return true
            end,
            open_editor = host.open_editor,
            open_pattern = function(document, target, cell)
                return self.open(document, target, cell)
            end,
            edit_rgb = function(row, target, document)
                return self.open(document, target, { row = row, column = 1, target = target, picker = true })
            end,
            edit_camo = function(row, color, target, document)
                return self.open(document, target, { row = row, column = 16 + color, target = target, picker = true })
            end,
            edit_pattern = function(channel, target, document, options)
                return self.open(document, target, {
                    row = 1,
                    column = channel,
                    target = target,
                    picker = true,
                    alpha_only = options and options.alpha_only,
                })
            end,
        }
        for _, name in ipairs({ 'import', 'map_imports', 'apply_preset', 'save_preset', 'export', 'share' }) do
            actions[name] = host[name]
        end
        if m.basic_camo then
            actions.camo_choices = m.basic_camo.CHOICES
            actions.camo_colorways = { 'Current / custom' }
            for _, palette in ipairs(m.basic_camo.COLORWAYS) do
                actions.camo_colorways[#actions.camo_colorways + 1] = palette.name
            end
            actions.camo_state = function(document, rows)
                return {
                    pattern = m.basic_camo.selection(document, 'weapon', rows),
                    colorway = m.basic_camo.colorway_selection(document, 'weapon', rows),
                }
            end
            actions.apply_camo = function(target, document, rows, choice, mode)
                return (host.mutate or function(fn)
                    return fn()
                end)(function()
                    source_group(target)
                    local copy = m.weapon_mapping.copy(document)
                    local result = m.basic_camo.apply(copy, choice, mode, nil, 'weapon', rows)
                    self.apply(target, copy)
                    host.load_editor(copy, target)
                    controller.sync()
                    return host.message(result)
                end)
            end
        end
        controller = m.weapon_controller.new(actions)
        return controller
    end
    return self
end
return B
