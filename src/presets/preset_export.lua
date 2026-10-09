-- Export stored Armory bytes, never the currently worn/editor table.
local E = {
    formats = {
        'Shareable Preset ZIP',
        'Selected LUT Patch ZIP',
        'Entire Preset Patch ZIP',
        'Raw DDS (selected LUT)',
        'Raw DDS (entire preset)',
    },
}
local kind_labels = { armor = 'Armor', helmet = 'Helmet', cape = 'Cape' }
local function collection(preset, include_capes)
    local entries = assert(preset and preset.entries, 'Choose a saved Armory preset first')
    if include_capes ~= false then
        return entries
    end
    local selected = {}
    for _, entry in ipairs(entries) do
        if entry.kind ~= 'cape' then
            selected[#selected + 1] = entry
        end
    end
    assert(
        #selected > 0,
        'No LUTs remain to export. Enable Include Capes in Armor Exports or export a selected Cape LUT.'
    )
    return selected
end
function E.lut_choices(preset)
    local choices, counts = {}, {}
    for _, entry in ipairs(preset and preset.entries or {}) do
        local pattern = entry.document.width == 3
        local kind = assert(kind_labels[entry.kind], 'Invalid saved LUT gear kind')
        local label = kind .. (pattern and ' Pattern LUT ' or ' LUT ')
        counts[label] = (counts[label] or 0) + 1
        choices[#choices + 1] = label
            .. counts[label]
            .. (entry.original and (' [' .. entry.original.resource .. ']') or '')
    end
    return #choices > 0 and choices or { 'Choose a saved preset first' }
end
function E.bundle(m, preset, include_capes)
    assert(
        preset and preset.entries and #preset.entries > 0 and #preset.entries <= 128,
        'Choose a saved Armory preset first'
    )
    local entries = collection(preset, include_capes)
    local manifest, files = { 'EPIC-OUTFIT\t2' }, {}
    for i, entry in ipairs(entries) do
        local file = string.format('lut%03d.dds', i)
        files[#files + 1] = { file, m.dds.encode(entry.document.data, entry.document.width, entry.document.height) }
        local fields = { entry.kind, entry.key, file, '-', '-', '-', '-' }
        if entry.original and entry.original.resource and entry.original.patch_source then
            local sidecar = file:gsub('%.dds$', '.patch-source')
            files[#files + 1] = { sidecar, entry.original.patch_source }
            fields[4], fields[5], fields[6], fields[7] =
                entry.original.resource, tostring(entry.original.width), tostring(entry.original.height), sidecar
        end
        manifest[#manifest + 1] = table.concat(fields, '\t')
    end
    files[#files + 1] = { 'preset.tsv', table.concat(manifest, '\n') }
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
    })
    function self.save(name, preset, format, index, naming)
        assert(preset and preset.entries and #preset.entries > 0, 'Choose a saved Armory preset first')
        assert(format >= 1 and format <= #E.formats and format % 1 == 0, 'Choose an Armory export format')
        index = index or 1
        assert(type(index) == 'number' and index % 1 == 0 and preset.entries[index], 'Choose a saved preset LUT')
        local include_capes = options.include_capes
        if type(include_capes) == 'function' then
            include_capes = include_capes()
        end
        local saved_entries = (format == 1 or format == 3 or format == 5) and collection(preset, include_capes)
        if format == 5 then
            local entries, counts = {}, {}
            for _, entry in ipairs(saved_entries) do
                local key = entry.kind .. ':' .. entry.document.width
                counts[key] = (counts[key] or 0) + 1
                entries[#entries + 1] = {
                    document = entry.document,
                    original = entry.original,
                    kind = entry.kind,
                    ordinal = counts[key],
                }
            end
            local folder, count =
                assert(m.bulk_dds_export, 'Bulk DDS exporter unavailable').new(m, paths).save(name, entries, naming)
            return folder, tostring(count) .. ' saved LUT DDS files', folder
        elseif format == 4 then
            local chosen = raw.save_unique(name, preset.entries[index].document)
            local file = paths.exports .. '/' .. chosen .. '.dds'
            return file, E.lut_choices(preset)[index], file
        elseif format == 2 or format == 3 then
            local entries = format == 2 and { preset.entries[index] } or saved_entries
            for _, entry in ipairs(entries) do
                assert(
                    entry.original and entry.original.resource and entry.original.patch_source,
                    'This preset has no patch destination IDs; resave it on the intended gear before exporting a patch'
                )
            end
            if format == 2 then
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
