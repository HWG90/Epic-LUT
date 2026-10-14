-- Owns only Epic LUT's writes. Keeps immutable GPU buffers and rolls back partial writes.
local B = { MAX_BYTES = 64 * 1024 * 1024, MAX_TEXTURES = 16384 }
function B.new(deps)
    local ffi = require('ffi')
    local retain = assert(deps.retain, 'Texture retention state required')
    local self = { owned = {} }
    local cohort = deps.cohort or retain.cohort
    local retirement_targets, retirement_seen = {}, {}
    if cohort then
        assert(type(cohort) == 'table', 'Texture cohort required to be a table')
        cohort.sessions = cohort.sessions or {}
        cohort.sessions[#cohort.sessions + 1] = self
    end
    local function remember(b)
        if not cohort then
            return
        end
        local key = deps.key(b)
        local prior = retirement_seen[key]
        if
            prior
            and prior.unit == b.unit
            and prior.mesh == b.mesh
            and prior.material == b.material
            and prior.slot == b.slot
            and prior.original == b.original
        then
            return
        end
        local captured = {
            key = key,
            unit = b.unit,
            mesh = b.mesh,
            material = b.material,
            slot = b.slot,
            original = b.original,
        }
        retirement_targets[#retirement_targets + 1] = captured
        retirement_seen[key] = captured
    end
    function self.apply(document, targets)
        assert(not cohort or not cohort.closing, 'Texture cohort is closing; reload Epic LUT before applying')
        assert(#targets > 0, 'No matching live LUTs; refresh first')
        for _, b in ipairs(targets) do
            assert(deps.present(b) and deps.binding(b) == b.current, 'Live LUT changed; refresh before applying')
        end
        local bytes = document.width * document.height * 16
        local key = document.width .. ':' .. document.height .. ':' .. ffi.string(document.data, bytes)
        local texture = retain.cache[key]
        if texture and texture.retiring then
            texture = nil
        end
        if not texture then
            assert(
                retain.bytes + bytes <= B.MAX_BYTES and #retain.records < B.MAX_TEXTURES,
                'Session texture budget reached ('
                    .. #retain.records
                    .. '/'
                    .. B.MAX_TEXTURES
                    .. ' textures, '
                    .. string.format('%.2f/%.0f MiB', retain.bytes / (1024 * 1024), B.MAX_BYTES / (1024 * 1024))
                    .. '). Reload Epic LUT to reclaim eligible textures; game restart clears all. Local draft kept. Restore alone does not clear the budget.'
            )
            local data = ffi.new('float[?]', document.width * document.height * 4)
            ffi.copy(data, document.data, bytes)
            local keep = { data = data, bytes = bytes, cohort = cohort }
            retain.records[#retain.records + 1] = keep
            retain.bytes = retain.bytes + bytes
            texture = assert(deps.create_texture(document.width, document.height, data))
            texture.data, texture.width, texture.height =
                texture.data or data, texture.width or document.width, texture.height or document.height
            keep.texture = texture
            keep.owned = true
            retain.cache[key] = texture
        end
        local known = {}
        for _, b in ipairs(self.owned) do
            known[deps.key(b)] = true
        end
        local changes = {}
        local ok, why = pcall(function()
            for _, b in ipairs(targets) do
                -- Remember before calling native code: a rejected bind can
                -- still have written a target before it reports failure.
                remember(b)
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
                local current = deps.present(b) and deps.binding(b)
                if current == old then
                    -- A rejected bind can leave native state untouched even
                    -- though our forward-write metadata already advanced.
                    b.current = old
                    b.previous = nil
                elseif current and current == b.current then
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
    function self.reconcile()
        assert(not cohort or not cohort.closing, 'Texture cohort is closing')
        local repaired, foreign = 0, 0
        for _, b in ipairs(self.owned) do
            if deps.present(b) then
                local current = deps.binding(b)
                if
                    current == b.original
                    and b.current ~= b.original
                    and b.texture
                    and b.texture.object == b.current
                then
                    deps.bind(b, b.current)
                    assert(deps.binding(b) == b.current, 'Shared LUT repair readback failed')
                    repaired = repaired + 1
                elseif current and current ~= 0 and current ~= b.current and current ~= b.original then
                    foreign = foreign + 1 -- Never adopt or overwrite another writer's replacement.
                end
            end
        end
        return repaired, foreign
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
    function self.retirement_certificate()
        if not cohort then
            return false, 'Legacy texture session has no retirement cohort'
        end
        local ok, why = pcall(function()
            local cohort_objects = {}
            for _, keep in ipairs(retain.records) do
                if keep.cohort == cohort and keep.texture and keep.texture.object then
                    cohort_objects[keep.texture.object] = true
                end
            end
            for _, captured in ipairs(retirement_targets) do
                assert(deps.key(captured) == captured.key, 'Texture target identity changed during retirement')
                -- Missing materials are not proof of unit death. Explicit
                -- confirmed death is safe only with the caller's fence drain.
                if not deps.dead or deps.dead(captured) ~= true then
                    assert(captured.original and captured.original ~= 0, 'Texture target original unavailable')
                    assert(deps.present(captured), 'Texture target inaccessible during retirement')
                    assert(deps.binding(captured) == captured.original, 'Texture target not restored during retirement')
                    assert(
                        not cohort_objects[captured.original],
                        'Texture target original belongs to the retiring cohort'
                    )
                end
            end
        end)
        if not ok then
            return false, tostring(why)
        end
        return true
    end
    return self
end
return B
