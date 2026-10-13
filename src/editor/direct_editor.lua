-- Active edit session, service composition and controller-owned gear transitions.
local ffi = require('ffi')
local ctx, memory, native, game, frontend, preferences, handle, api, paths, palette_editor
local updates
local groups = {}
local bindings, gear_catalog
local sharing, pattern_editor, armory_mirror
local edit = {} -- Current document, imported source, target and revision baseline.
local status = 'Load a DDS or ZIP, then refresh the live LUT list.'
local BINDING_EXPORT_PENDING = m.export_provenance.PENDING
local pending, palettes = nil, {}
local table_index
local operations = {}
local import_jobs
local setup, resume_job, resume_done
local original_luts
local appearance
local appearance_pending = {}
local appearance_elapsed = 0
local appearance_read
local appearance_proof
local defaults = {}
local default_proofs = {}
local select_suppressed = false
local live_select_suppressed = false
local basic_imported, basic_names
local populate_request
local populate_next = 0
local basic_state, basic_documents
local basic_selected
local basic_missing_reported = {}
local myc_warned = false
local region_indicator, stop_identification
local identify_kind
local checked_editor_target
local gear_edits
local weapon_editor
local import_target
local editor_pending
local history
local outfits, armory_collection
local import_view
local import_state
local source_tables, editor_tables = {}, {}
local import_ids = {}
local index_job
local refresh_needed, next_refresh = false, 0
local DEBUG_SOURCE = 'builtin:Debug.dds'
local import_counter = package.loaded['epic.import.counter.v1'] or { value = 0 }
package.loaded['epic.import.counter.v1'] = import_counter
local small, big = ffi.new('uint8_t[96]'), ffi.new('uint8_t[1024]')
local retain = package.loaded['epic.direct_lut.retained.v1'] or { records = {}, bytes = 0, cache = {} }
package.loaded['epic.direct_lut.retained.v1'] = retain
local function read(a, n, b)
    return memory.read_into(ffi.cast('const uint8_t *', a), n, b)
end
local function binding(b)
    return m.engine.binding(read, b.material, b.slot or m.engine.LUT_SLOT, small, big)
end
local function present(b)
    if native.alive(b.unit) == 0 then
        return false
    end
    for _, v in ipairs(m.engine.unit_materials(native, b.unit)) do
        if v.mesh == b.mesh and v.material == b.material then
            return true
        end
    end
    return false
end
local function material_key(b)
    return b.unit .. ':' .. b.mesh .. ':' .. b.material
end
local function applied_document(b)
    if b.texture and b.current == b.texture.object and b.texture.data then
        return b.texture
    end
    return b.document
end
local function restore(allow_quarantine)
    if stop_identification then
        stop_identification()
    end
    local weapons = operations.weapon_editor
    local weapon_done = not weapons or weapons.close(allow_quarantine)
    local gear_done = not bindings or bindings.restore()
    return weapon_done and gear_done
end
local function message(text)
    status = text
    ctx.log('Epic LUT: ' .. text)
    return text
end
local function disable_matching()
    if m.provider_menu then
        return m.provider_menu.disable_matching(api)
    end
    return true, false
end
local function palette_choices(labels)
    api.mods[handle.id].controls.palette.choices = labels
    select_suppressed = true
    local ok, why = handle.set('palette', 1)
    select_suppressed = false
    assert(ok, why)
end
local function action(fn, recover)
    local before
    if history and not history.busy and not region_indicator.job then
        local ok, value = pcall(history.capture)
        if ok then
            before = value
        else
            ctx.log('Action snapshot skipped: ' .. tostring(value))
        end
    end
    local ok, why = pcall(fn)
    if not ok then
        if recover then
            restore()
        end
        return message(tostring(why))
    end
    if before and not region_indicator.job then
        local ok, err = pcall(function()
            history.record(before, history.capture())
        end)
        if not ok then
            ctx.log('Action history recording failed: ' .. tostring(err))
        end
    end
    return why
end
local function refresh(silent)
    local proof = appearance_proof and appearance_proof()
    local cape_proof = proof and proof.cape
    if cape_proof and edit.cape_proof ~= cape_proof then
        -- The cape kit can change while its generic Armor mount stays alive.
        -- Retire only our former cape writes; another writer remains untouched.
        for _, b in ipairs(bindings.owned) do
            if b.cape and b.applied_cape_proof and b.applied_cape_proof ~= cape_proof then
                if present(b) and binding(b) == b.current and b.current ~= b.original then
                    m.engine.bind(native, b.material, m.engine.LUT_SLOT, b.original)
                    native.commit(b.mesh)
                    assert(binding(b) == b.original, 'Previous Cape material restoration pending')
                    b.current, b.texture, b.document, b.applied_cape_proof = b.original, nil, nil, nil
                end
            end
        end
        if edit.cape_proof then
            for key in pairs(basic_documents) do
                if key:sub(1, 5) == 'cape:' then
                    basic_documents[key] = nil
                end
            end
            if
                (edit.editor_target and edit.editor_target.kind == 'cape')
                or (basic_selected and basic_selected.kind == 'cape')
            then
                edit.loaded, edit.editor_target, edit.preview_document = nil, nil, nil
                basic_selected = nil
                edit.quick_selection = nil
                identify_kind = nil
                if palette_editor then
                    palette_editor.sync()
                end
            end
        end
        edit.cape_proof = cape_proof
    end
    local previous = handle and groups[handle.get('lut')]
    local previous_object = previous and previous.object
    local result = gear_catalog.refresh(bindings.owned, previous_object)
    groups, bindings.owned = result.groups, result.owned
    if operations.sync_armory_cape then
        operations.sync_armory_cape()
    end
    if edit.import_gear_signature ~= result.signature then
        edit.import_gear_signature = result.signature
        if import_view then
            import_view.gear_scroll = { armor = 0, helmet = 0 }
        end
    end
    local labels, selected = result.labels, result.selected
    api.mods[handle.id].controls.lut.choices = labels
    live_select_suppressed = true
    local ok, err = handle.set('lut', selected)
    live_select_suppressed = false
    assert(ok, err)
    if silent then
        return true
    end
    return message('Found ' .. #groups .. ' live LUTs. Select one, then Apply.')
end
local function load_dds(path)
    local bytes
    if path == DEBUG_SOURCE then
        bytes = assert(m.debug_lut_dds_hex, 'Debug LUT is unavailable in this build'):gsub('%x%x', function(pair)
            return string.char(tonumber(pair, 16))
        end)
    else
        bytes = m.file_io.read(path, m.dds.MAX_BYTES)
    end
    local data, w, h = m.dds.decode(bytes)
    if w == 3 and h == 1 and pattern_editor then
        local ok, changed = disable_matching()
        assert(ok, changed)
        if changed then
            groups = {}
        end
        edit.imported = nil
        local imported = { data = data, width = w, height = h, source = path, resource = import_ids[path] }
        source_tables[path] = imported
        -- Keep archive choices so another Pattern table in this variant remains selectable.
        local result = pattern_editor.import(imported)
        if api and handle then
            api.focus_page(handle.id, 'colors')
            pattern_editor.show()
        end
        return result
    end
    assert(w == 23, 'Expected a 23-column material LUT or 3x1 Pattern LUT DDS')
    edit.editor_target = nil
    editor_pending = nil
    local ok, changed = disable_matching()
    assert(ok, changed)
    if changed then
        groups = {}
    end
    edit.imported = { data = data, width = w, height = h, source = path, resource = import_ids[path] }
    source_tables[path] = edit.imported
    refresh_needed = not pcall(refresh)
    return message('DDS imported (' .. w .. ' x ' .. h .. '). Send to LUT Editor to edit; Apply LUT sends it to gear.')
end
local function load(pick, rows_mode)
    return operations.import_picker.load(pick, rows_mode)
end
local function cancel_import(retry)
    return operations.import_picker.cancel(retry)
end
local function accept_import(text, job)
    return action(function()
        local result = m.import_protocol.result(text)
        if result.canceled then
            return message('File selection canceled; current palette retained.')
        end
        if result.rows then
            assert(job.rows_mode, 'Unexpected Paydex row import result')
            local names, created = m.paydex_rows
                .new({
                    folder = paths.presets,
                    read = m.file_io.read,
                    write = m.file_io.write,
                    dds = m.dds,
                })
                .import(job.base, result.rows)
            assert(palette_editor.handle.set('row_preset', names[1]))
            palette_editor.refresh_presets()
            if job.menu_visible and frontend.menu then
                frontend.menu.visible = true
                frontend.menu.page = job.menu_page or frontend.menu.page
                frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
            end
            return message(
                'Imported '
                    .. #names
                    .. ' Paydex row presets ('
                    .. created
                    .. ' new). Choose a row preset and Apply when ready.'
            )
        end
        assert(not job.rows_mode, 'Paydex import returned a palette result')
        if result.preset then
            if job.menu_visible and frontend.menu then
                frontend.menu.visible, frontend.menu.suspended = true, true
                frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
            end
            return assert(operations.import_armory, 'Armory import unavailable')(
                job.base .. '/' .. result.preset,
                result.label
            )
        end
        local extracted, labels = {}, result.names
        for _, name in ipairs(labels) do
            extracted[#extracted + 1] = job.base .. '/' .. name
        end
        local metadata = io.open(job.base .. '/resources.tsv', 'rb')
        if metadata and m.import_matches then
            local text = metadata:read(16385) or ''
            metadata:close()
            local names = labels
            for file, hash in pairs(m.import_matches.metadata(text, names)) do
                import_ids[job.base .. '/' .. file] = hash
            end
        elseif metadata then
            metadata:close()
        end
        -- Validate the first file before replacing the current import selection.
        load_dds(extracted[1])
        palettes = extracted
        palette_choices(labels)
        local info = io.open(job.base .. '/import-info.txt', 'rb')
        if info then
            local label = info:read(1024)
            info:close()
            m.import_description = label
        end
        if job.menu_visible and frontend.menu then
            frontend.menu.visible = true
            frontend.menu.page = job.menu_page
            frontend.menu.suspended = true
            frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
            ctx.log('Import completed; restored editor menu after file picker')
        end
        index_job = table_index.start(palettes, source_tables, import_ids)
        return status
    end)
end
local function initialize_import_picker()
    import_jobs = m.import_job.new(m.import_protocol)
    operations.import_picker = m.import_picker.new({
        jobs = import_jobs,
        paths = paths,
        counter = import_counter,
        get = function(id)
            return handle.get(id)
        end,
        get_native_import = function()
            return m.native_import
        end,
        get_script_hex = function()
            return m.zip_import_script
        end,
        get_menu = function()
            return frontend and frontend.menu
        end,
        before_load = function(rows_mode)
            if not rows_mode then
                resume_done, resume_job = true, nil
            end
        end,
        load_direct = function(name)
            palettes = { paths.files .. '/' .. name .. '.dds' }
            palette_choices({ name })
            return load_dds(palettes[1])
        end,
        accept = accept_import,
        message = message,
        on_job = function(job)
            pending = job
        end,
    })
end
appearance_proof = function()
    if not m.avatar.resolve then
        return nil
    end
    local ok, identity = pcall(m.avatar.resolve, memory, game, appearance_read)
    if not ok or not identity or identity.body == nil or identity.armor == nil or identity.helmet == nil then
        return nil
    end
    return {
        armor = tostring(identity.body) .. ':' .. tostring(identity.armor),
        helmet = tostring(identity.helmet),
        cape = identity.cape ~= nil and (tostring(identity.body) .. ':' .. tostring(identity.cape)) or nil,
    }
end
local function appearance_resource(b)
    local original = original_luts and original_luts.get(b.original)
    return original and original.resource
end
local function set_default(kind, texture)
    defaults[kind] = texture
    local proof = texture and appearance_proof()
    default_proofs[kind] = proof and proof[kind] or nil
end
local function remember_appearance(targets, pattern)
    if not appearance then
        return
    end
    local proof = appearance_proof()
    if not proof then
        return
    end
    for _, b in ipairs(targets) do
        local kind = m.gear_catalog.kind(b)
        if b.cape then
            b.applied_cape_proof = proof.cape
        end
        for key, pending in pairs(appearance_pending) do
            if
                pending.kind == kind
                and pending.pattern == not not pattern
                and pending.proof == proof[kind]
                and pending.save_key == b.save_key
            then
                appearance_pending[key] = nil
            end
        end
    end
    local _, pending = appearance.remember(targets, pattern, proof, appearance_resource)
    for _, item in ipairs(pending or {}) do
        local key = tostring(item.pattern) .. ':' .. item.kind .. ':' .. item.proof .. ':' .. item.save_key
        appearance_pending[key] = item
    end
    edit.remember_application = true
end
local function apply_bindings(document, targets, transient)
    local count, texture = bindings.apply(document, targets)
    if not transient then
        remember_appearance(targets, false)
    end
    return count, texture
end
local function recover_appearance(dt)
    if not appearance then
        return
    end
    appearance_elapsed = appearance_elapsed + math.max(0, dt or 0)
    if appearance_elapsed < 0.5 then
        return
    end
    appearance_elapsed = 0
    if
        (region_indicator and region_indicator.job)
        or (pattern_editor and pattern_editor.flashing())
        or (
            frontend
            and frontend.menu
            and frontend.menu.visible
            and frontend.menu.is_interacting
            and frontend.menu.is_interacting()
        )
    then
        return
    end
    for key, pending in pairs(appearance_pending) do
        local b =
            { original = pending.original, save_key = pending.save_key, kind = pending.kind, texture = pending.texture }
        local captured_proof = { [pending.kind] = pending.proof }
        local count = appearance.remember({ b }, pending.pattern, captured_proof, appearance_resource)
        if count > 0 then
            appearance_pending[key] = nil
        end
    end
    if appearance.count() == 0 and not (edit.editor_target and edit.editor_target.kind == 'cape') then
        return
    end
    local proof = appearance_proof()
    if not proof then
        return
    end
    local material_ready = pcall(refresh, true)
    local function replay(collection, pattern, session)
        local targets = {}
        for _, group in ipairs(collection or {}) do
            for _, b in ipairs(group.bindings) do
                targets[#targets + 1] = b
            end
        end
        for _, batch in ipairs(appearance.batches(targets, pattern, proof, appearance_resource, binding)) do
            session.apply(batch.document, batch.targets)
            for _, b in ipairs(batch.targets) do
                if b.cape then
                    b.applied_cape_proof = proof.cape
                end
            end
        end
    end
    if material_ready then
        replay(groups, false, bindings)
    end
    if pattern_editor and operations.pattern_session then
        local ok, discovered = pcall(pattern_editor.scan, true)
        if ok then
            replay(discovered, true, operations.pattern_session)
        end
    end
end
local function initialize_editor_state()
    operations.live_edit = m.live_edit and m.live_edit.new()
    local cohort = { sessions = {} }
    retain.cohort = cohort
    operations.texture_cohort = cohort
    if m.texture_lifetime and native.destroy then
        operations.texture_lifetime = m.texture_lifetime.new({
            retain = retain,
            cohort = cohort,
            certified = function()
                if not cohort.cleanup_ready then
                    return false, 'Addon cleanup is incomplete'
                end
                if #(package.loaded['epic.preview.retired.targets'] or {}) > 0 then
                    return false, 'Lost preview context may still hold LUT textures'
                end
                for _, session in ipairs(cohort.sessions or {}) do
                    local ok, why = session.retirement_certificate()
                    if not ok then
                        return false, why
                    end
                end
                return true
            end,
            drain = function()
                if frontend and frontend.render_ready then
                    local ok, ready = pcall(frontend.render_ready)
                    if not ok or not ready then
                        return nil, 'Texture retirement waits for game focus and valid rendering'
                    end
                end
                -- Keep the attempt before calling native code: an exception can
                -- leave a queued creation/destruction with unknown completion.
                local keep = { data = ffi.new('float[4]', { 0, 0, 0, 1 }) }
                retain.fence_pending = retain.fence_pending or {}
                retain.fence_pending[#retain.fence_pending + 1] = keep
                local fence, why = m.engine.create_texture(native, 1, 1, keep.data, read, small)
                keep.texture = fence
                assert(fence, why)
                native.destroy(fence.handle)
                table.remove(retain.fence_pending)
                return fence
            end,
            destroy = function(texture)
                native.destroy(texture.handle)
            end,
        })
    end
    operations.appearance_proof = appearance_proof
    operations.import_target = import_target
    operations.checked_editor_target = checked_editor_target
    gear_catalog = m.gear_catalog.new({
        identity = function()
            return m.avatar.resolve_live(memory, game)
        end,
        units = function(identity)
            return m.avatar.units(memory, identity, nil, 0, 9)
        end,
        materials = function(unit)
            return m.engine.unit_materials(native, unit)
        end,
        resource_name = function(unit)
            local sr = rawget(_G, 'stingray')
            local U = sr and sr.Unit
            if not m.sdk_catalog or not U or not U.resource_name then
                return nil
            end
            if U.alive then
                local ok, alive = pcall(U.alive, unit)
                if not ok or not alive then
                    return nil
                end
            end
            local ok, value = pcall(U.resource_name, unit)
            if not ok then
                return nil
            end
            local hash = tostring(value):match('#ID%[(%x+)%]')
            return hash and m.sdk_catalog.resource_name(hash)
        end,
        present = present,
        binding = binding,
        key = material_key,
        is_cape = function(b)
            if not m.engine.CAPE_LUT_SLOT then
                return false
            end
            local object = m.engine.binding(read, b.material, m.engine.CAPE_LUT_SLOT, small, big)
            return object ~= nil and object ~= 0
        end,
    })
    bindings = m.binding_session.new({
        retain = retain,
        dead = function(b)
            return native.alive(b.unit) == 0
        end,
        present = present,
        binding = binding,
        key = material_key,
        create_texture = function(width, height, data)
            return m.engine.create_texture(native, width, height, data, read, small)
        end,
        bind = function(b, object)
            local camo_target = operations.camo_write_target
            if
                camo_target
                and camo_target.kit_proof
                and m.gear_catalog.kind(b) == camo_target.kind
                and object == b.current
            then
                local proof = appearance_proof()
                assert(
                    proof and proof[camo_target.kind] == camo_target.kit_proof,
                    'Worn kit changed; load current colors again'
                )
            end
            if b.cape and operations.armory_cape_proof then
                local proof = appearance_proof()
                assert(
                    proof and proof.cape == operations.armory_cape_proof,
                    'Cape kit changed; load current gear again'
                )
            end
            if operations.lut_apply_proofs then
                local proof, kind = appearance_proof(), m.gear_catalog.kind(b)
                assert(
                    proof and proof[kind] == operations.lut_apply_proofs[kind],
                    'Worn gear changed during preset application'
                )
            end
            m.engine.bind(native, b.material, m.engine.LUT_SLOT, object)
            native.commit(b.mesh)
            if b.cape and operations.armory_cape_proof then
                b.applied_cape_proof = operations.armory_cape_proof
            end
            if b.cape and camo_target then
                b.applied_cape_proof = camo_target.kit_proof
            end
        end,
    })
    basic_state = m.basic_state.new()
    basic_documents = basic_state.documents
    region_indicator = m.region_indicator.new({
        present = present,
        binding = binding,
        context = function()
            return frontend.menu and frontend.menu.page
        end,
        apply = function(document, targets)
            return apply_bindings(document, targets, true)
        end,
        bind = function(b, object)
            m.engine.bind(native, b.material, m.engine.LUT_SLOT, object)
            native.commit(b.mesh)
        end,
    })
    stop_identification = function()
        return region_indicator.stop() and (not pattern_editor or pattern_editor.stop_flash())
    end
end
local function identify_region()
    assert(stop_identification(), 'Previous highlight restoration pending')
    if frontend.basic_mode then
        assert(basic_selected, 'Click an Armor or Helmet color region first')
    end
    local selected = frontend.basic_mode and basic_selected or edit.editor_target
    local index = selected and checked_editor_target(selected) or handle.get('lut')
    local group = assert(groups[index], 'Select a live LUT first')
    local kind = selected and selected.kind or identify_kind
    if selected then
        live_select_suppressed = true
        local ok, why = handle.set('lut', index)
        live_select_suppressed = false
        assert(ok, why)
    end
    local row = handle.get('edit_row')
    local items = {}
    for _, b in ipairs(group.bindings) do
        if not kind or b[kind] then
            local source = applied_document(b) or (original_luts and original_luts.get(b.original))
            assert(source, 'Original colors unavailable for this target; cannot safely highlight')
            assert(row >= 1 and row <= source.height, 'Selected region does not exist on this target')
            items[#items + 1] =
                { binding = b, object = b.current, texture = b.texture, document = b.document, source = source }
        end
    end
    region_indicator.start(items, row)
    return message('Flashing region ' .. row .. ' in magenta for 4 seconds; prior bindings restore automatically.')
end
local function apply(document, selected_kind)
    if
        edit.editor_target
        and edit.editor_target.kind == 'weapon'
        and (selected_kind == nil or selected_kind == 'weapon')
    then
        return weapon_editor().apply(edit.editor_target, document)
    end
    local scope = handle.get('scope')
    selected_kind = scope == 5 and 'cape'
        or (selected_kind == 'armor' or selected_kind == 'helmet' or selected_kind == 'cape') and selected_kind
        or nil
    assert(stop_identification(), 'Highlight restoration pending')
    if selected_kind == 'cape' then
        local proof = appearance_proof()
        assert(proof and proof.cape, 'Current Cape identity unavailable; load current gear again')
        local selected = scope == 1 and (frontend.basic_mode and basic_selected or edit.editor_target) or nil
        if selected and selected.kind == 'cape' then
            assert(selected.cape_proof and selected.resource, 'Load current Cape colors with a known texture ID first')
        end
        assert(
            not selected or not selected.cape_proof or selected.cape_proof == proof.cape,
            'Cape kit changed; load current Cape colors again before editing'
        )
        if selected and selected.resource then
            local matching = original_luts
                and original_luts.get(groups[selected.group] and groups[selected.group].object)
            assert(
                matching and matching.resource == selected.resource,
                'Cape resource changed; load current colors again'
            )
        end
    end
    document = document or edit.loaded or edit.imported
    assert(document, 'Load a DDS first')
    resume_done = true
    resume_job = nil
    if #groups == 0 then
        refresh()
    end
    local targets = m.gear_catalog.targets(
        groups,
        scope,
        handle.get('lut'),
        selected_kind,
        frontend.basic_mode and basic_selected and basic_selected.kind
    )
    local count, texture
    local function refresh_applied_palettes()
        for _, b in ipairs(targets) do
            if b.document then
                local kind = m.gear_catalog.kind(b)
                basic_documents[kind .. ':' .. tostring(b.original)] = b.document
            end
        end
        if frontend.menu then
            frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
        end
    end
    if handle.get('preserve_emissives') then
        assert(original_luts, 'Original game LUT reader unavailable')
        original_luts.scan()
        assert(original_luts.loaded, 'Original game snapshots are not ready: ' .. original_luts.status)
        local variants = {}
        -- Resolve every game reference before changing any live target.
        for _, b in ipairs(targets) do
            local variant = variants[b.original]
            if not variant then
                variant = {
                    document = m.original_luts.preserve(document, original_luts.get(b.original), document.height > 8),
                    targets = {},
                }
                variants[b.original] = variant
            end
            variant.targets[#variant.targets + 1] = b
        end
        count = 0
        for _, variant in pairs(variants) do
            count = count + apply_bindings(variant.document, variant.targets)
        end
        refresh_applied_palettes()
        if scope == 2 or scope == 4 then
            set_default('armor', nil)
        end
        if scope == 3 or scope == 4 then
            set_default('helmet', nil)
        end
        return message(
            'Palette applied to ' .. count .. ' bindings with game-original emissives, including zero values.'
        )
    end
    count, texture = apply_bindings(document, targets)
    refresh_applied_palettes()
    if scope == 2 or scope == 4 then
        set_default('armor', texture)
    end
    if scope == 3 or scope == 4 then
        set_default('helmet', texture)
    end
    return message('Palette applied to ' .. count .. ' bindings. Other applied LUTs stay active.')
end
local function save_setup()
    assert(not stop_identification or stop_identification(), 'Highlight restoration pending')
    if pattern_editor then
        assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
    end
    local active = {}
    for _, b in ipairs(bindings.owned) do
        if present(b) and binding(b) == b.current and b.texture and b.current == b.texture.object then
            active[#active + 1] = b.cape
                    and {
                        save_key = b.save_key,
                        texture = b.texture,
                        cape = true,
                        cape_proof = b.applied_cape_proof,
                        resource = appearance_resource(b),
                    }
                or b
        end
    end
    if operations.pattern_session then
        for _, b in ipairs(operations.pattern_session.owned) do
            if present(b) and binding(b) == b.current and b.texture and b.current == b.texture.object then
                active[#active + 1] = {
                    save_key = 'p:' .. b.save_key,
                    texture = b.texture,
                    cape = b.cape,
                    cape_proof = b.applied_cape_proof,
                    resource = b.cape and appearance_resource(b) or nil,
                }
            end
        end
    end
    if #active == 0 then
        if appearance and (appearance.count() > 0 or next(appearance_pending)) then
            return message('Applied appearance retained while the player is temporarily unavailable.')
        end
        assert(setup, 'Setup storage unavailable').clear()
        return message('No owned palettes remain applied; saved setup cleared.')
    end
    local saved_defaults, proof = {}, appearance_proof()
    for kind, texture in pairs(defaults) do
        if not default_proofs[kind] or (proof and proof[kind] == default_proofs[kind]) then
            for _, b in ipairs(active) do
                if b[kind] then
                    saved_defaults[kind] = texture
                    break
                end
            end
        end
    end
    return message(
        'Saved '
            .. assert(setup, 'Setup storage unavailable').save(active, saved_defaults)
            .. ' applied palettes. Armor, helmet and Pattern LUTs will resume on later launches.'
    )
end
local function save_palette()
    edit.editor_target = nil
    editor_pending = nil
    local source = assert(edit.imported, 'Import a LUT first')
    local data = ffi.new('float[?]', source.width * source.height * 4)
    ffi.copy(data, source.data, source.width * source.height * 16)
    edit.loaded = { data = data, width = source.width, height = source.height, source = source.source }
    editor_tables[source.source] = edit.loaded
    edit.preview_document = edit.loaded
    edit.preview_revision = 0
    if palette_editor then
        palette_editor.sync()
    end
    if api.focus_page then
        api.focus_page(handle.id, 'colors')
    end
    return message(
        'Editor table overwritten with the selected imported LUT. Apply LUT sends the file LUT to checked targets.'
    )
end
local function load_debug_lut()
    return action(function()
        assert(not pending and not index_job, 'Wait for the current import to finish')
        load_dds(DEBUG_SOURCE)
        resume_done, resume_job, populate_request = true, nil, nil
        edit.populate_manual_request = nil
        basic_selected, m.quick_source, edit.quick_selection = nil, nil, nil
        basic_imported = edit.imported
        palettes = { DEBUG_SOURCE }
        palette_choices({ 'Debug.dds' })
        m.import_description = 'Built-in Debug.dds'
        save_palette()
        return message('Debug LUT by Plain Furniture loaded into the editor. Use Apply to put it on gear.')
    end)
end
local function apply_checked(document)
    if basic_selected and frontend.basic_mode then
        local selected = basic_selected
        live_select_suppressed = true
        assert(handle.set('lut', basic_selected.group))
        live_select_suppressed = false
        assert(handle.set('scope', 1))
        return apply(document or edit.loaded, selected.kind)
    end
    local armor, helmet = handle.get('target_armor'), handle.get('target_helmet')
    assert(armor or helmet, 'Check Armor and/or Helmet first')
    assert(handle.set('scope', armor and (helmet and 4 or 2) or 3))
    return apply(assert(document or edit.imported, 'Import a LUT file first'))
end
local function current_choices(container)
    return gear_edits().choices(container)
end
local function warm_worn_slots()
    return gear_edits().warm_worn()
end
local function populate_worn()
    return gear_edits().populate_worn()
end
local function mark_current_load()
    edit.load_seen = true
    if preferences and preferences.mark_load_seen then
        preferences.mark_load_seen(false)
    end
end
local function resource_id(object)
    local original = original_luts and original_luts.get(object)
    local hash = original and original.resource
    local label = operations.lut_names and hash and operations.lut_names.get(hash)
    if label then
        return label
    end
    return m.resource_ids.describe(hash, handle.get('resource_format') == 2, m.sdk_catalog)
end
local function matching_plan(refresh_patterns)
    if not m.import_matches then
        return nil
    end
    local documents = {}
    for _, path in ipairs(palettes) do
        if source_tables[path] then
            documents[#documents + 1] = source_tables[path]
        end
    end
    local material_groups = {}
    for _, group in ipairs(groups) do
        local targets = {}
        for _, b in ipairs(group.bindings) do
            if not b.cape then
                targets[#targets + 1] = b
            end
        end
        if #targets > 0 then
            material_groups[#material_groups + 1] = { object = group.object, bindings = targets }
        end
    end
    local resolve = function(hash)
        return m.engine.texture_object(native, hash)
    end
    local plan = m.import_matches.plan(documents, material_groups, resolve)
    -- Use the whole import for duplicate-resource checks, then route documents
    -- by shape. A Pattern table can never become a material-slot upload.
    for i = #plan.plans, 1, -1 do
        if plan.plans[i].document.width ~= 23 then
            table.remove(plan.plans, i)
            plan.matched = plan.matched - 1
        end
    end
    local needs_patterns = false
    for _, document in ipairs(documents) do
        needs_patterns = needs_patterns or (document.resource and document.width == 3 and document.height == 1)
    end
    if needs_patterns and pattern_editor then
        local cached = operations.matching_patterns
        if refresh_patterns or not cached or cached.material_groups ~= groups then
            local discovered = pattern_editor.flashing
                    and pattern_editor.flashing()
                    and (pattern_editor.all_groups or {})
                or pattern_editor.scan(true)
            cached = { material_groups = groups, groups = discovered }
            operations.matching_patterns = cached
        end
        local pattern_groups = {}
        for _, group in ipairs(cached.groups) do
            local targets = {}
            for _, b in ipairs(group.bindings) do
                if not b.cape then
                    targets[#targets + 1] = b
                end
            end
            if #targets > 0 then
                pattern_groups[#pattern_groups + 1] = { object = group.object, bindings = targets }
            end
        end
        local patterns = m.import_matches.plan(documents, pattern_groups, resolve)
        for _, p in ipairs(patterns.plans) do
            if p.document.width == 3 and p.document.height == 1 then
                p.pattern = true
                plan.plans[#plan.plans + 1] = p
                plan.matched = plan.matched + 1
            end
        end
    end
    plan.unmatched = plan.total - plan.matched - plan.ambiguous - plan.unidentified
    return plan
end
local function apply_matching()
    assert(not index_job, 'Import is still being indexed; wait for the LUT list')
    assert(stop_identification(), 'Highlight restoration pending')
    if pattern_editor then
        assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
    end
    refresh(true)
    local plan = assert(matching_plan(true), 'Matching unavailable')
    assert(plan.matched > 0, 'No imported resource IDs match the currently worn gear')
    local batches = {}
    for _, p in ipairs(plan.plans) do
        local document = p.document
        if p.pattern then
            assert(
                operations.pattern_session and document.width == 3 and document.height == 1,
                'Pattern application unavailable'
            )
            local original = original_luts and original_luts.get(p.targets[1].original)
            assert(
                original and original.width == 3 and original.height == 1 and original.resource == p.resource,
                'Matching Pattern snapshot is unavailable or changed; load current Pattern LUTs first'
            )
        elseif handle.get('preserve_emissives') then
            assert(original_luts, 'Original snapshot reader unavailable')
            document = m.original_luts.preserve(document, original_luts.get(p.targets[1].original), document.height > 8)
        end
        for _, b in ipairs(p.targets) do
            assert(not p.pattern or b.slot == m.engine.PATTERN_SLOT, 'Pattern target slot changed')
            assert(p.pattern or (b.slot or m.engine.LUT_SLOT) == m.engine.LUT_SLOT, 'Material target slot changed')
            assert(present(b) and binding(b) == b.current, 'Gear bindings changed; load current gear again')
        end
        batches[#batches + 1] = { document = document, targets = p.targets, pattern = p.pattern }
    end
    resume_done = true
    resume_job = nil
    local bindings = 0
    for _, p in ipairs(batches) do
        if p.pattern then
            bindings = bindings + operations.pattern_session.apply(p.document, p.targets)
            remember_appearance(p.targets, true)
        else
            bindings = bindings + apply_bindings(p.document, p.targets)
            for _, b in ipairs(p.targets) do
                basic_documents[(m.gear_catalog.kind(b)) .. ':' .. tostring(b.original)] =
                    m.basic_state.clone(p.document, p.document.source)
            end
        end
    end
    return message(
        'Applied '
            .. plan.matched
            .. ' matching LUTs to '
            .. bindings
            .. ' bindings; unmatched and ambiguous LUTs left untouched.'
    )
end
import_target = function(kind, index)
    return gear_edits().target(kind, index)
end
import_state = function()
    if not operations.import_summary then
        operations.import_summary = m.import_summary.new({
            gear_catalog = m.gear_catalog,
            basic_enabled = m.basic_view ~= nil,
            basic_camo = m.basic_camo,
            table_groups = m.table_groups,
            resource_ids = m.resource_ids,
            sdk_catalog = m.sdk_catalog,
        }, {
            frame = function()
                return {
                    groups = groups,
                    palettes = palettes,
                    editor_tables = editor_tables,
                    source_tables = source_tables,
                    basic_documents = basic_documents,
                    basic_state = basic_state,
                    original_luts = original_luts,
                    pending = pending,
                    index_job = index_job,
                    populate_request = populate_request,
                    status = status,
                    loaded = edit.loaded,
                    imported = edit.imported,
                    outfit = armory_collection and armory_collection.selected,
                    camo_thumbnails = operations.camo_thumbnails,
                    load_seen = edit.load_seen or (preferences and preferences.load_seen and preferences.load_seen(
                        false
                    )) or false,
                    import_description = m.import_description,
                }
            end,
            ui = function()
                return api.mods[handle.id].controls, handle.get
            end,
            missing_reports = function()
                return basic_missing_reported
            end,
            choices = function(...)
                return current_choices(...)
            end,
            target = function(...)
                return operations.import_target(...)
            end,
            resource_id = resource_id,
            matching_plan = matching_plan,
            appearance_proof = function()
                return operations.appearance_proof()
            end,
            cape_available = function(...)
                return operations.armory_cape_available(...)
            end,
            picker_info = function()
                return operations.import_picker.info()
            end,
            time = function()
                return memory.time and memory.time() or os.clock()
            end,
            log = ctx.log,
            sync_camo = function(control, value, disabled)
                control.disabled = false
                operations.syncing_basic_camo = true
                local called, ok, why = pcall(handle.set, control.id, value)
                operations.syncing_basic_camo = false
                control.disabled = disabled
                assert(called and ok, why or ok)
            end,
        })
    end
    return operations.import_summary.info()
end
gear_edits = function()
    if not operations.gear_edits then
        operations.gear_edits = m.gear_edit.new({
            gear_catalog = m.gear_catalog,
            basic_state = m.basic_state,
            basic_camo = m.basic_camo,
            material_slot = m.engine.LUT_SLOT,
        }, {
            groups = function()
                return groups
            end,
            original = function(object)
                return original_luts and original_luts.get(object)
            end,
            proof = function()
                return appearance_proof and appearance_proof()
            end,
            key = material_key,
            refresh = function()
                return refresh(true)
            end,
            stop_identification = function()
                return stop_identification()
            end,
            applied_document = applied_document,
            resource_id = resource_id,
            panels = function()
                return import_state().raw.basic
            end,
            busy = function()
                return pending or index_job
            end,
            menu = function()
                return frontend and frontend.menu
            end,
            loaded = function()
                return edit.loaded
            end,
            set_loaded = function(document)
                edit.loaded = document
            end,
            imported = function()
                return edit.imported
            end,
            basic_document = function(key)
                return basic_documents[key]
            end,
            cape_proof = function()
                return edit.cape_proof
            end,
            editor_container = function()
                return palette_editor and palette_editor.gear
            end,
            get = function(id)
                return handle.get(id)
            end,
            set = function(id, value)
                return handle.set(id, value)
            end,
            message = message,
            apply = apply,
            apply_bindings = apply_bindings,
            sync_import = import_state,
            select_lut = function(index)
                live_select_suppressed = true
                local ok, why = handle.set('lut', index)
                live_select_suppressed = false
                assert(ok, why)
            end,
            sync_palette = function(container)
                if palette_editor then
                    if container then
                        palette_editor.gear = container
                    end
                    palette_editor.sync()
                end
            end,
            seed_document = function(key, source, label)
                return basic_state.get(key, source, label)
            end,
            remember_document = function(key, document)
                basic_documents[key] = document
            end,
            set_editor_target = function(target)
                edit.editor_target = target
            end,
            preview = function(document, revision, clear_pending)
                edit.preview_document, edit.preview_revision = document, revision
                if clear_pending then
                    editor_pending = nil
                end
            end,
            commit_camo = function(target, document)
                edit.editor_target, basic_selected = nil, target
                basic_imported, edit.loaded = edit.imported, document
                edit.preview_document, edit.preview_revision = document, document.revision
            end,
            commit_loaded_target = function(document, target, kind)
                edit.loaded, edit.editor_target = document, target
                identify_kind, basic_selected, basic_imported, edit.quick_selection = kind, nil, edit.imported, nil
            end,
            commit_copy_target = function(document, target)
                edit.loaded, basic_selected, basic_imported = document, target, edit.imported
            end,
            commit_worn_target = function(document, target)
                edit.loaded, edit.editor_target = document, target
            end,
            finish_worn_selection = function(kind)
                edit.quick_selection, identify_kind, basic_imported = nil, kind, edit.imported
            end,
            consume_populate_request = function()
                local manual = populate_request ~= nil and edit.populate_manual_request == true
                populate_request, edit.populate_manual_request = nil, nil
                return manual
            end,
            get_pattern_prime = function()
                return pattern_editor and pattern_editor.prime
            end,
            get_binding_request = function()
                return operations.request_binding_sources
            end,
            log = function(text)
                if ctx.log then
                    ctx.log(text)
                end
            end,
            clear_basic_selection = function()
                basic_selected = nil
            end,
            clear_import_selection = function()
                if import_view then
                    import_view.selected = nil
                end
            end,
            resume = function()
                resume_done, resume_job = true, nil
            end,
            commit_copied_armor = function()
                if basic_selected and basic_selected.kind == 'armor' then
                    edit.loaded = basic_documents[basic_selected.key]
                    edit.preview_document, edit.preview_revision =
                        edit.loaded, edit.loaded and edit.loaded.revision or 0
                    if palette_editor then
                        palette_editor.sync()
                    end
                end
            end,
            write_camo = function(document, targets, target)
                local previous = operations.camo_write_target
                operations.camo_write_target = target
                local ok, count = pcall(apply_bindings, document, targets)
                operations.camo_write_target = previous
                return ok, count
            end,
        })
    end
    return operations.gear_edits
end

function operations.set_basic_camo_row(row, container, checked, expected_rows)
    return gear_edits().set_camo_row(row, container, checked, expected_rows)
end
checked_editor_target = function(target)
    if target and target.kind == 'weapon' then
        return weapon_editor().check(target)
    end
    return gear_edits().check_target(target)
end
operations.checked_editor_target = checked_editor_target
local function apply_basic_camo(container, choice, mode, color)
    return gear_edits().apply_camo(container, choice, mode, color)
end
operations.apply_basic_camo = apply_basic_camo
function operations.basic_camo_picker_guard(control, container)
    return gear_edits().picker_guard(control, container)
end
local function update_camo_previews()
    if not m.camo_patterns or not m.basic_camo or not frontend or not frontend.menu or not handle then
        return
    end
    local page = api.mods[handle.id].pages[frontend.menu.page]
    local visible = frontend.menu.visible and page and page.id == 'basic'
    if
        visible
        and not operations.camo_basic_visible
        and operations.camo_source
        and operations.camo_source.state == 'closed'
    then
        operations.camo_source = nil
    end
    operations.camo_basic_visible = visible
    if visible and not operations.camo_source then
        operations.camo_source = m.camo_patterns.new(m, { time = memory.time, log = ctx.log })
        operations.camo_source.start()
    end
    local source = operations.camo_source
    if source then
        source.tick()
        if source.state == 'failed' then
            source.close()
        end
        if source.get() and not operations.camo_thumbnails then
            operations.camo_thumbnails = m.basic_camo.thumbnails(source.get())
            frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
        end
    end
end
operations.update_camo_previews = update_camo_previews
local function load_editor_target(container)
    return gear_edits().load_target(container)
end
local function apply_editor_target(container, all)
    return gear_edits().apply_target(container, all)
end
local function apply_import_to(kind)
    return gear_edits().apply_import(kind)
end
local function copy_basic_palette(destination, source_kind)
    return gear_edits().copy_palette(destination, source_kind)
end
local function copy_helmet_all()
    return gear_edits().copy_helmet_all()
end
local function remove_lut()
    resume_done = true
    resume_job = nil
    assert(restore(), 'Restoration pending')
    if pattern_editor then
        assert(pattern_editor.close(), 'Pattern restoration pending')
    elseif operations.pattern_session then
        assert(operations.pattern_session.restore(), 'Pattern restoration pending')
    end
    defaults, default_proofs = {}, {}
    if appearance then
        appearance.clear()
    end
    appearance_pending = {}
    if setup then
        setup.clear()
        edit.remember_application = false
    end
    return message('All applied LUTs removed; original bindings restored and saved application cleared.')
end
local function resume_setup()
    if resume_done or not setup then
        return
    end
    if not resume_job then
        local identity = m.avatar.resolve_live(memory, game)
        if not identity then
            return
        end
        local valid, plan, capes = pcall(setup.read)
        if not valid then
            resume_done = true
            return message('Saved setup is invalid: ' .. tostring(plan))
        end
        if not next(plan) then
            resume_done = true
            return
        end
        capes = capes or {}
        local function matches(key, b)
            local captured = capes[key]
            if not b.cape then
                return captured == nil
            end
            if not captured then
                return false
            end
            local proof = appearance_proof()
            if not proof or not proof.cape then
                return nil
            end
            if proof.cape ~= captured.proof then
                return false
            end
            local original = original_luts and original_luts.get(b.original)
            if not original then
                return nil
            end
            return original.resource == captured.resource
        end
        resume_job = coroutine.create(function()
            local documents = {}
            local total = 0
            for _, file in pairs(plan) do
                if not documents[file] then
                    local f = assert(io.open(paths.presets .. '/' .. file, 'rb'), 'Saved palette missing')
                    local bytes = f:read(m.dds.MAX_BYTES + 1)
                    f:close()
                    local data, w, h = m.dds.decode(bytes)
                    assert(w == 23 or (w == 3 and h == 1), 'Saved palette is not a material or Pattern LUT')
                    total = total + w * h * 16
                    assert(total <= 8 * 1024 * 1024, 'Saved palette budget exceeded')
                    documents[file] = { data = data, width = w, height = h }
                    coroutine.yield()
                end
            end
            local files = {}
            local has_patterns = false
            for key, file in pairs(plan) do
                local pattern = key:sub(1, 2) == 'p:'
                local document = documents[file]
                assert(
                    (pattern and document.width == 3 and document.height == 1) or (not pattern and document.width == 23),
                    'Saved LUT layout does not match its destination'
                )
                has_patterns = has_patterns or pattern
            end
            if has_patterns then
                assert(pattern_editor and operations.pattern_session, 'Pattern setup restoration unavailable')
            end
            for file, document in pairs(documents) do
                if document.width == 23 then
                    files[#files + 1] = file
                end
            end
            table.sort(files)
            palettes = {}
            local labels = {}
            for i, file in ipairs(files) do
                palettes[i] = paths.presets .. '/' .. file
                labels[i] = file == plan['armor-all']
                        and (file == plan['helmet-all'] and 'Saved Armor + Helmet' or 'Saved Armor')
                    or file == plan['helmet-all'] and 'Saved Helmet'
                    or 'Saved LUT override ' .. i
            end
            palette_choices(#labels > 0 and labels or { 'Import first' })
            if not edit.loaded and files[1] then
                edit.loaded = documents[files[1]]
                if palette_editor then
                    palette_editor.sync()
                end
            end
            local ok, changed = disable_matching()
            assert(ok, changed)
            coroutine.yield()
            coroutine.yield() -- Let the original provider release its bindings.
            local by_file = {}
            local pattern_files = {}
            local began = os.time()
            local expected = 0
            local next_scan = 0
            for key in pairs(plan) do
                if key ~= 'armor-all' and key ~= 'helmet-all' then
                    expected = expected + 1
                end
            end
            repeat
                local now = memory.time and memory.time() or os.clock()
                if now < next_scan then
                    coroutine.yield()
                else
                    next_scan = now + 0.25
                    local scanned = pcall(refresh)
                    local matched, seen = 0, {}
                    by_file = {}
                    pattern_files = {}
                    if scanned then
                        for _, group in ipairs(groups) do
                            for _, b in ipairs(group.bindings) do
                                local accepted = matches(b.save_key, b)
                                if plan[b.save_key] and accepted ~= nil and not seen[b.save_key] then
                                    matched = matched + 1
                                    seen[b.save_key] = true
                                end
                                local file = accepted and plan[b.save_key]
                                    or (b.armor and plan['armor-all'])
                                    or (b.helmet and plan['helmet-all'])
                                if file then
                                    by_file[file] = by_file[file] or {}
                                    table.insert(by_file[file], b)
                                end
                            end
                        end
                    end
                    local patterns_ready = not has_patterns or pcall(pattern_editor.scan)
                    if has_patterns and patterns_ready then
                        for _, group in ipairs(pattern_editor.all_groups or {}) do
                            for _, b in ipairs(group.bindings) do
                                local key = 'p:' .. b.save_key
                                local accepted = matches(key, b)
                                local file = accepted and plan[key]
                                if plan[key] and accepted == false and not seen[key] then
                                    matched = matched + 1
                                    seen[key] = true
                                end
                                if file then
                                    if not seen[key] then
                                        matched = matched + 1
                                        seen[key] = true
                                    end
                                    pattern_files[file] = pattern_files[file] or {}
                                    table.insert(pattern_files[file], b)
                                end
                            end
                        end
                    end
                    if scanned and patterns_ready and (matched >= expected or os.time() - began >= 10) then
                        break
                    end
                    assert(os.time() - began < 15, 'Local LUTs are not ready for the saved setup')
                    coroutine.yield()
                end
            until false
            local applied = 0
            for file, targets in pairs(by_file) do
                local checked = {}
                for _, b in ipairs(targets) do
                    if matches(b.save_key, b) then
                        checked[#checked + 1] = b
                    end
                end
                local count, texture = 0
                if #checked > 0 then
                    count, texture = apply_bindings(documents[file], checked)
                end
                applied = applied + count
                if file == plan['armor-all'] then
                    set_default('armor', texture)
                end
                if file == plan['helmet-all'] then
                    set_default('helmet', texture)
                end
                if not edit.loaded then
                    edit.loaded = documents[file]
                    if palette_editor then
                        palette_editor.sync()
                    end
                end
                coroutine.yield()
            end
            for file, targets in pairs(pattern_files) do
                local checked = {}
                for _, b in ipairs(targets) do
                    if matches('p:' .. b.save_key, b) then
                        checked[#checked + 1] = b
                    end
                end
                if #checked > 0 then
                    applied = applied + operations.pattern_session.apply(documents[file], checked)
                    remember_appearance(checked, true)
                end
                coroutine.yield()
            end
            edit.remember_application = applied > 0
            message('Saved setup restored to ' .. applied .. ' local bindings. Unmatched slots were skipped.')
        end)
    end
    local ok, why = coroutine.resume(resume_job)
    if not ok then
        resume_done = true
        resume_job = nil
        message('Saved setup could not resume: ' .. tostring(why))
    elseif coroutine.status(resume_job) == 'dead' then
        resume_done = true
        resume_job = nil
    end
end
local function commit_history_snapshot(snapshot)
    edit.imported = snapshot.imported
    if appearance then
        appearance.replace(snapshot.appearance)
    end
    appearance_pending = {}
    for key, entry in pairs(snapshot.appearance_pending) do
        local copy = {}
        for k, v in pairs(entry) do
            copy[k] = v
        end
        appearance_pending[key] = copy
    end
    edit.remember_application = snapshot.remember_application
    edit.loaded = snapshot.loaded
    defaults = snapshot.defaults
    default_proofs = snapshot.default_proofs
    palettes = snapshot.palettes
    editor_tables = snapshot.editor_tables
    index_job = nil
    editor_pending = nil
    populate_request = nil
    edit.populate_manual_request = nil
    basic_state.clear(true)
    for key, d in pairs(snapshot.basic) do
        basic_documents[key] = d
    end
    basic_selected = snapshot.selected
    edit.editor_target = snapshot.editor_target
    basic_imported = edit.imported
    edit.preview_document = edit.loaded
    edit.preview_revision = edit.loaded and edit.loaded.revision or 0
    edit.quick_selection = nil
    local labels = {}
    for i, path in ipairs(palettes) do
        labels[i] = path:match('[^/\\]+$') or path
    end
    palette_choices(#labels > 0 and labels or { 'Import first' })
    select_suppressed = true
    handle.set('palette', snapshot.palette_index)
    select_suppressed = false
    handle.set('scope', snapshot.scope)
    if palette_editor then
        palette_editor.undo = {}
        palette_editor.redo = {}
        palette_editor.sync()
    end
    if import_view then
        import_view.selected = nil
    end
    refresh(true)
    if edit.remember_application and setup then
        if #bindings.owned > 0 or (operations.pattern_session and #operations.pattern_session.owned > 0) then
            save_setup()
        else
            setup.clear()
        end
    end
    return true
end
local function create_session_history()
    return m.session_history.new({
        copier = m.basic_state.copier,
        state = function()
            if not handle then
                return nil
            end
            -- Fresh history-specific inputs, not a shared/proxy context.
            return {
                loaded = edit.loaded,
                basic = basic_documents,
                editor_tables = editor_tables,
                defaults = defaults,
                default_proofs = default_proofs,
                palettes = palettes,
                selected = basic_selected,
                editor_target = edit.editor_target,
                imported = edit.imported,
                scope = handle.get('scope'),
                palette_index = handle.get('palette'),
                appearance = appearance and appearance.entries() or {},
                appearance_pending = appearance_pending,
                remember_application = edit.remember_application,
            }
        end,
        material_session = function()
            return bindings
        end,
        pattern_session = function()
            return operations.pattern_session
        end,
        material_slot = m.engine.LUT_SLOT,
        pattern_slot = m.engine.PATTERN_SLOT,
        material_key = material_key,
        appearance_resource = appearance_resource,
        stop_identification = function()
            return stop_identification()
        end,
        appearance_proof = function()
            return appearance_proof()
        end,
        present = present,
        binding = function(b, slot)
            return m.engine.binding(read, b.material, slot, small, big)
        end,
        bind = function(b, slot, object)
            m.engine.bind(native, b.material, slot, object)
            native.commit(b.mesh)
        end,
        commit = commit_history_snapshot,
        weapon_runtime = function()
            return operations.weapon_editor and operations.weapon_editor.runtime()
        end,
    })
end

local function action_snapshots()
    if not operations.history_snapshots then
        operations.history_snapshots = create_session_history()
    end
    return operations.history_snapshots
end
local function capture_action()
    return action_snapshots().capture()
end
local function restore_action(snapshot, expected)
    return action_snapshots().restore(snapshot, expected)
end
local function refresh_outfits()
    if handle and api.mods[handle.id].controls.armory_search then
        armory_collection.filter(handle.get('armory_search'), handle.get('armory_sort'))
    else
        armory_collection.refresh()
    end
end
local function binding_sources()
    if not operations.binding_sources then
        operations.binding_sources = m.export_provenance.new({
            binding_provenance = m.binding_provenance,
            binding_source_cache = m.binding_source_cache,
            binding_provenance_script = m.binding_provenance_script,
            binding_provenance_reader = m.binding_provenance_reader,
            original_snapshot_reader = m.original_snapshot_reader,
            unit_identity = m.unit_identity,
            material_identity = m.material_identity,
            binding_unit_layout = m.binding_unit_layout,
            binding_names = m.binding_names,
            avatar = m.avatar,
            engine = m.engine,
            gear_catalog = m.gear_catalog,
            windows = m.windows,
            paths = m.paths,
        }, {
            memory = memory,
            game = game,
            paths = paths,
            appearance_read = appearance_read,
            log = ctx.log,
            lua_engine = function()
                return rawget(_G, 'stingray')
            end,
            current_identity = function()
                return m.avatar.resolve(memory, game, appearance_read)
            end,
            material_count = function(mesh)
                return native.materials(mesh)
            end,
            material_at = function(mesh, index)
                return native.material(mesh, index)
            end,
            present = present,
            binding = binding,
            groups = function()
                return groups
            end,
            pattern_groups = function()
                return pattern_editor and pattern_editor.all_groups or {}
            end,
            original = function(object)
                return original_luts and original_luts.get(object)
            end,
            applied_document = applied_document,
            refresh = refresh,
            stop_identification = stop_identification,
            stop_pattern_flash = function()
                return not pattern_editor or pattern_editor.stop_flash()
            end,
            scan_patterns = function()
                if pattern_editor then
                    pattern_editor.scan()
                end
            end,
        })
    end
    return operations.binding_sources
end
function operations.ensure_binding_provenance()
    local service = binding_sources()
    local resolver, why = service.ensure()
    if not resolver and not service.state() then
        operations.binding_sources = nil
    end
    return resolver, why
end
function operations.request_binding_sources()
    local resolver, why = operations.ensure_binding_provenance()
    if not resolver then
        return false, why
    end
    return binding_sources().request()
end
function operations.binding_export_provider(preset)
    local provider
    local weapon_provider
    local garments = { entries = {} }
    for _, entry in ipairs(preset.entries) do
        if entry.kind ~= 'weapon' then
            garments.entries[#garments.entries + 1] = entry
        end
    end
    -- A shareable ZIP does not prepare native export proof. Hydrate lazily only
    -- when the exporter actually requests an entry's exact binding source.
    return function(entry)
        if entry.kind == 'weapon' then
            weapon_provider = weapon_provider or operations.weapon_sources().provider(preset)
            return weapon_provider(entry)
        end
        if not provider then
            local resolver, why = operations.ensure_binding_provenance()
            assert(resolver, why or 'Verified named Lua binding identity unavailable')
            provider = binding_sources().provider(garments)
        end
        return provider(entry)
    end
end
function operations.export_material_source(resource)
    if operations.weapon_sources_service then
        local ok, source = pcall(operations.weapon_sources_service.material, resource)
        if ok and source then
            return source
        end
    end
    return binding_sources().material(resource)
end
function operations.export_id_available(kind, resource)
    if operations.weapon_sources_service and operations.weapon_sources_service.state() == 'ready' then
        return operations.weapon_sources_service.id_available(kind, resource)
    end
    return binding_sources().id_available(kind, resource)
end
local function capture_outfit()
    if not operations.outfit_capture then
        operations.outfit_capture = m.outfit_capture.new({ gear_catalog = m.gear_catalog }, {
            groups = function()
                return groups
            end,
            original = function(object)
                return original_luts and original_luts.get(object)
            end,
            applied_document = applied_document,
            stop_identification = stop_identification,
            stop_pattern_flash = function()
                return not pattern_editor or pattern_editor.stop_flash()
            end,
            refresh = refresh,
            current_patterns = function()
                if pattern_editor then
                    pattern_editor.scan()
                    return pattern_editor.all_groups or {}
                end
            end,
            ensure_provenance = operations.ensure_binding_provenance,
            provenance_state = function()
                return binding_sources().state()
            end,
            validate_provenance_scope = function()
                return binding_sources().validate_scope()
            end,
            log = ctx.log,
            weapon_groups = function()
                local descriptors = weapon_editor().descriptors()
                for _, descriptor in ipairs(descriptors) do
                    if descriptor.family == 'material' then
                        descriptor.family = 'main'
                    end
                end
                return descriptors
            end,
            weapon_original = function(b)
                return original_luts and original_luts.request_object(b.original)
            end,
            weapon_applied_document = function(b)
                return b.document
            end,
            weapon_proof = function(b)
                local discovery = weapon_editor().discovery()
                assert(
                    discovery.present(b) and discovery.binding(b) == b.current,
                    'Weapon binding changed before saving'
                )
                return {
                    weapon_slot = b.weapon_slot,
                    weapon_resource = b.weapon_resource,
                    validate = function()
                        return discovery.present(b) and discovery.binding(b) == b.current
                    end,
                }
            end,
            capture_weapon_provenance = function(b, context)
                local _, refs = operations.weapon_sources().capture(b, context)
                return refs
            end,
        })
    end
    return operations.outfit_capture
end
local function keep_outfit(name, save_kind)
    assert(outfits, 'Outfit storage unavailable')
    local capture = capture_outfit()
    local entries, scope_label, summary = capture.capture(save_kind)
    armory_collection.save(name, entries)
    capture.report_saved(summary, #entries)
    if api.mods[handle.id].controls.armory_search then
        assert(handle.set('armory_search', ''))
    end
    capture.mark_saved(entries)
    if frontend.menu then
        frontend.menu.outfit_dialog = nil
        frontend.menu.text_edit = nil
    end
    return message('Saved ' .. name .. ' with ' .. scope_label .. ' LUTs in The Armory.')
end
function operations.outfit_documents(preset)
    if m.outfit_targets then
        local resolver = m.outfit_targets.new(preset, {
            document_bytes = function(d)
                return m.dds.encode(d.data, d.width, d.height)
            end,
        })
        local live = {}
        for _, collection in ipairs({ groups, pattern_editor and pattern_editor.all_groups or {} }) do
            local pattern = collection ~= groups
            for _, group in ipairs(collection) do
                for _, b in ipairs(group.bindings) do
                    if present(b) and binding(b) == b.current then
                        live[#live + 1] = {
                            kind = m.gear_catalog.kind(b),
                            binding = b,
                            pattern = pattern,
                            original = original_luts and original_luts.get(b.original),
                        }
                    end
                end
            end
        end
        resolver.prepare(live)
        return resolver
    end
    local exact = {}
    for _, entry in ipairs(preset and preset.entries or {}) do
        exact[entry.kind .. ':' .. entry.key] = entry.document
    end
    return exact
end
function operations.outfit_document(exact, b, pattern)
    if exact.resolve then
        return exact.resolve(m.gear_catalog.kind(b), b, pattern, original_luts and original_luts.get(b.original))
    end
    local key = (pattern and 'p:' or '') .. b.save_key
    -- Early presets recorded every non-Helmet mount as Armor. Only a currently
    -- recognized Cape at the exact saved destination can use that legacy entry.
    return exact[m.gear_catalog.kind(b) .. ':' .. key] or (b.cape and exact['armor:' .. key])
end
function operations.armory_cape_available(preset)
    local proof = preset and appearance_proof()
    if not proof or not proof.cape then
        return false
    end
    local exact = operations.outfit_documents(preset)
    for _, collection in ipairs({ groups, pattern_editor and pattern_editor.all_groups or {} }) do
        local pattern = collection ~= groups
        for _, group in ipairs(collection) do
            for _, b in ipairs(group.bindings) do
                local d = b.cape and operations.outfit_document(exact, b, pattern)
                if d and present(b) and binding(b) == b.current and appearance_resource(b) then
                    if pattern and d.width == 3 and d.height == 1 or not pattern and d.width == 23 then
                        return true
                    end
                end
            end
        end
    end
    return false
end
function operations.sync_armory_cape()
    local controls = handle and api.mods[handle.id].controls
    if controls and controls.outfit_apply_cape then
        controls.outfit_apply_cape.disabled =
            not operations.armory_cape_available(armory_collection and armory_collection.selected)
    end
end
local function armory_actions()
    if not operations.armory_actions then
        operations.armory_actions = m.armory_apply.new({
            gear_catalog = m.gear_catalog,
            material_slot = m.engine.LUT_SLOT,
            pattern_slot = m.engine.PATTERN_SLOT,
        }, {
            selected = function()
                return armory_collection and armory_collection.selected
            end,
            weapon_plan = function(preset, options)
                return operations.weapon_workflow().plan(preset, options)
            end,
            apply_weapon_plan = function(plan)
                return plan.apply()
            end,
            menu = function()
                return frontend.menu
            end,
            cape_available = operations.armory_cape_available,
            documents = operations.outfit_documents,
            document = operations.outfit_document,
            has_patterns = function()
                return pattern_editor ~= nil
            end,
            pattern_groups = function()
                return pattern_editor and pattern_editor.all_groups or {}
            end,
            pattern_session = function()
                return operations.pattern_session
            end,
            material_session = function()
                return bindings
            end,
            stop_patterns = function()
                return pattern_editor.stop_flash()
            end,
            scan_patterns = function()
                return pattern_editor.scan()
            end,
            stop_identification = stop_identification,
            refresh = function()
                return refresh(true)
            end,
            groups = function()
                return groups
            end,
            original = function(object)
                return original_luts and original_luts.get(object)
            end,
            key = material_key,
            resource = appearance_resource,
            proof = appearance_proof,
            choices = current_choices,
            target = import_target,
            present = present,
            binding = binding,
            resource_id = resource_id,
            log = ctx.log,
            message = message,
            clear_default = function(kind)
                set_default(kind, nil)
            end,
            capture = capture_action,
            restore = restore_action,
            capture_history = function()
                return history and history.capture()
            end,
            record_history = function(before)
                history.record(before, history.capture())
            end,
            begin_application = function()
                resume_done, resume_job = true, nil
            end,
            remember_basic = function(b, d)
                basic_documents[m.gear_catalog.kind(b) .. ':' .. tostring(b.original)] =
                    m.basic_state.clone(d, d.source)
            end,
            finish_application = function()
                edit.remember_application = true
                save_setup()
            end,
            apply_batch = function(document, targets, pattern, cape_proof, proofs)
                local previous, previous_proofs = operations.armory_cape_proof, operations.lut_apply_proofs
                operations.armory_cape_proof, operations.lut_apply_proofs = cape_proof, proofs
                local ok, count = pcall(function()
                    if cape_proof then
                        local proof = appearance_proof()
                        assert(proof and proof.cape == cape_proof, 'Cape kit changed; load current gear again')
                    end
                    if pattern then
                        local session = assert(operations.pattern_session, 'Pattern application unavailable')
                        local applied = session.apply(document, targets)
                        remember_appearance(targets, true)
                        return applied
                    end
                    return apply_bindings(document, targets)
                end)
                operations.armory_cape_proof, operations.lut_apply_proofs = previous, previous_proofs
                assert(ok, count)
                return count
            end,
        })
    end
    return operations.armory_actions
end
local function apply_outfit(kind, selection)
    return armory_actions().apply(kind, selection)
end
function operations.choose_outfit_luts()
    return armory_actions().choose_luts()
end
local function import_mapping()
    if not operations.mapping_chooser then
        operations.mapping_chooser = m.import_mapping.new({
            gear_catalog = m.gear_catalog,
            slots = { material = m.engine.LUT_SLOT, pattern = m.engine.PATTERN_SLOT },
            menu = function()
                return frontend.menu
            end,
            message = message,
            pixels = function(d)
                return d and ffi.string(d.data, d.width * d.height * 16)
            end,
            imports = {
                palettes = function()
                    return palettes
                end,
                document = function(path)
                    return editor_tables[path] or source_tables[path]
                end,
                resource = function(path, d)
                    return import_ids[path] or source_tables[path] and source_tables[path].resource or d and d.resource
                end,
                pending = function()
                    return pending
                end,
                indexing = function()
                    return index_job
                end,
                selected = function()
                    return handle.get('palette')
                end,
                defer = function(kind, catalog)
                    operations.import_map_request = { kind = kind, palettes = catalog }
                    if not index_job then
                        index_job = table_index.start(catalog, source_tables, import_ids)
                    end
                end,
            },
            gear = {
                proof = function()
                    return appearance_proof()
                end,
                refresh = function()
                    return refresh(true)
                end,
                choices = current_choices,
                target = function(kind, group)
                    return import_target(kind, group)
                end,
                groups = function()
                    return groups
                end,
                original = function(object)
                    return original_luts and original_luts.get(object)
                end,
                originals_ready = function()
                    return original_luts.loaded
                end,
                present = present,
                binding = binding,
                material_key = material_key,
            },
            patterns = {
                stop_flash = function()
                    return not pattern_editor or pattern_editor.stop_flash()
                end,
                scan = function()
                    if pattern_editor then
                        return pattern_editor.scan()
                    end
                end,
                groups = function()
                    return pattern_editor and pattern_editor.all_groups or {}
                end,
                apply = function(document, targets)
                    return assert(operations.pattern_session, 'Pattern application unavailable').apply(
                        document,
                        targets
                    )
                end,
            },
            application = {
                stop_identification = function()
                    return stop_identification()
                end,
                preserve_emissives = function()
                    return handle.get('preserve_emissives')
                end,
                preserve = function(document, original, extended)
                    return m.original_luts.preserve(document, original, extended)
                end,
                set_default = set_default,
                apply = apply_bindings,
                remember_appearance = remember_appearance,
                remember_document = function(kind, original, document)
                    basic_documents[kind .. ':' .. tostring(original)] = m.basic_state.clone(document, document.source)
                end,
                with_proofs = function(proof, cape, action)
                    local previous_proofs, previous_cape = operations.lut_apply_proofs, operations.armory_cape_proof
                    operations.lut_apply_proofs, operations.armory_cape_proof = proof, cape
                    local ok, value = pcall(action)
                    operations.lut_apply_proofs, operations.armory_cape_proof = previous_proofs, previous_cape
                    return ok, value
                end,
                finish = function()
                    edit.remember_application, resume_done, resume_job = true, true, nil
                    save_setup()
                end,
            },
            history = {
                capture = function()
                    return assert(history, 'Mapping history is unavailable; reopen Epic LUT').capture()
                end,
                record = function(before, after)
                    return history.record(before, after)
                end,
                restore = restore_action,
                current = capture_action,
            },
        })
    end
    return operations.mapping_chooser
end
function operations.open_import_map(kind, prepared)
    return import_mapping().open(kind, prepared)
end
local function gear_exports()
    if not operations.gear_export then
        operations.gear_export = m.gear_export.new({
            engine = m.engine,
            gear_catalog = m.gear_catalog,
            preset_export = m.preset_export,
            patch_export = m.patch_export,
            dds = m.dds,
            export_pairing = m.export_pairing,
            bulk_dds_export = m.bulk_dds_export,
            lut_files = m.lut_files,
            resource_ids = m.resource_ids,
            file_io = m.file_io,
        }, {
            paths = paths,
            armory_options = function()
                if handle then
                    local controls = api.mods[handle.id].controls
                    return {
                        selected = armory_collection and armory_collection.selected,
                        export = controls.armory_export,
                        lut = controls.armory_export_lut,
                    }
                end
            end,
            armory_format = function()
                return handle.get('armory_export_format')
            end,
            armory_lut = function()
                return handle.get('armory_export_lut')
            end,
            set_armory_lut = function(index)
                return handle.set('armory_export_lut', index)
            end,
            sync_armory_cape = operations.sync_armory_cape,
            export_preference = function(name)
                local reader = preferences and preferences[name]
                if reader then
                    return reader(), true
                end
                return nil, false
            end,
            export_control = function(name)
                local control = handle and api.mods[handle.id].controls[name]
                return control and handle.get(name), not not control
            end,
            selected = function()
                if frontend.basic_mode then
                    return basic_selected
                end
                return edit.editor_target
            end,
            current_lut = function()
                return handle.get('lut')
            end,
            checked_target = checked_editor_target,
            refresh = refresh,
            groups = function()
                return groups
            end,
            original = function(object)
                return original_luts and original_luts.get(object)
            end,
            original_resource = function(resource)
                return original_luts and original_luts.get_resource(resource)
            end,
            present = present,
            binding = binding,
            applied_document = applied_document,
            material_key = material_key,
            stop_identification = stop_identification,
            has_patterns = function()
                return pattern_editor ~= nil
            end,
            scan_patterns = function(quick)
                return pattern_editor.scan(quick)
            end,
        })
    end
    return operations.gear_export
end
local function sync_armory_export()
    return gear_exports().sync_armory_options()
end
local function include_capes_in_exports()
    return gear_exports().include_capes()
end
function operations.include_patterns_in_exports()
    return gear_exports().include_patterns()
end
function operations.selected_export_bindings(required)
    return gear_exports().selected_bindings(required)
end
function operations.export_original_patch(entry)
    return gear_exports().original_patch(entry)
end
function operations.export_pattern_entries(targets, pattern_groups)
    return gear_exports().pattern_entries(targets, pattern_groups)
end
local function export_custom_dds(name, naming)
    local folder, count = gear_exports().custom_dds(name, naming)
    return message('Exported ' .. count .. ' custom LUT DDS files to ' .. folder)
end
local function select_outfit(index)
    if armory_collection then
        armory_collection.select(index)
        sync_armory_export()
        if armory_collection.selected then
            assert(handle.set('armory_export_name', armory_collection.selected.name))
        end
    else
        assert(index == 1, 'Armory collection unavailable')
    end
end
local function manage_outfit(mode)
    if api.mods[handle.id].controls.armory_search then
        assert(handle.set('armory_search', ''))
    end
    return assert(armory_collection, 'Armory collection unavailable').manage(
        mode,
        assert(frontend.menu),
        api.mods[handle.id],
        message
    )
end
local function paint_quick(q, hex)
    return action(function()
        assert(q and q.document == edit.loaded, 'Select an editable region first')
        local target = edit.editor_target
        local index = target and checked_editor_target(target)
        if palette_editor then
            assert(palette_editor.can_pick(q.row, q.column, 1))
            palette_editor.paint_rgb(q.row, q.column, hex)
        else
            local r, g, b = m.palette.rgb(hex)
            local at = ((q.row - 1) * edit.loaded.width + q.column - 1) * 4
            edit.loaded.data[at], edit.loaded.data[at + 1], edit.loaded.data[at + 2] = r, g, b
            edit.loaded.revision = (edit.loaded.revision or 0) + 1
        end
        if target then
            live_select_suppressed = true
            local ok, why = handle.set('lut', index)
            live_select_suppressed = false
            assert(ok, why)
            assert(handle.set('scope', 1))
            apply(edit.loaded, target.kind)
            edit.preview_document = edit.loaded
            edit.preview_revision = edit.loaded.revision or 0
        end
        return true
    end)
end
local function select_import_cell(entry, row, column, identify, kind)
    kind = entry.kind or kind
    if entry.index then
        basic_selected = nil
        edit.editor_target = entry.target or operations.import_target(kind, entry.index)
        entry.index = checked_editor_target(edit.editor_target)
    end
    if identify or entry.index then
        identify_kind = (kind == 'armor' or kind == 'helmet' or kind == 'cape') and kind or nil
        if entry.index then
            live_select_suppressed = true
            local ok, why = handle.set('lut', entry.index)
            live_select_suppressed = false
            assert(ok, why)
        end
    end
    if not edit.loaded or (edit.loaded.data ~= entry.data and m.quick_source ~= entry.data) then
        local data = ffi.new('float[?]', entry.width * entry.height * 4)
        ffi.copy(data, entry.data, entry.width * entry.height * 16)
        edit.loaded = { data = data, width = entry.width, height = entry.height, source = entry.source or entry.name }
    end
    m.quick_source = entry.data
    local data = edit.loaded.data
    if entry.source then
        editor_tables[entry.source] = edit.loaded
    end
    edit.quick_selection = { row = row, column = column, document = edit.loaded }
    edit.preview_document = edit.loaded
    edit.preview_revision = edit.loaded.revision or 0
    if palette_editor then
        palette_editor.focus_cell(row, column)
    end
    local at = ((row - 1) * entry.width + column - 1) * 4
    -- Setting the picker seed must not edit the selected table.
    edit.quick_selection = nil
    assert(
        handle.set(
            'quick_color',
            string.format(
                '#%02X%02X%02X',
                math.floor(math.max(0, math.min(1, data[at])) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, data[at + 1])) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, data[at + 2])) * 255 + 0.5)
            )
        )
    )
    edit.quick_selection = { row = row, column = column, document = edit.loaded }
end
weapon_editor = function()
    if not operations.weapon_editor then
        operations.weapon_editor = m.weapon_bridge.new(m, {
            memory = function()
                return memory
            end,
            native = function()
                return native
            end,
            engine = function()
                return rawget(_G, 'stingray')
            end,
            retain = function()
                return retain
            end,
            cohort = function()
                return operations.texture_cohort
            end,
            remote_authorized = function(peer, slot, resource)
                if not sharing or not handle or not handle.get('share_appearance') then
                    return false, 'Shared LUT is disabled'
                end
                return sharing.authorized(peer, slot, resource)
            end,
            original = function(object)
                return original_luts and original_luts.request_object(object)
            end,
            bind = function(b, object)
                m.engine.bind(native, b.material, b.slot, object)
                native.commit(b.mesh)
            end,
            create_texture = function(w, h, data)
                return m.engine.create_texture(native, w, h, data, read, small)
            end,
            busy = function()
                return pending ~= nil or index_job ~= nil
            end,
            message = message,
            weapon_name = function(slot, resource)
                return m.weapon_names and m.weapon_names[resource] or ({ 'Primary', 'Secondary', 'Support' })[slot]
            end,
            load_editor = function(document, target)
                assert(stop_identification(), 'Highlight restoration pending')
                edit.loaded = m.weapon_mapping.copy(document)
                edit.loaded.source, edit.loaded.revision = target.label or 'Weapon LUT', 0
                edit.loaded.kind, edit.loaded.family = 'weapon', target.family == 'pattern' and 'pattern' or 'material'
                edit.loaded.weapon_slot, edit.loaded.weapon_resource = target.weapon_slot, target.weapon_resource
                edit.editor_target = target
                edit.preview_document, edit.preview_revision = edit.loaded, edit.loaded.revision or 0
                basic_selected, identify_kind, edit.quick_selection = nil, nil, nil
                if palette_editor then
                    palette_editor.gear = 'weapon'
                    palette_editor.sync()
                end
            end,
            open_editor = function(cell)
                if frontend.basic_mode then
                    frontend.open_advanced()
                end
                api.focus_page(handle.id, 'colors')
                if cell and cell.row then
                    palette_editor.focus_cell(cell.row, cell.column or 1)
                end
                if cell and cell.picker then
                    palette_editor.request_picker = { document = edit.loaded, mode = cell.alpha_only and 6 or 1 }
                end
                return true
            end,
            invalidate = function(changed)
                local target = edit.editor_target
                if target and target.kind == 'weapon' then
                    for _, slot in ipairs(changed) do
                        if slot == target.weapon_slot and edit.loaded then
                            edit.loaded.stale = true
                        end
                    end
                end
            end,
            imports = function()
                return palettes
            end,
            import = function()
                return operations.import_picker.load(true)
            end,
            map_imports = function(targets, options)
                return operations.weapon_workflow().map(targets, options)
            end,
            save_preset = function(targets)
                return operations.weapon_workflow().save(targets)
            end,
            export = function(targets)
                return operations.weapon_workflow().export(targets)
            end,
            share = function()
                assert(handle.set('share_appearance', true))
                return message('Shared LUT enabled for your applied gear and weapon palettes.')
            end,
        })
    end
    return operations.weapon_editor
end
function operations.weapon_workflow()
    if not operations.weapon_workflow_service then
        operations.weapon_workflow_service = m.weapon_workflow.new(m, {
            bridge = weapon_editor,
            menu = function()
                return frontend.menu
            end,
            mod = function()
                return api.mods[handle.id]
            end,
            outfits = function()
                return outfits
            end,
            original = function(b)
                return original_luts and original_luts.request_object(b.original)
            end,
            provenance = function(b, context)
                local _, refs = operations.weapon_sources().capture(b, context)
                return refs
            end,
            invalidate = function(name)
                refresh_outfits()
                armory_collection.select_name(name)
                sync_armory_export()
            end,
            message = message,
            imports = {
                palettes = function()
                    return palettes
                end,
                document = function(path)
                    return source_tables[path]
                end,
                resource = function(path, document)
                    return import_ids[path] or document.resource
                end,
                pending = function()
                    return pending ~= nil
                end,
                indexing = function()
                    return index_job ~= nil
                end,
            },
            prepare_imports = function(descriptors, options)
                assert(not pending and not index_job, 'Wait for imported LUTs to finish loading')
                local missing = false
                for _, path in ipairs(palettes) do
                    missing = missing or source_tables[path] == nil
                end
                if missing then
                    operations.weapon_map_request =
                        { descriptors = descriptors, options = options, palettes = palettes }
                    index_job = table_index.start(palettes, source_tables, import_ids)
                    message('Reading imported LUTs for weapon mapping…')
                    return false
                end
                return true
            end,
            export_options = function()
                return handle.get('armory_export_name'),
                    handle.get('armory_export_format'),
                    handle.get('armory_dds_naming')
            end,
            exporter = function(preset)
                return m.preset_export.new(m, paths, {
                    include_patterns = function()
                        return true
                    end,
                    binding_provenance = operations.binding_export_provider(preset),
                    original_patch = operations.export_original_patch,
                    material_source = operations.export_material_source,
                    unit_layout = m.binding_unit_layout,
                    resource_id_available = operations.export_id_available,
                    weapon_patch_archive = function(entries)
                        return operations.weapon_sources().patch_archive(entries)
                    end,
                    weapon_export_batch = function(entries, serialize)
                        return operations.weapon_sources().with_export_batch(entries, serialize)
                    end,
                })
            end,
        })
    end
    return operations.weapon_workflow_service
end
function operations.weapon_sources()
    if not operations.weapon_sources_service then
        operations.weapon_sources_service = assert(m.weapon_provenance, 'Weapon provenance module unavailable').new(m, {
            discovery = function()
                return weapon_editor().discovery()
            end,
            groups = function()
                return weapon_editor().descriptors()
            end,
            original = function(b)
                return original_luts and original_luts.request_object(b.original)
            end,
            paths = paths,
            memory = memory,
            game = game,
            native = native,
            lua_engine = function()
                return rawget(_G, 'stingray')
            end,
            log = ctx.log,
        })
    end
    return operations.weapon_sources_service
end
function operations.weapon_sharing()
    if not operations.weapon_sharing_service then
        local editor = weapon_editor()
        operations.weapon_sharing_service = m.weapon_shared.new({
            runtime = editor.runtime(),
            discovery = editor.discovery(),
            weapon_mapping = m.weapon_mapping,
            remote_snapshot = editor.remote_snapshot,
            remote_authorized = function(peer, slot, resource)
                if not sharing or not handle or not handle.get('share_appearance') then
                    return false
                end
                return sharing.authorized(peer, slot, resource)
            end,
            original = function(object)
                return original_luts and original_luts.request_object(object)
            end,
            binding_session = m.binding_session,
            retain = retain,
            cohort = operations.texture_cohort,
            create_texture = function(w, h, data)
                return m.engine.create_texture(native, w, h, data, read, small)
            end,
            bind = function(b, object)
                m.engine.bind(native, b.material, b.slot, object)
                native.commit(b.mesh)
            end,
        })
    end
    return operations.weapon_sharing_service
end
local function register(current)
    if api == current and handle then
        return
    end
    if handle then
        handle.unregister()
    end
    api = current
    local callbacks = m.editor_actions.new({
        action = action,
        message = message,
        dds = m.dds,
        handle = function()
            return handle
        end,
        mod = function()
            return api.mods[handle.id]
        end,
        frontend = function()
            return frontend
        end,
        preferences = function()
            return preferences
        end,
        palette_editor = function()
            return palette_editor
        end,
        import_view = function()
            return import_view
        end,
        history = function()
            return history
        end,
        armory_collection = function()
            return armory_collection
        end,
        outfits = function()
            return outfits
        end,
        quick_selection = function()
            return edit.quick_selection
        end,
        loaded_document = function()
            return edit.loaded
        end,
        imported_document = function()
            return edit.imported
        end,
        group = function(index)
            return groups[index]
        end,
        original = function(object)
            return original_luts and original_luts.get(object)
        end,
        group_original = function(index)
            return original_luts and original_luts.get(groups[index].object)
        end,
        basic_document = function(b)
            return basic_documents[m.gear_catalog.kind(b) .. ':' .. tostring(b.original)]
        end,
        current_page = function()
            return frontend.menu and api.mods[handle.id].pages[frontend.menu.page].id
        end,
        lut_label_resource = function()
            local panel = import_state().raw.basic[palette_editor and palette_editor.gear or 'armor']
            local original = panel and panel.group and original_luts and original_luts.get(groups[panel.group].object)
            return original and original.resource
        end,
        lut_labels = function()
            return operations.lut_names
        end,
        import_state = import_state,
        load = load,
        cancel_import = cancel_import,
        load_debug_lut = operations.load_debug_lut,
        paint_quick = operations.paint_quick,
        apply_matching = operations.apply_matching,
        open_editor = function()
            return api.focus_page(handle.id, 'colors')
        end,
        manage_outfit = operations.manage_outfit,
        select_outfit = select_outfit,
        sync_armory_export = sync_armory_export,
        apply_outfit = apply_outfit,
        armory_cape_available = operations.armory_cape_available,
        choose_outfit_luts = operations.choose_outfit_luts,
        open_import_map = operations.open_import_map,
        mark_current_load = mark_current_load,
        load_editor_target = load_editor_target,
        apply_editor_target = apply_editor_target,
        apply_import_to = apply_import_to,
        copy_basic_palette = copy_basic_palette,
        copy_helmet_all = copy_helmet_all,
        identify_region = identify_region,
        stop_identification = function()
            return stop_identification()
        end,
        populate_worn = populate_worn,
        refreshing_basic_presets = function()
            return edit.refreshing_basic_presets
        end,
        basic_preset_name = function(index)
            return basic_names[index - 1]
        end,
        presets_directory = function()
            return paths.presets
        end,
        preset_files = function()
            return operations.preset_files
        end,
        refresh_basic_presets = function(name)
            return operations.refresh_basic_presets(name)
        end,
        save_palette = save_palette,
        apply_checked = apply_checked,
        refresh = refresh,
        apply = apply,
        remove_lut = remove_lut,
        save_setup = save_setup,
        keep_outfit = keep_outfit,
        weapon_enabled = m.weapon_bridge ~= nil,
        appearance_proof = function()
            return operations.appearance_proof()
        end,
        live_selection_suppressed = function()
            return live_select_suppressed
        end,
        palette_path = function(index)
            return not select_suppressed and not pending and palettes[index] or nil
        end,
        queue_editor_target = function(kind)
            editor_pending = { kind = kind, began = os.time() }
        end,
        request_population = function()
            if original_luts and original_luts.retry then
                original_luts.retry()
            end
            populate_request = os.time()
            edit.populate_manual_request = true
        end,
        accept_basic_preset = function(document)
            edit.loaded = document
        end,
        resume_palette = function(path)
            resume_done = true
            resume_job = nil
            return load_dds(path)
        end,
        clear_live_draft = function()
            edit.loaded = nil
            basic_selected = nil
            edit.quick_selection = nil
        end,
        accept_live_draft = function(document)
            edit.loaded = document
            edit.preview_document = edit.loaded
            edit.preview_revision = 0
        end,
        accept_applied_draft = function(document)
            edit.loaded = document
            edit.preview_document = edit.loaded
            edit.preview_revision = 0
            edit.quick_selection = nil
        end,
        clear_removed_draft = function()
            edit.loaded = nil
            edit.imported = nil
            palettes = {}
        end,
        restoration_selection = function()
            return basic_selected,
                (edit.editor_target and edit.editor_target.kind) or (basic_selected and basic_selected.kind)
        end,
        clear_restoration_draft = function()
            basic_state.clear()
            basic_missing_reported = {}
            edit.quick_selection = nil
            edit.loaded = nil
        end,
        clear_basic_selection = function()
            basic_selected = nil
        end,
        accept_restored_draft = function(document, selected)
            edit.loaded = document
            basic_selected = selected
            basic_imported = edit.imported
            edit.preview_document = edit.loaded
            edit.preview_revision = edit.loaded and (edit.loaded.revision or 0) or 0
        end,
        export_armory = function()
            local preset =
                assert(armory_collection and armory_collection.selected, 'Choose a saved Armory preset first')
            local exporter = assert(m.preset_export, 'Armory exporter unavailable').new(m, paths, {
                include_capes = function()
                    return operations.include_capes_in_exports()
                end,
                include_patterns = operations.include_patterns_in_exports,
                binding_provenance = operations.binding_export_provider(preset),
                original_patch = operations.export_original_patch,
                material_source = operations.export_material_source,
                unit_layout = m.binding_unit_layout,
                weapon_patch_archive = function(entries)
                    return operations.weapon_sources().patch_archive(entries)
                end,
                weapon_export_batch = function(entries, serialize)
                    return operations.weapon_sources().with_export_batch(entries, serialize)
                end,
                resource_id_available = function(kind, id)
                    return operations.export_id_available(kind, id)
                end,
            })
            local output, description, sharefile = exporter.save(
                handle.get('armory_export_name'),
                preset,
                handle.get('armory_export_format'),
                handle.get('armory_export_lut'),
                handle.get('armory_dds_naming')
            )
            return message('Exported ' .. preset.name .. ' (' .. description .. ') to ' .. (sharefile or output))
        end,
    })
    local composition = m.editor_composition.new({
        registry = m.editor_registry,
        configuration = m.configuration,
        configuration_view = m.configuration_view,
        basic_view = m.basic_view,
        basic_camo = m.basic_camo,
        armory_view = m.armory_view,
        import_view = m.import_view,
        table_groups = m.table_groups,
        ui_core = m.ui_core,
        control_help = m.control_help,
        value_tooltip = m.palette.value_tooltip,
        key_name = m.ui_menu and m.ui_menu.key_name,
        sharing_enabled = not not m.shared_appearance,
        preferences = preferences,
        updates = updates,
        action = action,
        message = message,
        info = import_state,
        palette_editor = function()
            return palette_editor
        end,
        pattern_editor = function()
            return pattern_editor
        end,
        weapon_editor = m.weapon_bridge and weapon_editor or nil,
        weapon_view = m.weapon_view,
        open_weapons = function()
            api.focus_page(handle.id, 'weapons')
            return weapon_editor().load_current()
        end,
        apply_weapon_document = function()
            return action(function()
                assert(edit.editor_target and edit.editor_target.kind == 'weapon', 'Load a weapon LUT first')
                return weapon_editor().apply(edit.editor_target, edit.loaded)
            end)
        end,
        auto_populate_changed = function(enabled)
            edit.auto_signature = nil
            if enabled then
                edit.populate_manual_request = nil
                populate_request = os.time()
                populate_next = 0
            end
            return true
        end,
        resource_changed = function()
            if handle then
                import_state()
                if frontend.menu then
                    frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
                end
            end
        end,
        apply_camo = function(kind, value, mode, color)
            if not operations.syncing_basic_camo then
                local completed
                local result = action(function()
                    local text = operations.apply_basic_camo(kind, value, mode, color)
                    completed = true
                    return text
                end)
                if mode == 'color' then
                    return completed == true, result
                end
                return result
            end
        end,
        search_armory = function(value)
            armory_collection.filter(value, handle.get('armory_sort'))
        end,
        sort_armory = function(value)
            armory_collection.filter(handle.get('armory_search'), value)
        end,
        sharing_status_control = function(control)
            edit.sharing_status_control = control
        end,
        default_mod = function(id)
            frontend.default_mod_id = id
        end,
        remove_outfit_choice = armory_collection and function(index, label)
            local ok, result = armory_collection.remove_choice(index, label)
            sync_armory_export()
            return ok, result
        end,
        gear_ready = function()
            return edit.loaded ~= nil or edit.imported ~= nil
        end,
        load_seen = function()
            return edit.load_seen or (preferences and preferences.load_seen and preferences.load_seen(false)) or false
        end,
        camo_picker_guard = function(control, container)
            return operations.basic_camo_picker_guard(control, container)
        end,
        quick_selection = function()
            return edit.quick_selection
        end,
        loaded_document = function()
            return edit.loaded
        end,
        validate_quick_target = function()
            if edit.editor_target then
                return pcall(operations.checked_editor_target, edit.editor_target)
            end
            return true
        end,
        refresh_outfits = m.outfit_presets and refresh_outfits or nil,
        select_basic = function(row, kind)
            if kind then
                local panel = import_state().raw.basic[kind]
                if not panel or not panel.document then
                    message('Reading worn ' .. kind .. ' colors; try again when ready.')
                    return false
                end
                local proof = operations.appearance_proof()
                local original = original_luts and original_luts.get(groups[panel.group].object)
                if panel.kind == 'cape' then
                    assert(
                        proof and proof.cape and original and original.resource,
                        'Current Cape identity is still loading; load current colors again'
                    )
                end
                edit.editor_target = nil
                basic_selected = {
                    kind = panel.kind or kind,
                    container = kind,
                    key = panel.key,
                    group = panel.group,
                    cape_proof = panel.kind == 'cape' and proof and proof.cape or nil,
                    resource = original and original.resource,
                }
                edit.loaded = panel.document
                basic_imported = edit.imported
                edit.preview_document = edit.loaded
                edit.preview_revision = edit.loaded.revision or 0
                palette_editor.sync()
            end
            if edit.loaded and palette_editor then
                palette_editor.focus_cell(row, 1)
                return true
            end
        end,
        set_camo_row = function(...)
            return operations.set_basic_camo_row(...)
        end,
        initialize_basic_presets = function()
            operations.refresh_basic_presets = function(previous)
                local selector = api.mods[handle.id].controls.basic_preset
                previous = previous or selector.choices[handle.get('basic_preset')]
                basic_names = {}
                local choices, selected = { 'New preset...' }, 1
                for _, file in
                    ipairs(m.windows and m.windows.files and m.windows.files(paths.presets, 'palette-*.dds') or {})
                do
                    local name = file:match('^palette%-([%w _-]+)%.dds$')
                    if name then
                        basic_names[#basic_names + 1] = name
                        choices[#choices + 1] = name
                        if name == previous then
                            selected = #choices
                        end
                    end
                end
                selector.choices = choices
                edit.refreshing_basic_presets = true
                local called, ok, why = pcall(handle.set, 'basic_preset', selected)
                edit.refreshing_basic_presets = false
                assert(called and ok, called and why or ok)
            end
            api.mods[handle.id].controls.basic_preset.on_delete_choice = function(index, label)
                local name = assert(basic_names[index - 1], 'Choose a saved palette preset')
                assert(name == label, 'Preset list changed; reopen it before removing a preset')
                operations.preset_files.delete_palette(name)
                if handle.get('basic_preset_name') == name then
                    assert(handle.set('basic_preset_name', ''))
                end
                operations.refresh_basic_presets()
                return true, 'Removed saved palette preset: ' .. name
            end
            operations.refresh_basic_presets()
        end,
        select_import_cell = function(...)
            return operations.select_import_cell(...)
        end,
    })
    local pages = composition.pages(callbacks, current, {
        ui_scale = preferences.scale and preferences.scale() or 100,
        status = status,
    })
    handle = api.register({ id = 'epic_direct_lut', name = 'Epic LUT', pages = pages })
    local mounted_import_view = composition.mount(api, handle)
    if m.import_view then
        import_view = mounted_import_view
    end
    groups = {}
end
local function close()
    -- Loader cleanup polls replace normal updates. Hide retained UI and release
    -- its input lease before any worker or native cleanup can defer unloading.
    local dismissed = not frontend or not frontend.dismiss or frontend.dismiss()
    local portrait = package.loaded['epic.player_preview.v1']
    if portrait and portrait.before_editor_close then
        local ok, done = pcall(portrait.before_editor_close)
        if not ok or not done then
            return false
        end
    end
    if operations.camo_source and not operations.camo_source.close() then
        return false
    end
    if operations.binding_sources and not operations.binding_sources.close() then
        return false
    end
    if operations.weapon_sources_service and not operations.weapon_sources_service.close() then
        return false
    end
    if armory_mirror and not armory_mirror.close() then
        return false
    end
    if stop_identification and not stop_identification() then
        return false
    end
    if pattern_editor and not pattern_editor.stop_flash() then
        return false
    end
    if edit.remember_application and setup then
        local ok, why = pcall(save_setup)
        if not ok then
            message('Could not remember applied preset: ' .. tostring(why))
        end
        edit.remember_application = false
    end
    if pattern_editor and not pattern_editor.close() then
        return false
    end
    if sharing and not sharing.close() then
        return false
    end
    if operations.import_picker and not operations.import_picker.close() then
        return false
    end
    pending = nil
    if original_luts then
        original_luts.close()
    end
    if updates then
        updates.close()
    end
    if not restore(operations.texture_lifetime ~= nil) then
        return false
    end
    if not dismissed then
        return false
    end
    if operations.texture_lifetime then
        operations.texture_cohort.cleanup_ready = true
        local done = operations.texture_lifetime.close()
        local state = operations.texture_lifetime
        if not done then
            if operations.texture_retirement_note ~= state.reason then
                operations.texture_retirement_note = state.reason
                ctx.log('Epic LUT texture retirement pending: ' .. tostring(state.reason))
            end
            return false
        end
        if not operations.texture_retirement_reported then
            operations.texture_retirement_reported = true
            ctx.log(
                'Epic LUT texture retirement: '
                    .. state.state
                    .. ', freed '
                    .. state.freed_count
                    .. ' textures / '
                    .. state.freed_bytes
                    .. ' bytes'
                    .. (state.reason and ('; ' .. state.reason) or '')
            )
        end
        if retain.cohort == operations.texture_cohort then
            retain.cohort = nil
        end
    end
    -- Fences still need the frontend's live render-readiness probe. Dismiss
    -- releases input immediately; unregister only after texture retirement.
    if frontend and not frontend.close() then
        return false
    end
    -- Only complete addon cleanup discards history and dormant appearance
    -- references. Pending cleanup and ordinary Restore keep Undo/Redo intact.
    history = nil
    defaults, default_proofs, appearance_pending = {}, {}, {}
    if appearance then
        appearance.clear()
    end
    if handle then
        handle.unregister()
        handle = nil
    end
    if preferences then
        preferences.close()
    end
    return true
end
local function reset_transient_state()
    -- Cleanup must finish before these references are replaced. Uploaded backing
    -- Uncertified buffers in retain and the import sequence survive activations.
    ctx, memory, native, game, frontend, preferences, handle, api, paths, palette_editor = nil
    updates, bindings, gear_catalog, sharing, pattern_editor, armory_mirror = nil
    -- Keep only stateless helpers; services and jobs belong to the old
    -- activation. A shared table also keeps the initializer within LuaJIT's
    -- captured-variable limit.
    local export_helpers = {
        include_patterns_in_exports = operations.include_patterns_in_exports,
        selected_export_bindings = operations.selected_export_bindings,
        export_pattern_entries = operations.export_pattern_entries,
        export_original_patch = operations.export_original_patch,
        export_material_source = operations.export_material_source,
        export_id_available = operations.export_id_available,
        apply_basic_camo = operations.apply_basic_camo,
        basic_camo_picker_guard = operations.basic_camo_picker_guard,
        set_basic_camo_row = operations.set_basic_camo_row,
        update_camo_previews = operations.update_camo_previews,
        outfit_documents = operations.outfit_documents,
        outfit_document = operations.outfit_document,
        armory_cape_available = operations.armory_cape_available,
        choose_outfit_luts = operations.choose_outfit_luts,
        open_import_map = operations.open_import_map,
        sync_armory_cape = operations.sync_armory_cape,
        ensure_binding_provenance = operations.ensure_binding_provenance,
        request_binding_sources = operations.request_binding_sources,
        binding_export_provider = operations.binding_export_provider,
    }
    edit, groups, operations, defaults, default_proofs = {}, {}, export_helpers, {}, {}
    status = 'Load a DDS or ZIP, then refresh the live LUT list.'
    pending, palettes, table_index, import_jobs = nil, {}, nil, nil
    setup, resume_job, resume_done, original_luts = nil
    select_suppressed, live_select_suppressed = false, false
    basic_imported, basic_names, basic_state, basic_documents, basic_selected = nil
    basic_missing_reported, myc_warned = {}, false
    populate_request, populate_next = nil, 0
    region_indicator, stop_identification, identify_kind, editor_pending = nil
    history, outfits, armory_collection, import_view = nil
    appearance, appearance_pending, appearance_elapsed, appearance_read = nil, {}, 0, nil
    source_tables, editor_tables, import_ids = {}, {}, {}
    index_job, refresh_needed, next_refresh = nil, false, 0
    m.quick_source, m.import_description = nil, nil
end
return {
    name = 'Epic LUT' .. (m.version and (' ' .. m.version) or ''),
    version = m.version,
    description = m.description,
    author = 'Goose',
    on_enable = function(context)
        assert(close(), 'Previous Epic LUT cleanup is still pending; retry after it completes')
        reset_transient_state()
        ctx = context
        ctx.log('Epic LUT build: ' .. (m.build_label or m.version or 'development'))
        paths = m.paths.new(m)
        if m.resource_ids.labels and paths.storage then
            operations.lut_names = m.resource_ids.labels(paths.storage)
        end
        operations.preset_files = m.lut_files.new(paths.presets, { dds = m.dds, read = m.file_io.read })
        operations.export_files = m.lut_files.new(paths.exports, { dds = m.dds, read = m.file_io.read })
        ctx.settings_dir = paths.settings
        memory = m.bingus_memory.new(m.bingus_runtime)
        local ok, why = memory.verify_build({
            exe_sha256 = 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
            game_sha256 = '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
        })
        assert(ok, why)
        game = memory.address(assert(memory.module('game.dll')))
        native = assert(m.engine.open(memory, game, memory.address(assert(memory.module()))))
        initialize_editor_state()
        if m.appearance_state then
            appearance = m.appearance_state.new()
        end
        if m.avatar.reader then
            appearance_read = m.avatar.reader(memory)
        end
        if m.armory_mirror then
            local mirror_read = m.avatar.reader(memory)
            armory_mirror = m.armory_mirror.new({
                identity = function()
                    return m.avatar.resolve(memory, game, mirror_read)
                end,
                locate = function(slot)
                    return m.armory_watch.locate(mirror_read, game, slot)
                end,
                watch = function(where)
                    return m.armory_watch.watch(memory, where)
                end,
                units = function(where)
                    return m.avatar.units(memory, { units_at = where.units_at }, nil, 0, 9)
                end,
                materials = function(unit)
                    return m.engine.unit_materials(native, unit)
                end,
                slot = function(pattern)
                    return pattern and m.engine.PATTERN_SLOT or m.engine.LUT_SLOT
                end,
                binding = binding,
                is_cape = function(material)
                    local object = m.engine.binding(read, material.material, m.engine.CAPE_LUT_SLOT, small, big)
                    return object and object ~= 0
                end,
                entries = function()
                    local out = {}
                    for _, b in ipairs(bindings.owned) do
                        if not b.cape and b.texture and present(b) and binding(b) == b.current then
                            out[b.save_key] = { document = b.texture, helmet = b.helmet }
                        end
                    end
                    if operations.pattern_session then
                        for _, b in ipairs(operations.pattern_session.owned) do
                            if b.texture and present(b) and binding(b) == b.current then
                                out['p:' .. b.save_key] = { document = b.texture, helmet = b.helmet }
                            end
                        end
                    end
                    return out
                end,
                session = function()
                    return m.binding_session.new({
                        retain = retain,
                        dead = function(b)
                            return native.alive(b.unit) == 0
                        end,
                        present = present,
                        binding = binding,
                        key = function(b)
                            return material_key(b) .. ':' .. b.slot
                        end,
                        create_texture = function(w, h, data)
                            return m.engine.create_texture(native, w, h, data, read, small)
                        end,
                        bind = function(b, object)
                            m.engine.bind(native, b.material, b.slot, object)
                            native.commit(b.mesh)
                        end,
                    })
                end,
            })
        end
        if m.shared_appearance then
            local ok, value = pcall(function()
                local remote_read = m.avatar.reader(memory)
                return m.shared_appearance.new({
                    sync = m.lobby_sync,
                    codec = m.shared_lut_codec.new(nil, function(resource)
                        return original_luts and original_luts.get_resource(resource)
                    end),
                    memory = memory,
                    game = game,
                    note = function(text)
                        if ctx.log then
                            ctx.log(text)
                        end
                    end,
                    identity = function()
                        local identity = m.avatar.resolve(memory, game, remote_read)
                        return m.weapon_shared and operations.weapon_sharing().local_identity(identity) or identity
                    end,
                    highlighting = function()
                        return (region_indicator and region_indicator.job ~= nil)
                            or (pattern_editor and pattern_editor.flashing())
                    end,
                    entries = function()
                        local out = {}
                        for _, b in ipairs(bindings.owned) do
                            if
                                not b.cape
                                and b.document
                                and b.current ~= b.original
                                and present(b)
                                and binding(b) == b.current
                            then
                                out[#out + 1] = {
                                    key = b.save_key,
                                    document = applied_document(b),
                                    original = original_luts and original_luts.get(b.original),
                                }
                            end
                        end
                        if operations.pattern_session then
                            for _, b in ipairs(operations.pattern_session.owned) do
                                if
                                    b.document
                                    and b.current ~= b.original
                                    and present(b)
                                    and binding(b) == b.current
                                then
                                    out[#out + 1] = {
                                        key = 'p:' .. b.save_key,
                                        document = applied_document(b),
                                        original = original_luts and original_luts.get(b.original),
                                    }
                                end
                            end
                        end
                        if m.weapon_shared then
                            local identity =
                                operations.weapon_sharing().local_identity(m.avatar.resolve(memory, game, remote_read))
                            if identity then
                                for _, entry in ipairs(operations.weapon_sharing().local_entries(identity)) do
                                    out[#out + 1] = entry
                                end
                            end
                        end
                        return out
                    end,
                    players = function()
                        return m.avatar.players(remote_read, game)
                    end,
                    resolve = function(player)
                        local identity = m.avatar.resolve_remote(remote_read, game, player)
                        return m.weapon_shared and operations.weapon_sharing().remote_identity(identity) or identity
                    end,
                    targets = function(identity, appearance)
                        local targets, marks, seen = {}, {}, {}
                        local compatible = not m.weapon_shared
                            or m.weapon_shared.garment_compatible(identity, appearance)
                        for _, unit in ipairs(compatible and m.avatar.units(memory, identity, nil, 0, 9) or {}) do
                            marks[#marks + 1] = unit.unit
                            for i, material in ipairs(m.engine.unit_materials(native, unit.unit)) do
                                local key = (unit.type or 0)
                                    .. ':'
                                    .. unit.slot
                                    .. ':'
                                    .. (material.mesh_index or 0)
                                    .. ':'
                                    .. (material.material_index or i - 1)
                                for _, pattern in ipairs({ false, true }) do
                                    local entry = appearance.entries[(pattern and 'p:' or '') .. key]
                                    local b = {
                                        unit = unit.unit,
                                        mesh = material.mesh,
                                        material = material.material,
                                        slot = pattern and m.engine.PATTERN_SLOT or m.engine.LUT_SLOT,
                                    }
                                    local bound = entry and binding(b)
                                    local tag = material_key(b) .. ':' .. b.slot
                                    if bound and bound ~= 0 and not seen[tag] then
                                        seen[tag] = true
                                        b.original, b.current = bound, bound
                                        local document = entry.document
                                        targets[document] = targets[document] or {}
                                        targets[document][#targets[document] + 1] = b
                                    end
                                end
                            end
                        end
                        if m.weapon_shared then
                            local weapons, signature = operations.weapon_sharing().targets(identity, appearance)
                            marks[#marks + 1] = signature
                            for document, bindings in pairs(weapons) do
                                targets[document] = targets[document] or {}
                                for _, b in ipairs(bindings) do
                                    targets[document][#targets[document] + 1] = b
                                end
                            end
                        end
                        return targets, table.concat(marks, ':')
                    end,
                    bindings = function()
                        local garments = m.binding_session.new({
                            retain = retain,
                            dead = function(b)
                                return native.alive(b.unit) == 0
                            end,
                            present = present,
                            binding = binding,
                            key = function(b)
                                return material_key(b) .. ':' .. (b.slot or m.engine.LUT_SLOT)
                            end,
                            create_texture = function(w, h, data)
                                return m.engine.create_texture(native, w, h, data, read, small)
                            end,
                            bind = function(b, object)
                                m.engine.bind(native, b.material, b.slot or m.engine.LUT_SLOT, object)
                                native.commit(b.mesh)
                            end,
                        })
                        if not m.weapon_shared then
                            return garments
                        end
                        local weapons = operations.weapon_sharing().session()
                        return {
                            apply = function(document, targets)
                                local gear, weapon = {}, {}
                                for _, b in ipairs(targets) do
                                    local list = b.kind == 'weapon' and weapon or gear
                                    list[#list + 1] = b
                                end
                                if #gear > 0 then
                                    garments.apply(document, gear)
                                end
                                if #weapon > 0 then
                                    weapons.apply(document, weapon)
                                end
                            end,
                            restore = function()
                                local gear_done, weapon_done = garments.restore(), weapons.restore()
                                return gear_done and weapon_done
                            end,
                        }
                    end,
                })
            end)
            if ok then
                sharing = value
            else
                ctx.log('Appearance sharing unavailable: ' .. tostring(value))
            end
        end
        initialize_import_picker()
        table_index = m.table_index.new({ read = m.file_io.read, decode = m.dds.decode, max_bytes = m.dds.MAX_BYTES })
        operations.apply_matching = apply_matching
        operations.load_debug_lut = load_debug_lut
        operations.export_custom_dds = export_custom_dds
        operations.include_capes_in_exports = include_capes_in_exports
        operations.manage_outfit = manage_outfit
        operations.paint_quick = paint_quick
        operations.select_import_cell = select_import_cell
        if m.outfit_presets then
            outfits = m.outfit_presets.new(m, paths.presets)
            armory_collection = m.armory_collection.new(outfits, function()
                return api.mods[handle.id].controls.outfit_preset
            end, function()
                return handle
            end)
            operations.import_armory = function(manifest, label)
                local names, used = outfits.names(), {}
                for _, name in ipairs(names) do
                    used[name:lower()] = true
                end
                local chosen, suffix = label, 0
                while used[chosen:lower()] do
                    suffix = suffix + 1
                    local tail = '-' .. tostring(suffix)
                    chosen = label:sub(1, 48 - #tail) .. tail
                end
                outfits.import(manifest, chosen)
                if api.mods[handle.id].controls.armory_search then
                    assert(handle.set('armory_search', ''))
                end
                armory_collection.refresh()
                armory_collection.select_name(chosen)
                if api.focus_page and m.armory_view then
                    api.focus_page(handle.id, 'armory')
                end
                return message('Imported ' .. chosen .. ' into The Armory; select Apply to put it on gear.')
            end
        end
        m.format_resource_id = resource_id
        if m.action_history then
            history = m.action_history.new(capture_action, restore_action)
        end
        preferences = m.preferences.new(paths.storage)
        frontend = m.frontend.new(m, ctx, { memory = memory, game = game })
        frontend.preferences = preferences
        if m.update_check then
            updates = m.update_check.new(m.windows, paths.cache, m.version or 'R4-rc1')
        end
        if m.direct_setup then
            setup = m.direct_setup.new(m, paths)
        end
        if m.original_luts then
            original_luts = m.original_luts.new(m, paths, native, function()
                if not handle then
                    return nil
                end
                if not pcall(refresh, true) then
                    return nil
                end
                local objects = {}
                for _, group in ipairs(groups) do
                    for _, b in ipairs(group.bindings) do
                        if b.original then
                            objects[b.original] = true
                        end
                    end
                end
                for _, group in ipairs(groups) do
                    for _, b in ipairs(group.bindings) do
                        local object = m.engine.binding(read, b.material, m.engine.PATTERN_SLOT, small, big)
                        if operations.pattern_session then
                            for _, pattern in ipairs(operations.pattern_session.owned) do
                                if pattern.material == b.material and pattern.current == object then
                                    object = pattern.original
                                    break
                                end
                            end
                        end
                        if object and object ~= 0 then
                            objects[object] = true
                        end
                    end
                end
                return objects
            end)
            original_luts.start()
        end
        if m.pattern_luts then
            local pattern_session = m.binding_session.new({
                retain = retain,
                dead = function(b)
                    return native.alive(b.unit) == 0
                end,
                present = present,
                binding = binding,
                key = function(b)
                    return material_key(b) .. ':pattern'
                end,
                create_texture = function(w, h, data)
                    return m.engine.create_texture(native, w, h, data, read, small)
                end,
                bind = function(b, object)
                    if operations.lut_apply_proofs then
                        local proof, kind = appearance_proof(), m.gear_catalog.kind(b)
                        assert(
                            proof and proof[kind] == operations.lut_apply_proofs[kind],
                            'Worn gear changed during preset application'
                        )
                    end
                    if b.cape and operations.armory_cape_proof then
                        local proof = appearance_proof()
                        assert(
                            proof and proof.cape == operations.armory_cape_proof,
                            'Cape kit changed; load current gear again'
                        )
                    end
                    m.engine.bind(native, b.material, m.engine.PATTERN_SLOT, object)
                    native.commit(b.mesh)
                    if b.cape and operations.armory_cape_proof then
                        b.applied_cape_proof = operations.armory_cape_proof
                    end
                end,
            })
            local pattern_indicator = m.region_indicator.new({
                present = present,
                binding = binding,
                apply = pattern_session.apply,
                bind = function(b, object)
                    m.engine.bind(native, b.material, m.engine.PATTERN_SLOT, object)
                    native.commit(b.mesh)
                end,
            })
            pattern_editor = m.pattern_luts.new({
                applied = function(targets)
                    remember_appearance(targets, true)
                end,
                restored = function()
                    if appearance then
                        appearance.clear(nil, true)
                    end
                    for key, pending in pairs(appearance_pending) do
                        if pending.pattern then
                            appearance_pending[key] = nil
                        end
                    end
                end,
                present = present,
                auto_populate = function()
                    return handle and handle.get('auto_populate_worn') == true
                end,
                load_seen = function()
                    return preferences and preferences.load_seen and preferences.load_seen(true) or false
                end,
                mark_load_seen = function()
                    if preferences and preferences.mark_load_seen then
                        preferences.mark_load_seen(true)
                    end
                end,
                gear_signature = function()
                    local identity = m.avatar.resolve_live(memory, game)
                    if not identity then
                        return nil
                    end
                    -- resolve_live intentionally omits customization kit IDs.
                    -- Garment references also change when gear swaps on the same actor.
                    local parts =
                        { tostring(identity.player or 0), tostring(identity.unit or 0), tostring(identity.avatar or 0) }
                    for _, piece in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
                        parts[#parts + 1] = tostring(piece.type or 0)
                            .. ':'
                            .. tostring(piece.slot or 0)
                            .. ':'
                            .. tostring(piece.unit)
                    end
                    return table.concat(parts, '|')
                end,
                export_patch = function(name, document, original)
                    assert(original, 'Original Pattern LUT snapshot is not ready')
                    local exporter = m.patch_export.new(paths.exports, {
                        available_name = m.lut_files.available_name,
                        dds = m.dds,
                        directory_exists = paths.directory_exists,
                        mkdir_new = paths.mkdir_new,
                        rmdir = paths.rmdir,
                    })
                    local output, resource, zip = exporter.save(name, document, original)
                    return message('Exported Pattern LUT ' .. resource .. ' to ' .. (zip or output))
                end,
                indicator = pattern_indicator,
                session = pattern_session,
                key = material_key,
                binding = binding,
                rgb = m.palette.rgb,
                swatch = m.palette.swatch,
                log = ctx.log,
                current_gear = function()
                    return palette_editor and palette_editor.gear ~= 'cape' and palette_editor.gear or 'armor'
                end,
                note = message,
                resource_id = resource_id,
                original = function(object)
                    return original_luts and original_luts.get(object)
                end,
                cached_original = function(object)
                    return original_luts and original_luts.snapshots and original_luts.snapshots[object]
                end,
                quick_bindings = function()
                    if not edit.loaded or not original_luts or not original_luts.loaded then
                        return
                    end
                    local kind = edit.editor_target and edit.editor_target.kind
                        or palette_editor and palette_editor.gear
                        or 'armor'
                    if kind == 'cape' then
                        return
                    end
                    local out, focus = {}, nil
                    local target = edit.editor_target and edit.editor_target.group or handle.get('lut')
                    for index, group in ipairs(groups) do
                        for _, b in ipairs(group.bindings) do
                            local pattern = {
                                unit = b.unit,
                                mesh = b.mesh,
                                material = b.material,
                                slot = m.engine.PATTERN_SLOT,
                                armor = b.armor,
                                helmet = b.helmet,
                                cape = b.cape,
                                save_key = b.save_key,
                            }
                            local object = binding(pattern)
                            if object and object ~= 0 then
                                out[#out + 1] = pattern
                                if index == target and b[kind] and not focus then
                                    focus = material_key(pattern)
                                end
                            end
                        end
                    end
                    return kind, out, focus
                end,
                discover = function()
                    local identity = assert(m.avatar.resolve_live(memory, game), 'Worn gear not ready')
                    local out = {}
                    for _, unit in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
                        for i, material in ipairs(m.engine.unit_materials(native, unit.unit)) do
                            local cape_object = m.engine.CAPE_LUT_SLOT
                                and m.engine.binding(read, material.material, m.engine.CAPE_LUT_SLOT, small, big)
                            local is_cape = cape_object ~= nil and cape_object ~= 0
                            local b = {
                                unit = unit.unit,
                                mesh = material.mesh,
                                material = material.material,
                                slot = m.engine.PATTERN_SLOT,
                                helmet = unit.slot == 0,
                                armor = unit.slot ~= 0 and not is_cape,
                                cape = is_cape,
                                save_key = (unit.type or 0)
                                    .. ':'
                                    .. unit.slot
                                    .. ':'
                                    .. (material.mesh_index or 0)
                                    .. ':'
                                    .. (material.material_index or i - 1),
                            }
                            if binding(b) then
                                out[#out + 1] = b
                            end
                        end
                    end
                    return out
                end,
                export = function(name, document)
                    local chosen = operations.export_files.save_unique(name, document)
                    return message('Exported ' .. chosen .. '.dds to files/exports')
                end,
            })
            operations.pattern_session = pattern_session
        end
        if m.lut_editor then
            palette_editor = m.lut_editor.new(
                m,
                function()
                    return edit.loaded
                end,
                message,
                function(name)
                    return action(function()
                        assert(edit.loaded, 'Import a palette first')
                        local d = edit.loaded
                        assert(stop_identification(), 'Highlight restoration pending')
                        local targets = d.width == 23
                                and operations.include_patterns_in_exports()
                                and operations.selected_export_bindings(false)
                            or {}
                        local companions = operations.export_pattern_entries(targets)
                        if #companions > 0 then
                            local original = original_luts and original_luts.get(targets[1].original)
                            local entries = {
                                {
                                    document = d,
                                    original = original,
                                    kind = m.gear_catalog.kind(targets[1]),
                                    ordinal = 1,
                                },
                            }
                            for _, entry in ipairs(companions) do
                                entries[#entries + 1] = entry
                            end
                            local folder, count = m.bulk_dds_export.new(m, paths).save(name, entries, 1)
                            d.saved_pixels = ffi.string(d.data, d.width * d.height * 16)
                            return message('Saved LUT and matching Patterns: ' .. count .. ' DDS files to ' .. folder)
                        end
                        local chosen = operations.export_files.save_unique(name, d)
                        d.saved_pixels = ffi.string(d.data, d.width * d.height * 16)
                        return message('Saved ' .. chosen .. '.dds in Epic LUT/files/exports')
                    end)
                end,
                paths.presets,
                function()
                    if edit.editor_target and edit.editor_target.kind == 'weapon' then
                        weapon_editor().check(edit.editor_target)
                        return original_luts and original_luts.request_object(edit.editor_target.original)
                    end
                    local group = handle and groups[handle.get('lut')]
                    if not group then
                        return nil
                    end
                    for _, binding in ipairs(group.bindings) do
                        if binding.document then
                            return binding.document
                        end
                        if original_luts then
                            local original = original_luts.get(binding.original)
                            if original then
                                return original
                            end
                        end
                    end
                end,
                function()
                    paths.open_exports()
                    return message('Opened Epic LUT export folder')
                end,
                function(name, entire)
                    return action(function()
                        assert(m.patch_export, 'Patch exporter unavailable')
                        if edit.editor_target and edit.editor_target.kind == 'weapon' then
                            return operations
                                .weapon_workflow()
                                .export_editor(edit.editor_target, assert(edit.loaded, 'Load a weapon LUT first'), name, entire)
                        end
                        if entire then
                            assert(stop_identification(), 'Highlight restoration pending')
                            if pattern_editor then
                                assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
                            end
                            refresh(true)
                            local documents = {}
                            local function collect(group, pattern)
                                for _, b in ipairs(group.bindings) do
                                    if not b.cape or include_capes_in_exports() then
                                        assert(
                                            present(b) and binding(b) == b.current,
                                            'Gear changed; load current gear before exporting'
                                        )
                                        local original = original_luts and original_luts.get(b.original)
                                        assert(
                                            original,
                                            'Original palette snapshot is not ready for one of the worn LUTs'
                                        )
                                        local document = b.current ~= b.original and applied_document(b) or original
                                        assert(
                                            document,
                                            'Applied LUT data unavailable; cannot export the entire palette'
                                        )
                                        documents[#documents + 1] = {
                                            document = document,
                                            original = original,
                                            kind = m.gear_catalog.kind(b),
                                            key = (pattern and 'p:' or '') .. b.save_key,
                                        }
                                    end
                                end
                            end
                            for _, group in ipairs(groups) do
                                collect(group, false)
                            end
                            if pattern_editor and operations.include_patterns_in_exports() then
                                local patterns_found = pattern_editor.scan()
                                if patterns_found > 0 then
                                    pattern_editor.load()
                                end
                                for _, group in ipairs(pattern_editor.all_groups or {}) do
                                    collect(group, true)
                                end
                            end
                            local exporter = m.patch_export.new(paths.exports, {
                                available_name = m.lut_files.available_name,
                                dds = m.dds,
                                directory_exists = paths.directory_exists,
                                mkdir_new = paths.mkdir_new,
                                rmdir = paths.rmdir,
                                binding_writer = m.binding_patch_export,
                                provenance = operations.binding_export_provider({ entries = documents }),
                                original_patch = operations.export_original_patch,
                                material_source = operations.export_material_source,
                                unit_layout = m.binding_unit_layout,
                                id_available = function(kind, id)
                                    return operations.export_id_available(kind, id)
                                end,
                            })
                            local output, count, zip = exporter.save(name, documents)
                            return message('Exported entire worn palette: ' .. count .. ' to ' .. (zip or output))
                        end
                        assert(edit.loaded, 'Load or edit a LUT first')
                        assert(
                            edit.loaded.width == 23,
                            'Use the Pattern LUT Editor to export a standalone Pattern patch'
                        )
                        assert(stop_identification(), 'Highlight restoration pending')
                        local targets = operations.selected_export_bindings(true)
                        local original
                        for _, b in ipairs(targets) do
                            original = original_luts and original_luts.get(b.original)
                            if original then
                                break
                            end
                        end
                        assert(original, 'Original destination LUT snapshot is not ready')
                        local exporter = m.patch_export.new(paths.exports, {
                            available_name = m.lut_files.available_name,
                            dds = m.dds,
                            directory_exists = paths.directory_exists,
                            mkdir_new = paths.mkdir_new,
                            rmdir = paths.rmdir,
                        })
                        local companions = operations.export_pattern_entries(targets)
                        if #companions > 0 then
                            local first = assert(targets[1], 'Current material destination unavailable')
                            local documents = {
                                {
                                    document = edit.loaded,
                                    original = original,
                                    kind = m.gear_catalog.kind(first),
                                    key = first.save_key,
                                },
                            }
                            for _, entry in ipairs(companions) do
                                documents[#documents + 1] = entry
                            end
                            exporter = m.patch_export.new(paths.exports, {
                                available_name = m.lut_files.available_name,
                                dds = m.dds,
                                directory_exists = paths.directory_exists,
                                mkdir_new = paths.mkdir_new,
                                rmdir = paths.rmdir,
                                binding_writer = m.binding_patch_export,
                                provenance = operations.binding_export_provider({ entries = documents }),
                                original_patch = operations.export_original_patch,
                                material_source = operations.export_material_source,
                                unit_layout = m.binding_unit_layout,
                                id_available = function(kind, id)
                                    return operations.export_id_available(kind, id)
                                end,
                            })
                            local output, count, zip = exporter.save(name, documents)
                            return message('Exported LUT and matching Patterns: ' .. count .. ' to ' .. (zip or output))
                        end
                        local output, resource, zip = exporter.save(name, edit.loaded, original)
                        return message('Exported patch ZIP for ' .. resource .. ' to ' .. (zip or output))
                    end)
                end,
                function(name, naming)
                    return action(function()
                        return operations.export_custom_dds(name, naming)
                    end)
                end,
                function()
                    return action(function()
                        return load(true, true)
                    end)
                end
            )
        end
        local owner = frontend
        ctx.on_cleanup(function()
            return frontend ~= owner or close()
        end)
        message('Direct DDS editor ready; no archive discovery or Python')
    end,
    on_update = function(dt_context, dt)
        pcall(region_indicator.tick, dt, not frontend.menu or frontend.menu.visible)
        local myc = not not rawget(_G, 'MatchYourColorsInstalled')
        if frontend and frontend.menu then
            frontend.menu.warning = myc
                    and 'Match Your Colors detected: turn matching Off before loading or editing gear LUTs. It can prevent original colors resolving.'
                or nil
        end
        if myc and not myc_warned then
            myc_warned = true
            message('Warning: Match Your Colors detected. Turn matching Off before loading or editing gear LUTs.')
        end
        if updates then
            pcall(updates.tick, dt)
        end
        if operations.binding_sources then
            local report = operations.binding_sources.poll(status == BINDING_EXPORT_PENDING)
            if report then
                message(report)
            end
        end
        if operations.weapon_sources_service then
            local ok, report = pcall(
                operations.weapon_sources_service.poll,
                m.weapon_provenance and status == m.weapon_provenance.PENDING
            )
            if ok and report then
                message(report)
            end
            if not ok and edit.weapon_source_error ~= report then
                edit.weapon_source_error = report
                ctx.log('Weapon source cache error: ' .. tostring(report))
            end
        end
        if original_luts then
            local ok, why = pcall(original_luts.tick)
            if not ok then
                message('Original snapshot error: ' .. tostring(why))
            end
        end
        if operations.weapon_editor then
            local ok, why = pcall(operations.weapon_editor.update, dt)
            if not ok and why ~= edit.weapon_update_error then
                edit.weapon_update_error = why
                message('Weapon editor update: ' .. tostring(why))
            elseif ok then
                edit.weapon_update_error = nil
            end
        end
        local recovered, recovery_error = pcall(recover_appearance, dt)
        if not recovered and recovery_error ~= edit.appearance_error then
            edit.appearance_error = recovery_error
            ctx.log('Appearance recovery waiting: ' .. tostring(recovery_error))
        elseif recovered then
            edit.appearance_error = nil
        end
        frontend.tick(dt)
        local camo_ok, camo_error = pcall(operations.update_camo_previews)
        if not camo_ok and operations.camo_error ~= camo_error then
            operations.camo_error = camo_error
            ctx.log('Camo previews unavailable: ' .. tostring(camo_error))
        end
        local current = frontend.resolve()
        if current then
            register(current)
            if updates and api.mods[handle.id].controls.update_status then
                api.mods[handle.id].controls.update_status.label = updates.status
            end
            if updates and not updates.started and preferences.auto_updates and preferences.auto_updates() then
                pcall(updates.check)
            end
            if setup and not resume_done then
                action(resume_setup)
            end
            if refresh_needed then
                local now = memory.time and memory.time() or os.clock()
                if now >= next_refresh then
                    next_refresh = now + 0.25
                    refresh_needed = not pcall(refresh, true)
                end
            end
            operations.import_picker.poll()
            if api.mods[handle.id].controls.import_paydex_rows then
                api.mods[handle.id].controls.import_paydex_rows.disabled = pending ~= nil
            end
            if editor_pending and os.time() >= (editor_pending.next or 0) then
                local job = editor_pending
                job.next = os.time() + 1
                local ok, why = pcall(load_editor_target, job.kind)
                if not ok or (editor_pending and os.time() - job.began > 130) then
                    editor_pending = nil
                    message('Current ' .. job.kind .. ' colors unavailable: ' .. tostring(why or 'snapshot timeout'))
                end
            end
            edit.auto_elapsed = (edit.auto_elapsed or 0) + math.max(0, dt or 0)
            if handle.get('auto_populate_worn') and edit.auto_elapsed >= 1 then
                edit.auto_elapsed = 0
                local identity = m.avatar.resolve_live(memory, game)
                if identity then
                    local parts = { tostring(identity.unit or 0) }
                    local proof = appearance_proof()
                    if proof then
                        parts[#parts + 1] = proof.armor
                        parts[#parts + 1] = proof.helmet
                        parts[#parts + 1] = proof.cape or ''
                    end
                    for _, piece in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
                        parts[#parts + 1] = tostring(piece.unit)
                    end
                    local signature = table.concat(parts, ':')
                    local menu = frontend.menu
                    local interacting = menu
                        and (menu.is_interacting and menu.is_interacting() or menu.text_edit or menu.color_picker)
                    if edit.auto_signature ~= signature and not interacting then
                        basic_state.clear()
                        local ok, done = pcall(populate_worn)
                        if ok and done then
                            edit.auto_signature = signature
                        end
                    end
                end
            end
            if populate_request and os.time() >= populate_next then
                populate_next = os.time() + 1
                local ok, why = pcall(populate_worn)
                if not ok or (populate_request and os.time() - populate_request > 130) then
                    populate_request = nil
                    edit.populate_manual_request = nil
                    message(
                        'Could not load worn colors. Retry Load Current Colors. '
                            .. tostring(why or 'Snapshot timed out')
                    )
                end
            end
            local page = frontend.menu and api.mods[handle.id].pages[frontend.menu.page]
            if page and page.id == 'basic' and edit.imported and edit.imported ~= basic_imported then
                basic_imported = edit.imported
                local ok, why = pcall(save_palette)
                if not ok then
                    message('Import editor refresh failed; addon remains available: ' .. tostring(why))
                end
                api.focus_page(handle.id, 'basic')
                edit.preview_document = edit.loaded
                edit.preview_revision = 0
            end
            -- Selection/import establishes a baseline; only actual editor revisions apply.
            if edit.loaded ~= edit.preview_document then
                edit.preview_document = edit.loaded
                edit.preview_revision = edit.loaded and (edit.loaded.revision or 0)
                if operations.live_edit then
                    operations.live_edit.reset()
                end
            else
                local dirty = edit.loaded and (edit.loaded.revision or 0) ~= edit.preview_revision
                local active = frontend.menu and frontend.menu.is_interacting and frontend.menu.is_interacting()
                local ready = operations.live_edit and operations.live_edit.ready(dirty, active, dt)
                if dirty and (ready or not operations.live_edit) then
                    -- Consume the latest attempted revision only when due. A failed
                    -- write keeps the draft and waits for a new edit or explicit retry.
                    edit.preview_revision = edit.loaded.revision or 0
                    if edit.editor_target and edit.editor_target.kind == 'weapon' then
                        action(function()
                            return weapon_editor().apply(edit.editor_target, edit.loaded)
                        end)
                    elseif not frontend.basic_mode and edit.editor_target then
                        action(function()
                            checked_editor_target(edit.editor_target)
                            live_select_suppressed = true
                            local ok, why = handle.set('lut', edit.editor_target.group)
                            live_select_suppressed = false
                            assert(ok, why)
                            assert(handle.set('scope', 1))
                            return apply(edit.loaded, edit.editor_target.kind)
                        end)
                    elseif
                        (frontend.basic_mode and basic_selected)
                        or (not frontend.basic_mode and (handle.get('target_armor') or handle.get('target_helmet')))
                    then
                        action(function()
                            return apply_checked(edit.loaded)
                        end)
                    end
                end
            end
            if index_job then
                local ok, why = coroutine.resume(index_job)
                if not ok then
                    index_job = nil
                    operations.import_map_request = nil
                    operations.weapon_map_request = nil
                    message('Could not index all tables: ' .. tostring(why))
                elseif coroutine.status(index_job) == 'dead' then
                    index_job = nil
                    local requested = operations.import_map_request
                    operations.import_map_request = nil
                    local weapon_request = operations.weapon_map_request
                    operations.weapon_map_request = nil
                    if weapon_request and weapon_request.palettes == palettes then
                        local ready, value = pcall(
                            operations.weapon_workflow().map_prepared,
                            weapon_request.descriptors,
                            weapon_request.options
                        )
                        if not ready then
                            message('Could not prepare weapon mapping: ' .. tostring(value))
                        end
                    end
                    if requested and requested.palettes == palettes then
                        local ready, value = pcall(operations.open_import_map, requested.kind, true)
                        if not ready then
                            message('Could not prepare mapping: ' .. tostring(value))
                        end
                    end
                end
            end
            for _, control in ipairs(api.mods[handle.id].pages[1].controls) do
                if control.id == 'status' then
                    control.label = status
                end
            end
        end
        if pattern_editor and handle then
            local ok, why = pcall(pattern_editor.tick, dt)
            if not ok then
                pcall(pattern_editor.stop_flash)
                if ctx.log then
                    ctx.log('Pattern update stopped safely: ' .. tostring(why))
                end
            end
        end
        if armory_mirror and handle then
            local ok, why = pcall(armory_mirror.tick, dt)
            if not ok then
                pcall(armory_mirror.close)
                if ctx.log then
                    ctx.log('Armory mirror paused: ' .. tostring(why))
                end
                armory_mirror = nil
            end
        end
        if sharing and handle then
            local control = api.mods[handle.id].controls.share_appearance
            local ok, why = true, nil
            if not sharing.paused then
                ok, why = pcall(sharing.tick, dt, control and handle.get('share_appearance') or false)
            end
            if not ok then
                pcall(sharing.close)
                sharing.paused = true
                sharing.status = 'Sharing paused: ' .. tostring(why)
            end
            local label = edit.sharing_status_control
            if label then
                label.label = sharing.status
            end
        end
    end,
    on_disable = close,
    on_cleanup_poll = close,
}
