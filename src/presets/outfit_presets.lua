-- Named gear collections: validated manifest plus ordinary DDS files.
local O = { MAX_BINDINGS = 4096, MAX_MANIFEST = 2 * 1024 * 1024, MAX_PAYLOAD_BYTES = 8 * 1024 * 1024 }
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
    assert(original == nil or type(original) == 'table', 'Invalid preset patch metadata')
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
local function target(kind, key, version, strict, weapon_resource, weapon_slot)
    assert(
        (
            kind == 'armor'
            or kind == 'helmet'
            or (version >= 2 and kind == 'cape')
            or (version >= 4 and kind == 'weapon')
        ) and type(key) == 'string',
        'Invalid preset target'
    )
    local pattern = key:sub(1, 2) == 'p:'
    local destination = pattern and key:sub(3) or key
    assert(
        (not pattern or version >= 2) and destination:match(strict and '^%d+:%d+:%d+:%d+$' or '^[%d:]+$'),
        'Invalid preset target'
    )
    local slot
    if kind == 'weapon' then
        local unit_type, mesh, material
        unit_type, slot, mesh, material = destination:match('^(%d+):(%d+):(%d+):(%d+)$')
        unit_type, slot, mesh, material = tonumber(unit_type), tonumber(slot), tonumber(mesh), tonumber(material)
        assert(
            unit_type == 3 and slot and slot >= 1 and slot <= 3 and mesh and mesh <= 63 and material and material <= 63,
            'Invalid weapon preset target'
        )
        assert(weapon_slot == nil or weapon_slot == slot, 'Weapon preset slot disagrees with destination')
        assert(
            type(weapon_resource) == 'string'
                and #weapon_resource == 16
                and weapon_resource:match('^%x+$')
                and weapon_resource ~= string.rep('0', 16),
            'Invalid weapon preset resource ID'
        )
    else
        assert(weapon_resource == nil or weapon_resource == '-', 'Weapon resource on a garment preset target')
        assert(weapon_slot == nil, 'Weapon slot on a garment preset target')
    end
    return pattern, slot
end
local function assignment_identity(proof, kind, weapon_resource, weapon_slot)
    assert(type(proof) == 'table' and proof.kind == kind, 'Preset assignment gear family differs')
    if kind == 'weapon' then
        assert(
            proof.version == 4
                and type(proof.weapon_resource) == 'string'
                and proof.weapon_resource:lower() == weapon_resource:lower()
                and proof.weapon_slot == weapon_slot,
            'Preset weapon identity differs from assignment proof'
        )
    else
        assert(proof.version ~= 4, 'Weapon assignment on a garment preset target')
    end
end
-- Plain manifests and bounded DDS/metadata only. Never load code from a shared preset.
function O.read(m, path, label)
    local text = m.file_io.read(path, O.MAX_MANIFEST)
    local folder = assert(path:match('^(.*)[/\\][^/\\]+$'), 'Preset folder unavailable')
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do
        lines[#lines + 1] = line
    end
    local version = lines[1] == 'EPIC-OUTFIT\t1' and 1
        or lines[1] == 'EPIC-OUTFIT\t2' and 2
        or lines[1] == 'EPIC-OUTFIT\t3' and 3
        or lines[1] == 'EPIC-OUTFIT\t4' and 4
    assert(version and #lines > 1 and #lines <= O.MAX_BINDINGS + 1, 'Invalid outfit preset')
    local result = { name = label, armor = {}, helmet = {}, cape = {}, weapon = {}, entries = {} }
    local bytes, seen, documents, sidecars, payloads, metadata_payloads = 0, {}, {}, {}, {}, {}
    local provenance_sidecars, weapon_resources = {}, {}
    for i = 2, #lines do
        local fields = {}
        for field in (lines[i] .. '\t'):gmatch('([^\t]*)\t') do
            fields[#fields + 1] = field
        end
        assert(#fields == (version == 1 and 3 or version >= 3 and version + 5 or 7), 'Invalid preset entry')
        local kind, key, file = fields[1], fields[2], fields[3]
        local pattern, weapon_slot = target(kind, key, version, nil, fields[9])
        local weapon_resource = kind == 'weapon' and fields[9]:lower() or nil
        if weapon_slot then
            assert(
                not weapon_resources[weapon_slot] or weapon_resources[weapon_slot] == weapon_resource,
                'Conflicting weapon identities in preset slot'
            )
            weapon_resources[weapon_slot] = weapon_resource
        end
        assert(not seen[kind .. ':' .. key], 'Duplicate preset target')
        seen[kind .. ':' .. key] = true
        basename(file, 'dds')
        local document = documents[file:lower()]
        if not document then
            local data, w, h = m.dds.decode(m.file_io.read(folder .. '/' .. file, m.dds.MAX_BYTES))
            local payload = m.dds.encode(data, w, h)
            document = payloads[payload]
            if not document then
                bytes = bytes + #payload
                assert(bytes <= O.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                document = { data = data, width = w, height = h, source = label .. ' / ' .. kind }
                payloads[payload] = document
            end
            documents[file:lower()] = document
        end
        local w, h = document.width, document.height
        assert(
            (w == 23 and not pattern) or (version >= 2 and w == 3 and h == 1 and pattern),
            'Preset is not a material or Pattern LUT'
        )
        local original
        if version >= 2 and fields[4] ~= '-' then
            local sidecar = basename(fields[7], 'patch%-source')
            if not sidecars[sidecar:lower()] then
                sidecars[sidecar:lower()] = m.file_io.read(folder .. '/' .. sidecar, 357)
                local payload = sidecars[sidecar:lower()]
                if not metadata_payloads[payload] then
                    bytes = bytes + #payload
                    assert(bytes <= O.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                    metadata_payloads[payload] = true
                end
            end
            original = metadata({
                resource = fields[4],
                width = tonumber(fields[5]),
                height = tonumber(fields[6]),
                patch_source = sidecars[sidecar:lower()],
            })
        elseif version >= 2 then
            assert(fields[5] == '-' and fields[6] == '-' and fields[7] == '-', 'Incomplete preset patch metadata')
        end
        local provenance
        if version >= 3 and fields[8] ~= '-' then
            local module = assert(m.binding_provenance, 'Binding provenance reader unavailable')
            local filename = basename(fields[8], 'assignment')
            if not provenance_sidecars[filename:lower()] then
                local text = m.file_io.read(folder .. '/' .. filename, module.MAX_BYTES)
                bytes = bytes + #text
                assert(bytes <= O.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                provenance_sidecars[filename:lower()] = text
            end
            assert(original, 'Binding provenance requires original texture metadata')
            provenance = module.decode(provenance_sidecars[filename:lower()], kind, key, original)
            assignment_identity(provenance, kind, weapon_resource, weapon_slot)
        end
        result.entries[#result.entries + 1] = {
            kind = kind,
            key = key,
            document = document,
            original = original,
            binding_provenance = provenance,
            weapon_slot = weapon_slot,
            weapon_resource = weapon_resource,
        }
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
        assert(type(entries) == 'table', 'Invalid preset entries')
        assert(#entries > 0, 'No loaded LUTs to save. Load Current Gear, then try saving again.')
        assert(
            #entries <= O.MAX_BINDINGS,
            ('Preset has %d LUT bindings; the maximum is %d.'):format(#entries, O.MAX_BINDINGS)
        )
        local count = 0
        for index in pairs(entries) do
            assert(
                type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= #entries,
                'Preset entries must be a dense list'
            )
            count = count + 1
        end
        assert(count == #entries, 'Preset entries must be a dense list')
        local version = 2
        for _, entry in ipairs(entries) do
            if entry.binding_provenance ~= nil then
                version = math.max(version, 3)
            end
            if entry.kind == 'weapon' then
                version = 4
            end
        end
        local rows = { 'EPIC-OUTFIT\t' .. version }
        local files, pixels, sidecars, encoded, seen, bytes = {}, {}, {}, {}, {}, 0
        local weapon_resources = {}
        local function payload_name(stem, extension, payload)
            local candidate, suffix = stem .. extension, 1
            while true do
                local previous = m.file_io.read(folder .. '/' .. candidate, math.max(m.dds.MAX_BYTES, 357), true)
                if previous == payload then
                    return candidate
                elseif previous == nil then
                    files[#files + 1] = { candidate, payload }
                    return candidate
                end
                suffix = suffix + 1
                candidate = stem .. '-' .. suffix .. extension
            end
        end
        -- Validate and encode the complete set before writing any payload or manifest.
        -- Destination rows remain independent; only identical file bytes are shared.
        for i, e in ipairs(entries) do
            assert(type(e) == 'table' and type(e.document) == 'table', 'Invalid preset entry')
            assert(e.binding_provenance == nil or type(e.binding_provenance) == 'table', 'Invalid binding provenance')
            local pattern, weapon_slot = target(e.kind, e.key, version, true, e.weapon_resource, e.weapon_slot)
            if weapon_slot then
                local resource = e.weapon_resource:lower()
                assert(
                    not weapon_resources[weapon_slot] or weapon_resources[weapon_slot] == resource,
                    'Conflicting weapon identities in preset slot'
                )
                weapon_resources[weapon_slot] = resource
            end
            local identity = e.kind .. ':' .. e.key
            assert(not seen[identity], 'Duplicate preset target')
            seen[identity] = true
            assert(
                (e.document.width == 23 and not pattern)
                    or (e.document.width == 3 and e.document.height == 1 and pattern),
                'Invalid preset LUT layout'
            )
            local payload = encoded[e.document]
            if not payload then
                payload = m.dds.encode(e.document.data, e.document.width, e.document.height)
                encoded[e.document] = payload
            end
            local file = pixels[payload]
            if not file then
                file = payload_name('outfit-' .. label .. '-' .. e.kind .. '-' .. i, '.dds', payload)
                pixels[payload] = file
                bytes = bytes + #payload
                assert(bytes <= O.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
            end
            local original = metadata(e.original)
            local fields = { e.kind, e.key, file, '-', '-', '-', '-' }
            if original then
                local sidecar = sidecars[original.patch_source]
                if not sidecar then
                    sidecar = payload_name(
                        'outfit-' .. label .. '-' .. e.kind .. '-' .. i,
                        '.patch-source',
                        original.patch_source
                    )
                    sidecars[original.patch_source] = sidecar
                    bytes = bytes + #original.patch_source
                    assert(bytes <= O.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                end
                fields[4], fields[5], fields[6], fields[7] =
                    original.resource:lower(), tostring(original.width), tostring(original.height), sidecar
            end
            if version >= 3 then
                fields[8] = '-'
                if e.binding_provenance then
                    assert(original, 'Binding provenance requires original texture metadata')
                    local module = assert(m.binding_provenance, 'Binding provenance writer unavailable')
                    local text = module.encode(e.binding_provenance, e.kind, e.key, original)
                    assignment_identity(e.binding_provenance, e.kind, e.weapon_resource, weapon_slot)
                    fields[8] = payload_name('outfit-' .. label .. '-' .. e.kind .. '-' .. i, '.assignment', text)
                    bytes = bytes + #text
                    assert(bytes <= O.MAX_PAYLOAD_BYTES, 'Preset payload budget exceeded')
                end
            end
            if version >= 4 then
                fields[9] = e.kind == 'weapon' and e.weapon_resource:lower() or '-'
            end
            rows[#rows + 1] = table.concat(fields, '\t')
        end
        local manifest = table.concat(rows, '\n')
        assert(#manifest <= O.MAX_MANIFEST, 'Preset manifest budget exceeded')
        local target = folder .. '/outfit-' .. label .. '.tsv'
        local previous = m.file_io.read(target, O.MAX_MANIFEST, true)
        for _, file in ipairs(files) do
            m.file_io.write(folder .. '/' .. file[1], file[2])
        end
        local f = assert(io.open(target .. '.tmp', 'wb'))
        assert(f:write(manifest))
        assert(f:close())
        if previous then
            m.file_io.write(target .. '.previous', previous)
            assert(os.remove(target))
        end
        local published, why = os.rename(target .. '.tmp', target)
        if not published then
            if previous then
                os.rename(target .. '.previous', target)
            end
            error(why, 0)
        end
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
