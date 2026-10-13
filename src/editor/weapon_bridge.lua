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
        local expected = {}
        for _, binding in ipairs(target.bindings or { target }) do
            expected[binding.save_key] = binding
        end
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
        end
        return active, group, index, kind
    end
    function self.check(target)
        source_group(target)
        return true
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
                        local document, load_error = group.document, nil
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
        local active, _, index, kind = source_group(target)
        local count, texture = active.apply(document, target.weapon_slot, index, kind)
        status = 'Applied ' .. names[target.weapon_slot] .. ' LUT to ' .. count .. ' bindings.'
        host.message(status)
        return count, texture
    end
    function self.restore(target)
        if target then
            source_group(target)
        end
        local restored = get_runtime().restore(target and target.weapon_slot)
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
    function self.open(document, target, cell)
        source_group(target)
        assert(document and document.data, 'Weapon LUT pixels are loading')
        local active, _, index, kind = source_group(target)
        local copy = active.load(target.weapon_slot, index, kind)
        host.load_editor(copy, target)
        return host.open_editor(cell or { target = target })
    end
    function self.update(dt)
        if not runtime then
            return
        end
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.2 then
            return
        end
        elapsed = 0
        local prior = {}
        for slot = 1, 3 do
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
        local changed = runtime.update()
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
            local dead, foreign = true, false
            for _, binding in ipairs(candidate.bindings) do
                dead = discovery.dead(binding) == true and dead
                if discovery.present(binding) and discovery.binding(binding) ~= binding.current then
                    foreign = true
                end
            end
            if foreign then
                -- An external writer owns this change. A later death must not
                -- turn it into permission to restore our earlier draft.
                recovery[slot] = nil
            elseif dead then
                local current = identity.snapshot(slot)
                local resource = current and (current.weapon_resource or current.weapon_resource64)
                if resource and resource ~= candidate.resource then
                    recovery[slot] = nil
                elseif resource then
                    local ok, catalog, count = pcall(runtime.recovery, slot, true)
                    if ok and catalog then
                        recovery[slot] = nil
                        if count > 0 then
                            status = 'Recovered ' .. names[slot] .. ' LUTs after respawn.'
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
        recovery = {}
        if not runtime then
            return true
        end
        local ok, restored = pcall(runtime.restore)
        if not ok or not restored then
            status = 'Weapon restoration could not be certified; its texture allocations remain retained.'
        end
        return allow_quarantine == true or ok and restored
    end
    function self.controller()
        if controller then
            return controller
        end
        local actions = {
            snapshot = self.snapshot,
            load_current = self.load_current,
            apply = self.apply,
            restore = self.restore,
            load_editor = function(document, target)
                source_group(target)
                host.load_editor(document, target)
                return true
            end,
            open_editor = host.open_editor,
            open_pattern = function(document, target)
                return self.open(document, target)
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
        for _, name in ipairs({ 'import', 'map_imports', 'save_preset', 'export', 'share' }) do
            actions[name] = host[name]
        end
        controller = m.weapon_controller.new(actions)
        return controller
    end
    return self
end
return B
