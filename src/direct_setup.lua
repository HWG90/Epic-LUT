-- Persist applied DDS snapshots by local piece/mesh/material slot, never process pointers.
local S = {}
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
        assert(#text <= 524288 and text:sub(1, 9) == 'setup-v1\n', 'Invalid saved LUT setup')
        local plan = {}
        local count = 0
        for line in text:sub(10):gmatch('[^\r\n]+') do
            local key, file = line:match('^([^\t]+)\t(setup%-%d+%-%d+%-%d+%.dds)$')
            assert(key and not plan[key], 'Invalid or duplicate saved binding')
            if key ~= 'armor-all' and key ~= 'helmet-all' then
                local kind, slot, mesh, material = key:match('^(%d+):(%d+):(%d+):(%d+)$')
                assert(
                    kind
                        and tonumber(kind) <= 2
                        and tonumber(slot) <= 9
                        and tonumber(mesh) < 64
                        and tonumber(material) < 64,
                    'Saved binding exceeds local limits'
                )
            end
            count = count + 1
            assert(count <= 4098, 'Saved setup exceeds binding budget')
            plan[key] = file
        end
        return plan
    end
    function self.save(bindings, defaults)
        assert(#bindings > 0 and #bindings <= 4096, 'Apply a palette before saving')
        local prefix
        repeat
            self.sequence = self.sequence + 1
            prefix = 'setup-' .. os.time() .. '-' .. self.sequence .. '-'
            local f = io.open(paths.presets .. '/' .. prefix .. '1.dds', 'rb')
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
            rows[#rows + 1] = kind .. '-all\t' .. save_texture(texture)
        end
        for _, b in ipairs(bindings) do
            local texture = assert(b.texture, 'An applied LUT is awaiting recovery; restore it before saving')
            assert(not seen[b.save_key], 'Duplicate local binding key')
            seen[b.save_key] = true
            rows[#rows + 1] = b.save_key .. '\t' .. save_texture(texture)
        end
        table.sort(rows)
        local f = assert(io.open(manifest .. '.pending', 'wb'))
        assert(f:write('setup-v1\n', table.concat(rows, '\n'), '\n'))
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
        return count
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
