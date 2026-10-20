-- Current view data and registered choice presentation.
-- Reads one synchronous frame; host callbacks own suppressed camo changes.
local buffers = m and m.float_buffer or require('src.core.float_buffer')
local S = {}

function S.new(modules, host)
    local self = {}
    function self.info()
        local frame = host.frame()
        local groups, palettes = frame.groups, frame.palettes
        local editor_tables, source_tables = frame.editor_tables, frame.source_tables
        local basic_documents, basic_state = frame.basic_documents, frame.basic_state
        local original_luts = frame.original_luts
        local pending, index_job = frame.pending, frame.index_job
        local populate_request, status = frame.populate_request, frame.status
        local basic_missing_reported = host.missing_reports()
        local controls, get = host.ui()
        local palette_ready = frame.loaded ~= nil or frame.imported ~= nil
        local previews = { armor = {}, helmet = {}, cape = {} }
        for index, group in ipairs(groups) do
            local seen = { armor = {}, helmet = {}, cape = {} }
            for _, b in ipairs(group.bindings) do
                local kind = modules.gear_catalog.kind(b)
                local texture = b.texture
                if texture and b.current == texture.object and not seen[kind][texture] then
                    seen[kind][texture] = true
                    local document = b.document or texture
                    previews[kind][#previews[kind] + 1] = {
                        name = modules.gear_catalog.label(kind) .. ' LUT ' .. (#previews[kind] + 1),
                        index = index,
                        width = document.width,
                        height = document.height,
                        data = document.data,
                        revision = document.revision,
                        edited = (document.revision or 0) > 0,
                        target = host.target(kind, index),
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
            outfit = frame.outfit,
            matching = host.matching_plan(),
        }
        local choice_maps = {}
        if modules.basic_enabled then
            for _, container in ipairs({ 'armor', 'helmet' }) do
                local entries, choices, details, hashes, help = host.choices(container), {}, {}, {}, {}
                choice_maps[container] = entries
                for index, entry in ipairs(entries) do
                    choices[index], details[index] = entry.label, host.resource_id(groups[entry.group].object)
                    local original = original_luts and original_luts.get(groups[entry.group].object)
                    hashes[index] = original and original.resource
                    help[index] =
                        modules.resource_ids.describe(hashes[index], get('resource_format') == 2, modules.sdk_catalog)
                end
                local control = controls['basic_' .. container .. '_lut']
                control.choices = #choices > 0 and choices or { 'Waiting for gear...' }
                control.choice_details, control.choice_targets = details, entries
                control.choice_hashes, control.choice_help = hashes, help
                control.dropdown_width = 280
                control.disabled = not palette_ready or #choices == 0
                local selected = entries[get('basic_' .. container .. '_lut')]
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
                    resource = group and host.resource_id(group.object) or 'unavailable',
                    unavailable = not doc and original_luts and original_luts.loaded and key ~= nil,
                }
                local proof = host.appearance_proof()
                local camo_rows, camo_count = basic_state.camo_rows(
                    key,
                    doc,
                    raw.basic[container].kind,
                    proof and proof[raw.basic[container].kind]
                )
                raw.basic[container].camo_rows, raw.basic[container].camo_count = camo_rows, camo_count
                if modules.basic_camo then
                    local prefix = 'basic_' .. container .. '_camo'
                    local values = { [prefix] = modules.basic_camo.selection(doc, container, camo_rows) }
                    if modules.basic_camo.colorway_selection then
                        values[prefix .. '_colorway'] = modules.basic_camo.colorway_selection(doc, container, camo_rows)
                        for color = 1, 4 do
                            values[prefix .. '_color_' .. color] = modules.basic_camo.color(doc, color, camo_rows)
                        end
                    end
                    for id, value in pairs(values) do
                        local camo = controls[id]
                        if camo then
                            local disabled = pending ~= nil
                                or not modules.basic_camo.available(doc)
                                or not group
                                or camo_count == 0
                            if id == prefix then
                                camo.choice_pattern_previews = frame.camo_thumbnails
                            end
                            host.sync_camo(camo, value, disabled)
                        end
                    end
                end
                if doc then
                    previews[container] = {
                        {
                            name = selected.kind == 'cape' and selected.label
                                or modules.gear_catalog.label(selected.kind) .. ' LUT ' .. selected.ordinal,
                            kind = selected.kind,
                            resource = host.resource_id(group.object),
                            index = selected.group,
                            width = doc.width,
                            height = doc.height,
                            data = doc.data,
                            revision = doc.revision,
                            target = host.target(selected.kind, selected.group),
                        },
                    }
                end
                if raw.basic[container].unavailable and not basic_missing_reported[key] then
                    basic_missing_reported[key] = true
                    if host.log then
                        host.log(
                            'BASIC_SNAPSHOT_MISSING target='
                                .. raw.basic[container].kind
                                .. ' original_object='
                                .. tostring(group.object)
                        )
                    end
                end
            end
        end
        if modules.table_groups then
            tables = modules.table_groups.collapse(tables)
            previews.armor = modules.table_groups.collapse(previews.armor)
            previews.helmet = modules.table_groups.collapse(previews.helmet)
        end
        -- The Import workspace lists every loaded table, including game snapshots.
        raw.pending_luts = {}
        for _, container in ipairs({ 'armor', 'helmet' }) do
            local entries, choices = {}, choice_maps[container] or host.choices(container)
            for choice, entry in ipairs(choices) do
                local b, group = entry.binding, groups[entry.group]
                local doc = basic_documents[entry.key]
                    or b.document
                    or (original_luts and original_luts.get(b.original))
                if doc then
                    entries[#entries + 1] = {
                        name = entry.kind == 'cape' and entry.label
                            or modules.gear_catalog.label(entry.kind)
                                .. ' LUT '
                                .. entry.ordinal
                                .. (b.resource_name and (' / ' .. b.resource_name) or ''),
                        kind = entry.kind,
                        resource = host.resource_id(group.object),
                        lut = choice,
                        selected = choice == get('basic_' .. container .. '_lut'),
                        index = entry.group,
                        width = doc.width,
                        height = doc.height,
                        data = doc.data,
                        revision = doc.revision,
                        target = host.target(entry.kind, entry.group),
                    }
                end
            end
            raw[container], raw.pending_luts[container] = entries, #choices - #entries
        end
        local picker = host.picker_info()
        local dirty = frame.loaded
                and frame.loaded.original
                and buffers.bytes(frame.loaded.data, frame.loaded.width * frame.loaded.height * 4) ~= (frame.loaded.saved_pixels or buffers.bytes(
                    frame.loaded.original,
                    frame.loaded.width * frame.loaded.height * 4
                ))
            or false
        return {
            editor = frame.loaded,
            palette_ready = palette_ready,
            load_seen = frame.load_seen,
            dirty = dirty,
            export_name = get('save_name'),
            armory_export_name = get('armory_export_name'),
            armory_export_format = get('armory_export_format'),
            armory_query = controls.armory_search and get('armory_search'),
            raw = raw,
            palette_count = #palettes,
            palette_index = get('palette'),
            armor_lut = get('basic_armor_lut'),
            helmet_lut = get('basic_helmet_lut'),
            tables = tables,
            armor = previews.armor,
            helmet = previews.helmet,
            cape_available = #modules.gear_catalog.targets(groups, 5, nil, 'cape') > 0,
            armory_cape_available = host.cape_available(frame.outfit),
            armory_targets = {
                armor = get('outfit_target_armor'),
                helmet = get('outfit_target_helmet'),
                cape = get('outfit_target_cape'),
                weapon = controls.outfit_target_weapon and get('outfit_target_weapon') or false,
            },
            loaded = frame.imported,
            import_description = frame.import_description,
            import_detail = picker.detail,
            status = populate_request
                    and ('Loading worn colors: ' .. (original_luts and original_luts.status or 'snapshot unavailable'))
                or original_luts and not original_luts.loaded and original_luts.status
                or status,
            busy = picker.busy or index_job ~= nil,
            phase = index_job and 'Comparing imported tables...' or picker.phase,
            progress = picker.progress,
            waiting = picker.waiting,
            time = host.time(),
            elapsed = picker.elapsed,
            armor_checked = get('target_armor'),
            helmet_checked = get('target_helmet'),
            palette_name = get('palette_name'),
            preserve_emissives = get('preserve_emissives'),
        }
    end
    return self
end

return S
