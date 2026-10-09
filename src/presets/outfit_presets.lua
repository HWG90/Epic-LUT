-- Named gear collections: validated manifest plus ordinary DDS files.
local O = {}
local function valid_name(value)
    assert(
        type(value) == 'string' and #value > 0 and #value <= 48 and value:match('^[%w _-]+$'),
        'Use a preset name up to 48 letters, numbers, spaces, _ or -'
    )
    return value
end
local function basename(value, extension)
    assert(
        type(value) == 'string' and #value <= 160 and value:match('^[%w _-]+%.' .. extension .. '$'),
        'Invalid preset filename'
    )
    return value
end
local function metadata(original)
    if not original or not original.resource or not original.patch_source then
        return nil
    end
    assert(
        type(original.resource) == 'string' and original.resource:match('^%x+$') and #original.resource == 16,
        'Invalid preset texture ID'
    )
    assert(
        type(original.patch_source) == 'string'
            and #original.patch_source == 357
            and original.patch_source:sub(1, 16):match('^%x+$')
            and original.patch_source:sub(17, 17) == '\n',
        'Invalid preset patch metadata'
    )
    assert(
        type(original.width) == 'number'
            and type(original.height) == 'number'
            and (original.width == 23 or original.width == 3)
            and original.height >= 1
            and original.height <= 64
            and original.height % 1 == 0
            and (original.width ~= 3 or original.height == 1),
        'Invalid original LUT dimensions'
    )
    return original
end
-- Plain manifests and bounded DDS/metadata only. Never load code from a shared preset.
function O.read(m, path, label)
    local text = m.file_io.read(path, 65536)
    local folder = assert(path:match('^(.*)[/\\][^/\\]+$'), 'Preset folder unavailable')
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do
        lines[#lines + 1] = line
    end
    local version = lines[1] == 'EPIC-OUTFIT\t1' and 1 or lines[1] == 'EPIC-OUTFIT\t2' and 2
    assert(version and #lines > 1 and #lines <= 129, 'Invalid outfit preset')
    local result = { name = label, armor = {}, helmet = {}, cape = {}, entries = {} }
    local bytes, seen = 0, {}
    for i = 2, #lines do
        local fields = {}
        for field in (lines[i] .. '\t'):gmatch('([^\t]*)\t') do
            fields[#fields + 1] = field
        end
        assert(#fields == (version == 1 and 3 or 7), 'Invalid preset entry')
        local kind, key, file = fields[1], fields[2], fields[3]
        assert(
            (kind == 'armor' or kind == 'helmet' or (version == 2 and kind == 'cape'))
                and (key:match('^[%d:]+$') or (version == 2 and key:match('^p:[%d:]+$'))),
            'Invalid preset target'
        )
        assert(not seen[kind .. ':' .. key], 'Duplicate preset target')
        seen[kind .. ':' .. key] = true
        basename(file, 'dds')
        local data, w, h = m.dds.decode(m.file_io.read(folder .. '/' .. file, m.dds.MAX_BYTES))
        assert(
            (w == 23 and key:sub(1, 2) ~= 'p:') or (version == 2 and w == 3 and h == 1 and key:sub(1, 2) == 'p:'),
            'Preset is not a material or Pattern LUT'
        )
        bytes = bytes + w * h * 16
        assert(bytes <= 8 * 1024 * 1024, 'Preset pixel budget exceeded')
        local original
        if version == 2 and fields[4] ~= '-' then
            original = metadata({
                resource = fields[4],
                width = tonumber(fields[5]),
                height = tonumber(fields[6]),
                patch_source = m.file_io.read(folder .. '/' .. basename(fields[7], 'patch%-source'), 357),
            })
        elseif version == 2 then
            assert(fields[5] == '-' and fields[6] == '-' and fields[7] == '-', 'Incomplete preset patch metadata')
        end
        local document = { data = data, width = w, height = h, source = label .. ' / ' .. kind }
        result.entries[#result.entries + 1] = { kind = kind, key = key, document = document, original = original }
        result[kind][#result[kind] + 1] = document
    end
    return result
end
function O.new(m, folder)
    local self = {}
    local name = valid_name
    function self.names()
        local names = {}
        for _, file in ipairs(m.windows.files(folder, 'outfit-*.tsv')) do
            local n = file:match('^outfit%-([%w _-]+)%.tsv$')
            if n then
                names[#names + 1] = n
            end
        end
        return names
    end
    function self.save(label, entries)
        name(label)
        assert(#entries > 0, 'No loaded LUTs to save. Load Current Gear, then try saving again.')
        assert(#entries <= 128, ('Preset has %d LUT bindings; the maximum is 128.'):format(#entries))
        local rows = { 'EPIC-OUTFIT\t2' }
        for i, e in ipairs(entries) do
            assert(
                (e.kind == 'armor' or e.kind == 'helmet' or e.kind == 'cape')
                    and (e.key:match('^[%d:]+$') or e.key:match('^p:[%d:]+$')),
                'Invalid target'
            )
            assert(
                (e.document.width == 23 and e.key:sub(1, 2) ~= 'p:')
                    or (e.document.width == 3 and e.document.height == 1 and e.key:sub(1, 2) == 'p:'),
                'Invalid preset LUT layout'
            )
            local file = 'outfit-' .. label .. '-' .. e.kind .. '-' .. i .. '.dds'
            m.dds.write(folder .. '/' .. file, e.document.data, e.document.width, e.document.height)
            local original = metadata(e.original)
            local fields = { e.kind, e.key, file, '-', '-', '-', '-' }
            if original then
                local sidecar = file:gsub('%.dds$', '.patch-source')
                m.file_io.write(folder .. '/' .. sidecar, original.patch_source)
                fields[4], fields[5], fields[6], fields[7] =
                    original.resource:lower(), tostring(original.width), tostring(original.height), sidecar
            end
            rows[#rows + 1] = table.concat(fields, '\t')
        end
        local target = folder .. '/outfit-' .. label .. '.tsv'
        local f = assert(io.open(target .. '.tmp', 'wb'))
        assert(f:write(table.concat(rows, '\n')))
        assert(f:close())
        os.remove(target)
        assert(os.rename(target .. '.tmp', target))
        return true
    end
    function self.load(label)
        name(label)
        return O.read(m, folder .. '/outfit-' .. label .. '.tsv', label)
    end
    function self.import(path, label)
        name(label)
        local preset = O.read(m, path, label)
        self.save(label, preset.entries)
        return self.load(label)
    end
    function self.rename(old, new)
        name(old)
        name(new)
        assert(old:lower() ~= new:lower(), 'Enter a different preset name')
        self.load(old)
        local destination = folder .. '/outfit-' .. new .. '.tsv'
        local existing = io.open(destination, 'rb')
        if existing then
            existing:close()
            error('A preset with that name already exists')
        end
        assert(os.rename(folder .. '/outfit-' .. old .. '.tsv', destination))
        return true
    end
    function self.delete(label)
        name(label)
        self.load(label)
        -- Keep the DDS payloads and a recoverable manifest; remove only from the active library.
        local target = folder .. '/outfit-' .. label .. '.tsv'
        local backup = target .. '.deleted'
        local i = 0
        while true do
            local f = io.open(backup, 'rb')
            if not f then
                break
            end
            f:close()
            i = i + 1
            backup = target .. '.deleted-' .. i
        end
        assert(os.rename(target, backup))
        return true
    end
    return self
end
return O
