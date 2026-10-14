-- Weapon palette documents and owned main/Pattern binding sessions. The host
-- supplies verified native writes; discovery proves local identity and privacy.
local R = { SLOTS = 3, MATERIAL = 0x7e662968, PATTERN = 0x81d4c49d }
function R.new(deps)
    local ffi = require('ffi')
    local discovery = assert(deps.discovery, 'Weapon discovery service required')
    local factory = assert(deps.binding_session, 'Binding session module required')
    assert(
        type(factory.new) == 'function'
            and type(deps.document) == 'function'
            and type(deps.bind) == 'function'
            and type(deps.create_texture) == 'function'
            and deps.retain
            and deps.cohort,
        'Weapon runtime dependencies unavailable'
    )
    local self, catalogs, sessions, drafts, registered, active = { supports_target_subsets = true }, {}, {}, {}, {}, nil
    local function slot(value)
        assert(type(value) == 'number' and value % 1 == 0 and value >= 1 and value <= R.SLOTS, 'Invalid weapon slot')
        return value
    end
    local function family(value)
        value = value or 'material'
        assert(value == 'material' or value == 'pattern', 'Invalid weapon LUT family')
        return value
    end
    local function key(b)
        return b.unit .. ':' .. b.mesh .. ':' .. b.material .. ':' .. b.slot
    end
    local function document_copy(document)
        local w, h = document.width, document.height
        assert(
            type(w) == 'number'
                and type(h) == 'number'
                and w % 1 == 0
                and h % 1 == 0
                and w >= 1
                and w <= 64
                and h >= 1
                and h <= 64
                and type(document.data) == 'cdata',
            'Invalid weapon LUT document'
        )
        assert(
            ffi.istype('float[?]', document.data) and ffi.sizeof(document.data) >= w * h * 16,
            'Weapon LUT must own its complete float32 array'
        )
        for index = 0, w * h * 4 - 1 do
            local value = tonumber(document.data[index])
            assert(value == value and math.abs(value) ~= math.huge, 'Nonfinite weapon LUT value')
        end
        if deps.validate_document then
            deps.validate_document(document.data, w, h)
        end
        local copied = {}
        for name, value in pairs(document) do
            copied[name] = value
        end
        copied.data = ffi.new('float[?]', w * h * 4)
        ffi.copy(copied.data, document.data, w * h * 16)
        if document.original then
            assert(
                type(document.original) == 'cdata'
                    and ffi.istype('float[?]', document.original)
                    and ffi.sizeof(document.original) >= w * h * 16,
                'Invalid original weapon LUT array'
            )
            copied.original = ffi.new('float[?]', w * h * 4)
            ffi.copy(copied.original, document.original, w * h * 16)
        end
        return copied
    end
    for weapon_slot = 1, R.SLOTS do
        sessions[weapon_slot] = {}
        registered[weapon_slot] = {}
        for _, kind in ipairs({ 'material', 'pattern' }) do
            local known = {}
            registered[weapon_slot][kind] = known
            local function captured(b)
                local original = known[key(b)]
                assert(
                    original
                        and b.unit == original.unit
                        and b.mesh == original.mesh
                        and b.material == original.material
                        and b.slot == original.slot
                        and (b == original or b.original == original.original),
                    'Unknown weapon retirement target'
                )
                return original
            end
            sessions[weapon_slot][kind] = factory.new({
                retain = deps.retain,
                cohort = deps.cohort,
                key = key,
                present = function(b)
                    local ok, original = pcall(captured, b)
                    return ok and discovery.present(original) or false
                end,
                binding = function(b)
                    return discovery.binding(captured(b))
                end,
                dead = function(b)
                    local ok, original = pcall(captured, b)
                    return ok and discovery.dead(original) or false
                end,
                create_texture = deps.create_texture,
                bind = function(b, object)
                    assert(active and active.keys[key(b)], 'Weapon write has no current ownership operation')
                    assert(discovery.present(b), 'Weapon changed during native binding write')
                    deps.bind(b, object)
                end,
            })
        end
    end
    local function operation(targets, callback)
        assert(not active, 'Nested weapon binding operation refused')
        local private, why = discovery.prove_private(targets)
        assert(private, why)
        active = { keys = {}, targets = targets }
        for _, b in ipairs(targets) do
            active.keys[key(b)] = true
        end
        local ok, a, b = pcall(callback)
        active = nil
        if not ok then
            error(a, 0)
        end
        return a, b
    end
    function self.refresh(weapon_slot)
        slot(weapon_slot)
        local receipt, why = discovery.capture(weapon_slot)
        if not receipt then
            catalogs[weapon_slot] = {
                available = false,
                reason = why,
                weapon_slot = weapon_slot,
                material = {},
                pattern = {},
            }
            return nil, why
        end
        local owned = {}
        for _, kind in ipairs({ 'material', 'pattern' }) do
            for _, b in ipairs(sessions[weapon_slot][kind].owned) do
                if discovery.present(b) then
                    local current = discovery.binding(b)
                    assert(
                        current == b.current or current == b.original,
                        'Foreign weapon LUT write detected; restore before refreshing'
                    )
                    if current == b.original then
                        b.current, b.previous, b.texture = b.original, nil, nil
                    end
                    owned[key(b)] = b
                end
            end
        end
        local catalog = {
            available = true,
            weapon_slot = weapon_slot,
            weapon_resource64 = receipt.weapon_resource64,
            weapon_resource = receipt.weapon_resource64,
            unit_resource64 = receipt.unit_resource64,
            receipt = receipt,
            material = {},
            pattern = {},
        }
        local by_family = { material = {}, pattern = {} }
        for _, row in ipairs(discovery.materials(receipt)) do
            for _, kind in ipairs({ 'material', 'pattern' }) do
                local b = discovery.descriptor(receipt, row, kind == 'material' and R.MATERIAL or R.PATTERN)
                if b then
                    local kept = owned[key(b)]
                    b = kept or b
                    registered[weapon_slot][kind][key(b)] = registered[weapon_slot][kind][key(b)] or b
                    local object = b.original
                    local group = by_family[kind][object]
                    if not group then
                        group = {
                            kind = 'weapon',
                            weapon = true,
                            family = kind,
                            weapon_slot = weapon_slot,
                            weapon_resource64 = receipt.weapon_resource64,
                            weapon_resource = receipt.weapon_resource64,
                            object = object,
                            bindings = {},
                        }
                        by_family[kind][object] = group
                        catalog[kind][#catalog[kind] + 1] = group
                    end
                    if kept and kept.current ~= kept.original and kept.document then
                        group.applied_document = group.applied_document or document_copy(kept.document)
                    end
                    group.bindings[#group.bindings + 1] = b
                end
            end
        end
        assert(discovery.validate(receipt), 'Weapon changed during discovery')
        for _, kind in ipairs({ 'material', 'pattern' }) do
            table.sort(catalog[kind], function(a, b)
                return a.object < b.object
            end)
            for group_index, group in ipairs(catalog[kind]) do
                group.index = group_index
                local current_object
                group.mixed, group.binding_documents = false, {}
                for _, b in ipairs(group.bindings) do
                    b.group_index = group_index
                    if current_object and current_object ~= b.current then
                        group.mixed = true
                    end
                    current_object = current_object or b.current
                    if b.current ~= b.original and b.document then
                        group.binding_documents[b.save_key] = document_copy(b.document)
                    end
                end
                if group.mixed then
                    group.applied_document = nil
                end
            end
        end
        catalogs[weapon_slot] = catalog
        return catalog
    end
    function self.catalog(weapon_slot)
        return catalogs[slot(weapon_slot)]
    end
    function self.groups(weapon_slot, kind)
        local catalog = catalogs[slot(weapon_slot)]
        return catalog and catalog[family(kind)] or {}
    end
    local function selected(weapon_slot, selected_index, kind)
        local groups = self.groups(weapon_slot, kind)
        assert(
            type(selected_index) == 'number' and selected_index % 1 == 0 and selected_index >= 1,
            'Invalid weapon LUT selection'
        )
        return assert(groups[selected_index], 'Weapon LUT selection is unavailable')
    end
    local function group_documents(group, chosen)
        local first, signature, mixed, by_key = nil, nil, false, {}
        for _, b in ipairs(chosen or group.bindings) do
            local source = b.current ~= b.original and b.document or group.source_document
            assert(source, 'Weapon binding pixels unavailable')
            local copy = document_copy(source)
            copy.mixed, copy.binding_documents = nil, nil
            local bytes = copy.width
                .. ':'
                .. copy.height
                .. ':'
                .. ffi.string(copy.data, copy.width * copy.height * 16)
            if signature and signature ~= bytes then
                mixed = true
            end
            first, signature = first or copy, signature or bytes
            by_key[b.save_key] = copy
        end
        if not chosen then
            group.mixed, group.binding_documents = mixed, by_key
            group.applied_document = not mixed and first or nil
        end
        return first, by_key, mixed
    end
    function self.load(weapon_slot, selected_index, kind, chosen)
        kind = family(kind)
        local group = selected(slot(weapon_slot), selected_index, kind)
        for _, b in ipairs(group.bindings) do
            assert(discovery.present(b) and discovery.binding(b) == b.current, 'Weapon LUT changed before loading')
        end
        if chosen then
            assert(type(chosen) == 'table' and #chosen > 0 and #chosen <= #group.bindings, 'Weapon load subset bounds')
            local members, seen = {}, {}
            for _, binding in ipairs(group.bindings) do
                members[binding] = true
            end
            for _, binding in ipairs(chosen) do
                assert(members[binding] and not seen[binding], 'Invalid weapon load subset')
                seen[binding] = true
            end
        end
        if not group.source_document then
            local original = deps.document(group.object, group.bindings[1], kind)
            assert(type(original) == 'table', 'Original weapon LUT pixels unavailable')
            group.source_document = document_copy(original)
            group.source_resource = original.resource
        end
        local source, by_key, mixed = group_documents(group, chosen)
        local document = document_copy(source)
        assert(
            kind == 'pattern' and document.width == 3 and document.height == 1
                or kind == 'material' and document.width == 23,
            'Unsupported weapon LUT dimensions'
        )
        document.kind, document.family, document.weapon_slot, document.weapon_resource64 =
            'weapon', kind, weapon_slot, group.weapon_resource64
        document.weapon_resource = group.weapon_resource64
        document.mixed = mixed
        if mixed then
            document.binding_documents = by_key
        end
        if not chosen then
            group.document = not mixed and document or nil
            group.preview_document = document
        end
        group.width, group.height = document.width, document.height
        for _, b in ipairs(group.bindings) do
            b.width, b.height = document.width, document.height
        end
        return document, group
    end
    function self.apply_plan(entries, restore_targets, temporary)
        assert(temporary == nil or temporary == true, 'Invalid temporary weapon plan flag')
        assert(type(entries) == 'table' and #entries <= 3072, 'Weapon application plan bounds')
        local plan, targets, before, seen, material_intents = {}, {}, {}, {}, {}
        for _, entry in ipairs(entries) do
            local weapon_slot, kind = slot(entry.weapon_slot), family(entry.family)
            local group = selected(weapon_slot, entry.index, kind)
            if not group.width then
                self.load(weapon_slot, entry.index, kind)
            end
            local expected_resource = entry.weapon_resource or entry.weapon_resource64
            assert(
                not expected_resource or expected_resource == group.weapon_resource64,
                'Weapon application resource changed'
            )
            assert(
                not entry.source_resource or entry.source_resource == group.source_resource,
                'Weapon application source LUT changed'
            )
            local copy = document_copy(entry.document)
            assert(copy.width == group.width and copy.height == group.height, 'Weapon LUT dimensions differ')
            copy.kind, copy.family, copy.weapon_slot, copy.weapon_resource64, copy.weapon_resource =
                'weapon', kind, weapon_slot, group.weapon_resource64, group.weapon_resource64
            copy.resource = group.source_resource or copy.resource
            copy.mixed, copy.binding_documents = nil, nil
            local bytes = ffi.string(copy.data, copy.width * copy.height * 16)
            local chosen = entry.targets or group.bindings
            assert(
                type(chosen) == 'table' and #chosen > 0 and #chosen <= #group.bindings,
                'Weapon target subset bounds'
            )
            local members, subset = {}, {}
            for _, b in ipairs(group.bindings) do
                members[b] = true
            end
            for _, b in ipairs(chosen) do
                assert(members[b], 'Weapon target subset belongs to another group')
                local material_key = b.material .. ':' .. b.slot
                assert(
                    not material_intents[material_key] or material_intents[material_key] == bytes,
                    'Conflicting shared weapon material assignment'
                )
                material_intents[material_key] = bytes
                local binding_key = key(b)
                assert(
                    not seen[binding_key] or seen[binding_key] == bytes,
                    'Conflicting shared weapon binding assignment'
                )
                if not seen[binding_key] then
                    seen[binding_key] = bytes
                    targets[#targets + 1] = b
                    subset[#subset + 1] = b
                    before[b] =
                        { current = b.current, previous = b.previous, texture = b.texture, document = b.document }
                end
            end
            if #subset > 0 then
                plan[#plan + 1] = {
                    group = group,
                    document = copy,
                    weapon_slot = weapon_slot,
                    family = kind,
                    targets = subset,
                }
            end
        end
        restore_targets = restore_targets or {}
        assert(type(restore_targets) == 'table' and #restore_targets <= 3072, 'Weapon restoration plan bounds')
        local owned = {}
        for _, b in ipairs(self.all_owned()) do
            owned[b] = true
        end
        for _, b in ipairs(restore_targets) do
            assert(
                owned[b] and discovery.present(b) and discovery.binding(b) == b.current,
                'Weapon history original target changed'
            )
            local binding_key, material_key = key(b), b.material .. ':' .. b.slot
            assert(not seen[binding_key], 'Weapon target cannot be both assigned and omitted')
            assert(
                not material_intents[material_key] or material_intents[material_key] == '!restore:' .. b.original,
                'Weapon omitted target aliases a retained assignment'
            )
            material_intents[material_key] = '!restore:' .. b.original
            seen[binding_key] = '!restore:' .. b.original
            targets[#targets + 1] = b
            before[b] = { current = b.current, previous = b.previous, texture = b.texture, document = b.document }
        end
        if #targets == 0 then
            return {}
        end
        local results = operation(targets, function()
            local results = {}
            local ok, why = pcall(function()
                for _, b in ipairs(restore_targets) do
                    assert(
                        active.keys[key(b)] and discovery.present(b) and discovery.binding(b) == b.current,
                        'Weapon changed during omitted-target restoration'
                    )
                    b.previous, b.current = b.current, b.original
                    deps.bind(b, b.original)
                    assert(discovery.binding(b) == b.original, 'Weapon original restoration readback failed')
                    b.current, b.previous, b.texture, b.document = b.original, nil, nil, nil
                end
                for _, entry in ipairs(plan) do
                    local count, texture =
                        sessions[entry.weapon_slot][entry.family].apply(entry.document, entry.targets)
                    results[#results + 1] = { count = count, texture = texture }
                end
            end)
            if not ok then
                for index = #targets, 1, -1 do
                    local b = targets[index]
                    local old = before[b]
                    local present = discovery.present(b)
                    local current = present and discovery.binding(b)
                    local restored = current == old.current
                    if current and current ~= old.current and (current == b.current or current == b.previous) then
                        restored = pcall(function()
                            assert(active.keys[key(b)] and discovery.present(b), 'Weapon changed during plan rollback')
                            deps.bind(b, old.current)
                            assert(discovery.binding(b) == old.current, 'Weapon plan rollback readback failed')
                        end)
                    end
                    if restored then
                        b.current, b.previous, b.texture, b.document =
                            old.current, old.previous, old.texture, old.document
                    end
                end
                error(why, 0)
            end
            return results
        end)
        -- Identification owns only temporary bindings; never retain its pixels
        -- as a recovery draft or publish them to the cached editor preview.
        if temporary then
            return results
        end
        local changed_groups = {}
        for _, b in ipairs(restore_targets) do
            local kind = b.slot == R.PATTERN and 'pattern' or 'material'
            local catalog = catalogs[b.weapon_slot]
            local group = catalog and catalog[kind][b.group_index]
            if group then
                changed_groups[group] = true
                local resource = group.source_resource
                local draft_key = resource
                    and b.weapon_slot .. ':' .. group.weapon_resource64 .. ':' .. kind .. ':' .. resource:lower()
                if draft_key and drafts[draft_key] then
                    drafts[draft_key][b.save_key] = nil
                end
            end
        end
        for _, entry in ipairs(plan) do
            changed_groups[entry.group] = true
            local resource = entry.group.source_resource
            if type(resource) == 'string' and #resource == 16 and resource:match('^%x+$') then
                local draft_key = entry.weapon_slot
                    .. ':'
                    .. entry.group.weapon_resource64
                    .. ':'
                    .. entry.family
                    .. ':'
                    .. resource:lower()
                drafts[draft_key] = drafts[draft_key] or {}
                for _, b in ipairs(entry.targets) do
                    drafts[draft_key][b.save_key] = document_copy(entry.document)
                end
            end
        end
        for group in pairs(changed_groups) do
            local representative, _, mixed = group_documents(group)
            group.document = not mixed and document_copy(representative) or nil
            group.preview_document = document_copy(representative)
            group.preview_document.mixed = mixed
        end
        return results
    end
    function self.apply(document, weapon_slot, selected_index, kind)
        local results = self.apply_plan({
            { document = document, weapon_slot = weapon_slot, index = selected_index, family = kind },
        })
        return results[1].count, results[1].texture
    end
    function self.restore(weapon_slot)
        if weapon_slot then
            slot(weapon_slot)
        end
        local targets, selected_sessions = {}, {}
        for index = 1, R.SLOTS do
            if not weapon_slot or index == weapon_slot then
                for _, kind in ipairs({ 'material', 'pattern' }) do
                    local session = sessions[index][kind]
                    selected_sessions[#selected_sessions + 1] = session
                    for _, b in ipairs(session.owned) do
                        if discovery.present(b) then
                            local current = discovery.binding(b)
                            if current ~= b.original and (current == b.current or current == b.previous) then
                                targets[#targets + 1] = b
                            end
                        end
                    end
                end
            end
        end
        local function restore()
            local complete = true
            for _, session in ipairs(selected_sessions) do
                complete = session.restore() and complete
                local certified = session.retirement_certificate()
                complete = certified and complete
            end
            return complete
        end
        local restored
        if #targets > 0 then
            restored = operation(targets, restore)
        else
            restored = restore()
        end
        if restored then
            for index = 1, R.SLOTS do
                if not weapon_slot or index == weapon_slot then
                    catalogs[index] = nil
                end
            end
        end
        return restored
    end
    function self.retirement_certificate()
        for index = 1, R.SLOTS do
            for _, kind in ipairs({ 'material', 'pattern' }) do
                local ok, why = sessions[index][kind].retirement_certificate()
                if not ok then
                    return false, why
                end
            end
        end
        return true
    end
    function self.target(weapon_slot, selected_index, kind)
        local group = selected(slot(weapon_slot), selected_index, family(kind))
        for _, b in ipairs(group.bindings) do
            assert(discovery.present(b) and discovery.binding(b) == b.current, 'Weapon target changed')
        end
        return group
    end
    function self.sessions()
        local out = {}
        for index = 1, R.SLOTS do
            for _, kind in ipairs({ 'material', 'pattern' }) do
                out[#out + 1] = sessions[index][kind]
            end
        end
        return out
    end
    function self.all_owned()
        local out = {}
        for _, session in ipairs(self.sessions()) do
            for _, b in ipairs(session.owned) do
                out[#out + 1] = b
            end
        end
        return out
    end
    function self.capture_state()
        local state = { version = 1, entries = {} }
        for index = 1, R.SLOTS do
            local catalog = catalogs[index]
            if catalog and catalog.available then
                for _, kind in ipairs({ 'material', 'pattern' }) do
                    for group_index, group in ipairs(catalog[kind]) do
                        if group.source_document then
                            self.target(index, group_index, kind)
                            local _, by_key = group_documents(group)
                            local variants = {}
                            for _, b in ipairs(group.bindings) do
                                if b.current ~= b.original and b.document then
                                    local document = by_key[b.save_key]
                                    local bytes = ffi.string(document.data, document.width * document.height * 16)
                                    local entry = variants[bytes]
                                    if not entry then
                                        entry = {
                                            weapon_slot = index,
                                            weapon_resource = group.weapon_resource64,
                                            weapon_resource64 = group.weapon_resource64,
                                            family = kind,
                                            index = group_index,
                                            source_resource = group.source_resource,
                                            document = document_copy(document),
                                            save_keys = {},
                                        }
                                        state.entries[#state.entries + 1] = entry
                                        variants[bytes] = entry
                                    end
                                    entry.save_keys[#entry.save_keys + 1] = b.save_key
                                end
                            end
                        end
                    end
                end
            end
        end
        return state
    end
    function self.restore_state(state)
        assert(
            type(state) == 'table' and state.version == 1 and type(state.entries) == 'table',
            'Invalid weapon history state'
        )
        local entries, desired = {}, {}
        for _, prior in ipairs(state.entries) do
            local entry = {}
            for name, value in pairs(prior) do
                entry[name] = value
            end
            if prior.save_keys then
                local group = self.target(prior.weapon_slot, prior.index, prior.family)
                local by_key = {}
                for _, b in ipairs(group.bindings) do
                    by_key[b.save_key] = b
                end
                assert(
                    type(prior.save_keys) == 'table' and #prior.save_keys > 0 and #prior.save_keys <= #group.bindings,
                    'Weapon history assignment bounds'
                )
                entry.targets = {}
                for _, save_key in ipairs(prior.save_keys) do
                    entry.targets[#entry.targets + 1] = assert(by_key[save_key], 'Weapon history destination changed')
                end
            end
            entries[#entries + 1] = entry
            local group = self.target(prior.weapon_slot, prior.index, prior.family)
            for _, b in ipairs(entry.targets or group.bindings) do
                desired[key(b)] = true
            end
        end
        local omitted = {}
        for _, b in ipairs(self.all_owned()) do
            if not desired[key(b)] and b.current ~= b.original then
                if discovery.dead(b) then
                    -- Dead receipts need no native mutation; retirement still
                    -- requires the caller's ordinary render fences.
                else
                    assert(
                        discovery.present(b) and discovery.binding(b) == b.current,
                        'Cannot restore an inaccessible or foreign weapon history target'
                    )
                    omitted[#omitted + 1] = b
                end
            end
        end
        return self.apply_plan(entries, omitted)
    end
    function self.update()
        local changed = {}
        for weapon_slot = 1, R.SLOTS do
            local catalog = catalogs[weapon_slot]
            if catalog and catalog.available then
                local checked, valid, why = pcall(discovery.with_validation_batch or function(fn)
                    return fn()
                end, function()
                    local valid, why = discovery.validate(catalog.receipt)
                    if valid then
                        for _, kind in ipairs({ 'material', 'pattern' }) do
                            for _, group in ipairs(catalog[kind]) do
                                for _, b in ipairs(group.bindings) do
                                    -- binding() already proves the complete locator and identity.
                                    -- A separate present() repeated that native work for every cell.
                                    if discovery.binding(b) ~= b.current then
                                        valid, why = false, 'Weapon material or LUT changed'
                                    end
                                end
                            end
                        end
                    end
                    return valid, why
                end)
                if not checked then
                    valid, why = false, tostring(valid)
                end
                if not valid then
                    catalog.available, catalog.reason = false, why
                    catalog.material, catalog.pattern = {}, {}
                    changed[#changed + 1] = weapon_slot
                end
            end
        end
        return changed
    end
    function self.recovery(weapon_slot, apply_retained)
        local catalog, why = self.refresh(slot(weapon_slot))
        if not catalog then
            return nil, why
        end
        local entries = {}
        if apply_retained == true then
            for _, kind in ipairs({ 'material', 'pattern' }) do
                for index in ipairs(catalog[kind]) do
                    local original = self.load(weapon_slot, index, kind)
                    local resource = original.resource
                    if type(resource) == 'string' and #resource == 16 and resource:match('^%x+$') then
                        local saved =
                            drafts[weapon_slot .. ':' .. catalog.weapon_resource64 .. ':' .. kind .. ':' .. resource:lower()]
                        if saved then
                            local grouped = {}
                            for _, b in ipairs(catalog[kind][index].bindings) do
                                local document = saved[b.save_key]
                                if document then
                                    local bytes = ffi.string(document.data, document.width * document.height * 16)
                                    local entry = grouped[bytes]
                                    if not entry then
                                        entry = {
                                            document = document,
                                            weapon_slot = weapon_slot,
                                            weapon_resource = catalog.weapon_resource64,
                                            index = index,
                                            family = kind,
                                            source_resource = resource:lower(),
                                            targets = {},
                                        }
                                        entries[#entries + 1] = entry
                                        grouped[bytes] = entry
                                    end
                                    entry.targets[#entry.targets + 1] = b
                                end
                            end
                        end
                    end
                end
            end
        end
        if #entries > 0 then
            self.apply_plan(entries)
        end
        return catalog, #entries
    end
    return self
end
return R
