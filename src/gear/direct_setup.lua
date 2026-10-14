-- Persist applied DDS snapshots by local piece/mesh/material slot, never process pointers.
local S = { MAX_BINDINGS = 4096, MAX_PAYLOAD_BYTES = 8 * 1024 * 1024 }
local function weapon_entries(m, entries)
    assert(type(entries) == 'table' and #entries <= S.MAX_BINDINGS, 'Invalid saved weapon bindings')
    local count, seen, resources = 0, {}, {}
    for index in pairs(entries) do
        assert(
            type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= #entries,
            'Saved weapon bindings must be a dense list'
        )
        count = count + 1
    end
    assert(count == #entries, 'Saved weapon bindings must be a dense list')
    local module = #entries > 0 and assert(m.binding_provenance, 'Weapon setup assignment reader unavailable')
    for _, entry in ipairs(entries) do
        assert(
            type(entry) == 'table' and entry.kind == 'weapon' and type(entry.key) == 'string',
            'Saved weapon setup cannot include garment targets'
        )
        local pattern = entry.key:sub(1, 2) == 'p:'
        local slot, mesh, material = (pattern and entry.key:sub(3) or entry.key):match('^3:(%d+):(%d+):(%d+)$')
        slot, mesh, material = tonumber(slot), tonumber(mesh), tonumber(material)
        assert(
            slot
                and slot >= 1
                and slot <= 3
                and mesh
                and mesh < 64
                and material
                and material < 64
                and entry.key == (pattern and 'p:' or '') .. '3:' .. slot .. ':' .. mesh .. ':' .. material,
            'Invalid canonical saved weapon destination'
        )
        assert(not seen[entry.key], 'Duplicate saved weapon destination')
        seen[entry.key] = true
        assert(
            entry.weapon_slot == slot
                and type(entry.weapon_resource) == 'string'
                and #entry.weapon_resource == 16
                and entry.weapon_resource:match('^%x+$'),
            'Invalid saved weapon configuration'
        )
        local resource = entry.weapon_resource:lower()
        assert(not resources[slot] or resources[slot] == resource, 'Conflicting saved weapon slot configurations')
        resources[slot] = resource
        local original, document = entry.original, entry.document
        assert(
            type(original) == 'table'
                and type(original.patch_source) == 'string'
                and #original.patch_source == 357
                and original.patch_source:sub(1, 16):match('^%x+$')
                and original.patch_source:sub(17, 17) == '\n',
            'Weapon setup requires complete original texture metadata'
        )
        assert(
            type(document) == 'table'
                and document.data
                and document.width == (pattern and 3 or 23)
                and type(document.height) == 'number'
                and document.height % 1 == 0
                and document.height >= 1
                and document.height <= 64
                and (not pattern or document.height == 1)
                and original.width == document.width
                and original.height == document.height,
            'Saved weapon LUT dimensions differ from original'
        )
        local proof = module.validate(entry.binding_provenance, 'weapon', entry.key, original)
        assert(
            proof.version == 4 and proof.weapon_slot == slot and proof.weapon_resource == resource,
            'Weapon setup requires complete matching version4 assignment proof'
        )
    end
    return entries
end
local function cape_identity(proof, resource)
    assert(
        type(proof) == 'string' and #proof <= 32 and proof:match('^%d+:%d+$'),
        'Cape setup requires its captured body and cape kit'
    )
    assert(
        type(resource) == 'string' and #resource == 16 and resource:match('^%x+$'),
        'Cape setup requires its original texture ID'
    )
end
local function target(key)
    assert(type(key) == 'string', 'Saved binding key unavailable')
    local pattern = key:sub(1, 2) == 'p:'
    local kind, slot, mesh, material = (pattern and key:sub(3) or key):match('^(%d+):(%d+):(%d+):(%d+)$')
    assert(
        kind and tonumber(kind) <= 2 and tonumber(slot) <= 9 and tonumber(mesh) < 64 and tonumber(material) < 64,
        'Saved binding exceeds local limits'
    )
    return pattern
end
function S.new(m, paths)
    local self = { sequence = 0 }
    local manifest = paths.settings .. '/direct-applied.tsv'
    function self.read()
        local f = io.open(manifest, 'rb')
        if not f then
            return {}
        end
        local text = f:read(524289)
        f:close()
        local version = text:sub(1, 9)
        assert(
            #text <= 524288 and (version == 'setup-v1\n' or version == 'setup-v2\n' or version == 'setup-v3\n'),
            'Invalid saved LUT setup'
        )
        local plan = {}
        local capes = {}
        local count = 0
        local weapon_label
        for line in text:sub(10):gmatch('[^\r\n]+') do
            if version == 'setup-v3\n' and line:match('^weapons\t') then
                local label = line:match('^weapons\toutfit%-(setup%-%d+%-%d+%-weapons)%.tsv$')
                assert(
                    label and #label <= 48 and not weapon_label,
                    'Invalid or duplicate saved weapon manifest pointer'
                )
                weapon_label = label
            else
                local key, file = line:match('^([^\t]+)\t(setup%-%d+%-%d+%-%d+%.dds)$')
                if not key and version ~= 'setup-v1\n' then
                    local proof, resource
                    key, file, proof, resource =
                        line:match('^([^\t]+)\t(setup%-%d+%-%d+%-%d+%.dds)\tcape\t([^\t]+)\t([^\t]+)$')
                    if key then
                        assert(
                            key ~= 'armor-all' and key ~= 'helmet-all',
                            'A Cape setup cannot be a blanket Armor/Helmet default'
                        )
                        cape_identity(proof, resource)
                        capes[key] = { proof = proof, resource = resource:lower() }
                    end
                end
                assert(key and not plan[key], 'Invalid or duplicate saved binding')
                if key ~= 'armor-all' and key ~= 'helmet-all' then
                    target(key)
                end
                count = count + 1
                assert(count <= 4098, 'Saved setup exceeds binding budget')
                plan[key] = file
            end
        end
        local weapons
        if version == 'setup-v3\n' then
            assert(weapon_label, 'Saved weapon manifest pointer missing')
            weapons =
                assert(m.outfit_presets, 'Weapon setup storage unavailable').new(m, paths.settings).load(weapon_label)
            assert(#weapons.entries > 0, 'Saved weapon manifest is empty')
            weapon_entries(m, weapons.entries)
            local destinations = count - (plan['armor-all'] and 1 or 0) - (plan['helmet-all'] and 1 or 0)
            assert(destinations + #weapons.entries <= S.MAX_BINDINGS, 'Combined saved setup exceeds binding budget')
            local bytes, seen_payloads, files = 0, {}, {}
            local function budget(payload, namespace)
                local identity = namespace .. payload
                if not seen_payloads[identity] then
                    seen_payloads[identity] = true
                    bytes = bytes + #payload
                    assert(bytes <= S.MAX_PAYLOAD_BYTES, 'Combined saved setup payload budget exceeded')
                end
            end
            for key, filename in pairs(plan) do
                local document = files[filename]
                if not document then
                    local data, width, height =
                        m.dds.decode(m.file_io.read(paths.presets .. '/' .. filename, m.dds.MAX_BYTES))
                    document = { width = width, height = height, data = data }
                    files[filename] = document
                    budget(m.dds.encode(data, width, height), 'gear-dds:')
                end
                assert(
                    (key:sub(1, 2) == 'p:' and document.width == 3 and document.height == 1)
                        or (key:sub(1, 2) ~= 'p:' and document.width == 23),
                    'Saved LUT layout does not match its destination'
                )
            end
            for _, entry in ipairs(weapons.entries) do
                budget(m.dds.encode(entry.document.data, entry.document.width, entry.document.height), 'weapon-dds:')
                budget(entry.original.patch_source, 'weapon-source:')
                budget(
                    m.binding_provenance.encode(entry.binding_provenance, 'weapon', entry.key, entry.original),
                    'weapon-proof:'
                )
            end
        end
        return plan, capes, weapons
    end
    function self.save(bindings, defaults, weapons)
        weapons = weapon_entries(m, weapons or {})
        assert(
            type(bindings) == 'table' and #bindings + #weapons > 0 and #bindings + #weapons <= S.MAX_BINDINGS,
            'Apply a palette before saving; combined binding budget exceeded'
        )
        local version = 'setup-v1\n'
        local bytes, payloads, weapon_documents, weapon_count = 0, {}, {}, 0
        local function budget(payload, namespace)
            local identity = namespace .. payload
            if not payloads[identity] then
                payloads[identity] = true
                bytes = bytes + #payload
                assert(bytes <= S.MAX_PAYLOAD_BYTES, 'Combined saved setup payload budget exceeded')
            end
        end
        for _, entry in ipairs(weapons) do
            local payload = m.dds.encode(entry.document.data, entry.document.width, entry.document.height)
            budget(payload, 'weapon-dds:')
            if not weapon_documents[payload] then
                weapon_documents[payload], weapon_count = true, weapon_count + 1
            end
            budget(entry.original.patch_source, 'weapon-source:')
            budget(
                m.binding_provenance.encode(entry.binding_provenance, 'weapon', entry.key, entry.original),
                'weapon-proof:'
            )
        end
        for _, b in ipairs(bindings) do
            if b.cape then
                cape_identity(b.cape_proof, b.resource)
                version = 'setup-v2\n'
            end
        end
        local prefix
        repeat
            self.sequence = self.sequence + 1
            prefix = 'setup-' .. os.time() .. '-' .. self.sequence .. '-'
            local f = io.open(paths.presets .. '/' .. prefix .. '1.dds', 'rb')
            if not f and #weapons > 0 then
                f = io.open(paths.settings .. '/outfit-' .. prefix .. 'weapons.tsv', 'rb')
            end
            if f then
                f:close()
            else
                break
            end
        until false
        local textures, rows, seen = {}, {}, {}
        local count = 0
        local function save_texture(texture)
            local file = textures[texture]
            if not file then
                count = count + 1
                file = prefix .. count .. '.dds'
                textures[texture] = file
                budget(m.dds.encode(texture.data, texture.width, texture.height), 'gear-dds:')
                m.dds.write(paths.presets .. '/' .. file, texture.data, texture.width, texture.height)
            end
            return file
        end
        if #weapons > 0 then
            local label = prefix .. 'weapons'
            assert(m.outfit_presets, 'Weapon setup storage unavailable').new(m, paths.settings).save(label, weapons)
            rows[#rows + 1] = 'weapons\toutfit-' .. label .. '.tsv'
            version = 'setup-v3\n'
        end
        for kind, texture in pairs(defaults or {}) do
            assert(kind == 'armor' or kind == 'helmet', 'Invalid saved target')
            assert(texture.width == 23, 'A material default must be a 23-column LUT')
            rows[#rows + 1] = kind .. '-all\t' .. save_texture(texture)
        end
        for _, b in ipairs(bindings) do
            local texture = assert(b.texture, 'An applied LUT is awaiting recovery; restore it before saving')
            local pattern = target(b.save_key)
            assert(
                (pattern and texture.width == 3 and texture.height == 1) or (not pattern and texture.width == 23),
                'Saved LUT layout does not match its destination'
            )
            assert(not seen[b.save_key], 'Duplicate local binding key')
            seen[b.save_key] = true
            rows[#rows + 1] = b.save_key
                .. '\t'
                .. save_texture(texture)
                .. (b.cape and ('\tcape\t' .. b.cape_proof .. '\t' .. b.resource:lower()) or '')
        end
        table.sort(rows)
        local f = assert(io.open(manifest .. '.pending', 'wb'))
        assert(f:write(version, table.concat(rows, '\n'), '\n'))
        assert(f:close())
        local ffi = require('ffi')
        local _, kernel = m.native_import.verify_interface()
        local function wide(text)
            local n = kernel.epic_native_wide(65001, 8, text, -1, nil, 0)
            assert(n > 0)
            local out = ffi.new('uint16_t[?]', n)
            assert(kernel.epic_native_wide(65001, 8, text, -1, out, n) == n)
            return out
        end
        assert(
            kernel.epic_native_move(wide(manifest .. '.pending'), wide(manifest), 1) ~= 0,
            'Could not save the applied setup; previous setup retained'
        )
        return count + weapon_count
    end
    function self.clear()
        local f = io.open(manifest, 'rb')
        if f then
            f:close()
            assert(os.remove(manifest))
        end
    end
    return self
end
return S
