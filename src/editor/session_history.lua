-- History snapshots and transactional restoration of owned material/Pattern writes.
-- UI, persistence and activation state remain with the session controller.
local H = {}
local buffers = m and m.float_buffer or require('src.core.float_buffer')
local function field(value)
    local kind = type(value)
    value = value == nil and '' or tostring(value)
    return kind .. ':' .. #value .. ':' .. value
end
local function weapon_signature(state)
    assert(
        type(state) == 'table' and state.version == 1 and type(state.entries) == 'table' and #state.entries <= 3072,
        'Invalid weapon history state'
    )
    local entries = {}
    for _, entry in ipairs(state.entries) do
        local d = assert(entry.document, 'Weapon history document unavailable')
        local keys = {}
        for _, key in ipairs(entry.save_keys or {}) do
            keys[#keys + 1] = field(key)
        end
        table.sort(keys)
        local parts = {
            field(entry.weapon_slot),
            field(entry.weapon_resource or entry.weapon_resource64),
            field(entry.family),
            field(entry.index),
            field(entry.source_resource),
            field(table.concat(keys)),
            field(d.width),
            field(d.height),
            field(buffers.bytes(d.data, d.width * d.height * 4)),
            field(d.source),
            field(d.resource),
            field(d.revision),
            field(d.saved_pixels),
            field(d.kind or 'weapon'),
            field(d.family or entry.family),
            field(d.weapon_slot or entry.weapon_slot),
            field(d.weapon_resource or entry.weapon_resource or entry.weapon_resource64),
            field(d.weapon_resource64 or entry.weapon_resource64 or entry.weapon_resource),
            field(d.original and buffers.bytes(d.original, d.width * d.height * 4)),
        }
        entries[#entries + 1] = table.concat(parts)
    end
    table.sort(entries)
    return field(state.version) .. table.concat(entries)
end
local function copy_weapons(state, copier)
    weapon_signature(state)
    local result = { version = state.version, entries = {} }
    for index, entry in ipairs(state.entries) do
        local copied = {}
        for key, value in pairs(entry) do
            copied[key] = value
        end
        copied.document = copier(entry.document)
        if entry.save_keys then
            copied.save_keys = {}
            for i, key in ipairs(entry.save_keys) do
                copied.save_keys[i] = key
            end
        end
        result.entries[index] = copied
    end
    return result
end
local function weapon_receipts(runtime, state)
    if type(runtime.catalog) ~= 'function' then
        return ''
    end
    local slots, parts = {}, {}
    for _, entry in ipairs(state.entries) do
        slots[entry.weapon_slot] = true
    end
    for slot = 1, 3 do
        if slots[slot] then
            local catalog = assert(runtime.catalog(slot), 'Weapon history catalog disappeared')
            assert(catalog.available and catalog.receipt, 'Weapon history receipt unavailable')
            local receipt = catalog.receipt
            parts[#parts + 1] = field(slot)
            for _, name in ipairs({
                'unit',
                'lua_unit',
                'world',
                'weapon_slot',
                'weapon_resource',
                'weapon_resource64',
                'unit_resource64',
                'remote',
                'peer_scope',
                'peer_player',
                'peer_unit',
                'peer_low',
                'peer_high',
            }) do
                parts[#parts + 1] = field(receipt[name])
            end
            local bindings = {}
            for _, family in ipairs({ 'material', 'pattern' }) do
                for _, group in ipairs(catalog[family] or {}) do
                    for _, b in ipairs(group.bindings) do
                        bindings[#bindings + 1] = field(family)
                            .. field(b.save_key)
                            .. field(b.unit)
                            .. field(b.mesh)
                            .. field(b.material)
                            .. field(b.slot)
                            .. field(b.original)
                    end
                end
            end
            table.sort(bindings)
            parts[#parts + 1] = field(table.concat(bindings))
        end
    end
    return table.concat(parts)
end

function H.new(deps)
    for _, name in ipairs({
        'copier',
        'state',
        'material_session',
        'pattern_session',
        'material_key',
        'appearance_resource',
        'stop_identification',
        'appearance_proof',
        'present',
        'binding',
        'bind',
        'commit',
    }) do
        assert(type(deps[name]) == 'function', 'Session history dependency required: ' .. name)
    end
    local self = {}

    function self.capture()
        local state = deps.state()
        if not state then
            return nil
        end
        local snapshot = {
            bytes = 0,
            owned = {},
            pattern_owned = {},
            basic = {},
            editor_tables = {},
            defaults = {},
            default_proofs = {},
            palettes = {},
            selected = state.selected,
            editor_target = state.editor_target,
            imported = state.imported,
            scope = state.scope,
            palette_index = state.palette_index,
            appearance = state.appearance,
            appearance_pending = {},
            remember_application = state.remember_application,
        }
        local copier = deps.copier()
        local document = copier.copy
        snapshot.loaded = document(state.loaded)
        if state.editor_target then
            snapshot.editor_target = {}
            for k, v in pairs(state.editor_target) do
                snapshot.editor_target[k] = v
            end
        end
        for key, d in pairs(state.basic) do
            snapshot.basic[key] = document(d)
        end
        for key, d in pairs(state.editor_tables) do
            snapshot.editor_tables[key] = document(d)
        end
        local signature = {
            tostring(state.imported),
            state.loaded and buffers.bytes(state.loaded.data, state.loaded.width * state.loaded.height * 4) or '',
            state.loaded and state.loaded.source or '',
        }
        local weapon_runtime = deps.weapon_runtime and deps.weapon_runtime()
        if weapon_runtime then
            assert(
                type(weapon_runtime.capture_state) == 'function' and type(weapon_runtime.restore_state) == 'function',
                'Weapon history runtime unavailable'
            )
            local weapons = weapon_runtime.capture_state()
            snapshot.weapon_state = copy_weapons(weapons, document)
            snapshot.weapon_signature = weapon_signature(snapshot.weapon_state)
            snapshot.weapon_receipts = weapon_receipts(weapon_runtime, weapons)
            signature[#signature + 1] = 'weapons:'
                .. field(snapshot.weapon_signature)
                .. field(snapshot.weapon_receipts)
        end
        if state.loaded and state.loaded.kind == 'weapon' then
            for _, name in ipairs({
                'kind',
                'family',
                'weapon_slot',
                'weapon_resource',
                'weapon_resource64',
                'width',
                'height',
                'mixed',
                'resource',
                'resource_object',
                'source_resource',
                'revision',
                'saved_pixels',
            }) do
                signature[#signature + 1] = 'weapon_editor:' .. name .. ':' .. field(state.loaded[name])
            end
        end
        if state.editor_target and state.editor_target.kind == 'weapon' then
            for _, name in ipairs({
                'kind',
                'family',
                'weapon_slot',
                'weapon_resource',
                'weapon_resource64',
                'group',
                'index',
                'group_id',
                'save_key',
            }) do
                signature[#signature + 1] = 'weapon_target:' .. name .. ':' .. field(state.editor_target[name])
            end
        end
        for _, pool in ipairs({
            { session = deps.material_session(), records = snapshot.owned, pattern = false },
            { session = deps.pattern_session(), records = snapshot.pattern_owned, pattern = true },
        }) do
            for _, b in ipairs(pool.session and pool.session.owned or {}) do
                local key = deps.material_key(b) .. (pool.pattern and ':pattern' or '')
                pool.records[#pool.records + 1] = {
                    binding = b,
                    key = key,
                    current = b.current,
                    texture = b.texture,
                    cape_proof = b.applied_cape_proof,
                    cape_resource = b.cape and deps.appearance_resource(b) or nil,
                    save_key = b.save_key,
                    document = document(b.document),
                }
                signature[#signature + 1] = key .. ':' .. tostring(b.current)
            end
        end
        for k, v in pairs(state.defaults) do
            snapshot.defaults[k] = v
            snapshot.default_proofs[k] = state.default_proofs[k]
        end
        for i, v in ipairs(state.palettes) do
            snapshot.palettes[i] = v
        end
        for _, entry in ipairs(snapshot.appearance) do
            signature[#signature + 1] = 'appearance:'
                .. entry.kind
                .. ':'
                .. tostring(entry.pattern)
                .. ':'
                .. entry.proof
                .. ':'
                .. entry.save_key
                .. ':'
                .. entry.resource
                .. ':'
                .. tostring(entry.texture.object)
        end
        local pending_keys = {}
        for key, entry in pairs(state.appearance_pending) do
            local copy = {}
            for k, v in pairs(entry) do
                copy[k] = v
            end
            snapshot.appearance_pending[key] = copy
            pending_keys[#pending_keys + 1] = key
        end
        table.sort(pending_keys)
        for _, key in ipairs(pending_keys) do
            signature[#signature + 1] = 'pending:'
                .. key
                .. ':'
                .. tostring(state.appearance_pending[key].texture.object)
        end
        snapshot.bytes = copier.bytes
        snapshot.signature = table.concat(signature, '|')
        return snapshot
    end

    function self.restore(snapshot, expected)
        -- History frames stay immutable when their documents return to the editor.
        local saved = snapshot
        snapshot = {}
        for k, v in pairs(saved) do
            snapshot[k] = v
        end
        local clone = deps.copier().copy
        if saved.weapon_state then
            snapshot.weapon_state = copy_weapons(saved.weapon_state, clone)
        end
        snapshot.loaded = clone(saved.loaded)
        if saved.editor_target then
            snapshot.editor_target = {}
            for k, v in pairs(saved.editor_target) do
                snapshot.editor_target[k] = v
            end
        end
        snapshot.basic = {}
        snapshot.editor_tables = {}
        snapshot.defaults = {}
        snapshot.default_proofs = {}
        snapshot.palettes = {}
        snapshot.owned = {}
        snapshot.pattern_owned = {}
        for k, d in pairs(saved.basic) do
            snapshot.basic[k] = clone(d)
        end
        for k, d in pairs(saved.editor_tables) do
            snapshot.editor_tables[k] = clone(d)
        end
        for k, v in pairs(saved.defaults) do
            snapshot.defaults[k] = v
            snapshot.default_proofs[k] = saved.default_proofs[k]
        end
        for k, v in pairs(saved.palettes) do
            snapshot.palettes[k] = v
        end
        for _, name in ipairs({ 'owned', 'pattern_owned' }) do
            for i, e in ipairs(saved[name] or {}) do
                local copy = {}
                for k, v in pairs(e) do
                    copy[k] = v
                end
                copy.document = clone(e.document)
                snapshot[name][i] = copy
            end
        end
        local weapon_runtime = deps.weapon_runtime and deps.weapon_runtime()
        if saved.weapon_state or expected.weapon_state then
            assert(
                weapon_runtime
                    and type(weapon_runtime.capture_state) == 'function'
                    and type(weapon_runtime.restore_state) == 'function',
                'Weapon history runtime unavailable'
            )
            assert(saved.weapon_state and expected.weapon_state, 'Weapon history scope changed')
        end
        local function validate_weapons()
            if not expected.weapon_state then
                return
            end
            assert(
                weapon_signature(saved.weapon_state) == saved.weapon_signature
                    and weapon_signature(expected.weapon_state) == expected.weapon_signature,
                'Saved weapon history frame changed'
            )
            local actual = weapon_runtime.capture_state()
            assert(
                weapon_signature(actual) == expected.weapon_signature,
                'Weapon bytes or assignments changed; cannot safely undo this action'
            )
            assert(
                weapon_receipts(weapon_runtime, actual) == expected.weapon_receipts,
                'Weapon receipt changed; cannot safely undo this action'
            )
        end
        validate_weapons() -- Reject stale weapons before highlight cleanup or garment writes.
        assert(deps.stop_identification(), 'Highlight restoration pending')
        local proof = deps.appearance_proof()
        for _, frame in ipairs({ snapshot, expected }) do
            for _, name in ipairs({ 'owned', 'pattern_owned' }) do
                for _, entry in ipairs(frame[name] or {}) do
                    assert(
                        not entry.cape_proof or (proof and proof.cape == entry.cape_proof),
                        'Cape kit changed; cannot safely undo or redo its old material colors'
                    )
                    assert(
                        not entry.cape_resource
                            or (
                                entry.binding.cape
                                and entry.binding.save_key == entry.save_key
                                and deps.appearance_resource(entry.binding) == entry.cape_resource
                            ),
                        'Cape resource changed; cannot safely undo or redo its old colors'
                    )
                end
            end
        end
        local plans = {}
        local pools = {
            { session = deps.material_session(), name = 'owned', slot = deps.material_slot, suffix = '' },
            {
                session = deps.pattern_session(),
                name = 'pattern_owned',
                slot = deps.pattern_slot,
                suffix = ':pattern',
            },
        }
        local function read_plan(plan)
            return deps.binding(plan.binding, plan.slot)
        end
        for _, pool in ipairs(pools) do
            local desired, expected_bindings, owned = {}, {}, {}
            for _, entry in ipairs(snapshot[pool.name] or {}) do
                desired[entry.key] = entry
            end
            for _, entry in ipairs(expected[pool.name] or {}) do
                expected_bindings[entry.key] = entry
            end
            assert(pool.session or not next(desired) and not next(expected_bindings), 'Pattern application unavailable')
            for _, b in ipairs(pool.session and pool.session.owned or {}) do
                local key = deps.material_key(b) .. pool.suffix
                owned[key] = true
                local e, d = expected_bindings[key], desired[key]
                local plan = {
                    binding = b,
                    slot = pool.slot,
                    pool = pool,
                    old = b.current,
                    object = d and d.current or b.original,
                    desired = d,
                    cape_proof = e and e.cape_proof or d and d.cape_proof,
                }
                assert(
                    e and deps.present(b) and b.current == e.current and read_plan(plan) == e.current,
                    'Gear bindings changed; cannot safely undo this action'
                )
                plans[#plans + 1] = plan
            end
            for key in pairs(expected_bindings) do
                assert(owned[key], 'Gear ownership changed; cannot safely undo this action')
            end
            for key, d in pairs(desired) do
                if not expected_bindings[key] then
                    local b = d.binding
                    local plan = {
                        binding = b,
                        slot = pool.slot,
                        pool = pool,
                        old = b.original,
                        object = d.current,
                        desired = d,
                        cape_proof = d.cape_proof,
                    }
                    assert(
                        deps.present(b) and read_plan(plan) == b.original,
                        'Gear changed; cannot safely redo this action'
                    )
                    plans[#plans + 1] = plan
                end
            end
        end
        local changed = {}
        local ok, why = pcall(function()
            for _, plan in ipairs(plans) do
                assert(
                    deps.present(plan.binding) and read_plan(plan) == plan.old,
                    'Gear bindings changed during history restoration'
                )
                if plan.cape_proof then
                    local current_proof = deps.appearance_proof()
                    assert(
                        current_proof and current_proof.cape == plan.cape_proof,
                        'Cape kit changed during history restoration'
                    )
                end
                if plan.object ~= plan.old then
                    changed[#changed + 1] = plan
                    deps.bind(plan.binding, plan.slot, plan.object)
                    assert(read_plan(plan) == plan.object)
                end
            end
            if snapshot.weapon_state then
                validate_weapons()
                local restored, reason = weapon_runtime.restore_state(snapshot.weapon_state)
                assert(restored ~= false, reason or 'Weapon history restoration failed')
            end
        end)
        if not ok then
            for i = #changed, 1, -1 do
                local p = changed[i]
                if deps.present(p.binding) and read_plan(p) == p.object then
                    local restored = pcall(function()
                        deps.bind(p.binding, p.slot, p.old)
                        assert(read_plan(p) == p.old)
                    end)
                    if not restored and deps.present(p.binding) and read_plan(p) == p.object then
                        -- The forward write is still ours. Keep its exact receipt
                        -- so later Restore/cleanup can remove it even when this
                        -- history action could not finish its rollback.
                        local b, d = p.binding, p.desired
                        b.current, b.previous = p.object, p.old
                        b.texture, b.document = d and d.texture or nil, d and d.document or nil
                        b.applied_cape_proof = d and d.cape_proof or p.cape_proof
                        local found = false
                        for _, owned in ipairs(p.pool.session.owned) do
                            if deps.material_key(owned) == deps.material_key(b) then
                                found = true
                                break
                            end
                        end
                        if not found then
                            p.pool.session.owned[#p.pool.session.owned + 1] = b
                        end
                    end
                end
            end
            error(why, 0)
        end
        for _, pool in ipairs(pools) do
            if pool.session then
                pool.session.owned = {}
            end
        end
        for _, plan in ipairs(plans) do
            local b, d = plan.binding, plan.desired
            b.current = plan.object
            b.previous = nil
            b.texture = d and d.texture or nil
            b.document = d and d.document or nil
            b.applied_cape_proof = d and d.cape_proof or nil
            if d then
                plan.pool.session.owned[#plan.pool.session.owned + 1] = b
            end
        end
        return deps.commit(snapshot)
    end

    return self
end

return H
