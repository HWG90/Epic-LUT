-- DDS -> selected local live LUT. No equipment catalogue or file service.
local ffi = require('ffi')
local ctx, memory, native, game, frontend, preferences, handle, api, paths, palette_editor
local updates
local groups = {}
local bindings, gear_catalog
local edit = {} -- Current document, imported source, target and revision baseline.
local status = 'Load a DDS or ZIP, then refresh the live LUT list.'
local pending, palettes = nil, {}
local table_index
local operations = {}
local import_jobs
local setup, resume_job, resume_done
local original_luts
local defaults = {}
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
local editor_pending
local history
local outfits, armory_collection
local import_view
local source_tables, editor_tables = {}, {}
local import_ids = {}
local index_job
local refresh_needed, next_refresh = false, 0
local import_counter = package.loaded['epic.import.counter.v1'] or { value = 0 }
package.loaded['epic.import.counter.v1'] = import_counter
local small, big = ffi.new('uint8_t[96]'), ffi.new('uint8_t[1024]')
local retain = package.loaded['epic.direct_lut.retained.v1'] or { records = {}, bytes = 0, cache = {} }
package.loaded['epic.direct_lut.retained.v1'] = retain
local function read(a, n, b)
    return memory.read_into(ffi.cast('const uint8_t *', a), n, b)
end
local function binding(b)
    return m.engine.binding(read, b.material, m.engine.LUT_SLOT, small, big)
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
    local previous = handle and groups[handle.get('lut')]
    local previous_object = previous and previous.object
    local result = gear_catalog.refresh(bindings.owned, previous_object)
    groups, bindings.owned = result.groups, result.owned
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
    local bytes = m.file_io.read(path, m.dds.MAX_BYTES)
    local data, w, h = m.dds.decode(bytes)
    assert(w == 23, 'This simple editor accepts 23-column material LUT DDS files')
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
local function load(pick)
    assert(not pending, 'ZIP import is still pending')
    resume_done = true
    resume_job = nil
    local name
    if not pick then
        name = handle.get('file')
        assert(
            type(name) == 'string' and #name > 0 and #name <= 48 and name:match('^[%w _-]+$'),
            'Enter the filename without its extension'
        )
        if handle.get('format') == 1 then
            palettes = { paths.files .. '/' .. name .. '.dds' }
            palette_choices({ name })
            return load_dds(palettes[1])
        end
    end
    local _, kernel = m.native_import.verify_interface()
    assert(not paths.files:find('"', 1, true) and not paths.cache:find('"', 1, true), 'Invalid import path')
    local script = paths.cache .. '/import-zip.ps1'
    local f = assert(io.open(script, 'wb'))
    assert(f:write((m.zip_import_script:gsub('%x%x', function(pair)
        return string.char(tonumber(pair, 16))
    end))))
    assert(f:close())
    import_counter.value = import_counter.value + 1
    local pid = tonumber(kernel.epic_native_pid())
    local base = paths.cache .. '/zip-' .. pid .. '-' .. os.time() .. '-' .. import_counter.value
    local extension = handle.get('format') == 3 and '.rar' or '.zip'
    local input = pick and ' -Pick' or ' -Package "' .. paths.files .. '/' .. name .. extension .. '"'
    local args = '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'
        .. script
        .. '"'
        .. input
        .. ' -Navigate -Output "'
        .. base
        .. '" -Result "'
        .. base
        .. '.txt" -OwnerPID '
        .. pid
    local worker = m.native_import.launch_worker(args, paths.cache)
    pending = import_jobs.start({
        base = base,
        pick = pick,
        worker = worker,
        menu_visible = frontend.menu and frontend.menu.visible,
        menu_page = frontend.menu and frontend.menu.page,
    })
    return message(
        pick and 'Choose a DDS or ZIP in the Windows file picker.' or 'Extracting ZIP palettes. No Python is used.'
    )
end
local function cancel_import(retry)
    if not import_jobs.cancel(retry) then
        if retry then
            return load(true)
        end
        return message('No import is running.')
    end
    return message(
        retry and 'Closing the previous picker before retrying...' or 'Canceling import; current palettes stay active.'
    )
end
local function accept_import(text, job)
    return action(function()
        local result = m.import_protocol.result(text)
        if result.canceled then
            return message('File selection canceled; current palette retained.')
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
local function poll_job()
    local event = import_jobs.poll()
    pending = import_jobs.job
    if not event then
        return
    end
    if event.kind == 'result' then
        return accept_import(event.text, event.job)
    end
    if event.kind == 'retry' then
        return load(true)
    end
    return message(event.message)
end
local function apply_bindings(document, targets)
    return bindings.apply(document, targets)
end
local function initialize_editor_state()
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
        present = present,
        binding = binding,
        key = material_key,
    })
    bindings = m.binding_session.new({
        retain = retain,
        present = present,
        binding = binding,
        key = material_key,
        create_texture = function(width, height, data)
            return m.engine.create_texture(native, width, height, data, read, small)
        end,
        bind = function(b, object)
            m.engine.bind(native, b.material, m.engine.LUT_SLOT, object)
            native.commit(b.mesh)
        end,
    })
    basic_state = m.basic_state.new()
    basic_documents = basic_state.documents
    region_indicator = m.region_indicator.new({
        present = present,
        binding = binding,
        apply = apply_bindings,
        bind = function(b, object)
            m.engine.bind(native, b.material, m.engine.LUT_SLOT, object)
            native.commit(b.mesh)
        end,
    })
    stop_identification = region_indicator.stop
end
local function identify_region()
    assert(stop_identification(), 'Previous highlight restoration pending')
    local group = assert(groups[handle.get('lut')], 'Select a live LUT first')
    if frontend.basic_mode then
        assert(basic_selected, 'Click an Armor or Helmet color region first')
        group = assert(groups[basic_selected.group])
    end
    local row = handle.get('edit_row')
    local items = {}
    for _, b in ipairs(group.bindings) do
        if
            frontend.basic_mode and b[basic_selected.kind]
            or not frontend.basic_mode and (not identify_kind or b[identify_kind])
        then
            local source = b.document or (original_luts and original_luts.get(b.original))
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
    selected_kind = (selected_kind == 'armor' or selected_kind == 'helmet') and selected_kind or nil
    assert(stop_identification(), 'Highlight restoration pending')
    document = document or edit.loaded or edit.imported
    assert(document, 'Load a DDS first')
    resume_done = true
    resume_job = nil
    if #groups == 0 then
        refresh()
    end
    local scope = handle.get('scope')
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
                local kind = b.helmet and 'helmet' or 'armor'
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
                variant = { document = m.original_luts.preserve(document, original_luts.get(b.original)), targets = {} }
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
            defaults.armor = nil
        end
        if scope == 3 or scope == 4 then
            defaults.helmet = nil
        end
        return message(
            'Palette applied to ' .. count .. ' bindings with game-original emissives, including zero values.'
        )
    end
    count, texture = apply_bindings(document, targets)
    refresh_applied_palettes()
    if scope == 2 or scope == 4 then
        defaults.armor = texture
    end
    if scope == 3 or scope == 4 then
        defaults.helmet = texture
    end
    return message('Palette applied to ' .. count .. ' bindings. Other applied LUTs stay active.')
end
local function save_setup()
    local active = {}
    for _, b in ipairs(bindings.owned) do
        if present(b) and binding(b) == b.current and b.texture and b.current == b.texture.object then
            active[#active + 1] = b
        end
    end
    return message(
        'Saved '
            .. assert(setup, 'Setup storage unavailable').save(active, defaults)
            .. ' applied palettes. Armor and helmet will resume on later launches.'
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
local function apply_checked(document)
    if basic_selected and frontend.basic_mode then
        assert(handle.set('lut', basic_selected.group))
        assert(handle.set('scope', 1))
        return apply(document or edit.loaded)
    end
    local armor, helmet = handle.get('target_armor'), handle.get('target_helmet')
    assert(armor or helmet, 'Check Armor and/or Helmet first')
    assert(handle.set('scope', armor and (helmet and 4 or 2) or 3))
    return apply(assert(document or edit.imported, 'Import a LUT file first'))
end
local function populate_worn()
    refresh(true)
    local kind = 'armor'
    local helmet_ready = false
    for _, group in ipairs(groups) do
        for _, b in ipairs(group.bindings) do
            if b.helmet then
                local snapshot = b.document or (original_luts and original_luts.get(b.original))
                if snapshot then
                    helmet_ready = true
                end
            end
        end
    end
    local source
    for _, group in ipairs(groups) do
        for _, binding in ipairs(group.bindings) do
            if binding[kind] then
                if binding.document and binding.texture and binding.current == binding.texture.object then
                    source = binding.document
                elseif original_luts then
                    source = original_luts.get(binding.original)
                end
                if source then
                    break
                end
            end
        end
        if source then
            break
        end
    end
    if not source then
        return false
    end
    local data = ffi.new('float[?]', source.width * source.height * 4)
    ffi.copy(data, source.data, source.width * source.height * 16)
    edit.loaded = { data = data, width = source.width, height = source.height, source = 'Worn ' .. kind }
    edit.preview_document = edit.loaded
    edit.preview_revision = 0
    edit.quick_selection = nil
    basic_imported = edit.imported -- Do not replace this game snapshot with the last ZIP.
    if palette_editor then
        palette_editor.sync()
    end
    if not helmet_ready then
        if original_luts and original_luts.loaded then
            populate_request = nil
            message('Armor loaded. Helmet original LUT unavailable; both panels remain independent.')
            return true
        end
        return false
    end
    populate_request = nil
    message('Loaded worn Armor and Helmet colors. Click either panel to edit that target.')
    return true
end
local function resource_id(object)
    local original = original_luts and original_luts.get(object)
    local hash = original and original.resource
    return m.resource_ids.format(hash, handle.get('resource_format') == 2)
end
local function matching_plan()
    if not m.import_matches then
        return nil
    end
    local documents = {}
    for _, path in ipairs(palettes) do
        if source_tables[path] then
            documents[#documents + 1] = source_tables[path]
        end
    end
    return m.import_matches.plan(documents, groups, function(hash)
        return m.engine.texture_object(native, hash)
    end)
end
local function apply_matching()
    assert(not index_job, 'Import is still being indexed; wait for the LUT list')
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local plan = assert(matching_plan(), 'Matching unavailable')
    assert(plan.matched > 0, 'No imported resource IDs match the currently worn gear')
    local batches = {}
    for _, p in ipairs(plan.plans) do
        local document = p.document
        if handle.get('preserve_emissives') then
            assert(original_luts, 'Original snapshot reader unavailable')
            document = m.original_luts.preserve(document, original_luts.get(p.targets[1].original))
        end
        for _, b in ipairs(p.targets) do
            assert(present(b) and binding(b) == b.current, 'Gear bindings changed; load current gear again')
        end
        batches[#batches + 1] = { document = document, targets = p.targets }
    end
    resume_done = true
    resume_job = nil
    local bindings = 0
    for _, p in ipairs(batches) do
        bindings = bindings + apply_bindings(p.document, p.targets)
        for _, b in ipairs(p.targets) do
            basic_documents[(b.helmet and 'helmet' or 'armor') .. ':' .. tostring(b.original)] =
                m.basic_state.clone(p.document, p.document.source)
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
local function import_state()
    local previews = { armor = {}, helmet = {} }
    for index, group in ipairs(groups) do
        local seen = { armor = {}, helmet = {} }
        for _, b in ipairs(group.bindings) do
            local kind = b.helmet and 'helmet' or 'armor'
            local texture = b.texture
            if texture and b.current == texture.object and not seen[kind][texture] then
                seen[kind][texture] = true
                local document = b.document or texture
                previews[kind][#previews[kind] + 1] = {
                    name = (kind == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. (#previews[kind] + 1),
                    index = index,
                    width = document.width,
                    height = document.height,
                    data = document.data,
                    revision = document.revision,
                    edited = (document.revision or 0) > 0,
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
    if m.basic_view then
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            local choices, indices, details = {}, {}, {}
            for index, group in ipairs(groups) do
                for _, b in ipairs(group.bindings) do
                    if b[kind] then
                        choices[#choices + 1] = 'LUT ' .. (#choices + 1)
                        details[#choices] = resource_id(group.object)
                        indices[#indices + 1] = index
                        break
                    end
                end
            end
            local control = api.mods[handle.id].controls['basic_' .. kind .. '_lut']
            if control then
                control.choices = #choices > 0 and choices or { 'Waiting for gear...' }
                control.choice_details = details
                control.dropdown_width = 280
            end
            local index = indices[handle.get('basic_' .. kind .. '_lut')]
            local group = index and groups[index]
            local doc, key
            if group then
                for _, b in ipairs(group.bindings) do
                    if b[kind] then
                        key = kind .. ':' .. tostring(b.original)
                        doc = basic_documents[key]
                        if not doc then
                            local source = b.document or (original_luts and original_luts.get(b.original))
                            doc = basic_state.get(key, source, 'Worn ' .. kind)
                        end
                        break
                    end
                end
            end
            raw.basic[kind] = {
                document = doc,
                key = key,
                group = index,
                resource = group and resource_id(group.object) or 'unavailable',
                unavailable = not doc and original_luts and original_luts.loaded and key ~= nil,
            }
            if doc then
                previews[kind] = {
                    {
                        name = (kind == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. tostring(
                            handle.get('basic_' .. kind .. '_lut')
                        ),
                        resource = resource_id(group.object),
                        index = index,
                        width = doc.width,
                        height = doc.height,
                        data = doc.data,
                        revision = doc.revision,
                    },
                }
            end
            if raw.basic[kind].unavailable and not basic_missing_reported[key] then
                basic_missing_reported[key] = true
                if ctx.log then
                    ctx.log(
                        'BASIC_SNAPSHOT_MISSING target='
                            .. kind
                            .. ' group='
                            .. tostring(index)
                            .. ' original_object='
                            .. tostring(group.object)
                            .. ' reader='
                            .. tostring(original_luts.status)
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
    -- Show All must include game snapshots, not just palettes already applied by Epic LUT.
    for _, kind in ipairs({ 'armor', 'helmet' }) do
        local entries = {}
        for index, group in ipairs(groups) do
            for _, b in ipairs(group.bindings) do
                if b[kind] then
                    local doc = basic_documents[kind .. ':' .. tostring(b.original)]
                        or b.document
                        or (original_luts and original_luts.get(b.original))
                    if doc then
                        entries[#entries + 1] = {
                            name = (kind == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. (#entries + 1),
                            index = index,
                            width = doc.width,
                            height = doc.height,
                            data = doc.data,
                            revision = doc.revision,
                        }
                        break
                    end
                end
            end
        end
        raw[kind] = entries
    end
    local phase = pending and pending.phase or ''
    local labels = {
        starting = 'Opening file picker...',
        picker = 'Waiting for file selection...',
        reading = 'Reading archive...',
        extracting = 'Extracting LUTs...',
    }
    local dirty = edit.loaded
            and edit.loaded.original
            and ffi.string(edit.loaded.data, edit.loaded.width * edit.loaded.height * 16) ~= ffi.string(
                edit.loaded.original,
                edit.loaded.width * edit.loaded.height * 16
            )
        or false
    return {
        editor = edit.loaded,
        dirty = dirty,
        raw = raw,
        palette_count = #palettes,
        palette_index = handle.get('palette'),
        armor_lut = handle.get('basic_armor_lut'),
        helmet_lut = handle.get('basic_helmet_lut'),
        tables = tables,
        armor = previews.armor,
        helmet = previews.helmet,
        loaded = edit.imported,
        import_description = m.import_description,
        import_detail = pending and pending.detail,
        status = populate_request
                and ('Loading worn colors: ' .. (original_luts and original_luts.status or 'snapshot unavailable'))
            or original_luts and not original_luts.loaded and original_luts.status
            or status,
        busy = pending ~= nil or index_job ~= nil,
        phase = index_job and 'Comparing imported tables...'
            or pending and pending.canceling and 'Canceling...'
            or labels[phase]
            or phase,
        progress = pending and pending.percent or 0,
        waiting = pending and (pending.phase == 'picker' or pending.phase == 'starting'),
        time = memory.time and memory.time() or os.clock(),
        elapsed = pending and (os.time() - pending.started) or 0,
        armor_checked = handle.get('target_armor'),
        helmet_checked = handle.get('target_helmet'),
        palette_name = handle.get('palette_name'),
        preserve_emissives = handle.get('preserve_emissives'),
    }
end
local function load_editor_target(kind)
    refresh(true)
    local panel = import_state().raw.basic[kind]
    local source
    local group = panel and panel.group and groups[panel.group]
    if group then
        for _, b in ipairs(group.bindings) do
            if b[kind] then
                source = b.document or (original_luts and original_luts.get(b.original))
                if source then
                    break
                end
            end
        end
    end
    if not source then
        return false
    end
    edit.loaded = m.basic_state.clone(
        source,
        (kind == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. handle.get('basic_' .. kind .. '_lut') .. ' (worn)'
    )
    edit.loaded.resource = resource_id(group.object)
    edit.loaded.resource_object = group.object
    edit.editor_target = { kind = kind, group = panel.group, object = group.object }
    identify_kind = kind
    basic_selected = nil
    basic_imported = edit.imported
    edit.quick_selection = nil
    live_select_suppressed = true
    local ok, why = handle.set('lut', panel.group)
    live_select_suppressed = false
    assert(ok, why)
    edit.preview_document = edit.loaded
    edit.preview_revision = 0
    editor_pending = nil
    if palette_editor then
        palette_editor.sync()
    end
    return message('Editor populated from ' .. loaded.source .. '. Edits affect this LUT only.')
end
local function apply_editor_target(kind, all)
    assert(edit.loaded, 'Load current colors or send an imported LUT to the editor first')
    if all then
        assert(handle.set('scope', kind == 'armor' and 2 or kind == 'helmet' and 3 or 4))
        return apply(edit.loaded, kind)
    end
    local p = import_state().raw.basic[kind]
    assert(p and p.group, 'Selected LUT unavailable')
    live_select_suppressed = true
    local ok, why = handle.set('lut', p.group)
    live_select_suppressed = false
    assert(ok, why)
    assert(handle.set('scope', 1))
    edit.editor_target = { kind = kind, group = p.group, object = groups[p.group].object }
    return apply(edit.loaded, kind)
end
local function apply_import_to(kind)
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local panel = import_state().raw.basic[kind]
    assert(panel and panel.group, 'Select a ' .. kind .. ' LUT first')
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
    edit.loaded = d
    basic_selected = { kind = destination, key = target.key, group = target.group }
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
    defaults = {}
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
        local valid, plan = pcall(setup.read)
        if not valid then
            resume_done = true
            return message('Saved setup is invalid: ' .. tostring(plan))
        end
        if not next(plan) then
            resume_done = true
            return
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
                    assert(w == 23, 'Saved palette is not a material LUT')
                    total = total + w * h * 16
                    assert(total <= 8 * 1024 * 1024, 'Saved palette budget exceeded')
                    documents[file] = { data = data, width = w, height = h }
                    coroutine.yield()
                end
            end
            local files = {}
            for file in pairs(documents) do
                files[#files + 1] = file
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
            palette_choices(labels)
            if not edit.loaded then
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
                    local matched = 0
                    by_file = {}
                    if scanned then
                        for _, group in ipairs(groups) do
                            for _, b in ipairs(group.bindings) do
                                if plan[b.save_key] then
                                    matched = matched + 1
                                end
                                local file = plan[b.save_key] or plan[b.armor and 'armor-all' or 'helmet-all']
                                if file then
                                    by_file[file] = by_file[file] or {}
                                    table.insert(by_file[file], b)
                                end
                            end
                        end
                    end
                    if scanned and (matched >= expected or os.time() - began >= 10) then
                        break
                    end
                    assert(os.time() - began < 15, 'Local LUTs are not ready for the saved setup')
                    coroutine.yield()
                end
            until false
            local applied = 0
            for file, targets in pairs(by_file) do
                local count, texture = apply_bindings(documents[file], targets)
                applied = applied + count
                if file == plan['armor-all'] then
                    defaults.armor = texture
                end
                if file == plan['helmet-all'] then
                    defaults.helmet = texture
                end
                if not edit.loaded then
                    edit.loaded = documents[file]
                    if palette_editor then
                        palette_editor.sync()
                    end
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
        basic = {},
        editor_tables = {},
        defaults = {},
        palettes = {},
        selected = basic_selected,
        editor_target = edit.editor_target,
        imported = edit.imported,
        scope = handle.get('scope'),
        palette_index = handle.get('palette'),
    }
    local copier = m.basic_state.copier()
    local document = copier.copy
    snapshot.loaded = document(edit.loaded)
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
    for _, b in ipairs(bindings.owned) do
        snapshot.owned[#snapshot.owned + 1] = {
            binding = b,
            key = material_key(b),
            current = b.current,
            texture = b.texture,
            document = document(b.document),
        }
        signature[#signature + 1] = material_key(b) .. ':' .. tostring(b.current)
    end
    for k, v in pairs(defaults) do
        snapshot.defaults[k] = v
    end
    for i, v in ipairs(palettes) do
        snapshot.palettes[i] = v
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
    snapshot.basic = {}
    snapshot.editor_tables = {}
    snapshot.defaults = {}
    snapshot.palettes = {}
    snapshot.owned = {}
    for k, d in pairs(saved.basic) do
        snapshot.basic[k] = clone(d)
    end
    for k, d in pairs(saved.editor_tables) do
        snapshot.editor_tables[k] = clone(d)
    end
    for k, v in pairs(saved.defaults) do
        snapshot.defaults[k] = v
    end
    for k, v in pairs(saved.palettes) do
        snapshot.palettes[k] = v
    end
    for i, e in ipairs(saved.owned) do
        local copy = {}
        for k, v in pairs(e) do
            copy[k] = v
        end
        copy.document = clone(e.document)
        snapshot.owned[i] = copy
    end
    assert(stop_identification(), 'Highlight restoration pending')
    local desired, expected_bindings = {}, {}
    for _, entry in ipairs(snapshot.owned) do
        desired[entry.key] = entry
    end
    for _, entry in ipairs(expected.owned) do
        expected_bindings[entry.key] = entry
    end
    local plans = {}
    for _, b in ipairs(bindings.owned) do
        local key = material_key(b)
        local e = expected_bindings[key]
        assert(e and present(b) and binding(b) == e.current, 'Gear bindings changed; cannot safely undo this action')
        local d = desired[key]
        plans[#plans + 1] = { binding = b, old = b.current, object = d and d.current or b.original, desired = d }
    end
    for key, d in pairs(desired) do
        if not expected_bindings[key] then
            local b = d.binding
            assert(present(b) and binding(b) == b.original, 'Gear changed; cannot safely redo this action')
            plans[#plans + 1] = { binding = b, old = b.original, object = d.current, desired = d }
        end
    end
    local changed = {}
    local ok, why = pcall(function()
        for _, plan in ipairs(plans) do
            changed[#changed + 1] = plan
            m.engine.bind(native, plan.binding.material, m.engine.LUT_SLOT, plan.object)
            native.commit(plan.binding.mesh)
            assert(binding(plan.binding) == plan.object)
        end
    end)
    if not ok then
        for i = #changed, 1, -1 do
            local p = changed[i]
            if present(p.binding) and binding(p.binding) == p.object then
                pcall(function()
                    m.engine.bind(native, p.binding.material, m.engine.LUT_SLOT, p.old)
                    native.commit(p.binding.mesh)
                end)
            end
        end
        error(why, 0)
    end
    bindings.owned = {}
    for _, plan in ipairs(plans) do
        local b, d = plan.binding, plan.desired
        b.current = plan.object
        b.previous = nil
        b.texture = d and d.texture or nil
        b.document = d and d.document or nil
        if d then
            bindings.owned[#bindings.owned + 1] = b
        end
    end
    edit.imported = snapshot.imported
    edit.loaded = snapshot.loaded
    defaults = snapshot.defaults
    palettes = snapshot.palettes
    editor_tables = snapshot.editor_tables
    index_job = nil
    editor_pending = nil
    populate_request = nil
    basic_state.clear()
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
        if #bindings.owned > 0 then
            save_setup()
        else
            setup.clear()
        end
    end
    return true
end
local function refresh_outfits()
    armory_collection.refresh()
end
local function keep_outfit(name, save_kind)
    assert(outfits, 'Outfit storage unavailable')
    refresh(true)
    local entries, seen = {}, {}
    for _, group in ipairs(groups) do
        for _, b in ipairs(group.bindings) do
            local kind = b.helmet and 'helmet' or 'armor'
            local key = kind .. ':' .. b.save_key
            if not seen[key] and (not save_kind or save_kind == 'both' or save_kind == kind) then
                local source = b.document or (original_luts and original_luts.get(b.original))
                assert(source, 'Current ' .. kind .. ' LUT unavailable; load current gear before saving')
                entries[#entries + 1] = { kind = kind, key = b.save_key, document = source }
                seen[key] = true
            end
        end
    end
    armory_collection.save(name, entries)
    if frontend.menu then
        frontend.menu.outfit_dialog = nil
        frontend.menu.text_edit = nil
    end
    return message(
        'Saved '
            .. name
            .. ' with '
            .. (save_kind == 'armor' and 'Armor only' or save_kind == 'helmet' and 'Helmet only' or 'Armor and Helmet')
            .. ' LUTs in The Armory.'
    )
end
local function apply_outfit(kind)
    local selected_outfit = assert(armory_collection and armory_collection.selected, 'Choose an outfit preset first')
    assert(stop_identification(), 'Highlight restoration pending')
    refresh(true)
    local exact = {}
    local fallback
    for _, entry in ipairs(selected_outfit.entries) do
        if entry.kind == kind then
            exact[entry.key] = entry.document
            fallback = fallback or entry.document
        end
    end
    assert(fallback, 'This preset has no ' .. kind .. ' palette')
    local batches = {}
    for _, group in ipairs(groups) do
        for _, b in ipairs(group.bindings) do
            if b[kind] then
                assert(present(b) and binding(b) == b.current, 'Gear changed; load current gear again')
                local d = exact[b.save_key] or fallback
                batches[d] = batches[d] or {}
                table.insert(batches[d], b)
            end
        end
    end
    resume_done = true
    resume_job = nil
    local count = 0
    for d, targets in pairs(batches) do
        count = count + apply_bindings(d, targets)
        for _, b in ipairs(targets) do
            basic_documents[kind .. ':' .. tostring(b.original)] = m.basic_state.clone(d, d.source)
        end
    end
    assert(count > 0, 'No worn gear bindings available for this preset')
    edit.remember_application = true
    save_setup()
    return message('Applied ' .. selected_outfit.name .. ' ' .. kind .. ' palettes to ' .. count .. ' bindings.')
end
local function select_outfit(index)
    if armory_collection then
        armory_collection.select(index)
    else
        assert(index == 1, 'Armory collection unavailable')
    end
end
local function manage_outfit(mode)
    return assert(armory_collection, 'Armory collection unavailable').manage(
        mode,
        assert(frontend.menu),
        api.mods[handle.id],
        message
    )
end
local function paint_quick(q, hex)
    return action(function()
        if palette_editor then
            palette_editor.paint_rgb(q.row, q.column, hex)
        else
            local r, g, b = m.palette.rgb(hex)
            local at = ((q.row - 1) * edit.loaded.width + q.column - 1) * 4
            edit.loaded.data[at], edit.loaded.data[at + 1], edit.loaded.data[at + 2] = r, g, b
            edit.loaded.revision = (edit.loaded.revision or 0) + 1
        end
        if edit.editor_target then
            assert(handle.set('lut', edit.editor_target.group))
            assert(handle.set('scope', 1))
            apply(edit.loaded, edit.editor_target.kind)
            edit.preview_document = edit.loaded
            edit.preview_revision = edit.loaded.revision or 0
        end
        return true
    end)
end
local function select_import_cell(entry, row, column, identify, kind)
    if entry.index then
        basic_selected = nil
        edit.editor_target =
            { kind = kind, group = entry.index, object = groups[entry.index] and groups[entry.index].object }
    end
    if identify or entry.index then
        identify_kind = (kind == 'armor' or kind == 'helmet') and kind or nil
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
    edit.quick_selection = { row = row, column = column }
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
    edit.quick_selection = { row = row, column = column }
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
        browse_activate = function()
            return action(function()
                return load(true)
            end)
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
            return action(function()
                editor_pending = { kind = 'armor', began = os.time() }
                return load_editor_target('armor')
            end)
        end,
        editor_load_helmet_activate = function()
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
            return action(function()
                if original_luts and original_luts.retry then
                    original_luts.retry()
                end
                populate_request = os.time()
                if not populate_worn() then
                    return message('Reading worn gear colors; editor will populate when ready.')
                end
                return true
            end)
        end,
        basic_preset_change = function(index)
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
                basic_names = {}
                local choices = { 'New preset...' }
                for _, file in ipairs(m.windows.files(paths.presets, 'palette-*.dds')) do
                    local value = file:match('^palette%-([%w _-]+)%.dds$')
                    if value then
                        basic_names[#basic_names + 1] = value
                        choices[#choices + 1] = value
                    end
                end
                api.mods[handle.id].controls.basic_preset.choices = choices
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
                        source = basic_documents[(b.helmet and 'helmet' or 'armor') .. ':' .. tostring(b.original)]
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
                mod = api.mods[handle.id],
                control = api.mods[handle.id].controls.outfit_name,
                on_save = keep_outfit,
            }
            return message('Keep this Armor and Helmet setup as a named preset?')
        end,
        restore_activate = function()
            return action(function()
                local selected = basic_selected
                remove_lut()
                basic_state.clear()
                basic_missing_reported = {}
                edit.quick_selection = nil
                edit.loaded = nil
                refresh(true)
                local panels = import_state().raw.basic
                if frontend.basic_mode and selected and panels[selected.kind] then
                    local p = panels[selected.kind]
                    edit.loaded = p.document
                    basic_selected = p.document and { kind = selected.kind, key = p.key, group = p.group } or nil
                else
                    basic_selected = nil
                    local group = groups[handle.get('lut')]
                    if group then
                        for _, b in ipairs(group.bindings) do
                            local source = original_luts and original_luts.get(b.original)
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
    if m.basic_view then
        table.insert(pages, 1, { id = 'basic', name = 'Basic', require_confirmation = false, controls = {} })
    end
    if m.armory_view then
        table.insert(pages, #pages, { id = 'armory', name = 'The Armory', require_confirmation = false, controls = {} })
    end
    handle = api.register({ id = 'epic_direct_lut', name = 'Epic LUT', pages = pages })
    api.mods[handle.id].tabs_top = true
    api.mods[handle.id].minimum_width = 1420
    api.mods[handle.id].minimum_height = 960
    frontend.default_mod_id = handle.id
    if palette_editor then
        palette_editor.attach(api, handle)
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
                basic_selected = { kind = kind, key = panel.key, group = panel.group }
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
        end, m.control_help)
        local page = api.mods[handle.id].pages[1]
        page.minimum_width = 1100
        page.minimum_height = 780
        page.render_layout = basic.draw
        page.on_wheel = basic.wheel
        basic_names = {}
        local choices = { 'New preset...' }
        for _, file in ipairs(m.windows.files(paths.presets, 'palette-*.dds')) do
            local name = file:match('^palette%-([%w _-]+)%.dds$')
            if name then
                basic_names[#basic_names + 1] = name
                choices[#choices + 1] = name
            end
        end
        api.mods[handle.id].controls.basic_preset.choices = choices
    end
    if m.import_view then
        import_view =
            m.import_view.new(import_state, m.table_groups, operations.select_import_cell, m.ui_core, m.control_help)
        direct_page.render_layout = import_view.draw
        direct_page.on_wheel = import_view.wheel
    end
    groups = {}
end
local function close()
    if stop_identification and not stop_identification() then
        return false
    end
    if edit.remember_application and setup then
        local ok, why = pcall(save_setup)
        if not ok then
            message('Could not remember applied preset: ' .. tostring(why))
        end
        edit.remember_application = false
    end
    if import_jobs and not import_jobs.close() then
        pending = import_jobs.job
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
    if handle then
        handle.unregister()
        handle = nil
    end
    if preferences then
        preferences.close()
    end
    return not frontend or frontend.close()
end
return {
    name = 'Epic LUT',
    author = 'Goose',
    on_enable = function(context)
        ctx = context
        paths = m.paths.new(m)
        operations.preset_files = m.lut_files.new(paths.presets, { dds = m.dds, read = m.file_io.read })
        operations.export_files = m.lut_files.new(paths.files, { dds = m.dds, read = m.file_io.read })
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
        import_jobs = m.import_job.new(m.import_protocol)
        table_index = m.table_index.new({ read = m.file_io.read, decode = m.dds.decode, max_bytes = m.dds.MAX_BYTES })
        operations.apply_matching = apply_matching
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
        end
        m.format_resource_id = resource_id
        if m.action_history then
            history = m.action_history.new(capture_action, restore_action)
        end
        preferences = m.preferences.new(paths.storage)
        frontend = m.frontend.new(m, ctx)
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
                return objects
            end)
            original_luts.start()
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
                        assert(name:match('^[%w _-]+$') and #name <= 48 and #name > 0, 'Invalid DDS filename')
                        operations.export_files.save(name, edit.loaded)
                        return message('Saved ' .. name .. '.dds in Epic LUT/files')
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
                end
            )
        end
        ctx.on_cleanup(close)
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
        if original_luts then
            local ok, why = pcall(original_luts.tick)
            if not ok then
                message('Original snapshot error: ' .. tostring(why))
            end
        end
        frontend.tick(dt)
        local current = frontend.resolve()
        if current then
            register(current)
            if updates and api.mods[handle.id].controls.update_status then
                api.mods[handle.id].controls.update_status.label = updates.status
            end
            if updates and not updates.started and preferences.auto_updates and preferences.auto_updates() then
                pcall(updates.check)
            end
            if setup then
                action(resume_setup)
            end
            if refresh_needed then
                local now = memory.time and memory.time() or os.clock()
                if now >= next_refresh then
                    next_refresh = now + 0.25
                    refresh_needed = not pcall(refresh, true)
                end
            end
            local import_ok, import_error = pcall(poll_job)
            if not import_ok then
                if import_jobs then
                    pcall(import_jobs.abort)
                    pending = import_jobs.job
                end
                message('Import stopped safely; editor remains available: ' .. tostring(import_error))
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
            if populate_request and os.time() >= populate_next then
                populate_next = os.time() + 1
                local ok, why = pcall(populate_worn)
                if not ok or (populate_request and os.time() - populate_request > 130) then
                    populate_request = nil
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
            elseif edit.loaded and (edit.loaded.revision or 0) ~= edit.preview_revision then
                edit.preview_revision = edit.loaded.revision or 0
                if not frontend.basic_mode and edit.editor_target then
                    action(function()
                        assert(
                            groups[edit.editor_target.group]
                                and groups[edit.editor_target.group].object == edit.editor_target.object,
                            'Worn gear changed; populate the editor again before editing'
                        )
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
            if index_job then
                local ok, why = coroutine.resume(index_job)
                if not ok then
                    index_job = nil
                    message('Could not index all tables: ' .. tostring(why))
                elseif coroutine.status(index_job) == 'dead' then
                    index_job = nil
                end
            end
            for _, control in ipairs(api.mods[handle.id].pages[1].controls) do
                if control.id == 'status' then
                    control.label = status
                end
            end
        end
    end,
    on_disable = close,
    on_cleanup_poll = close,
}
