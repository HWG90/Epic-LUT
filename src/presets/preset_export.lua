-- Export stored Armory bytes, never the currently worn/editor table.
local E = {
    MAX_BINDINGS = 4096,
    MAX_MANIFEST_BYTES = 2 * 1024 * 1024,
    MAX_PAYLOAD_BYTES = 8 * 1024 * 1024,
    formats = {
        'Shareable Preset ZIP',
        'Selected LUT Patch ZIP',
        'Entire Preset Patch ZIP',
        'Raw DDS (selected LUT)',
        'Raw DDS (entire preset)',
    },
}
local kind_labels = { armor = 'Armor', helmet = 'Helmet', cape = 'Cape' }
local function collection(preset, include_capes, include_patterns)
    local entries = assert(preset and preset.entries, 'Choose a saved Armory preset first')
    if include_capes ~= false and include_patterns ~= false then
        return entries
    end
    local selected = {}
    for _, entry in ipairs(entries) do
        local pattern = entry.document.width == 3 and entry.document.height == 1
        if (include_capes ~= false or entry.kind ~= 'cape') and (include_patterns ~= false or not pattern) then
            selected[#selected + 1] = entry
        end
    end
    assert(
        #selected > 0,
        'No LUTs remain to export. Enable '
            .. (include_capes == false and 'Include Capes in Armor Exports' or 'Include Patterns in Exports')
            .. (include_capes == false and include_patterns == false and ' or Include Patterns in Exports' or '')
            .. ', or export a selected LUT.'
    )
    return selected
end
function E.lut_choices(preset, lookup)
    local choices, counts = {}, {}
    for _, entry in ipairs(preset and preset.entries or {}) do
        local pattern = entry.document.width == 3
        local kind = assert(kind_labels[entry.kind], 'Invalid saved LUT gear kind')
        local label = kind .. (pattern and ' Pattern LUT ' or ' LUT ')
        counts[label] = (counts[label] or 0) + 1
        choices[#choices + 1] = (lookup and entry.original and lookup(entry.original.resource) or (label .. counts[label]))
            .. (entry.original and (' [' .. entry.original.resource .. ']') or '')
    end
    return #choices > 0 and choices or { 'Choose a saved preset first' }
end
function E.bundle(m, preset, include_capes, include_patterns)
    assert(preset and preset.entries and #preset.entries > 0, 'Choose a saved Armory preset first')
    assert(#preset.entries <= E.MAX_BINDINGS, 'Preset exceeds 4096 LUT bindings')
    local entries = collection(preset, include_capes, include_patterns)
    local version = 2
    for _, entry in ipairs(entries) do
        if entry.binding_provenance then
            version = 3
        end
    end
    local manifest, files = { 'EPIC-OUTFIT\t' .. version }, {}
    local payloads, sources, payload_count, source_count, bytes = {}, {}, 0, 0, 0
    local assignments, assignment_count = {}, 0
    for _, entry in ipairs(entries) do
        local encoded = m.dds.encode(entry.document.data, entry.document.width, entry.document.height)
        local file = payloads[encoded]
        if not file then
            bytes = bytes + #encoded
            assert(bytes <= E.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
            payload_count = payload_count + 1
            file = string.format('lut%03d.dds', payload_count)
            payloads[encoded] = file
            files[#files + 1] = { file, encoded }
        end
        -- Retain every destination row, even when several targets share exact payload bytes.
        local fields = { entry.kind, entry.key, file, '-', '-', '-', '-' }
        if entry.original and entry.original.resource and entry.original.patch_source then
            local source = entry.original.patch_source
            local sidecar = sources[source]
            if not sidecar then
                bytes = bytes + #source
                assert(bytes <= E.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                source_count = source_count + 1
                sidecar = string.format('source%03d.patch-source', source_count)
                sources[source] = sidecar
                files[#files + 1] = { sidecar, source }
            end
            fields[4], fields[5], fields[6], fields[7] =
                entry.original.resource, tostring(entry.original.width), tostring(entry.original.height), sidecar
        end
        if version == 3 then
            fields[8] = '-'
            if entry.binding_provenance then
                assert(fields[4] ~= '-', 'Binding provenance requires original texture metadata')
                local module = assert(m.binding_provenance, 'Binding provenance writer unavailable')
                local encoded_proof = module.encode(entry.binding_provenance, entry.kind, entry.key, entry.original)
                local filename = assignments[encoded_proof]
                if not filename then
                    bytes = bytes + #encoded_proof
                    assert(bytes <= E.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                    assignment_count = assignment_count + 1
                    filename = string.format('assignment%03d.assignment', assignment_count)
                    assignments[encoded_proof] = filename
                    files[#files + 1] = { filename, encoded_proof }
                end
                fields[8] = filename
            end
        end
        manifest[#manifest + 1] = table.concat(fields, '\t')
    end
    local text = table.concat(manifest, '\n')
    assert(#text <= E.MAX_MANIFEST_BYTES, 'Preset manifest budget exceeded')
    files[#files + 1] = { 'preset.tsv', text }
    return files
end
function E.new(m, paths, options)
    options = options or {}
    local move_file = m.file_io and m.file_io.rename or function(...) return os.rename(...) end
    local remove_file = m.file_io and m.file_io.remove or function(...) return os.remove(...) end
    local self = {}
    local raw = m.lut_files.new(paths.exports, {
        dds = m.dds, open = m.file_io and m.file_io.open, read = m.file_io and m.file_io.read,
    })
    local patch = m.patch_export.new(paths.exports, {
        file_io = m.file_io,
        available_name = m.lut_files.available_name,
        dds = m.dds,
        directory_exists = paths.directory_exists,
        mkdir_new = paths.mkdir_new,
        rmdir = paths.rmdir,
        binding_writer = m.binding_patch_export,
        provenance = options.binding_provenance,
        id_available = options.resource_id_available,
        original_patch = options.original_patch,
        material_source = options.material_source,
        unit_layout = options.unit_layout or m.binding_unit_layout,
    })
    function self.save(name, preset, format, index, naming)
        assert(preset and preset.entries and #preset.entries > 0, 'Choose a saved Armory preset first')
        assert(#preset.entries <= E.MAX_BINDINGS, 'Preset exceeds 4096 LUT bindings')
        assert(format >= 1 and format <= #E.formats and format % 1 == 0, 'Choose an Armory export format')
        index = index or 1
        assert(type(index) == 'number' and index % 1 == 0 and preset.entries[index], 'Choose a saved preset LUT')
        local include_capes = options.include_capes
        if type(include_capes) == 'function' then
            include_capes = include_capes()
        end
        local include_patterns = options.include_patterns
        if type(include_patterns) == 'function' then
            include_patterns = include_patterns()
        end
        local saved_entries = (format == 1 or format == 3 or format == 5)
            and collection(preset, include_capes, include_patterns)
        local selected_entries = (format == 2 or format == 4)
            and (
                include_patterns == false and { preset.entries[index] }
                or assert(m.export_pairing, 'Selected LUT pairing unavailable').saved(preset.entries, index)
            )
        if format == 5 or (format == 4 and #selected_entries > 1) then
            local entries, counts = {}, {}
            for _, entry in ipairs(format == 5 and saved_entries or selected_entries) do
                local key = entry.kind .. ':' .. entry.document.width
                counts[key] = (counts[key] or 0) + 1
                entries[#entries + 1] = {
                    document = entry.document,
                    original = entry.original,
                    kind = entry.kind,
                    ordinal = counts[key],
                    label = options.lut_label and entry.original and options.lut_label(entry.original.resource),
                }
            end
            local folder, count = assert(m.bulk_dds_export, 'Bulk DDS exporter unavailable')
                .new(m, paths)
                .save(name, entries, naming or 1)
            return folder, tostring(count) .. ' saved LUT DDS files', folder
        elseif format == 4 then
            local chosen = raw.save_unique(name, preset.entries[index].document)
            local file = paths.exports .. '/' .. chosen .. '.dds'
            return file, E.lut_choices(preset)[index], file
        elseif format == 2 or format == 3 then
            local entries = format == 2 and selected_entries or saved_entries
            for _, entry in ipairs(entries) do
                assert(
                    entry.original and entry.original.resource and entry.original.patch_source,
                    'This preset has no patch destination IDs; resave it on the intended gear before exporting a patch'
                )
            end
            if format == 2 and #entries == 1 then
                return patch.save(name, entries[1].document, entries[1].original)
            end
            return patch.save(name, entries)
        end
        local chosen = m.lut_files.available_name(name, function(candidate)
            return paths.directory_exists(paths.exports .. '/' .. candidate .. '.zip')
                or paths.directory_exists(paths.exports .. '/' .. candidate .. '.zip.pending')
        end)
        local output = paths.exports .. '/' .. chosen .. '.zip'
        local staging = output .. '.pending'
        local bytes = m.patch_export.zip_entries(E.bundle(m, { entries = saved_entries }))
        local ok, why = pcall(function()
            m.file_io.write(staging, bytes)
            assert(move_file(staging, output), 'Could not publish preset export')
        end)
        if not ok then
            remove_file(staging)
            error(why, 0)
        end
        return output, tostring(#saved_entries) .. ' saved LUTs', output
    end
    return self
end
return E
