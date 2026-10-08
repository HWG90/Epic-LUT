-- Owns only Epic LUT's writes. Keeps immutable GPU buffers and rolls back partial writes.
local B = {}
function B.new(deps)
    local ffi = require('ffi')
    local retain = assert(deps.retain, 'Texture retention state required')
    local self = { owned = {} }
    function self.apply(document, targets)
        assert(#targets > 0, 'No matching live LUTs; refresh first')
        for _, b in ipairs(targets) do
            assert(deps.present(b) and deps.binding(b) == b.current, 'Live LUT changed; refresh before applying')
        end
        local bytes = document.width * document.height * 16
        local key = document.width .. ':' .. document.height .. ':' .. ffi.string(document.data, bytes)
        local texture = retain.cache[key]
        if not texture then
            assert(
                retain.bytes + bytes <= 8 * 1024 * 1024 and #retain.records < 2048,
                'Session texture budget reached; restore and restart'
            )
            local data = ffi.new('float[?]', document.width * document.height * 4)
            ffi.copy(data, document.data, bytes)
            local keep = { data = data }
            retain.records[#retain.records + 1] = keep
            retain.bytes = retain.bytes + bytes
            texture = assert(deps.create_texture(document.width, document.height, data))
            texture.data, texture.width, texture.height =
                texture.data or data, texture.width or document.width, texture.height or document.height
            keep.texture = texture
            retain.cache[key] = texture
        end
        local known = {}
        for _, b in ipairs(self.owned) do
            known[deps.key(b)] = true
        end
        local changes = {}
        local ok, why = pcall(function()
            for _, b in ipairs(targets) do
                if not known[deps.key(b)] then
                    self.owned[#self.owned + 1] = b
                    known[deps.key(b)] = true
                end
                if b.current ~= texture.object then
                    changes[#changes + 1] = { binding = b, old = b.current }
                    b.previous = b.current
                    b.current = texture.object
                    deps.bind(b, b.current)
                    assert(deps.binding(b) == b.current, 'LUT binding readback failed')
                    b.previous = nil
                end
            end
        end)
        if not ok then
            -- Roll back only this operation; previously applied targets remain active.
            for i = #changes, 1, -1 do
                local b, old = changes[i].binding, changes[i].old
                if deps.present(b) and deps.binding(b) == b.current then
                    local restored = pcall(function()
                        deps.bind(b, old)
                        assert(deps.binding(b) == old)
                    end)
                    if restored then
                        b.current = old
                        b.previous = nil
                    end
                end
            end
            error(why, 0)
        end
        for _, b in ipairs(targets) do
            b.texture = texture
            b.document = document
        end
        return #targets, texture
    end
    function self.restore()
        local pending = {}
        for _, b in ipairs(self.owned) do
            local current = deps.present(b) and deps.binding(b)
            if current and current ~= b.original and (current == b.current or current == b.previous) then
                local ok = pcall(function()
                    deps.bind(b, b.original)
                end)
                if not ok or deps.binding(b) ~= b.original then
                    pending[#pending + 1] = b
                else
                    b.current = b.original
                    b.previous = nil
                    b.texture = nil
                end
            elseif current == b.original then
                b.current = b.original
                b.previous = nil
                b.texture = nil
            end
        end
        self.owned = pending
        return #pending == 0
    end
    return self
end
return B
