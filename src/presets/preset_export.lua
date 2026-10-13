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
local kind_labels = { armor = 'Armor', helmet = 'Helmet', cape = 'Cape', weapon = 'Weapon' }
local weapon_labels = { 'Primary', 'Secondary', 'Support' }
local function weapon_target(entry)
    if entry.kind ~= 'weapon' then
        assert(entry.weapon_resource == nil and entry.weapon_slot == nil, 'Weapon identity on a garment preset target')
        return
    end
    local key = type(entry.key) == 'string' and entry.key:gsub('^p:', '') or ''
    local unit_type, slot, mesh, material = key:match('^(%d+):(%d+):(%d+):(%d+)$')
    unit_type, slot, mesh, material = tonumber(unit_type), tonumber(slot), tonumber(mesh), tonumber(material)
    assert(
        unit_type == 3 and slot and slot >= 1 and slot <= 3 and mesh and mesh <= 63 and material and material <= 63,
        'Invalid weapon preset target'
    )
    assert(entry.weapon_slot == nil or entry.weapon_slot == slot, 'Weapon preset slot disagrees with destination')
    assert(
        type(entry.weapon_resource) == 'string'
            and #entry.weapon_resource == 16
            and entry.weapon_resource:match('^%x+$')
            and entry.weapon_resource ~= string.rep('0', 16),
        'Invalid weapon preset resource ID'
    )
    return slot
end
local function validate(entries)
    assert(type(entries) == 'table' and #entries <= E.MAX_BINDINGS, 'Invalid saved preset entries')
    local count, seen, weapons = 0, {}, {}
    for index in pairs(entries) do
        assert(
            type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= #entries,
            'Saved preset entries must be a dense list'
        )
        count = count + 1
    end
    assert(count == #entries, 'Saved preset entries must be a dense list')
    for _, entry in ipairs(entries) do
        assert(
            type(entry) == 'table' and kind_labels[entry.kind] and type(entry.key) == 'string',
            'Invalid saved LUT gear target'
        )
        local identity = entry.kind .. ':' .. entry.key
        assert(not seen[identity], 'Duplicate saved LUT target')
        seen[identity] = true
        local slot = weapon_target(entry)
        if slot then
            local resource = entry.weapon_resource:lower()
            assert(not weapons[slot] or weapons[slot] == resource, 'Conflicting weapon identities in preset slot')
            weapons[slot] = resource
        end
    end
end
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
function E.lut_choices(preset)
    local choices, counts = {}, {}
    validate(preset and preset.entries or {})
    for _, entry in ipairs(preset and preset.entries or {}) do
        local pattern = entry.document.width == 3
        local kind = assert(kind_labels[entry.kind], 'Invalid saved LUT gear kind')
        local slot = weapon_target(entry)
        if slot then
            kind = weapon_labels[slot]
        end
        local label = kind .. (pattern and ' Pattern LUT ' or ' LUT ')
        counts[label] = (counts[label] or 0) + 1
        choices[#choices + 1] = label
            .. counts[label]
            .. (entry.original and (' [' .. entry.original.resource .. ']') or '')
    end
    return #choices > 0 and choices or { 'Choose a saved preset first' }
end
function E.bundle(m, preset, include_capes, include_patterns)
    assert(preset and preset.entries and #preset.entries > 0, 'Choose a saved Armory preset first')
    assert(#preset.entries <= E.MAX_BINDINGS, 'Preset exceeds 4096 LUT bindings')
    validate(preset.entries)
    local entries = collection(preset, include_capes, include_patterns)
    local version = 2
    for _, entry in ipairs(entries) do
        if entry.binding_provenance then
            version = math.max(version, 3)
        end
        if entry.kind == 'weapon' then
            version = 4
        end
    end
    local manifest, files = { 'EPIC-OUTFIT\t' .. version }, {}
    local payloads, sources, payload_count, source_count, bytes = {}, {}, 0, 0, 0
    local assignments, assignment_count = {}, 0
    for _, entry in ipairs(entries) do
        assert(kind_labels[entry.kind], 'Invalid saved LUT gear kind')
        local weapon_slot = weapon_target(entry)
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
        if version >= 3 then
            fields[8] = '-'
            if entry.binding_provenance then
                assert(fields[4] ~= '-', 'Binding provenance requires original texture metadata')
                local module = assert(m.binding_provenance, 'Binding provenance writer unavailable')
                local encoded_proof = module.encode(entry.binding_provenance, entry.kind, entry.key, entry.original)
                if entry.kind == 'weapon' then
                    assert(
                        entry.binding_provenance.version == 4
                            and type(entry.binding_provenance.weapon_resource) == 'string'
                            and entry.binding_provenance.weapon_resource:lower() == entry.weapon_resource:lower()
                            and entry.binding_provenance.weapon_slot == weapon_slot,
                        'Preset weapon identity differs from assignment proof'
                    )
                else
                    assert(
                        entry.binding_provenance.kind == entry.kind and entry.binding_provenance.version ~= 4,
                        'Preset assignment gear family differs'
                    )
                end
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
        if version >= 4 then
            fields[9] = entry.kind == 'weapon' and entry.weapon_resource:lower() or '-'
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
    local self = {}
    local raw = m.lut_files.new(paths.exports, { dds = m.dds })
    local patch = m.patch_export.new(paths.exports, {
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
        weapon_patch_archive = options.weapon_patch_archive,
        weapon_export_batch = options.weapon_export_batch,
    })
    function self.save(name, preset, format, index, naming)
        assert(preset and preset.entries and #preset.entries > 0, 'Choose a saved Armory preset first')
        assert(#preset.entries <= E.MAX_BINDINGS, 'Preset exceeds 4096 LUT bindings')
        validate(preset.entries)
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
                local weapon_slot = weapon_target(entry)
                local key = entry.kind .. ':' .. (weapon_slot or 0) .. ':' .. entry.document.width
                counts[key] = (counts[key] or 0) + 1
                entries[#entries + 1] = {
                    document = entry.document,
                    original = entry.original,
                    kind = entry.kind,
                    ordinal = counts[key],
                    weapon_slot = weapon_slot,
                    weapon_resource = entry.weapon_resource and entry.weapon_resource:lower(),
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
            if format == 2 and #entries == 1 and entries[1].kind ~= 'weapon' then
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
            assert(os.rename(staging, output), 'Could not publish preset export')
        end)
        if not ok then
            os.remove(staging)
            error(why, 0)
        end
        return output, tostring(#saved_entries) .. ' saved LUTs', output
    end
    return self
end
return E
