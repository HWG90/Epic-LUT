-- Weapon workspace state and actions. Native ownership belongs to the host.
local C = { SLOT_NAMES = { 'Primary', 'Secondary', 'Support' } }
local function integer(value, maximum)
    return type(value) == 'number' and value % 1 == 0 and value >= 0 and value <= maximum
end
local function copy(value)
    local result = {}
    for key, entry in pairs(value) do
        result[key] = entry
    end
    return result
end
local function descriptor(value, slot, resource, family)
    assert(type(value) == 'table' and value.kind == 'weapon', 'Weapon destination unavailable')
    assert(value.weapon_slot == slot and value.weapon_resource == resource, 'Weapon destination identity changed')
    local a, b, c = tostring(value.save_key):match('^3:(%d+):(%d+):(%d+)$')
    assert(
        tonumber(a) == slot and integer(tonumber(b), 511) and integer(tonumber(c), 63),
        'Invalid weapon destination key'
    )
    assert(value.mesh_index == nil or value.mesh_index == tonumber(b), 'Weapon mesh/key differs')
    assert(value.material_index == nil or value.material_index == tonumber(c), 'Weapon material/key differs')
    local result = copy(value)
    result.family, result.mesh_index, result.material_index = family, tonumber(b), tonumber(c)
    return result
end
function C.new(host)
    assert(type(host) == 'table' and type(host.snapshot) == 'function', 'Weapon workspace host unavailable')
    local self = { weapon_slot = 1, family = 'main', selected_weapons = { true, false, false }, selected = {} }
    local registry, handle, syncing
    local function target(group, slot, weapon, family)
        assert(
            type(weapon.resource) == 'string' and #weapon.resource == 16 and weapon.resource:match('^%x+$'),
            'Invalid weapon resource ID'
        )
        assert(
            type(group.targets) == 'table' and #group.targets >= 1 and #group.targets <= 512,
            'Weapon LUT destinations unavailable'
        )
        local bindings, seen = {}, {}
        for _, source in ipairs(group.targets) do
            local entry = descriptor(source, slot, weapon.resource, family)
            assert(not seen[entry.save_key], 'Duplicate weapon LUT destination')
            seen[entry.save_key], bindings[#bindings + 1] = true, entry
        end
        local result = copy(bindings[1])
        result.bindings, result.group_id = bindings, group.id or group.label or group
        result.group_bindings = bindings
        local keys = {}
        for _, binding in ipairs(bindings) do
            keys[#keys + 1] = binding.save_key
        end
        table.sort(keys)
        result.scope_id = table.concat(keys, '|')
        result.label, result.document = group.label, group.document
        return result
    end
    local function groups_for(weapon, family)
        local groups = weapon and weapon[family] or {}
        assert(type(groups) == 'table' and #groups <= 64, 'Weapon LUT group bounds changed')
        return groups
    end
    local function pick(weapon, slot, family)
        local groups = groups_for(weapon, family)
        local selected = self.selected[slot .. ':' .. family]
        local index = 1
        for i, group in ipairs(groups) do
            if (group.id or group.label or group) == selected then
                index = i
            end
        end
        return groups[index], groups, index
    end
    local function pattern_for(state)
        local weapon = state.weapon
        if not weapon or weapon.status ~= 'ready' then
            return
        end
        local group = pick(weapon, self.weapon_slot, 'pattern')
        if self.family == 'main' and state.target then
            local keys = {}
            for _, binding in ipairs(state.target.bindings) do
                keys[binding.save_key] = true
            end
            group = nil
            local matching, remembered = {}, self.selected[self.weapon_slot .. ':pattern']
            for _, candidate in ipairs(groups_for(weapon, 'pattern')) do
                local members = {}
                for _, binding in ipairs(candidate.targets or {}) do
                    if keys[binding.save_key] then
                        members[#members + 1] = binding
                    end
                end
                if #members > 0 then
                    matching[#matching + 1] = { group = candidate, members = members }
                end
            end
            local chosen = matching[1]
            for _, candidate in ipairs(matching) do
                if (candidate.group.id or candidate.group.label or candidate.group) == remembered then
                    chosen = candidate
                end
            end
            if chosen then
                group = chosen.group
                local selected = target(group, self.weapon_slot, weapon, 'pattern')
                local wanted, members, scope = {}, {}, {}
                for _, binding in ipairs(chosen.members) do
                    wanted[binding.save_key] = true
                end
                for _, binding in ipairs(selected.bindings) do
                    if wanted[binding.save_key] then
                        members[#members + 1], scope[#scope + 1] = binding, binding.save_key
                    end
                end
                for key, value in pairs(members[1]) do
                    selected[key] = value
                end
                selected.bindings = members
                table.sort(scope)
                selected.scope_id = table.concat(scope, '|')
                selected.save_key = members[1].save_key
                return group, selected
            end
        end
        if group then
            return group, target(group, self.weapon_slot, weapon, 'pattern')
        end
    end
    function self.state()
        local source = host.snapshot() or {}
        local weapons = source.weapons or {}
        local weapon = weapons[self.weapon_slot]
        local state = {
            weapons = weapons,
            weapon = weapon,
            weapon_slot = self.weapon_slot,
            family = self.family,
            status = source.status,
            busy = source.busy == true,
            imports = source.imports,
            presets = source.presets,
            shared = source.shared,
            selected_weapons = self.selected_weapons,
        }
        if weapon and weapon.status == 'ready' then
            state.group, state.groups, state.group_index = pick(weapon, self.weapon_slot, self.family)
            if state.group then
                state.document = state.group.document
                state.target = target(state.group, self.weapon_slot, weapon, self.family)
                state.quick_ready = self.family == 'main'
                    and state.document
                    and state.document.width == 23
                    and integer(state.document.height, 64)
                    and state.document.height >= 1
                    and state.document.data ~= nil
                    and not state.document.stale
                    and not state.document.read_only
                    and (state.group.verified_shape == true or state.group.verified == true)
            end
            state.pattern_group, state.pattern_target = pattern_for(state)
            state.pattern_document = state.pattern_group and state.pattern_group.document
            if state.pattern_target and state.pattern_group.binding_documents then
                local first = state.pattern_target.bindings[1]
                state.pattern_document = state.pattern_group.binding_documents[first.save_key] or state.pattern_document
            end
            local d, g = state.pattern_document, state.pattern_group
            state.pattern_ready = d
                and d.width == 3
                and d.height == 1
                and d.data ~= nil
                and not d.stale
                and not d.read_only
                and (g.verified_shape == true or g.verified == true)
        else
            state.groups = {}
        end
        return state
    end
    local camo_rows = {}
    local function camo_key(state)
        return state.target
            and state.target.weapon_slot .. ':' .. state.target.weapon_resource .. ':' .. state.target.group_id
    end
    function self.camo_selection()
        local state = self.state()
        local key = camo_key(state)
        return key and camo_rows[key] or {}
    end
    function self.toggle_camo_row(row, enabled)
        local state = self.state()
        assert(state.quick_ready and integer(row, state.document.height) and row >= 1, 'Choose a current material row')
        local key = camo_key(state)
        camo_rows[key] = camo_rows[key] or {}
        camo_rows[key][row] = enabled == true or nil
        self.sync()
        return true
    end
    function self.select_camo_rows(enabled)
        local state = self.state()
        assert(state.quick_ready, 'Choose a current material LUT')
        local rows = {}
        if enabled then
            for row = 1, state.document.height do
                rows[row] = true
            end
        end
        camo_rows[camo_key(state)] = rows
        self.sync()
        return true
    end
    local function current(expected, pattern)
        local state = self.state()
        assert(not state.busy, 'Weapons are loading')
        local selected = pattern and state.pattern_target or state.target
        assert(selected, 'No current weapon LUT selected')
        if expected then
            assert(
                expected.weapon_slot == selected.weapon_slot
                    and expected.weapon_resource == selected.weapon_resource
                    and expected.family == selected.family
                    and expected.group_id == selected.group_id
                    and (expected.scope_id == nil or expected.scope_id == selected.scope_id),
                'Weapon selection changed'
            )
        end
        return state, selected, pattern and state.pattern_document or state.document
    end
    local function invoke(name, ...)
        assert(type(host[name]) == 'function', 'Weapon action unavailable: ' .. name)
        return host[name](...)
    end
    function self.available(name)
        return type(host[name]) == 'function'
    end
    function self.choose_slot(slot)
        assert(integer(slot, 3) and slot >= 1, 'Invalid weapon slot')
        self.weapon_slot, self.selected_weapons[slot] = slot, true
        self.sync()
        return true
    end
    function self.choose_family(value)
        local family = value == 1 and 'main' or value == 2 and 'pattern' or value
        assert(family == 'main' or family == 'pattern', 'Invalid weapon LUT family')
        self.family = family
        self.sync()
        return true
    end
    function self.choose_group(index)
        local state = self.state()
        assert(integer(index, #state.groups) and index >= 1, 'Invalid weapon LUT choice')
        local group = state.groups[index]
        self.selected[self.weapon_slot .. ':' .. self.family] = group.id or group.label or group
        self.sync()
        return true
    end
    function self.toggle_weapon(slot, enabled)
        assert(integer(slot, 3) and slot >= 1, 'Invalid weapon slot')
        local weapon = (host.snapshot().weapons or {})[slot]
        assert(not enabled or weapon and weapon.status == 'ready', 'Weapon is not available')
        self.selected_weapons[slot] = enabled == true
        return true
    end
    function self.targets()
        local source, result = host.snapshot() or {}, {}
        assert(not source.busy, 'Weapons are loading')
        for slot = 1, 3 do
            local weapon = (source.weapons or {})[slot]
            if self.selected_weapons[slot] and weapon and weapon.status == 'ready' then
                for _, family in ipairs({ 'main', 'pattern' }) do
                    for _, group in ipairs(groups_for(weapon, family)) do
                        result[#result + 1] = target(group, slot, weapon, family)
                    end
                end
            end
        end
        assert(#result > 0, 'Select an available weapon first')
        return result
    end
    function self.load_current()
        return invoke('load_current')
    end
    function self.open_editor(row, column, expected)
        local state, selected, document = current(expected)
        assert(document and document.data, 'Weapon LUT data unavailable')
        if row ~= nil then
            assert(integer(row, document.height) and row >= 1, 'Invalid weapon LUT row')
        end
        if column ~= nil then
            assert(integer(column, document.width) and column >= 1, 'Invalid weapon LUT column')
        end
        if state.family == 'pattern' then
            assert(state.pattern_ready, 'Verified 3 x 1 Pattern LUT required')
            return invoke('open_pattern', document, selected, { row = row, column = column, target = selected })
        end
        local loaded, why = invoke('load_editor', document, selected)
        if loaded == false then
            return false, why
        end
        return invoke('open_editor', { row = row, column = column, target = selected })
    end
    function self.edit_rgb(row, expected)
        local state, selected, document = current(expected)
        assert(
            state.quick_ready and integer(row, state.document.height) and row >= 1,
            'Verified 23-column weapon LUT required'
        )
        return invoke('edit_rgb', row, selected, document)
    end
    function self.edit_camo(row, color, expected)
        local state, selected, document = current(expected)
        assert(
            state.quick_ready and integer(row, state.document.height) and row >= 1 and integer(color, 4) and color >= 1,
            'Verified weapon camo cell required'
        )
        return invoke('edit_camo', row, color, selected, document)
    end
    function self.edit_pattern(channel, expected)
        local state, selected, document = current(expected, true)
        assert(state.pattern_ready and integer(channel, 3) and channel >= 1, 'Verified 3 x 1 Pattern LUT required')
        return invoke('edit_pattern', channel, selected, document, { alpha_only = channel == 3 })
    end
    function self.open_pattern(expected)
        local state, selected, document = current(expected, true)
        assert(state.pattern_ready, 'Verified 3 x 1 Pattern LUT required')
        return invoke('open_pattern', document, selected)
    end
    function self.apply(expected)
        local _, selected, document = current(expected)
        return invoke('apply', selected, document)
    end
    function self.restore(expected)
        local _, selected = current(expected)
        return invoke('restore', selected)
    end
    function self.import()
        return invoke('import')
    end
    function self.map_imports(auto)
        return invoke('map_imports', self.targets(), { auto = auto == true, rollover = true })
    end
    function self.apply_camo(choice, mode)
        if choice == 1 then
            return true
        end
        local _, selected, document = current()
        local rows = self.camo_selection()
        assert(next(rows), 'Check at least one Camo row first')
        return invoke('apply_camo', selected, document, rows, choice, mode)
    end
    function self.apply_preset()
        return invoke('apply_preset', self.targets())
    end
    function self.save_preset()
        return invoke('save_preset', self.targets())
    end
    function self.export()
        return invoke('export', self.targets())
    end
    function self.share()
        return invoke('share', self.targets())
    end
    function self.controls()
        local controls = {
            {
                id = 'weapon_slot',
                type = 'choice',
                label = 'Weapon',
                choices = C.SLOT_NAMES,
                default = 1,
                on_change = function(value)
                    if not syncing then
                        local ok, why = self.choose_slot(value)
                        if ok and host.selection_changed then
                            return host.selection_changed(self.state())
                        end
                        return ok, why
                    end
                end,
            },
            {
                id = 'weapon_family',
                type = 'choice',
                label = 'LUT family',
                choices = { 'Material LUTs', 'Pattern LUTs' },
                default = 1,
                on_change = function(value)
                    if not syncing then
                        local ok, why = self.choose_family(value)
                        if ok and host.selection_changed then
                            return host.selection_changed(self.state())
                        end
                        return ok, why
                    end
                end,
            },
            {
                id = 'weapon_lut',
                type = 'choice',
                presentation = 'dropdown',
                label = 'Weapon LUT',
                choices = { 'Load Current Weapons' },
                default = 1,
                on_change = function(value)
                    if not syncing then
                        local ok, why = self.choose_group(value)
                        if ok and host.selection_changed then
                            return host.selection_changed(self.state())
                        end
                        return ok, why
                    end
                end,
            },
        }
        if host.apply_camo and host.camo_choices then
            for _, spec in ipairs({
                { 'weapon_camo_pattern', 'Camo pattern', host.camo_choices, nil },
                { 'weapon_camo_colorway', 'Camo colorway', host.camo_colorways, 'colorway' },
            }) do
                local id, label, choices, mode = unpack(spec)
                controls[#controls + 1] = {
                    id = id,
                    type = 'choice',
                    label = label,
                    choices = choices,
                    default = 1,
                    on_change = function(value)
                        if not syncing then
                            return self.apply_camo(value, mode)
                        end
                    end,
                }
            end
        end
        return controls
    end
    function self.page()
        return { id = 'weapons', name = 'Weapons', require_confirmation = false, controls = self.controls() }
    end
    function self.attach(attached, controls)
        handle, registry = attached, controls
        self.labels_fingerprint = nil
        self.sync()
    end
    function self.sync()
        if not registry or syncing then
            return
        end
        local state = self.state()
        local labels = {}
        for index, group in ipairs(state.groups or {}) do
            labels[index] = group.label or ('LUT ' .. index)
        end
        if #labels == 0 then
            labels = { state.weapon and state.weapon.status or 'Absent' }
        end
        syncing = true
        local ok, why = pcall(function()
            if registry.weapon_lut then
                local joined = table.concat(labels, '\0')
                if self.labels_fingerprint ~= joined then
                    registry.weapon_lut.choices, self.labels_fingerprint = labels, joined
                end
                registry.weapon_lut.disabled = #state.groups == 0 or state.busy
            end
            if handle and handle.set then
                local function update(id, value)
                    local control = registry[id]
                    if not control or handle.get and handle.get(id) == value then
                        return
                    end
                    local disabled = control.disabled
                    control.disabled = false
                    local saved, result, reason = pcall(handle.set, id, value)
                    control.disabled = disabled
                    assert(saved and result ~= false, reason or result)
                end
                update('weapon_slot', self.weapon_slot)
                update('weapon_family', self.family == 'main' and 1 or 2)
                if registry.weapon_camo_pattern and host.camo_state then
                    local rows = self.camo_selection()
                    local recipe = host.camo_state(state.document, rows)
                    update('weapon_camo_pattern', recipe.pattern)
                    update('weapon_camo_colorway', recipe.colorway)
                    registry.weapon_camo_pattern.disabled = not state.quick_ready or not next(rows)
                    registry.weapon_camo_colorway.disabled = registry.weapon_camo_pattern.disabled
                end
                update('weapon_lut', state.group_index or 1)
            end
        end)
        syncing = false
        assert(ok, why)
    end
    for _, name in ipairs({
        'choose_slot',
        'toggle_camo_row',
        'select_camo_rows',
        'apply_camo',
        'choose_family',
        'choose_group',
        'toggle_weapon',
        'load_current',
        'open_editor',
        'edit_rgb',
        'edit_camo',
        'edit_pattern',
        'open_pattern',
        'apply',
        'restore',
        'import',
        'map_imports',
        'apply_preset',
        'save_preset',
        'export',
        'share',
    }) do
        local action = self[name]
        self[name] = function(...)
            local ok, result, reason = pcall(action, ...)
            if not ok then
                result, reason = false, tostring(result)
            end
            self.error = result == false and tostring(reason or 'Weapon action refused') or nil
            if self.error and type(host.message) == 'function' then
                host.message(self.error)
            end
            return result, reason
        end
    end
    return self
end
return C
