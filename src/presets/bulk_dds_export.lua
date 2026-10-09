-- Transactional raw DDS export; all pixels and names validate before creating a folder.
local B = { formats = { 'LUT# + HEX', 'LUT# + Decimal', 'LUT#', 'HEX', 'Decimal' } }
local kind_labels = { armor = 'Armor', helmet = 'Helmet', cape = 'Cape' }
function B.new(m, paths)
    local self = {}
    function self.save(prefix, entries, naming)
        naming = naming or 1
        assert(type(naming) == 'number' and naming % 1 == 0 and B.formats[naming], 'Choose a DDS naming format')
        assert(type(entries) == 'table' and #entries > 0 and #entries <= 128, 'Choose between 1 and 128 LUTs to export')
        -- Reuse shared name validation without touching the filesystem.
        m.lut_files.available_name(prefix, function()
            return false
        end)
        local files, resources, targets, stems = {}, {}, {}, {}
        for _, entry in ipairs(entries) do
            assert(kind_labels[entry.kind], 'Invalid LUT gear kind')
            assert(
                type(entry.ordinal) == 'number' and entry.ordinal >= 1 and entry.ordinal % 1 == 0,
                'Invalid LUT ordinal'
            )
            local document = assert(entry.document, 'LUT document unavailable')
            local bytes = m.dds.encode(document.data, document.width, document.height)
            local resource = entry.original and entry.original.resource
            if resource ~= nil then
                assert(
                    type(resource) == 'string' and #resource == 16 and resource:match('^%x+$'),
                    'Invalid LUT resource ID'
                )
                resource = resource:lower()
            end
            local ordinal = (document.width == 3 and document.height == 1 and 'PatternLUT' or 'LUT')
                .. string.format('%.0f', entry.ordinal)
            local key = resource or (entry.kind .. ':' .. ordinal)
            local identity = resource and ('resource ID ' .. resource) or (entry.kind .. ' ' .. ordinal)
            local target = key .. ':' .. entry.kind .. ':' .. ordinal
            assert(not targets[target] or targets[target] == bytes, 'Conflicting LUT values for ' .. identity)
            targets[target] = bytes
            resources[key] = resources[key] or {}
            if not resources[key][bytes] then
                resources[key][bytes] = true
                local id = resource
                if resource and (naming == 2 or naming == 5) then
                    id = m.resource_ids.format(resource, true):match('^%[(%d+)%]$')
                    assert(id, 'Could not format LUT resource ID')
                end
                local suffix = ordinal
                if naming == 1 or naming == 2 then
                    suffix = ordinal .. (id and '-' .. id or '')
                elseif naming == 4 or naming == 5 then
                    suffix = id or ordinal
                end
                local stem = prefix .. ' ' .. suffix
                stems[stem:lower()] = (stems[stem:lower()] or 0) + 1
                files[#files + 1] = { stem = stem, kind = entry.kind, bytes = bytes }
            end
        end
        local used = {}
        for _, file in ipairs(files) do
            local stem = file.stem
            if stems[stem:lower()] > 1 then
                stem = stem .. '-' .. kind_labels[file.kind]
            end
            local chosen, counter = stem, 1
            while used[chosen:lower()] do
                counter = counter + 1
                chosen = stem .. '-' .. string.format('%02d', counter)
            end
            assert(#chosen <= 240 and not chosen:find('[\\/:]'), 'DDS filename is too long or invalid')
            used[chosen:lower()] = true
            file.name = chosen .. '.dds'
        end
        local folder = m.lut_files.available_name(prefix, function(candidate)
            local output = paths.exports .. '/' .. candidate
            return paths.directory_exists(output) or paths.directory_exists(output .. '.pending')
        end)
        local destination = paths.exports .. '/' .. folder
        local staging = destination .. '.pending'
        local owned, written = false, {}
        local ok, why = pcall(function()
            paths.mkdir_new(staging)
            owned = true
            for _, file in ipairs(files) do
                local path = staging .. '/' .. file.name
                written[#written + 1] = path -- A failed write can still leave a partial file.
                m.file_io.write(path, file.bytes)
            end
            assert(not paths.directory_exists(destination), 'Export folder already exists')
            assert(os.rename(staging, destination), 'Could not publish DDS export folder')
            owned = false
        end)
        if not ok then
            if owned then
                for _, path in ipairs(written) do
                    os.remove(path)
                end
                paths.rmdir(staging) -- Nonrecursive: unrelated files are never removed.
            end
            error(why, 0)
        end
        return destination, #files
    end
    return self
end
return B
