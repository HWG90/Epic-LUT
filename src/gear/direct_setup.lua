-- Persist applied DDS snapshots by local piece/mesh/material slot, never process pointers.
local S = {}
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
    local remove_file = m.file_io and m.file_io.remove or os.remove
    local open_file = m.file_io and m.file_io.open or io.open
    local self = { sequence = 0 }
    local manifest = paths.settings .. '/direct-applied.tsv'
    function self.read()
        local f = open_file(manifest, 'rb')
        if not f then
            return {}
        end
        local text = f:read(524289)
        f:close()
        local version = text:sub(1, 9)
        assert(#text <= 524288 and (version == 'setup-v1\n' or version == 'setup-v2\n'), 'Invalid saved LUT setup')
        local plan = {}
        local capes = {}
        local count = 0
        for line in text:sub(10):gmatch('[^\r\n]+') do
            local key, file = line:match('^([^\t]+)\t(setup%-%d+%-%d+%-%d+%.dds)$')
            if not key and version == 'setup-v2\n' then
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
        return plan, capes
    end
    function self.save(bindings, defaults)
        assert(#bindings > 0 and #bindings <= 4096, 'Apply a palette before saving')
        local version = 'setup-v1\n'
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
            local f = open_file(paths.presets .. '/' .. prefix .. '1.dds', 'rb')
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
                m.dds.write(paths.presets .. '/' .. file, texture.data, texture.width, texture.height)
            end
            return file
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
        local f = assert(open_file(manifest .. '.pending', 'wb'))
        assert(f:write(version, table.concat(rows, '\n'), '\n'))
        assert(f:close())
        local windows = m.native_import or m.windows
        local replaced
        if windows.replace then
            replaced = windows.replace(manifest .. '.pending', manifest)
        else
            -- Compatibility for older adapters/test stubs; FFI stays isolated.
            local legacy = m.legacy_windows or require('src.platform.legacy_windows')
            replaced = legacy.replace(manifest .. '.pending', manifest, windows.verify_interface)
        end
        assert(replaced == true, 'Could not save the applied setup; previous setup retained')
        return count
    end
    function self.clear()
        local f = open_file(manifest, 'rb')
        if f then
            f:close()
            assert(remove_file(manifest))
        end
    end
    return self
end
return S
