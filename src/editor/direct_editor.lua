-- DDS -> selected local live LUT. No equipment catalogue or file service.
local ffi = require('ffi')
local ctx, memory, native, game, frontend, preferences, handle, api, paths, palette_editor
local updates
local groups = {}
local bindings, gear_catalog
local sharing, pattern_editor, armory_mirror
local edit = {} -- Current document, imported source, target and revision baseline.
local status = 'Load a DDS or ZIP, then refresh the live LUT list.'
local BINDING_EXPORT_PENDING = 'Reading exact binding sources; retry Export after the background cache is ready'
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
local function restore()
    if stop_identification then
        stop_identification()
    end
    return not bindings or bindings.restore()
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
    if m.texture_lifetime and native.destroy then
        local cohort = { sessions = {} }
        retain.cohort = cohort
        operations.texture_cohort = cohort
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
    local entries = {}
    for _, kind in ipairs(container == 'armor' and { 'armor', 'cape' } or { 'helmet' }) do
        local ordinal = 0
        for index, group in ipairs(groups) do
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
local function warm_worn_slots()
    refresh(true)
    local selected, complete, total = {}, true, 0
    for _, container in ipairs({ 'armor', 'helmet' }) do
        for choice, entry in ipairs(current_choices(container)) do
            local b = entry.binding
            local source = b.current ~= b.original and applied_document(b)
                or (original_luts and original_luts.get(b.original))
            total = total + 1
            if source then
                basic_state.get(entry.key, source, 'Worn ' .. entry.kind)
                if not selected[container] or choice == handle.get('basic_' .. container .. '_lut') then
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
local function populate_worn()
    local complete, selected = warm_worn_slots()
    if not complete then
        return false
    end
    local container = palette_editor and palette_editor.gear == 'helmet' and 'helmet' or 'armor'
    if not selected[container] then
        container = selected.armor and 'armor' or 'helmet'
    end
    local target = selected[container]
    if not target then
        return false
    end
    edit.loaded = m.basic_state.clone(
        target.document,
        target.kind == 'cape' and target.label .. ' (worn)' or 'Worn ' .. target.kind
    )
    edit.loaded.resource_object = target.object
    local original = original_luts and original_luts.get(target.object)
    edit.editor_target = {
        kind = target.kind,
        group = target.group,
        object = target.object,
        resource = original and original.resource,
        cape_proof = target.kind == 'cape' and edit.cape_proof or nil,
    }
    live_select_suppressed = true
    local ok, why = handle.set('lut', target.group)
    live_select_suppressed = false
    assert(ok, why)
    edit.preview_document, edit.preview_revision = edit.loaded, 0
    edit.quick_selection = nil
    identify_kind = target.kind
    basic_imported = edit.imported
    if palette_editor then
        palette_editor.gear = container
        palette_editor.sync()
    end
    import_state()
    local manual_request = populate_request ~= nil and edit.populate_manual_request == true
    populate_request = nil
    edit.populate_manual_request = nil
    message('Loaded every current Armor, Cape and Helmet LUT slot. Select a table to edit.')
    if manual_request and pattern_editor and pattern_editor.prime then
        local ok, ready, why = pcall(pattern_editor.prime, container)
        if (not ok or ready == false) and ctx.log then
            ctx.log('Material LUTs loaded; Pattern quick editor not ready: ' .. tostring(ok and why or ready))
        end
    end
    if manual_request and operations.request_binding_sources then
        local ok, ready, why = pcall(operations.request_binding_sources)
        local reason = ok and why or ready
        if (not ok or ready == false) and reason and ctx.log then
            ctx.log('Binding source request: ' .. tostring(reason))
        end
    end
    return true
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
    local group = assert(groups[index], 'Selected live LUT is unavailable')
    local proof = appearance_proof and appearance_proof()
    local original = original_luts and original_luts.get(group.object)
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
            target.binding_keys[material_key(b) .. ':' .. tostring(b.slot or m.engine.LUT_SLOT)] = b.save_key or ''
        end
    end
    assert(next(target.binding_keys), 'Selected live LUT has no matching binding')
    return target
end
import_state = function()
    local palette_ready = edit.loaded ~= nil or edit.imported ~= nil
    local previews = { armor = {}, helmet = {}, cape = {} }
    for index, group in ipairs(groups) do
        local seen = { armor = {}, helmet = {}, cape = {} }
        for _, b in ipairs(group.bindings) do
            local kind = m.gear_catalog.kind(b)
            local texture = b.texture
            if texture and b.current == texture.object and not seen[kind][texture] then
                seen[kind][texture] = true
                local document = b.document or texture
                previews[kind][#previews[kind] + 1] = {
                    name = m.gear_catalog.label(kind) .. ' LUT ' .. (#previews[kind] + 1),
                    index = index,
                    width = document.width,
                    height = document.height,
                    data = document.data,
                    revision = document.revision,
                    edited = (document.revision or 0) > 0,
                    target = operations.import_target(kind, index),
                }
            end
        end
    end
    local tables = {}
    for i, path in ipairs(palettes) do
        local document = editor_tables[path] or source_tables[path]
        if document then
            tables[#tables + 1] = {
                name = 'Table ' .. i,
                index = i,
                source = path,
                width = document.width,
                height = document.height,
                data = document.data,
                revision = document.revision,
                edited = (document.revision or 0) > 0,
            }
        end
    end
    local raw = {
        tables = tables,
        armor = previews.armor,
        helmet = previews.helmet,
        basic = {},
        outfit = armory_collection and armory_collection.selected,
        matching = matching_plan(),
    }
    local choice_maps = {}
    if m.basic_view then
        for _, container in ipairs({ 'armor', 'helmet' }) do
            local entries, choices, details, hashes, help = current_choices(container), {}, {}, {}, {}
            choice_maps[container] = entries
            for index, entry in ipairs(entries) do
                choices[index], details[index] = entry.label, resource_id(groups[entry.group].object)
                local original = original_luts and original_luts.get(groups[entry.group].object)
                hashes[index] = original and original.resource
                help[index] = m.resource_ids.describe(hashes[index], handle.get('resource_format') == 2, m.sdk_catalog)
            end
            local control = api.mods[handle.id].controls['basic_' .. container .. '_lut']
            control.choices = #choices > 0 and choices or { 'Waiting for gear...' }
            control.choice_details, control.choice_targets = details, entries
            control.choice_hashes, control.choice_help = hashes, help
            control.dropdown_width = 280
            control.disabled = not palette_ready or #choices == 0
            local selected = entries[handle.get('basic_' .. container .. '_lut')]
            local group = selected and groups[selected.group]
            local doc, key = nil, selected and selected.key
            if selected then
                local b = selected.binding
                local source = b.document or (original_luts and original_luts.get(b.original))
                doc = basic_documents[key] or basic_state.get(key, source, 'Worn ' .. selected.kind)
            end
            raw.basic[container] = {
                document = doc,
                key = key,
                group = selected and selected.group,
                kind = selected and selected.kind or container,
                label = selected and selected.label,
                ordinal = selected and selected.ordinal,
                resource = group and resource_id(group.object) or 'unavailable',
                unavailable = not doc and original_luts and original_luts.loaded and key ~= nil,
            }
            local proof = operations.appearance_proof()
            local camo_rows, camo_count =
                basic_state.camo_rows(key, doc, raw.basic[container].kind, proof and proof[raw.basic[container].kind])
            raw.basic[container].camo_rows, raw.basic[container].camo_count = camo_rows, camo_count
            if m.basic_camo then
                local prefix = 'basic_' .. container .. '_camo'
                local values = { [prefix] = m.basic_camo.selection(doc, container, camo_rows) }
                if m.basic_camo.colorway_selection then
                    values[prefix .. '_colorway'] = m.basic_camo.colorway_selection(doc, container, camo_rows)
                    for color = 1, 4 do
                        values[prefix .. '_color_' .. color] = m.basic_camo.color(doc, color, camo_rows)
                    end
                end
                for id, value in pairs(values) do
                    local camo = api.mods[handle.id].controls[id]
                    if camo then
                        local disabled = pending ~= nil
                            or not m.basic_camo.available(doc)
                            or not group
                            or camo_count == 0
                        camo.disabled = false
                        if id == prefix then
                            camo.choice_pattern_previews = operations.camo_thumbnails
                        end
                        operations.syncing_basic_camo = true
                        local called, ok, why = pcall(handle.set, camo.id, value)
                        operations.syncing_basic_camo = false
                        camo.disabled = disabled
                        assert(called and ok, why or ok)
                    end
                end
            end
            if doc then
                previews[container] = {
                    {
                        name = selected.kind == 'cape' and selected.label
                            or m.gear_catalog.label(selected.kind) .. ' LUT ' .. selected.ordinal,
                        kind = selected.kind,
                        resource = resource_id(group.object),
                        index = selected.group,
                        width = doc.width,
                        height = doc.height,
                        data = doc.data,
                        revision = doc.revision,
                        target = operations.import_target(selected.kind, selected.group),
                    },
                }
            end
            if raw.basic[container].unavailable and not basic_missing_reported[key] then
                basic_missing_reported[key] = true
                if ctx.log then
                    ctx.log(
                        'BASIC_SNAPSHOT_MISSING target='
                            .. raw.basic[container].kind
                            .. ' original_object='
                            .. tostring(group.object)
                    )
                end
            end
        end
    end
    if m.table_groups then
        tables = m.table_groups.collapse(tables)
        previews.armor = m.table_groups.collapse(previews.armor)
        previews.helmet = m.table_groups.collapse(previews.helmet)
    end
    -- The Import workspace lists every loaded table, including game snapshots.
    raw.pending_luts = {}
    for _, container in ipairs({ 'armor', 'helmet' }) do
        local entries, choices = {}, choice_maps[container] or current_choices(container)
        for choice, entry in ipairs(choices) do
            local b, group = entry.binding, groups[entry.group]
            local doc = basic_documents[entry.key] or b.document or (original_luts and original_luts.get(b.original))
            if doc then
                entries[#entries + 1] = {
                    name = entry.kind == 'cape' and entry.label
                        or m.gear_catalog.label(entry.kind)
                            .. ' LUT '
                            .. entry.ordinal
                            .. (b.resource_name and (' / ' .. b.resource_name) or ''),
                    kind = entry.kind,
                    resource = resource_id(group.object),
                    lut = choice,
                    selected = choice == handle.get('basic_' .. container .. '_lut'),
                    index = entry.group,
                    width = doc.width,
                    height = doc.height,
                    data = doc.data,
                    revision = doc.revision,
                    target = operations.import_target(entry.kind, entry.group),
                }
            end
        end
        raw[container], raw.pending_luts[container] = entries, #choices - #entries
    end
    local picker = operations.import_picker.info()
    local dirty = edit.loaded
            and edit.loaded.original
            and ffi.string(edit.loaded.data, edit.loaded.width * edit.loaded.height * 16) ~= (edit.loaded.saved_pixels or ffi.string(
                edit.loaded.original,
                edit.loaded.width * edit.loaded.height * 16
            ))
        or false
    return {
        editor = edit.loaded,
        palette_ready = palette_ready,
        load_seen = edit.load_seen or (preferences and preferences.load_seen and preferences.load_seen(false)) or false,
        dirty = dirty,
        export_name = handle and handle.get('save_name'),
        armory_export_name = handle and handle.get('armory_export_name'),
        armory_export_format = handle and handle.get('armory_export_format'),
        armory_query = handle and api.mods[handle.id].controls.armory_search and handle.get('armory_search'),
        raw = raw,
        palette_count = #palettes,
        palette_index = handle.get('palette'),
        armor_lut = handle.get('basic_armor_lut'),
        helmet_lut = handle.get('basic_helmet_lut'),
        tables = tables,
        armor = previews.armor,
        helmet = previews.helmet,
        cape_available = #m.gear_catalog.targets(groups, 5, nil, 'cape') > 0,
        armory_cape_available = operations.armory_cape_available(armory_collection and armory_collection.selected),
        armory_targets = {
            armor = handle.get('outfit_target_armor'),
            helmet = handle.get('outfit_target_helmet'),
            cape = handle.get('outfit_target_cape'),
        },
        loaded = edit.imported,
        import_description = m.import_description,
        import_detail = picker.detail,
        status = populate_request
                and ('Loading worn colors: ' .. (original_luts and original_luts.status or 'snapshot unavailable'))
            or original_luts and not original_luts.loaded and original_luts.status
            or status,
        busy = picker.busy or index_job ~= nil,
        phase = index_job and 'Comparing imported tables...' or picker.phase,
        progress = picker.progress,
        waiting = picker.waiting,
        time = memory.time and memory.time() or os.clock(),
        elapsed = picker.elapsed,
        armor_checked = handle.get('target_armor'),
        helmet_checked = handle.get('target_helmet'),
        palette_name = handle.get('palette_name'),
        preserve_emissives = handle.get('preserve_emissives'),
    }
end
function operations.set_basic_camo_row(row, container, checked, expected_rows)
    local panel = import_state().raw.basic[container]
    if
        not panel
        or not m.basic_camo.available(panel.document)
        or pending
        or index_job
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
    if frontend.menu then
        frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
    end
    return true
end
checked_editor_target = function(target)
    assert(target, 'Load current gear again')
    if target.binding_keys then
        local proof = appearance_proof and appearance_proof()
        assert(
            not target.kit_proof or proof and proof[target.kind] == target.kit_proof,
            'Worn kit changed; load current colors again'
        )
        refresh(true)
        for index, group in ipairs(groups) do
            if group.object == target.object then
                local actual = {}
                for _, b in ipairs(group.bindings) do
                    if b[target.kind] then
                        actual[material_key(b) .. ':' .. tostring(b.slot or m.engine.LUT_SLOT)] = b.save_key or ''
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
        refresh(true)
        for index, group in ipairs(groups) do
            if
                target.object and group.object == target.object
                or not target.object and target.key == target.kind .. ':' .. tostring(group.object)
            then
                for _, b in ipairs(group.bindings) do
                    if b[target.kind] then
                        local original = original_luts and original_luts.get(b.original)
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
    local proof = appearance_proof()
    assert(proof and proof.cape == target.cape_proof, 'Cape kit changed; load current Cape colors again')
    assert(target.resource, 'Cape resource identity unavailable; load current colors again')
    refresh(true)
    for index, group in ipairs(groups) do
        for _, b in ipairs(group.bindings) do
            local original = b.cape and original_luts and original_luts.get(b.original)
            if original and original.resource == target.resource then
                target.group, target.object = index, group.object
                return index
            end
        end
    end
    error('Cape material changed; load current Cape colors again')
end
operations.checked_editor_target = checked_editor_target
local function apply_basic_camo(container, choice, mode, color)
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local panel = import_state().raw.basic[container]
    assert(panel and m.basic_camo.available(panel.document), 'Load a current Armor or Helmet material LUT first')
    assert(panel.camo_count > 0, 'Select at least one Camo region')
    local target = import_target(panel.kind, panel.group)
    local index = checked_editor_target(target)
    local targets = {}
    for _, b in ipairs(groups[index].bindings) do
        if m.gear_catalog.kind(b) == panel.kind then
            targets[#targets + 1] = b
        end
    end
    assert(#targets > 0, 'Selected LUT has no current material bindings')
    local document = m.basic_state.copier().copy(panel.document)
    local rows, label = m.basic_camo.apply(document, choice, mode, color, panel.kind, panel.camo_rows)
    local previous = operations.camo_write_target
    operations.camo_write_target = target
    local ok, count = pcall(apply_bindings, document, targets)
    operations.camo_write_target = previous
    assert(ok, count)
    basic_documents[panel.key] = document
    for _, b in ipairs(targets) do
        basic_documents[m.gear_catalog.kind(b) .. ':' .. tostring(b.original)] = document
    end
    edit.editor_target = nil
    basic_selected = target
    basic_selected.container, basic_selected.key = container, panel.key
    basic_imported, edit.loaded = edit.imported, document
    edit.preview_document, edit.preview_revision = document, document.revision
    if palette_editor then
        palette_editor.sync()
    end
    if mode == 'color' then
        -- The selector follows the committed checked-region RGB immediately.
        -- State synchronization suppresses callbacks, preserving the custom
        -- recipe instead of applying the old named colorway again.
        import_state()
    end
    if frontend.menu then
        frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
    end
    return message(
        'Applied '
            .. (label or m.basic_camo.CHOICES[choice])
            .. ' to '
            .. rows
            .. ' checked regions in this '
            .. m.gear_catalog.label(panel.kind)
            .. ' LUT ('
            .. count
            .. ' bindings).'
    )
end
operations.apply_basic_camo = apply_basic_camo
function operations.basic_camo_picker_guard(control, container)
    return function()
        local panel = import_state().raw.basic[container]
        if not panel or not m.basic_camo.available(panel.document) then
            return false, 'Load a current material LUT first.'
        end
        if panel.camo_count == 0 then
            return false, 'Select at least one Camo region.'
        end
        local picker = frontend.menu and frontend.menu.color_picker
        if picker and picker.control == control then
            if control.camo_key ~= panel.key then
                return false, 'The selected LUT changed; reopen the camo color picker.'
            end
            checked_editor_target(control.camo_target)
        else
            control.camo_key = panel.key
            control.camo_target = import_target(panel.kind, panel.group)
            checked_editor_target(control.camo_target)
        end
        return true
    end
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
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local panel = import_state().raw.basic[container]
    local kind = panel and panel.kind or container
    local source
    local group = panel and panel.group and groups[panel.group]
    if group then
        for _, b in ipairs(group.bindings) do
            if b[kind] then
                source = applied_document(b) or (original_luts and original_luts.get(b.original))
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
    local original = original_luts and original_luts.get(group.object)
    local proof = appearance_proof()
    if kind == 'cape' then
        assert(original and original.resource and proof and proof.cape, 'Current Cape identity unavailable')
    end
    edit.loaded = m.basic_state.clone(
        source,
        kind == 'cape' and panel.label .. ' (worn)'
            or m.gear_catalog.label(kind) .. ' LUT ' .. panel.ordinal .. ' (worn)'
    )
    edit.loaded.resource, edit.loaded.resource_object = resource_id(group.object), group.object
    edit.editor_target = {
        kind = kind,
        group = panel.group,
        object = group.object,
        resource = original and original.resource,
        cape_proof = kind == 'cape' and proof.cape or nil,
    }
    identify_kind, basic_selected, basic_imported, edit.quick_selection = kind, nil, edit.imported, nil
    live_select_suppressed = true
    local ok, why = handle.set('lut', panel.group)
    live_select_suppressed = false
    assert(ok, why)
    edit.preview_document, edit.preview_revision, editor_pending = edit.loaded, 0, nil
    if palette_editor then
        palette_editor.gear = container
        palette_editor.sync()
    end
    return message('Editor populated from ' .. edit.loaded.source .. '. Edits affect this LUT only.')
end
local function apply_editor_target(container, all)
    assert(edit.loaded, 'Load current colors or send an imported LUT to the editor first')
    if all then
        assert(handle.set('scope', container == 'armor' and 2 or container == 'helmet' and 3 or 4))
        return apply(edit.loaded, container)
    end
    local panel = import_state().raw.basic[container]
    assert(panel and panel.group, 'Selected LUT unavailable')
    local kind = panel.kind or container
    if kind == 'cape' then
        assert(stop_identification(), 'Highlight restoration pending')
        refresh(true)
        assert(edit.loaded, 'Cape changed; load current colors again')
        panel = import_state().raw.basic[container]
    end
    local group = groups[panel.group]
    local original = original_luts and original_luts.get(group.object)
    local proof = appearance_proof()
    live_select_suppressed = true
    local ok, why = handle.set('lut', panel.group)
    live_select_suppressed = false
    assert(ok, why)
    assert(handle.set('scope', 1))
    edit.editor_target = {
        kind = kind,
        group = panel.group,
        object = group.object,
        resource = original and original.resource,
        cape_proof = kind == 'cape' and proof and proof.cape or nil,
    }
    return apply(edit.loaded, kind)
end
local function apply_import_to(kind)
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local panel = import_state().raw.basic[kind]
    assert(panel and panel.group, 'Select a ' .. kind .. ' LUT first')
    kind = panel.kind or kind
    assert(edit.imported, 'Import a LUT file first')
    local group = groups[panel.group]
    live_select_suppressed = true
    local ok, why = handle.set('lut', panel.group)
    live_select_suppressed = false
    assert(ok, why)
    assert(handle.set('scope', 1))
    basic_selected = nil
    local result = apply(edit.imported, kind)
    for _, b in ipairs(group.bindings) do
        if b[kind] and b.document then
            basic_documents[kind .. ':' .. tostring(b.original)] =
                m.basic_state.clone(b.document, 'Applied ' .. kind .. ' LUT')
        end
    end
    if import_view then
        import_view.selected = nil
    end
    return result
end
local function copy_basic_palette(destination, source_kind)
    assert(stop_identification(), 'Highlight restoration pending')
    local panels = import_state().raw.basic
    local target, source = panels[destination], panels[source_kind]
    assert(target and target.document and source and source.document, 'Load both gear palettes before copying')
    local d, s = target.document, source.document
    assert(d.width == s.width, 'Palette columns differ')
    local proof = appearance_proof()
    local original = original_luts and original_luts.get(groups[target.group].object)
    if target.kind == 'cape' then
        assert(
            proof and proof.cape and original and original.resource,
            'Current Cape identity is still loading; load current colors again'
        )
    end
    edit.loaded = d
    basic_selected = {
        kind = target.kind or destination,
        container = destination,
        key = target.key,
        group = target.group,
        cape_proof = target.kind == 'cape' and proof and proof.cape or nil,
        resource = original and original.resource,
    }
    basic_imported = edit.imported
    if palette_editor then
        palette_editor.sync()
    end
    local rows = m.basic_state.copy(d, s)
    edit.preview_document = d
    edit.preview_revision = d.revision - 1
    if palette_editor then
        palette_editor.sync()
    end
    return message(
        'Copied '
            .. rows
            .. ' rows from '
            .. source_kind
            .. ' to '
            .. destination
            .. '. Live colors update automatically.'
    )
end
local function copy_helmet_all()
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local panel = import_state().raw.basic.helmet
    local source = assert(panel and panel.document, 'Load Helmet colors first')
    local plans = {}
    for index, group in ipairs(groups) do
        if group.armor then
            local targets = {}
            local original
            for _, b in ipairs(group.bindings) do
                if b.armor then
                    targets[#targets + 1] = b
                    original = original
                        or basic_documents['armor:' .. tostring(b.original)]
                        or b.document
                        or (original_luts and original_luts.get(b.original))
                end
            end
            assert(original, 'Armor LUT ' .. index .. ' colors unavailable; no palettes copied')
            assert(original.width == source.width, 'Armor LUT columns differ; no palettes copied')
            local data = ffi.new('float[?]', original.width * original.height * 4)
            ffi.copy(data, original.data, original.width * original.height * 16)
            ffi.copy(data, source.data, math.min(original.height, source.height) * original.width * 16)
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
    resume_done = true
    resume_job = nil
    for _, plan in ipairs(plans) do
        apply_bindings(plan.document, plan.targets)
        for _, b in ipairs(plan.targets) do
            basic_documents['armor:' .. tostring(b.original)] = plan.document
        end
    end
    if basic_selected and basic_selected.kind == 'armor' then
        edit.loaded = basic_documents[basic_selected.key]
        edit.preview_document = edit.loaded
        edit.preview_revision = edit.loaded and edit.loaded.revision or 0
        if palette_editor then
            palette_editor.sync()
        end
    end
    return message('Copied Helmet palette to all ' .. #plans .. ' Armor LUTs and applied live.')
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
local function capture_action()
    if not handle then
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
        selected = basic_selected,
        editor_target = edit.editor_target,
        imported = edit.imported,
        scope = handle.get('scope'),
        palette_index = handle.get('palette'),
        appearance = appearance and appearance.entries() or {},
        appearance_pending = {},
        remember_application = edit.remember_application,
    }
    local copier = m.basic_state.copier()
    local document = copier.copy
    snapshot.loaded = document(edit.loaded)
    if edit.editor_target then
        snapshot.editor_target = {}
        for k, v in pairs(edit.editor_target) do
            snapshot.editor_target[k] = v
        end
    end
    for key, d in pairs(basic_documents) do
        snapshot.basic[key] = document(d)
    end
    for key, d in pairs(editor_tables) do
        snapshot.editor_tables[key] = document(d)
    end
    local signature = {
        tostring(edit.imported),
        edit.loaded and ffi.string(edit.loaded.data, edit.loaded.width * edit.loaded.height * 16) or '',
        edit.loaded and edit.loaded.source or '',
    }
    for _, pool in ipairs({
        { session = bindings, records = snapshot.owned, pattern = false },
        { session = operations.pattern_session, records = snapshot.pattern_owned, pattern = true },
    }) do
        for _, b in ipairs(pool.session and pool.session.owned or {}) do
            local key = material_key(b) .. (pool.pattern and ':pattern' or '')
            pool.records[#pool.records + 1] = {
                binding = b,
                key = key,
                current = b.current,
                texture = b.texture,
                cape_proof = b.applied_cape_proof,
                cape_resource = b.cape and appearance_resource(b) or nil,
                save_key = b.save_key,
                document = document(b.document),
            }
            signature[#signature + 1] = key .. ':' .. tostring(b.current)
        end
    end
    for k, v in pairs(defaults) do
        snapshot.defaults[k] = v
        snapshot.default_proofs[k] = default_proofs[k]
    end
    for i, v in ipairs(palettes) do
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
    for key, entry in pairs(appearance_pending) do
        local copy = {}
        for k, v in pairs(entry) do
            copy[k] = v
        end
        snapshot.appearance_pending[key] = copy
        pending_keys[#pending_keys + 1] = key
    end
    table.sort(pending_keys)
    for _, key in ipairs(pending_keys) do
        signature[#signature + 1] = 'pending:' .. key .. ':' .. tostring(appearance_pending[key].texture.object)
    end
    snapshot.bytes = copier.bytes
    snapshot.signature = table.concat(signature, '|')
    return snapshot
end
local function restore_action(snapshot, expected)
    -- History frames stay immutable when their documents return to the editor.
    local saved = snapshot
    snapshot = {}
    for k, v in pairs(saved) do
        snapshot[k] = v
    end
    local clone = m.basic_state.copier().copy
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
    assert(stop_identification(), 'Highlight restoration pending')
    local proof = appearance_proof()
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
                            and appearance_resource(entry.binding) == entry.cape_resource
                        ),
                    'Cape resource changed; cannot safely undo or redo its old colors'
                )
            end
        end
    end
    local plans = {}
    local pools = {
        { session = bindings, name = 'owned', slot = m.engine.LUT_SLOT, suffix = '' },
        {
            session = operations.pattern_session,
            name = 'pattern_owned',
            slot = m.engine.PATTERN_SLOT,
            suffix = ':pattern',
        },
    }
    local function read_plan(plan)
        return m.engine.binding(read, plan.binding.material, plan.slot, small, big)
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
            local key = material_key(b) .. pool.suffix
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
                e and present(b) and b.current == e.current and read_plan(plan) == e.current,
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
                assert(present(b) and read_plan(plan) == b.original, 'Gear changed; cannot safely redo this action')
                plans[#plans + 1] = plan
            end
        end
    end
    local changed = {}
    local ok, why = pcall(function()
        for _, plan in ipairs(plans) do
            assert(
                present(plan.binding) and read_plan(plan) == plan.old,
                'Gear bindings changed during history restoration'
            )
            if plan.cape_proof then
                local current_proof = appearance_proof()
                assert(
                    current_proof and current_proof.cape == plan.cape_proof,
                    'Cape kit changed during history restoration'
                )
            end
            if plan.object ~= plan.old then
                changed[#changed + 1] = plan
                m.engine.bind(native, plan.binding.material, plan.slot, plan.object)
                native.commit(plan.binding.mesh)
                assert(read_plan(plan) == plan.object)
            end
        end
    end)
    if not ok then
        for i = #changed, 1, -1 do
            local p = changed[i]
            if present(p.binding) and read_plan(p) == p.object then
                local restored = pcall(function()
                    m.engine.bind(native, p.binding.material, p.slot, p.old)
                    native.commit(p.binding.mesh)
                    assert(read_plan(p) == p.old)
                end)
                if not restored and present(p.binding) and read_plan(p) == p.object then
                    -- The forward write is still ours. Keep its exact receipt
                    -- so later Restore/cleanup can remove it even when this
                    -- history action could not finish its rollback.
                    local b, d = p.binding, p.desired
                    b.current, b.previous = p.object, p.old
                    b.texture, b.document = d and d.texture or nil, d and d.document or nil
                    b.applied_cape_proof = d and d.cape_proof or p.cape_proof
                    local found = false
                    for _, owned in ipairs(p.pool.session.owned) do
                        if material_key(owned) == material_key(b) then
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
local function refresh_outfits()
    if handle and api.mods[handle.id].controls.armory_search then
        armory_collection.filter(handle.get('armory_search'), handle.get('armory_sort'))
    else
        armory_collection.refresh()
    end
end
function operations.provenance_unit_resource(unit, identity)
    local helper = assert(operations.provenance_unit_identity, 'Verified Lua Unit identity unavailable')
    identity = identity or assert(m.avatar.resolve(memory, game, appearance_read), 'Current local avatar unavailable')
    return helper.resource(unit, identity)
end
function operations.provenance_read(address, size)
    assert(
        type(address) == 'number'
            and address >= 65536
            and address < 2 ^ 47
            and type(size) == 'number'
            and size >= 1
            and size <= 96,
        'Invalid kit snapshot read'
    )
    local buffer = ffi.new('uint8_t[?]', size)
    return memory.read_into(ffi.cast('const uint8_t *', address), size, buffer) and ffi.string(buffer, size) or nil
end
function operations.ensure_binding_provenance()
    if operations.provenance_resolver then
        return operations.provenance_resolver
    end
    if
        not (
            m.binding_provenance
            and m.binding_source_cache
            and m.binding_provenance_script
            and m.binding_provenance_reader
            and m.unit_identity
            and m.material_identity
            and m.binding_unit_layout
            and m.binding_names
        )
    then
        return nil, 'Verified named Lua binding identity unavailable'
    end
    local ready, unit_identity, material_identity = pcall(function()
        local E = assert(rawget(_G, 'stingray'), 'Lua Unit APIs unavailable')
        local units =
            m.unit_identity.new(E, { avatar = m.avatar, memory = memory, game = game, read = appearance_read })
        local materials = m.material_identity.new(E, {
            unit_identity = units,
            section_name = m.binding_names.section,
            mesh_name = m.binding_names.mesh,
            single_material = function(b)
                return native.materials(b.mesh) == 1
                    and tonumber(native.material(b.mesh, 0)) == b.material
                    and native.materials(b.mesh) == 1
            end,
        })
        return units, materials
    end)
    if not ready then
        return nil, tostring(unit_identity)
    end
    local cache = m.binding_source_cache.new(m, { paths = paths, log = ctx.log })
    local resolver = m.binding_provenance.new({
        engine = m.engine,
        present = present,
        binding = binding,
        unit_source = cache.unit,
        material_source = cache.material,
        unit_resource = operations.provenance_unit_resource,
        identity = function()
            return m.avatar.resolve(memory, game, appearance_read)
        end,
        kit_override = function(b, hash, slot)
            local identity = assert(m.avatar.resolve(memory, game, appearance_read), 'Current kit identity unavailable')
            return m.binding_provenance.kit_override(operations.provenance_read, game, identity, b, hash, slot)
        end,
        material_identity = material_identity,
        layout = m.binding_unit_layout.parse,
    })
    operations.provenance_cache, operations.provenance_resolver, operations.provenance_unit_identity =
        cache, resolver, unit_identity
    return resolver
end
function operations.request_binding_sources()
    local resolver, why = operations.ensure_binding_provenance()
    if not resolver then
        return false, why
    end
    local identity = assert(m.avatar.resolve(memory, game, appearance_read), 'Current kit identity unavailable')
    local units, seen, refused = {}, {}, nil
    for _, group in ipairs(groups) do
        for _, b in ipairs(group.bindings) do
            if not seen[b.unit] then
                seen[b.unit] = true
                local ok, value = pcall(function()
                    local hash = operations.provenance_unit_resource(b.unit, identity)
                    local _, kit = m.binding_provenance.kit_override(
                        operations.provenance_read,
                        game,
                        identity,
                        b,
                        hash,
                        m.engine.LUT_SLOT
                    )
                    return { resource = hash, archive = kit.archive }
                end)
                if ok then
                    units[#units + 1] = value
                else
                    refused = refused or tostring(value)
                end
            end
        end
    end
    if #units == 0 then
        return false, refused or 'No current units have a unique kit source proof'
    end
    if refused and ctx.log then
        ctx.log('Binding source request omitted unproven units: ' .. refused:sub(1, 512))
    end
    local ok, why = operations.provenance_cache.start(units, true)
    if ok then
        operations.provenance_probe_requested = true
    end
    return ok, why
end
function operations.probe_binding_sources()
    local cache = operations.provenance_cache
    if not operations.provenance_probe_requested or not cache or cache.state ~= 'ready' then
        return
    end
    operations.provenance_probe_requested = nil
    local counts = { targets = 0, matched = 0, unmatched = 0, ambiguous = 0, kit_override = 0, unready = 0 }
    local reasons, seen_reasons = {}, {}
    -- Explicit-request completion is read-only: do not refresh/discover, stop
    -- flashes, mutate documents or bind anything while collecting evidence.
    for _, pool in ipairs({
        { targets = groups, pattern = false },
        { targets = pattern_editor and pattern_editor.all_groups or {}, pattern = true },
    }) do
        for _, group in ipairs(pool.targets) do
            for _, b in ipairs(group.bindings) do
                local original = original_luts and original_luts.get(b.original)
                counts.targets = counts.targets + 1
                local ok, why = pcall(operations.provenance_resolver.capture, b, {
                    kind = m.gear_catalog.kind(b),
                    key = (pool.pattern and 'p:' or '') .. b.save_key,
                    original = original,
                })
                if ok then
                    counts.matched = counts.matched + 1
                else
                    why = tostring(why)
                    local category = why:find('Active kit texture override', 1, true) and 'kit_override'
                        or why:find('matches=0', 1, true) and 'unmatched'
                        or why:find('pointer proof', 1, true) and 'ambiguous'
                        or 'unready'
                    counts[category] = counts[category] + 1
                    local distinct = category .. ':' .. why:gsub('^.-:%d+: ', '')
                    if #reasons < 8 and not seen_reasons[distinct] then
                        seen_reasons[distinct] = true
                        reasons[#reasons + 1] = why:sub(1, 256)
                    end
                end
            end
        end
    end
    if ctx.log then
        ctx.log(
            'BINDING_PROVENANCE_PROBE index='
                .. cache.index_stamp
                .. ' targets='
                .. counts.targets
                .. ' matched='
                .. counts.matched
                .. ' unmatched='
                .. counts.unmatched
                .. ' ambiguous='
                .. counts.ambiguous
                .. ' kit_overrides='
                .. counts.kit_override
                .. ' unready='
                .. counts.unready
                .. (#reasons > 0 and ' reasons=' .. table.concat(reasons, ' | ') or '')
        )
    end
end
local function binding_export_unavailable(cache)
    return tostring(cache.error or cache.status or 'Exact binding sources unavailable')
        .. '; press Load Current Gear to retry'
end
function operations.binding_export_provider(preset)
    local hydrated, matches = {}
    local function prepare()
        local resolver, why = operations.ensure_binding_provenance()
        assert(resolver, why or 'Verified named Lua binding identity unavailable')
        local cache = operations.provenance_cache
        if cache.state == 'failed' or cache.state == 'stale' then
            error(binding_export_unavailable(cache), 0)
        end
        if cache.state == 'idle' or cache.state == 'closed' then
            local started, reason = operations.request_binding_sources()
            assert(started, reason or 'Exact binding source request could not start')
        end
        if cache.state == 'loading' then
            error(BINDING_EXPORT_PENDING, 0)
        end
        assert(cache.state == 'ready', binding_export_unavailable(cache))
        local valid, reason = cache.validate_scope()
        if not valid then
            cache.error = reason or cache.status or 'Current binding source scope changed'
            error(binding_export_unavailable(cache), 0)
        end
        assert(stop_identification(), 'Highlight restoration pending')
        if pattern_editor then
            assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
        end
        refresh(true)
        if pattern_editor then
            pattern_editor.scan()
        end
        local current = {}
        for _, pool in ipairs({
            { targets = groups, pattern = false },
            { targets = pattern_editor and pattern_editor.all_groups or {}, pattern = true },
        }) do
            for _, group in ipairs(pool.targets) do
                for _, b in ipairs(group.bindings) do
                    local key = m.gear_catalog.kind(b) .. ':' .. (pool.pattern and 'p:' or '') .. b.save_key
                    current[key] = current[key] or {}
                    current[key][#current[key] + 1] = b
                end
            end
        end
        local found = {}
        -- Legacy manifests have no stable asset IDs. Require the complete
        -- saved target set and original texture metadata to match current gear
        -- before the independent pointer/SectionID proof can hydrate anything.
        for _, entry in ipairs(preset.entries) do
            local candidates = current[entry.kind .. ':' .. entry.key]
            local b = candidates and #candidates == 1 and candidates[1]
            local original = b and original_luts and original_luts.get(b.original)
            assert(
                b
                    and original
                    and entry.original
                    and original.resource == entry.original.resource
                    and original.width == entry.original.width
                    and original.height == entry.original.height,
                'Saved preset does not uniquely match the complete current gear; binding assignments were not retargeted'
            )
            assert(present(b) and binding(b) == b.current, 'Current binding changed before export')
            found[entry] = { binding = b, original = original }
        end
        matches = found
        return resolver
    end
    return function(entry)
        local resolver = matches and operations.provenance_resolver or prepare()
        local target = assert(matches[entry], 'Export entry is not in the verified preset')
        if not hydrated[entry] then
            if not entry.binding_provenance then
                local current = applied_document(target.binding) or target.original
                assert(
                    current
                        and current.width == entry.document.width
                        and current.height == entry.document.height
                        and ffi.string(current.data, current.width * current.height * 16)
                            == ffi.string(entry.document.data, entry.document.width * entry.document.height * 16),
                    'Apply this legacy preset to the current gear first; its assigned colors do not match the active binding context'
                )
            end
            local source, refs =
                resolver.capture(target.binding, { kind = entry.kind, key = entry.key, original = target.original })
            if entry.binding_provenance then
                assert(
                    m.binding_provenance.matches(entry.binding_provenance, refs),
                    'Saved binding provenance differs from current pristine assets/kit; no assignments guessed'
                )
            end
            hydrated[entry] = source
        end
        return hydrated[entry]
    end
end
function operations.export_material_source(resource)
    return assert(operations.provenance_cache, 'Exact material source cache unavailable').material(resource)
end
local function keep_outfit(name, save_kind)
    assert(outfits, 'Outfit storage unavailable')
    local explicit = type(save_kind) == 'table'
    local scope = {}
    if explicit then
        for kind, checked in pairs(save_kind) do
            assert(kind == 'armor' or kind == 'helmet' or kind == 'cape', 'Unknown Armory save target')
            assert(type(checked) == 'boolean', 'Armory save targets must be checked or unchecked')
        end
        for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
            scope[kind] = save_kind[kind] == true
        end
    else
        assert(
            save_kind == nil or save_kind == 'armor' or save_kind == 'helmet' or save_kind == 'both',
            'Choose Armor, Helmet or Cape to save'
        )
        -- Historical programmatic Armor saves include capes. The explicit UI
        -- mask selects all three families independently.
        scope.armor = save_kind ~= 'helmet'
        scope.helmet = save_kind ~= 'armor'
        scope.cape = save_kind ~= 'helmet'
    end
    assert(scope.armor or scope.helmet or scope.cape, 'Check at least one gear type to save')
    local labels = {}
    for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
        if scope[kind] then
            labels[#labels + 1] = m.gear_catalog.label(kind)
        end
    end
    local scope_label = table.concat(labels, ' + ')
    assert(stop_identification(), 'Highlight restoration pending')
    if pattern_editor then
        assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
    end
    refresh(true)
    local entries, seen = {}, {}
    local counts = { armor = 0, helmet = 0, cape = 0 }
    local material_counts = { armor = 0, helmet = 0, cape = 0 }
    local resolver = operations.ensure_binding_provenance()
    if resolver and operations.provenance_cache.state == 'ready' then
        operations.provenance_cache.validate_scope()
    end
    local provenance_count, provenance_error = 0, nil
    local function collect(targets, pattern)
        for _, group in ipairs(targets) do
            for _, b in ipairs(group.bindings) do
                local kind = m.gear_catalog.kind(b)
                local saved_key = (pattern and 'p:' or '') .. b.save_key
                local key = kind .. ':' .. saved_key
                if not seen[key] and scope[kind] then
                    local original = original_luts and original_luts.get(b.original)
                    local source = applied_document(b) or original
                    if not pattern or (source and source.width == 3 and source.height == 1) then
                        assert(source, 'Current ' .. kind .. ' LUT unavailable; load current gear before saving')
                        local provenance
                        if
                            resolver
                            and original
                            and original.patch_source
                            and operations.provenance_cache.state == 'ready'
                        then
                            local ok, _, refs =
                                pcall(resolver.capture, b, { kind = kind, key = saved_key, original = original })
                            if ok then
                                provenance = refs
                                provenance_count = provenance_count + 1
                            else
                                provenance_error = provenance_error or tostring(_)
                            end
                        end
                        entries[#entries + 1] = {
                            kind = kind,
                            key = saved_key,
                            document = source,
                            original = original,
                            binding_provenance = provenance,
                        }
                        counts[kind] = counts[kind] + 1
                        if not pattern then
                            material_counts[kind] = material_counts[kind] + 1
                        end
                        seen[key] = true
                    end
                end
            end
        end
    end
    collect(groups, false)
    if pattern_editor then
        pattern_editor.scan()
        collect(pattern_editor.all_groups or {}, true)
    end
    if explicit then
        for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
            assert(
                not scope[kind] or material_counts[kind] > 0,
                'Current '
                    .. m.gear_catalog.label(kind)
                    .. ' material LUTs are unavailable or still loading. Load Current Gear, then try saving again.'
            )
        end
    else
        assert(
            not scope.armor or counts.armor + counts.cape > 0,
            'Current Armor/Cape LUTs are unavailable or still loading. Load Current Gear, then try saving again.'
        )
        assert(
            not scope.helmet or counts.helmet > 0,
            'Current Helmet LUTs are unavailable or still loading. Load Current Gear, then try saving again.'
        )
    end
    if ctx.log then
        ctx.log(
            'ARMORY_SAVE scope='
                .. scope_label
                .. ' armor='
                .. counts.armor
                .. ' cape='
                .. counts.cape
                .. ' helmet='
                .. counts.helmet
                .. ' total='
                .. #entries
        )
    end
    armory_collection.save(name, entries)
    if resolver and ctx.log then
        ctx.log(
            'ARMORY_PROVENANCE captured='
                .. provenance_count
                .. ' total='
                .. #entries
                .. ' cache='
                .. operations.provenance_cache.state
                .. (provenance_error and ' reason=' .. provenance_error:sub(1, 512) or '')
        )
    end
    if api.mods[handle.id].controls.armory_search then
        assert(handle.set('armory_search', ''))
    end
    for _, entry in ipairs(entries) do
        local d = entry.document
        d.saved_pixels = ffi.string(d.data, d.width * d.height * 16)
    end
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
local function apply_outfit(kind, selection)
    local selected_outfit = assert(armory_collection and armory_collection.selected, 'Choose an outfit preset first')
    local combined = type(kind) == 'table'
    local scope, names = {}, {}
    for _, family in ipairs({ 'armor', 'helmet', 'cape' }) do
        local wanted = combined and kind[family] == true or not combined and kind == family
        if wanted then
            local available = not combined
                or family == 'cape' and operations.armory_cape_available(selected_outfit)
                or family ~= 'cape' and #(selected_outfit[family] or {}) > 0
            if available then
                scope[family] = true
                names[#names + 1] = m.gear_catalog.label(family)
            end
        end
    end
    assert(next(scope), 'Check at least one available gear type to apply')
    local scope_label = table.concat(names, ' + ')
    assert(stop_identification(), 'Highlight restoration pending')
    if pattern_editor then
        assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
    end
    if scope.cape then
        for _, session in ipairs({ bindings, operations.pattern_session or {} }) do
            for _, b in ipairs(session.owned or {}) do
                assert(
                    not b.cape or not present(b) or binding(b) == b.current,
                    'Cape binding changed; load current gear again'
                )
            end
        end
    end
    refresh(true)
    if pattern_editor then
        pattern_editor.scan()
    end
    if selection then
        selection.validate(true)
    end
    local exact = operations.outfit_documents(selected_outfit)
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
    for _, group in ipairs(groups) do
        for _, b in ipairs(group.bindings) do
            local family = m.gear_catalog.kind(b)
            if scope[family] and (not selection or selection.material[family .. ':' .. material_key(b)]) then
                assert(present(b) and binding(b) == b.current, 'Gear changed; load current gear again')
                local d, match = operations.outfit_document(exact, b, false)
                if d then
                    assert(d.width == 23, 'Saved material LUT must have 23 columns')
                    assert(not b.cape or appearance_resource(b), 'Current Cape resource identity unavailable')
                    batches[d] = batches[d] or {}
                    table.insert(batches[d], b)
                    matches[b] = match or 'exact'
                    family_matches[family] = true
                    selected_material[family .. ':' .. material_key(b)] = true
                else
                    skipped = skipped + 1
                    if ctx.log then
                        ctx.log(
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
    if pattern_editor then
        for _, group in ipairs(pattern_editor.all_groups or {}) do
            for _, b in ipairs(group.bindings) do
                local d, match
                local family = m.gear_catalog.kind(b)
                if scope[family] and (not selection or selection.pattern[family .. ':' .. material_key(b)]) then
                    d, match = operations.outfit_document(exact, b, true)
                end
                if d then
                    assert(d.width == 3 and d.height == 1, 'Saved Pattern LUT must be 3 x 1')
                    assert(not b.cape or appearance_resource(b), 'Current Cape resource identity unavailable')
                    assert(present(b) and binding(b) == b.current, 'Pattern gear changed; load current gear again')
                    patterns[d] = patterns[d] or {}
                    patterns[d][#patterns[d] + 1] = b
                    matches[b] = match or 'exact'
                    family_matches[family] = true
                    selected_pattern[family .. ':' .. material_key(b)] = true
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
                    local proof = appearance_proof()
                    cape_proof =
                        assert(proof and proof.cape, 'Current Cape identity unavailable; load current gear again')
                end
            end
        end
    end
    local function apply_batch(session, document, targets, pattern)
        local previous = operations.armory_cape_proof
        local previous_lut_proofs = operations.lut_apply_proofs
        operations.armory_cape_proof = cape_proof
        operations.lut_apply_proofs = selection and selection.proofs or nil
        local ok, count = pcall(function()
            if cape_proof then
                local proof = appearance_proof()
                assert(proof and proof.cape == cape_proof, 'Cape kit changed; load current gear again')
            end
            if pattern then
                local applied = session.apply(document, targets)
                remember_appearance(targets, true)
                return applied
            end
            return apply_bindings(document, targets)
        end)
        operations.armory_cape_proof = previous
        operations.lut_apply_proofs = previous_lut_proofs
        assert(ok, count)
        return count
    end
    local function log_applied(targets, pattern)
        if not ctx.log then
            return
        end
        for _, b in ipairs(targets) do
            ctx.log(
                'ARMORY_APPLY preset='
                    .. selected_outfit.name
                    .. ' kind='
                    .. m.gear_catalog.kind(b)
                    .. ' slot='
                    .. (pattern and 'p:' or '')
                    .. b.save_key
                    .. ' resource='
                    .. resource_id(b.original)
                    .. ' match='
                    .. matches[b]
                    .. ' verified=true'
            )
        end
    end
    local before = combined and capture_action()
    local ok, count = pcall(function()
        -- Multi-LUT presets never become blanket overrides for unmatched pieces.
        for family in pairs(scope) do
            set_default(family, nil)
        end
        resume_done = true
        resume_job = nil
        local applied = 0
        for d, targets in pairs(batches) do
            applied = applied + apply_batch(bindings, d, targets, false)
            log_applied(targets, false)
            for _, b in ipairs(targets) do
                basic_documents[m.gear_catalog.kind(b) .. ':' .. tostring(b.original)] =
                    m.basic_state.clone(d, d.source)
            end
        end
        for d, targets in pairs(patterns) do
            applied = applied
                + apply_batch(assert(operations.pattern_session, 'Pattern application unavailable'), d, targets, true)
            log_applied(targets, true)
        end
        assert(applied > 0, 'No worn gear bindings available for this preset')
        edit.remember_application = true
        save_setup()
        return applied
    end)
    if not ok then
        if before then
            local restored, reason = pcall(restore_action, before, capture_action())
            assert(restored and reason ~= false, tostring(count) .. '; preset rollback failed: ' .. tostring(reason))
        end
        error(count, 0)
    end
    return message(
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
function operations.choose_outfit_luts()
    local preset = assert(armory_collection and armory_collection.selected, 'Choose an outfit preset first')
    assert(frontend.menu, 'Preset chooser requires the editor menu')
    assert(stop_identification(), 'Highlight restoration pending')
    if pattern_editor then
        assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
    end
    refresh(true)
    if pattern_editor then
        pattern_editor.scan()
    end
    local proof = assert(appearance_proof(), 'Current gear identity unavailable; load current gear again')
    local exact = operations.outfit_documents(preset)
    local columns = { { title = 'Armor / Cape', items = {} }, { title = 'Helmet', items = {} } }
    local records, saved, saved_pixels = {}, {}, {}
    local function bytes(d)
        return ffi.string(d.data, d.width * d.height * 16)
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
    for _, group in ipairs(pattern_editor and pattern_editor.all_groups or {}) do
        for _, b in ipairs(group.bindings) do
            pattern_bindings[m.gear_catalog.kind(b) .. ':' .. material_key(b)] = b
        end
    end
    local function receipt(b, pattern)
        local original = original_luts and original_luts.get(b.original)
        return {
            binding = b,
            kind = m.gear_catalog.kind(b),
            unit = b.unit,
            mesh = b.mesh,
            material = b.material,
            slot = b.slot or (pattern and m.engine.PATTERN_SLOT or m.engine.LUT_SLOT),
            original = b.original,
            current = b.current,
            save_key = b.save_key,
            resource = original and original.resource,
            width = original and original.width,
            height = original and original.height,
            pattern = pattern,
        }
    end
    local function companion(material, match)
        local kind = m.gear_catalog.kind(material)
        local key = kind .. ':' .. material_key(material)
        local b = pattern_bindings[key]
        local candidate = b
            or {
                unit = material.unit,
                mesh = material.mesh,
                material = material.material,
                save_key = material.save_key,
                cape = material.cape,
                helmet = material.helmet,
                armor = material.armor,
            }
        local d
        if b then
            d = operations.outfit_document(exact, b, true)
        elseif exact.resolve then
            d = exact.resolve(kind, candidate, true, nil)
        else
            d = exact[kind .. ':p:' .. material.save_key] or material.cape and exact['armor:p:' .. material.save_key]
        end
        local required = d ~= nil
        if not required and match == 'mesh-family' then
            local own_prefix, own_index = material.save_key:match('^(%d+:%d+):%d+:(%d+)$')
            for _, entry in ipairs(preset.entries) do
                local prefix, index = entry.key:match('^p:(%d+:%d+):%d+:(%d+)$')
                if own_prefix and entry.kind == kind and prefix == own_prefix and index == own_index then
                    required = true
                end
            end
        end
        if not required then
            return
        end
        local original = b and original_luts and original_luts.get(b.original)
        assert(
            b
                and d
                and d.width == 3
                and d.height == 1
                and original
                and original.width == 3
                and original.height == 1
                and b.slot == m.engine.PATTERN_SLOT
                and present(b)
                and binding(b) == b.current,
            'Associated Pattern LUT is unavailable or changed; load current Pattern LUTs again'
        )
        return receipt(b, true)
    end
    for column, container in ipairs({ 'armor', 'helmet' }) do
        for _, choice in ipairs(current_choices(container)) do
            local group = groups[choice.group]
            local record =
                { target = import_target(choice.kind, choice.group), material = {}, patterns = {}, members = {} }
            local allowed, reason = pcall(function()
                assert(proof[choice.kind], 'Current gear identity unavailable')
                for _, b in ipairs(group.bindings) do
                    if m.gear_catalog.kind(b) == choice.kind then
                        record.members[#record.members + 1] = receipt(b, false)
                        assert(present(b) and binding(b) == b.current, 'Current LUT binding changed')
                        local d, match = operations.outfit_document(exact, b, false)
                        if d then
                            assert(d.width == 23, 'Saved material LUT must have 23 columns')
                            record.material[#record.material + 1] = receipt(b, false)
                            local paired = companion(b, match)
                            if paired then
                                record.patterns[#record.patterns + 1] = paired
                            end
                        end
                    end
                end
                assert(#record.material > 0, 'No saved material LUT matches this current LUT')
            end)
            record.enabled = allowed
            records[choice.key] = record
            local detail = #record.patterns > 0 and 'Pattern included' or nil
            if not allowed then
                detail = tostring(reason):gsub('^.-%.lua:%d+:%s*', '')
            end
            columns[column].items[#columns[column].items + 1] = {
                id = choice.key,
                label = (choice.kind == 'cape' and 'Cape' or m.gear_catalog.label(choice.kind))
                    .. ' LUT '
                    .. choice.ordinal,
                kind = choice.kind,
                enabled = allowed,
                checked = allowed,
                detail = detail,
            }
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
                and (b.slot or m.engine.LUT_SLOT) == r.slot
                and present(b)
                and binding(b) == r.current,
            'Current LUT target changed; reopen Apply Preset'
        )
        local original = original_luts and original_luts.get(r.original)
        assert(
            original and original.resource == r.resource and original.width == r.width and original.height == r.height,
            'Current LUT resource changed; reopen Apply Preset'
        )
        if r.pattern then
            assert(original.width == 3 and original.height == 1, 'Associated Pattern LUT is unavailable or changed')
        end
    end
    dialog.on_apply = function(selected)
        assert(frontend.menu.lut_apply_dialog == dialog, 'Preset chooser changed; reopen Apply Preset')
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
                armory_collection.selected == preset and #preset.entries == #saved,
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
            local current = appearance_proof()
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
                    for _, group in ipairs(groups) do
                        if group.object == record.target.object then
                            for _, b in ipairs(group.bindings) do
                                if m.gear_catalog.kind(b) == record.target.kind then
                                    actual[material_key(b) .. ':' .. tostring(b.slot or m.engine.LUT_SLOT)] = b.save_key
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
                selection.material[r.kind .. ':' .. material_key(r.binding)] = true
            end
            for _, r in ipairs(record.patterns) do
                selection.pattern[r.kind .. ':' .. material_key(r.binding)] = true
            end
        end
        local before = history and history.capture()
        local result = apply_outfit(scope, selection)
        if before then
            history.record(before, history.capture())
        end
        frontend.menu.lut_apply_dialog = nil
        return true, result
    end
    frontend.menu.lut_apply_dialog = dialog
    return message('Choose current LUTs to apply. Associated Pattern LUTs are always included.')
end
function operations.open_import_map(kind, prepared)
    assert(kind == 'gear' or kind == 'armor' or kind == 'helmet' or kind == 'cape', 'Choose gear to map')
    assert(frontend.menu and #palettes > 0, 'Import a LUT file first')
    assert(not pending, 'Wait for the current import to finish')
    local missing = false
    for _, path in ipairs(palettes) do
        missing = missing or (editor_tables[path] or source_tables[path]) == nil
    end
    if not prepared and (index_job or missing) then
        operations.import_map_request = { kind = kind, palettes = palettes }
        if not index_job then
            index_job = table_index.start(palettes, source_tables, import_ids)
        end
        return message('Reading imported LUTs; the mapping chooser will open when ready.')
    end
    assert(stop_identification(), 'Highlight restoration pending')
    if pattern_editor then
        assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
    end
    refresh(true)
    if pattern_editor then
        pattern_editor.scan()
    end
    local proof = assert(appearance_proof(), 'Current gear identity unavailable; load current gear again')
    local catalog = palettes
    local kinds = kind == 'gear' and { 'armor', 'helmet', 'cape' } or { kind }
    local columns = { { title = 'Imported LUTs', items = {} } }
    for _, k in ipairs(kinds) do
        local label = k == 'cape' and 'Cape' or m.gear_catalog.label(k)
        columns[#columns + 1] = {
            title = kind == 'gear' and label or 'Current ' .. label .. ' LUTs',
            kind = k,
            items = {},
            enabled = false,
            checked = false,
        }
    end
    local sources, source_order, resources = {}, {}, {}
    local function pixels(d)
        return d and ffi.string(d.data, d.width * d.height * 16)
    end
    local function resource(path, d)
        return import_ids[path] or source_tables[path] and source_tables[path].resource or d and d.resource
    end
    for index, path in ipairs(catalog) do
        local d = editor_tables[path] or source_tables[path]
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
        local original = original_luts and original_luts.get(b.original)
        return {
            binding = b,
            unit = b.unit,
            mesh = b.mesh,
            material = b.material,
            slot = b.slot or m.engine.LUT_SLOT,
            save_key = b.save_key,
            original = b.original,
            current = b.current,
            resource = original and original.resource,
            width = original and original.width,
            height = original and original.height,
        }
    end
    local function validate_receipt(r)
        local b, original = r.binding, original_luts and original_luts.get(r.original)
        assert(
            b.unit == r.unit
                and b.mesh == r.mesh
                and b.material == r.material
                and b.original == r.original
                and b.save_key == r.save_key
                and (b.slot or m.engine.LUT_SLOT) == r.slot
                and present(b)
                and binding(b) == r.current,
            'Current mapping target changed; reopen Map LUTs'
        )
        assert(
            original and original.resource == r.resource and original.width == r.width and original.height == r.height,
            'Original mapping target changed; load current gear again'
        )
    end
    local targets, target_order = {}, {}
    for column_index, target_kind in ipairs(kinds) do
        local column = columns[column_index + 1]
        local container = target_kind == 'helmet' and 'helmet' or 'armor'
        for _, choice in ipairs(current_choices(container)) do
            if choice.kind == target_kind then
                local target = { target = import_target(target_kind, choice.group), members = {}, patterns = {} }
                local enabled, why = pcall(function()
                    assert(proof[target_kind], 'Current gear identity unavailable')
                    for _, b in ipairs(groups[choice.group].bindings) do
                        if m.gear_catalog.kind(b) == target_kind then
                            local r = receipt(b)
                            validate_receipt(r)
                            assert(r.width == 23, 'Current material LUT is not ready')
                            target.members[#target.members + 1] = r
                            for _, group in ipairs(pattern_editor and pattern_editor.all_groups or {}) do
                                for _, p in ipairs(group.bindings) do
                                    if m.gear_catalog.kind(p) == target_kind and material_key(p) == material_key(b) then
                                        target.patterns[material_key(b)] = receipt(p)
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
                        or (target_kind == 'cape' and 'Cape' or m.gear_catalog.label(target_kind))
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
            .. (kind == 'gear' and 'Gear' or kind == 'cape' and 'Cape' or m.gear_catalog.label(kind)),
        columns = columns,
        gear_columns = kind == 'gear',
    }
    local current_source = catalog[handle.get('palette')]
    dialog.source_id = current_source and sources['source:' .. current_source].enabled and 'source:' .. current_source
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
            frontend.menu.lut_apply_dialog == dialog
                and palettes == catalog
                and #palettes == #source_order
                and not pending
                and not index_job,
            'Imported palette changed; reopen Map LUTs'
        )
        for index, r in ipairs(source_order) do
            local d = editor_tables[r.path] or source_tables[r.path]
            assert(
                palettes[index] == r.path
                    and d == r.document
                    and resource(r.path, d) == r.resource
                    and (not d or d.width == r.width and d.height == r.height and pixels(d) == r.bytes),
                'Imported LUT data changed; reopen Map LUTs'
            )
        end
        local current = appearance_proof()
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
        assert(stop_identification(), 'Highlight restoration pending')
        if pattern_editor then
            assert(pattern_editor.stop_flash(), 'Pattern highlight restoration pending')
        end
        refresh(true)
        if pattern_editor then
            pattern_editor.scan()
        end
        validate_catalog()
        local plans, included = {}, {}
        for _, assignment in ipairs(assignments) do
            local source, target = assignment.source, assignment.target
            local target_kind = target.target.kind
            local actual, members = {}, {}
            for _, group in ipairs(groups) do
                if group.object == target.target.object then
                    for _, b in ipairs(group.bindings) do
                        if m.gear_catalog.kind(b) == target_kind then
                            actual[material_key(b) .. ':' .. tostring(b.slot or m.engine.LUT_SLOT)] = b.save_key
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
                local original = original_luts and original_luts.get(b.original)
                local d = source.document
                if handle.get('preserve_emissives') then
                    assert(original_luts.loaded, 'Original game LUT snapshots are not ready')
                    variants[b.original] = variants[b.original]
                        or { document = m.original_luts.preserve(d, original, d.height > 8), targets = {} }
                else
                    variants[b.original] = variants[b.original] or { document = d, targets = {} }
                end
                variants[b.original].targets[#variants[b.original].targets + 1] = b
                -- Only unique, metadata-certified resources at this exact native
                -- material can establish an imported material/Pattern pair.
                if source.resource and original.resource == source.resource and #resources[source.resource] == 1 then
                    local p = target.patterns[material_key(b)]
                    local candidates = p and p.resource and resources[p.resource]
                    if
                        candidates
                        and #candidates == 1
                        and candidates[1].document.width == 3
                        and candidates[1].document.height == 1
                    then
                        validate_receipt(p)
                        assert(
                            p.width == 3 and p.height == 1 and p.slot == m.engine.PATTERN_SLOT,
                            'Associated Pattern LUT is not ready'
                        )
                        local fresh
                        for _, group in ipairs(pattern_editor.all_groups or {}) do
                            for _, current in ipairs(group.bindings) do
                                if
                                    m.gear_catalog.kind(current) == target_kind
                                    and material_key(current) == material_key(b)
                                then
                                    fresh = current
                                end
                            end
                        end
                        assert(
                            fresh and fresh.original == p.original and fresh.current == p.current,
                            'Associated Pattern target changed; reopen Map LUTs'
                        )
                        assignment.paired[material_key(b)] = fresh
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
        local before = assert(history, 'Mapping history is unavailable; reopen Epic LUT').capture()
        local previous_proofs, previous_cape = operations.lut_apply_proofs, operations.armory_cape_proof
        local applied_kinds = {}
        for _, assignment in ipairs(assignments) do
            applied_kinds[assignment.target.target.kind] = true
        end
        operations.lut_apply_proofs, operations.armory_cape_proof = proof, applied_kinds.cape and proof.cape or nil
        local ok, count = pcall(function()
            local applied = 0
            for k in pairs(applied_kinds) do
                set_default(k, nil)
            end
            for _, plan in ipairs(plans) do
                if plan.pattern then
                    applied = applied
                        + assert(operations.pattern_session, 'Pattern application unavailable').apply(
                            plan.document,
                            plan.targets
                        )
                    remember_appearance(plan.targets, true)
                else
                    applied = applied + apply_bindings(plan.document, plan.targets)
                    for _, b in ipairs(plan.targets) do
                        basic_documents[m.gear_catalog.kind(b) .. ':' .. tostring(b.original)] =
                            m.basic_state.clone(plan.document, plan.document.source)
                    end
                end
            end
            edit.remember_application, resume_done, resume_job = true, true, nil
            save_setup()
            return applied
        end)
        operations.lut_apply_proofs, operations.armory_cape_proof = previous_proofs, previous_cape
        if not ok then
            if before then
                local restored, why = pcall(restore_action, before, capture_action())
                assert(restored and why ~= false, tostring(count) .. '; mapping rollback failed: ' .. tostring(why))
                -- History restoration clones palette lists and edited source
                -- documents. Reuse this dialog only when every frozen byte
                -- and resource still agrees with those restored copies.
                local same = #palettes == #source_order
                for index, r in ipairs(source_order) do
                    local d = editor_tables[r.path] or source_tables[r.path]
                    same = same
                        and palettes[index] == r.path
                        and resource(r.path, d) == r.resource
                        and (
                            not d and not r.document
                            or d and d.width == r.width and d.height == r.height and pixels(d) == r.bytes
                        )
                end
                if same then
                    catalog = palettes
                    for _, r in ipairs(source_order) do
                        r.document = editor_tables[r.path] or source_tables[r.path]
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
        if frontend.menu then
            frontend.menu.redraw_revision = (frontend.menu.redraw_revision or 0) + 1
        end
        return true,
            message('Mapped ' .. #assignments .. ' imported LUTs to ' .. count .. ' exact ' .. kind .. ' bindings.')
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
    frontend.menu.lut_apply_dialog = dialog
    return message('Choose an imported LUT, then click the current LUT to map it.')
end
local function sync_armory_export()
    if not handle then
        return
    end
    local controls = api.mods[handle.id].controls
    local selected = armory_collection and armory_collection.selected
    operations.sync_armory_cape()
    controls.armory_export.disabled = not selected
    local lut = controls.armory_export_lut
    lut.choices = m.preset_export and m.preset_export.lut_choices(selected) or { 'Choose a saved preset first' }
    local disabled = not selected
        or (handle.get('armory_export_format') ~= 2 and handle.get('armory_export_format') ~= 4)
    lut.disabled = false
    assert(handle.set('armory_export_lut', math.min(handle.get('armory_export_lut'), #lut.choices)))
    lut.disabled = disabled
end
local function include_capes_in_exports()
    if preferences and preferences.include_capes_in_armor_exports then
        return preferences.include_capes_in_armor_exports() ~= false
    end
    local control = handle and api.mods[handle.id].controls.include_capes_in_armor_exports
    return not control or handle.get('include_capes_in_armor_exports') ~= false
end
function operations.include_patterns_in_exports()
    if preferences and preferences.include_patterns_in_exports then
        return preferences.include_patterns_in_exports() ~= false
    end
    local control = handle and api.mods[handle.id].controls.include_patterns_in_exports
    return not control or handle.get('include_patterns_in_exports') ~= false
end
function operations.selected_export_bindings(required)
    local selected
    if frontend.basic_mode then
        selected = basic_selected
    else
        selected = edit.editor_target
    end
    if not selected and not required then
        return {}
    end
    refresh(true)
    local index = selected and checked_editor_target(selected) or handle.get('lut')
    local group = assert(groups[index], 'Select a Live LUT destination first')
    local targets = {}
    for _, b in ipairs(group.bindings) do
        if
            (not selected or not selected.kind or m.gear_catalog.kind(b) == selected.kind)
            and (not b.cape or selected and selected.kind == 'cape' or include_capes_in_exports())
        then
            assert(present(b) and binding(b) == b.current, 'Gear changed; load current gear before exporting')
            targets[#targets + 1] = b
        end
    end
    assert(#targets > 0, 'Selected LUT has no live export destination')
    return targets
end
function operations.export_original_patch(entry)
    local original = assert(entry.original, 'Original texture metadata unavailable')
    local baseline = original.data and original or original_luts and original_luts.get_resource(original.resource)
    assert(
        baseline
            and baseline.data
            and baseline.resource == original.resource
            and baseline.width == original.width
            and baseline.height == original.height,
        'Original texture palette is not ready; load current gear before exporting'
    )
    return m.patch_export.encode(m.dds, baseline, original)
end

function operations.export_pattern_entries(targets, pattern_groups)
    if
        not operations.include_patterns_in_exports()
        or not pattern_editor
        or not m.engine.PATTERN_SLOT
        or #targets == 0
    then
        return {}
    end
    pattern_groups = pattern_groups or pattern_editor.scan(true)
    local matched = assert(m.export_pairing, 'Export pairing unavailable').live(targets, pattern_groups, {
        key = material_key,
        kind = m.gear_catalog.kind,
    })
    local entries, counts = {}, {}
    for _, b in ipairs(matched) do
        assert(present(b) and binding(b) == b.current, 'Pattern gear changed; load current gear before exporting')
        local original = original_luts and original_luts.get(b.original)
        local document = original
        if b.current ~= b.original then
            document = applied_document(b)
        end
        assert(document, 'Matching Pattern LUT snapshot is not ready; load current patterns before exporting')
        assert(document.width == 3 and document.height == 1, 'Matching Pattern snapshot is not a 3x1 LUT')
        local kind = m.gear_catalog.kind(b)
        counts[kind] = (counts[kind] or 0) + 1
        entries[#entries + 1] = {
            document = document,
            original = original,
            kind = kind,
            ordinal = counts[kind],
            key = 'p:' .. b.save_key,
        }
    end
    return entries, matched
end
local function export_custom_dds(name, naming)
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local entries, material_targets = {}, {}
    local function collect(collection, companion_targets)
        local counts = { armor = 0, helmet = 0, cape = 0 }
        for _, group in ipairs(collection) do
            local ordinals = {}
            for _, b in ipairs(group.bindings) do
                local kind = m.gear_catalog.kind(b)
                if (not b.cape or include_capes_in_exports()) and not ordinals[kind] then
                    counts[kind] = counts[kind] + 1
                    ordinals[kind] = counts[kind]
                end
                if
                    (not b.cape or include_capes_in_exports())
                    and (
                        b.current ~= b.original
                        or companion_targets and companion_targets[kind .. ':' .. material_key(b)]
                    )
                then
                    assert(present(b) and binding(b) == b.current, 'Gear changed; load current gear before exporting')
                    local original = original_luts and original_luts.get(b.original)
                    local document = original
                    if b.current ~= b.original then
                        document = applied_document(b)
                    end
                    assert(document, 'LUT data is unavailable; load current patterns before exporting')
                    entries[#entries + 1] = {
                        document = document,
                        original = original,
                        kind = kind,
                        ordinal = ordinals[kind],
                    }
                    if not companion_targets then
                        material_targets[#material_targets + 1] = b
                    end
                end
            end
        end
    end
    collect(groups)
    if pattern_editor and operations.include_patterns_in_exports() then
        local pattern_groups = pattern_editor.scan(true)
        local _, matched = operations.export_pattern_entries(material_targets, pattern_groups)
        local companions = {}
        for _, b in ipairs(matched or {}) do
            companions[m.gear_catalog.kind(b) .. ':' .. material_key(b)] = true
        end
        collect(pattern_groups, companions)
    end
    assert(#entries > 0, 'No custom LUTs available for the selected export settings')
    local folder, count = m.bulk_dds_export.new(m, paths).save(name, entries, naming)
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
local function register(current)
    if api == current and handle then
        return
    end
    if handle then
        handle.unregister()
    end
    api = current
    local callbacks = {
        rename_lut_activate = function()
            local panel = import_state().raw.basic[palette_editor and palette_editor.gear or 'armor']
            local original = panel and panel.group and original_luts and original_luts.get(groups[panel.group].object)
            local hash = assert(original and original.resource, 'Load a current LUT with a known texture ID first')
            local labels = assert(operations.lut_names, 'Local LUT naming is unavailable')
            local menu = assert(frontend.menu, 'Open the LUT Editor first')
            local name = labels.get(hash) or ''
            assert(handle.set('lut_label', name))
            local mod = api.mods[handle.id]
            menu.outfit_dialog = {
                phase = 'name',
                title = 'Name This LUT',
                mod = mod,
                control = mod.controls.lut_label,
                action_label = 'Save Name',
                initial_text = name,
                placeholder = 'Click to enter a LUT name',
                description = 'Clear the name to show the texture ID again.',
                on_save = function(value)
                    labels.set(hash, value)
                    import_state()
                    menu.outfit_dialog, menu.text_edit = nil, nil
                    return message(
                        not labels.get(hash) and 'LUT name cleared; texture ID restored.' or 'LUT name saved locally.'
                    )
                end,
            }
            menu.text_edit = { mod = mod, control = mod.controls.lut_label, text = name, replace = true }
            return true
        end,
        browse_activate = function()
            return action(function()
                return load(true)
            end)
        end,
        load_debug_lut_activate = function()
            return operations.load_debug_lut()
        end,
        cancel_import_activate = function()
            return action(function()
                return cancel_import(false)
            end)
        end,
        retry_import_activate = function()
            return action(function()
                return cancel_import(true)
            end)
        end,
        ui_scale_change = function(value)
            frontend.menu.ui_scale = value / 100
            if preferences.save_scale then
                preferences.save_scale(value)
            end
        end,
        quick_color_change = function(hex)
            if not edit.quick_selection then
                return
            end
            local q = edit.quick_selection
            return operations.paint_quick(q, hex)
        end,
        apply_matching_activate = function()
            return action(function()
                return operations.apply_matching()
            end)
        end,
        basic_advanced_activate = function()
            return frontend.open_advanced()
        end,
        open_editor_activate = function()
            return api.focus_page(handle.id, 'colors')
        end,
        outfit_rename_activate = function()
            return operations.manage_outfit('rename')
        end,
        outfit_delete_activate = function()
            return operations.manage_outfit('delete')
        end,
        outfit_preset_change = select_outfit,
        armory_export_format_change = sync_armory_export,
        armory_import_activate = function()
            return action(function()
                return load(true)
            end)
        end,
        armory_export_activate = function()
            return action(function()
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
                    resource_id_available = function(kind, id)
                        return assert(operations.provenance_cache, 'Binding collision catalog unavailable').id_available(
                            kind,
                            id
                        )
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
            end)
        end,
        outfit_apply_armor_activate = function()
            return action(function()
                return apply_outfit('armor')
            end)
        end,
        outfit_apply_helmet_activate = function()
            return action(function()
                return apply_outfit('helmet')
            end)
        end,
        outfit_apply_cape_activate = function()
            return action(function()
                return apply_outfit('cape')
            end)
        end,
        outfit_apply_selected_activate = function()
            return action(function()
                return apply_outfit({
                    armor = handle.get('outfit_target_armor'),
                    helmet = handle.get('outfit_target_helmet'),
                    cape = handle.get('outfit_target_cape')
                        and operations.armory_cape_available(armory_collection.selected),
                })
            end)
        end,
        outfit_choose_luts_activate = function()
            local ok, value = pcall(operations.choose_outfit_luts)
            return ok and value or message(tostring(value))
        end,
        imported_map_gear_activate = function()
            local ok, value = pcall(operations.open_import_map, 'gear')
            return ok and value or message(tostring(value))
        end,
        imported_map_armor_activate = function()
            local ok, value = pcall(operations.open_import_map, 'armor')
            return ok and value or message(tostring(value))
        end,
        imported_map_helmet_activate = function()
            local ok, value = pcall(operations.open_import_map, 'helmet')
            return ok and value or message(tostring(value))
        end,
        imported_map_cape_activate = function()
            local ok, value = pcall(operations.open_import_map, 'cape')
            return ok and value or message(tostring(value))
        end,
        global_undo_activate = function()
            assert(history, 'Action history unavailable')
            history.undo_action()
            return message('Last action undone; palettes and gear refreshed.')
        end,
        global_redo_activate = function()
            assert(history, 'Action history unavailable')
            history.redo_action()
            return message('Last action redone; palettes and gear refreshed.')
        end,
        basic_armor_lut_change = function()
            if frontend.menu and api.mods[handle.id].pages[frontend.menu.page].id == 'colors' then
                editor_pending = { kind = 'armor', began = os.time() }
                action(function()
                    return load_editor_target('armor')
                end)
            end
        end,
        basic_helmet_lut_change = function()
            if frontend.menu and api.mods[handle.id].pages[frontend.menu.page].id == 'colors' then
                editor_pending = { kind = 'helmet', began = os.time() }
                action(function()
                    return load_editor_target('helmet')
                end)
            end
        end,
        editor_load_armor_activate = function()
            mark_current_load()
            return action(function()
                editor_pending = { kind = 'armor', began = os.time() }
                return load_editor_target('armor')
            end)
        end,
        editor_load_helmet_activate = function()
            mark_current_load()
            return action(function()
                editor_pending = { kind = 'helmet', began = os.time() }
                return load_editor_target('helmet')
            end)
        end,
        editor_apply_armor_activate = function()
            return action(function()
                return apply_editor_target('armor')
            end)
        end,
        editor_apply_helmet_activate = function()
            return action(function()
                return apply_editor_target('helmet')
            end)
        end,
        editor_all_armor_activate = function()
            return action(function()
                return apply_editor_target('armor', true)
            end)
        end,
        editor_all_both_activate = function()
            return action(function()
                return apply_editor_target(nil, true)
            end)
        end,
        editor_all_helmet_activate = function()
            return action(function()
                return apply_editor_target('helmet', true)
            end)
        end,
        apply_import_armor_activate = function()
            return action(function()
                return apply_import_to('armor')
            end)
        end,
        apply_import_helmet_activate = function()
            return action(function()
                return apply_import_to('helmet')
            end)
        end,
        basic_copy_helmet_activate = function()
            return action(function()
                return copy_basic_palette('armor', 'helmet')
            end)
        end,
        basic_copy_helmet_all_activate = function()
            return action(copy_helmet_all)
        end,
        basic_copy_armor_activate = function()
            return action(function()
                return copy_basic_palette('helmet', 'armor')
            end)
        end,
        identify_region_activate = function()
            return action(identify_region)
        end,
        stop_identify_activate = function()
            return action(function()
                assert(stop_identification(), 'Highlight restoration pending')
                return message('Highlight stopped; previous bindings restored.')
            end)
        end,
        populate_worn_activate = function()
            mark_current_load()
            return action(function()
                if original_luts and original_luts.retry then
                    original_luts.retry()
                end
                populate_request = os.time()
                edit.populate_manual_request = true
                if not populate_worn() then
                    return message('Reading worn gear colors; editor will populate when ready.')
                end
                return true
            end)
        end,
        basic_preset_change = function(index)
            if edit.refreshing_basic_presets then
                return
            end
            select_outfit(1)
            if index == 1 then
                assert(handle.set('basic_preset_name', ''))
                return
            end
            action(function()
                local name = assert(basic_names[index - 1])
                local f = assert(io.open(paths.presets .. '/palette-' .. name .. '.dds', 'rb'))
                local bytes = f:read(m.dds.MAX_BYTES + 1)
                f:close()
                local data, w, h = m.dds.decode(bytes)
                assert(w == 23)
                edit.loaded = { data = data, width = w, height = h, source = 'Preset ' .. name }
                assert(handle.set('basic_preset_name', name))
                if palette_editor then
                    palette_editor.sync()
                end
                return message('Palette preset loaded: ' .. name)
            end)
        end,
        basic_save_activate = function()
            return action(function()
                local name = handle.get('basic_preset_name')
                assert(name:match('^[%w _-]+$') and #name > 0 and #name <= 48, 'Enter a preset name')
                assert(edit.loaded, 'Import a palette first')
                operations.preset_files.save(name, edit.loaded, 'palette-')
                operations.refresh_basic_presets(name)
                return message('Palette preset saved: ' .. name)
            end)
        end,
        basic_export_activate = function()
            assert(
                handle.set(
                    'save_name',
                    handle.get('basic_preset_name') ~= '' and handle.get('basic_preset_name') or 'my-palette'
                )
            )
            return handle.activate('save_dds')
        end,
        populate_applied_activate = function()
            return action(function()
                refresh()
                local group = assert(groups[handle.get('lut')], 'No live LUT selected')
                local source
                for _, binding in ipairs(group.bindings) do
                    if binding.document and binding.texture and binding.current == binding.texture.object then
                        source = binding.document
                        break
                    end
                end
                assert(
                    source,
                    'No Epic LUT palette is applied to this Live LUT. Select another Live LUT or apply a file first.'
                )
                local data = ffi.new('float[?]', source.width * source.height * 4)
                ffi.copy(data, source.data, source.width * source.height * 16)
                edit.loaded = {
                    data = data,
                    width = source.width,
                    height = source.height,
                    source = 'Current applied Live LUT ' .. handle.get('lut'),
                }
                edit.preview_document = edit.loaded
                edit.preview_revision = 0
                edit.quick_selection = nil
                if palette_editor then
                    palette_editor.sync()
                end
                return message('Editor populated from the selected applied Live LUT; game bindings unchanged.')
            end)
        end,
        save_palette_activate = function()
            return action(save_palette)
        end,
        apply_checked_activate = function()
            return action(apply_checked)
        end,
        apply_file_armor_activate = function()
            return action(function()
                assert(edit.imported, 'Import a palette first')
                assert(stop_identification(), 'Highlight restoration pending')
                refresh(true)
                assert(handle.set('scope', 2))
                return apply(edit.imported, 'armor')
            end)
        end,
        apply_file_helmet_activate = function()
            return action(function()
                assert(edit.imported, 'Import a palette first')
                assert(stop_identification(), 'Highlight restoration pending')
                refresh(true)
                assert(handle.set('scope', 3))
                return apply(edit.imported, 'helmet')
            end)
        end,
        apply_file_cape_activate = function()
            return action(function()
                assert(edit.imported, 'Import a palette first')
                assert(stop_identification(), 'Highlight restoration pending')
                refresh(true)
                assert(handle.set('scope', 5))
                return apply(edit.imported, 'cape')
            end)
        end,
        apply_file_both_activate = function()
            return action(function()
                assert(edit.imported, 'Import a palette first')
                assert(handle.set('scope', 4))
                return apply(edit.imported)
            end)
        end,
        apply_editor_activate = function()
            return action(function()
                return apply_checked(assert(edit.loaded, 'Save a LUT to Palette first'))
            end)
        end,
        palette_change = function(index)
            if not select_suppressed and not pending and palettes[index] then
                action(function()
                    resume_done = true
                    resume_job = nil
                    return load_dds(palettes[index])
                end)
            end
        end,
        refresh_activate = function()
            return action(refresh)
        end,
        lut_change = function(index)
            if live_select_suppressed then
                return
            end
            action(function()
                assert(stop_identification(), 'Highlight restoration pending')
                local group = groups[index]
                local source
                if group then
                    for _, b in ipairs(group.bindings) do
                        source = basic_documents[(m.gear_catalog.kind(b)) .. ':' .. tostring(b.original)]
                            or b.document
                            or (original_luts and original_luts.get(b.original))
                        if source then
                            break
                        end
                    end
                end
                edit.loaded = nil
                basic_selected = nil
                edit.quick_selection = nil
                if source then
                    local data = ffi.new('float[?]', source.width * source.height * 4)
                    ffi.copy(data, source.data, source.width * source.height * 16)
                    edit.loaded = {
                        data = data,
                        width = source.width,
                        height = source.height,
                        source = 'Live LUT ' .. index,
                    }
                end
                edit.preview_document = edit.loaded
                edit.preview_revision = 0
                if import_view then
                    import_view.selected = nil
                    import_view.scroll = 0
                end
                if palette_editor then
                    palette_editor.sync()
                end
                return message(
                    source and ('Loaded Live LUT ' .. index .. ' into editor')
                        or 'Selected Live LUT colors unavailable; waiting for original snapshot'
                )
            end)
        end,
        apply_activate = function()
            return action(apply)
        end,
        apply_armor_activate = function()
            return action(function()
                assert(handle.set('scope', 2))
                return apply()
            end)
        end,
        apply_helmet_activate = function()
            return action(function()
                assert(handle.set('scope', 3))
                return apply()
            end)
        end,
        remove_lut_activate = function()
            return action(function()
                remove_lut()
                edit.loaded = nil
                edit.imported = nil
                palettes = {}
                if palette_editor then
                    palette_editor.sync()
                end
                return message('LUT removed; original bindings restored.')
            end)
        end,
        save_setup_activate = function()
            if not frontend.menu or not outfits then
                return action(save_setup)
            end
            assert(stop_identification(), 'Highlight restoration pending')
            frontend.menu.outfit_dialog = {
                phase = 'scope',
                save_kind = { armor = true, helmet = true, cape = true },
                mod = api.mods[handle.id],
                control = api.mods[handle.id].controls.outfit_name,
                names = outfits.names(),
                on_save = keep_outfit,
            }
            return message('Choose Armor, Helmet and Cape LUTs to keep as a named preset.')
        end,
        restore_activate = function()
            return action(function()
                local selected = basic_selected
                local selected_kind = (edit.editor_target and edit.editor_target.kind) or (selected and selected.kind)
                remove_lut()
                basic_state.clear()
                basic_missing_reported = {}
                edit.quick_selection = nil
                edit.loaded = nil
                refresh(true)
                local panels = import_state().raw.basic
                if
                    frontend.basic_mode
                    and selected
                    and panels[selected.container or (selected.kind == 'cape' and 'armor' or selected.kind)]
                then
                    local p = panels[selected.container or (selected.kind == 'cape' and 'armor' or selected.kind)]
                    local proof = operations.appearance_proof()
                    local original = p.group and original_luts and original_luts.get(groups[p.group].object)
                    edit.loaded = p.document
                    basic_selected = p.document
                            and {
                                kind = p.kind,
                                key = p.key,
                                group = p.group,
                                container = selected.container,
                                cape_proof = p.kind == 'cape' and proof and proof.cape or nil,
                                resource = original and original.resource,
                            }
                        or nil
                    if
                        p.kind == 'cape'
                        and not (basic_selected and basic_selected.cape_proof and basic_selected.resource)
                    then
                        edit.loaded, basic_selected = nil, nil
                    end
                else
                    basic_selected = nil
                    local group = groups[handle.get('lut')]
                    if group then
                        for _, b in ipairs(group.bindings) do
                            local source = (not selected_kind or b[selected_kind])
                                and original_luts
                                and original_luts.get(b.original)
                            if source then
                                local data = ffi.new('float[?]', source.width * source.height * 4)
                                ffi.copy(data, source.data, source.width * source.height * 16)
                                edit.loaded = {
                                    data = data,
                                    width = source.width,
                                    height = source.height,
                                    source = 'Original game LUT',
                                }
                                break
                            end
                        end
                    end
                end
                basic_imported = edit.imported
                edit.preview_document = edit.loaded
                edit.preview_revision = edit.loaded and (edit.loaded.revision or 0) or 0
                if import_view then
                    import_view.selected = nil
                end
                if palette_editor then
                    palette_editor.sync()
                end
                return message(
                    edit.loaded and 'Original bindings and displayed colors restored; imported file retained.'
                        or 'Original bindings restored; original colors are not available yet.'
                )
            end)
        end,
        reset_custom_activate = function()
            return action(function()
                assert(palette_editor, 'Palette editor unavailable')
                return palette_editor.reset()
            end)
        end,
        restore_imported_activate = function()
            return action(function()
                assert(palette_editor, 'Save an import to the editor first')
                return palette_editor.reset()
            end)
        end,
        load_activate = function()
            return action(function()
                return load(false)
            end)
        end,
    }
    local pages = m.editor_registry.pages(
        callbacks,
        { ui_scale = preferences.scale and preferences.scale() or 100, status = status }
    )
    if palette_editor then
        m.configuration.append(pages, palette_editor.pages(), {
            api = current,
            preferences = preferences,
            updates = updates,
            action = action,
            message = message,
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
        })
    end
    -- Material controls remain registered for the LUT Editor's Value Editor, without a duplicate tab.
    local colors_page
    for _, page in ipairs(pages) do
        if page.id == 'colors' then
            colors_page = page
        end
    end
    for i = #pages, 1, -1 do
        if pages[i].id == 'advanced' and colors_page then
            for _, control in ipairs(pages[i].controls) do
                colors_page.controls[#colors_page.controls + 1] = control
            end
            table.remove(pages, i)
        end
    end
    if m.basic_view then
        table.insert(pages, 1, {
            id = 'basic',
            name = 'Basic',
            require_confirmation = false,
            controls = m.basic_camo and m.basic_camo.controls(function(kind, value, mode, color)
                if not operations.syncing_basic_camo then
                    local completed
                    local result = action(function()
                        local message = operations.apply_basic_camo(kind, value, mode, color)
                        completed = true
                        return message
                    end)
                    if mode == 'color' then
                        return completed == true, result
                    end
                    return result
                end
            end) or {},
        })
    end
    if m.armory_view then
        table.insert(pages, #pages, {
            id = 'armory',
            name = 'The Armory',
            require_confirmation = false,
            controls = {
                {
                    id = 'armory_search',
                    type = 'input',
                    allow_empty = true,
                    label = 'Search Armory',
                    default = '',
                    on_change = function(value)
                        armory_collection.filter(value, handle.get('armory_sort'))
                    end,
                },
                {
                    id = 'armory_sort',
                    type = 'choice',
                    label = 'Sort presets',
                    choices = { 'Name A-Z', 'Name Z-A' },
                    default = 1,
                    on_change = function(value)
                        armory_collection.filter(handle.get('armory_search'), value)
                    end,
                },
            },
        })
    end
    if pattern_editor then
        for _, page in ipairs(pages) do
            if page.id == 'colors' then
                for _, control in ipairs(pattern_editor.controls()) do
                    page.controls[#page.controls + 1] = control
                end
            end
        end
    end
    if m.shared_appearance then
        for _, page in ipairs(pages) do
            if page.id == 'save' then
                page.controls[#page.controls + 1] = {
                    id = 'share_appearance',
                    type = 'toggle',
                    label = 'Share full LUT appearance with Epic LUT users',
                    default = true,
                    description = 'Shares equipped Armor and Helmet tables with compatible Epic LUT squadmates. Both players need this version. Oversized appearances remain local.',
                }
                page.controls[#page.controls + 1] =
                    { id = 'sharing_status', type = 'text', label = 'Sharing: waiting for lobby' }
            end
        end
    end
    handle = api.register({ id = 'epic_direct_lut', name = 'Epic LUT', pages = pages })
    if m.configuration.attach then
        m.configuration.attach(api, handle, m.configuration_view, m.ui_menu and m.ui_menu.key_name)
    end
    for _, page in ipairs(api.mods[handle.id].pages) do
        for _, control in ipairs(page.controls) do
            if control.id == 'sharing_status' then
                edit.sharing_status_control = control
            end
        end
    end
    if pattern_editor then
        pattern_editor.attach(handle, api.mods[handle.id].controls)
    end
    api.mods[handle.id].tabs_top = true
    api.mods[handle.id].minimum_width = 1420
    api.mods[handle.id].minimum_height = 960
    frontend.default_mod_id = handle.id
    if armory_collection and api.mods[handle.id].controls.outfit_preset then
        api.mods[handle.id].controls.outfit_preset.on_delete_choice = function(index, label)
            local ok, status = armory_collection.remove_choice(index, label)
            sync_armory_export()
            return ok, status
        end
    end
    if palette_editor then
        palette_editor.pattern_editor = pattern_editor
        palette_editor.can_select_gear = function(kind)
            local ready = edit.loaded ~= nil or edit.imported ~= nil
            local control = api.mods[handle.id].controls['basic_' .. kind .. '_lut']
            control.disabled = not ready or control.choices[1] == 'Waiting for gear...'
            return not control.disabled
        end
        palette_editor.load_seen = function()
            return edit.load_seen or (preferences and preferences.load_seen and preferences.load_seen(false)) or false
        end
        palette_editor.attach(api, handle)
        if palette_editor.tools and palette_editor.tools.mount_preferences then
            palette_editor.tools.mount_preferences(preferences)
        end
        if m.basic_camo then
            for _, container in ipairs({ 'armor', 'helmet' }) do
                for color = 1, 4 do
                    local control = api.mods[handle.id].controls['basic_' .. container .. '_camo_color_' .. color]
                    if control then
                        control.can_open_picker = operations.basic_camo_picker_guard(control, container)
                    end
                end
            end
        end
        local quick = api.mods[handle.id].controls.quick_color
        local cell = api.mods[handle.id].controls.cell_color
        if quick and cell then
            quick.can_open_picker = function()
                local q = edit.quick_selection
                if not q or q.document ~= edit.loaded then
                    return false, 'Select an editable region first'
                end
                if edit.editor_target then
                    local current, why = pcall(operations.checked_editor_target, edit.editor_target)
                    if not current then
                        return false, why
                    end
                end
                return palette_editor.can_pick(q.row, q.column, 1)
            end
            quick.picker_begin = function()
                local allowed, why = quick.can_open_picker()
                if not allowed then
                    return false, why
                end
                local q = edit.quick_selection
                palette_editor.focus_cell(q.row, q.column)
                return cell.picker_begin(1)
            end
            quick.picker_preview = function(color)
                local allowed, why = quick.can_open_picker()
                assert(allowed, why)
                return cell.picker_preview(color, cell.picker_alpha())
            end
            quick.picker_end = function(commit)
                if cell.picker_end then
                    return cell.picker_end(commit)
                end
            end
            quick.picker_channel_enabled = function(channel, mode)
                return cell.picker_channel_enabled and cell.picker_channel_enabled(channel, mode)
            end
            quick.picker_commit = function(color)
                quick.picker_preview(color)
                return true
            end
        end
    end
    if m.armory_view then
        local armory = m.armory_view.new(import_state, palette_editor and palette_editor.preview)
        for _, page in ipairs(api.mods[handle.id].pages) do
            if page.id == 'armory' then
                page.render_layout = armory.draw
                page.on_wheel = armory.wheel
            end
        end
    end
    if m.outfit_presets then
        refresh_outfits()
    end
    local direct_page
    for _, page in ipairs(api.mods[handle.id].pages) do
        if page.id == 'direct' then
            direct_page = page
        end
    end
    if m.basic_view then
        local basic = m.basic_view.new(import_state, function(row, kind)
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
        end, m.control_help, operations.set_basic_camo_row)
        local page = api.mods[handle.id].pages[1]
        page.minimum_width = 1100
        page.minimum_height = m.basic_view.minimum_height or 1000
        page.render_layout = basic.draw
        page.on_wheel = basic.wheel
    end
    if api.mods[handle.id].controls.basic_preset then
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
    end
    if m.import_view then
        import_view = m.import_view.new(
            import_state,
            m.table_groups,
            operations.select_import_cell,
            m.ui_core,
            m.control_help,
            m.palette.value_tooltip
        )
        direct_page.render_layout = import_view.draw
        direct_page.on_wheel = import_view.wheel
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
    if operations.provenance_cache and not operations.provenance_cache.close() then
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
    if not restore() then
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
        provenance_unit_resource = operations.provenance_unit_resource,
        provenance_read = operations.provenance_read,
        ensure_binding_provenance = operations.ensure_binding_provenance,
        request_binding_sources = operations.request_binding_sources,
        binding_export_provider = operations.binding_export_provider,
        probe_binding_sources = operations.probe_binding_sources,
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
                        return m.avatar.resolve(memory, game, remote_read)
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
                        return out
                    end,
                    players = function()
                        return m.avatar.players(remote_read, game)
                    end,
                    resolve = function(player)
                        return m.avatar.resolve_remote(remote_read, game, player)
                    end,
                    targets = function(identity, appearance)
                        local targets, marks, seen = {}, {}, {}
                        for _, unit in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
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
                        return targets, table.concat(marks, ':')
                    end,
                    bindings = function()
                        return m.binding_session.new({
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
                                    return assert(operations.provenance_cache, 'Binding collision catalog unavailable').id_available(
                                        kind,
                                        id
                                    )
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
                                    return assert(operations.provenance_cache, 'Binding collision catalog unavailable').id_available(
                                        kind,
                                        id
                                    )
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
        if operations.provenance_cache then
            local cache = operations.provenance_cache
            local ticked, tick_error = pcall(cache.tick)
            if status == BINDING_EXPORT_PENDING then
                if not ticked then
                    message('Binding source cache update failed: ' .. tostring(tick_error))
                elseif cache.state == 'ready' then
                    message('Exact binding sources ready; retry Export')
                elseif cache.state == 'failed' or cache.state == 'stale' then
                    message(binding_export_unavailable(cache))
                end
            end
            local ok, why = pcall(operations.probe_binding_sources)
            if not ok and ctx.log then
                ctx.log('Binding provenance probe unavailable: ' .. tostring(why):sub(1, 512))
            end
        end
        if original_luts then
            local ok, why = pcall(original_luts.tick)
            if not ok then
                message('Original snapshot error: ' .. tostring(why))
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
                    if not frontend.basic_mode and edit.editor_target then
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
                    message('Could not index all tables: ' .. tostring(why))
                elseif coroutine.status(index_job) == 'dead' then
                    index_job = nil
                    local requested = operations.import_map_request
                    operations.import_map_request = nil
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
