-- Resolve native uint32 avatar references through actual Lua World Unit handles.
-- Read-only: never creates, changes, releases or retains ownership of a world/unit.
local I = { MAX_WORLDS = 64, MAX_UNITS = 131072, MAX_GARMENTS = 30 }
local identity_fields = { 'player', 'unit', 'avatar', 'avatar_index', 'units_at', 'peer_low', 'peer_high' }
local function reference(value)
    return type(value) == 'number' and value % 1 == 0 and value >= 1 and value < 0xffffffff
end
local function snapshot(identity)
    assert(type(identity) == 'table' and identity.units_at and identity['local'] ~= false, 'Local avatar unavailable')
    local out = {}
    for _, name in ipairs(identity_fields) do
        out[name] = identity[name]
    end
    return out
end
local function same(identity, expected)
    for _, name in ipairs(identity_fields) do
        if identity[name] ~= expected[name] then
            return false
        end
    end
    return true
end
function I.new(E, deps)
    local ffi = require('ffi')
    local A, W, U = E.Application, E.World, E.Unit
    assert(
        A
            and W
            and U
            and type(A.worlds) == 'function'
            and type(W.units) == 'function'
            and type(U.alive) == 'function'
            and type(U.resource_name) == 'function'
            and deps.avatar
            and type(deps.avatar.resolve_live) == 'function'
            and type(deps.avatar.units) == 'function',
        'Lua Unit identity APIs unavailable'
    )
    local receipts = setmetatable({}, { __mode = 'k' })
    local self, handles = {}, {}
    local function token(unit)
        -- World.units returns Lua handles, not the numeric references read from
        -- avatar memory. Do not cast a caller's number into a Unit argument.
        local kind = type(unit)
        if kind ~= 'userdata' and kind ~= 'cdata' then
            return nil
        end
        if kind == 'cdata' and not tostring(ffi.typeof(unit)):match('%*%s*>$') then
            return nil
        end
        local ok, address = pcall(function()
            return tonumber(ffi.cast('uintptr_t', unit))
        end)
        if not ok or not address then
            return nil
        end
        -- Match the established preview adapter: the genuine handle can carry
        -- two low tag bits. Decode its reference, retain the handle unchanged.
        local ref = math.floor(address / 4)
        return reference(ref) and ref or nil
    end
    local function worlds()
        local listed = A.worlds()
        assert(type(listed) == 'table' and #listed <= I.MAX_WORLDS, 'World list bounds changed')
        local out, seen = {}, {}
        local function append(world)
            if world ~= nil and not seen[world] then
                assert(#out < I.MAX_WORLDS, 'World list bounds changed')
                out[#out + 1], seen[world] = world, true
            end
        end
        -- The existing preview captures main_world first; worlds() is not
        -- assumed to contain it. Never create or release either world here.
        if type(A.main_world) == 'function' then
            append(A.main_world())
        end
        for _, world in ipairs(listed) do
            append(world)
        end
        return out
    end
    local function scan(ref, expected, kept)
        assert(reference(ref), 'Invalid native Unit reference')
        -- resolve_live proves local machine ownership; remote/preview resolver
        -- callbacks are deliberately not accepted in this helper's interface.
        local identity = assert(deps.avatar.resolve_live(deps.memory, deps.game, deps.read), 'Local avatar unavailable')
        local proof = snapshot(identity)
        assert(not expected or same(proof, expected), 'Local avatar identity changed')
        local garments = deps.avatar.units(deps.memory, identity, nil, 0, 9)
        assert(type(garments) == 'table' and #garments <= I.MAX_GARMENTS, 'Local garment list bounds changed')
        local found = false
        for _, garment in ipairs(garments) do
            if garment.unit == ref and garment.preview == false then
                found = true
            end
        end
        assert(found, 'Unit reference is not a current local garment')
        if kept and type(U.world) == 'function' then
            -- A receipt retains the genuine engine handle acquired by the
            -- initial census. Recheck current ownership directly rather than
            -- allocate every mission Unit again to validate that one handle.
            assert(token(kept.unit) == ref and U.alive(kept.unit) == true, 'Local garment Unit disappeared')
            assert(U.world(kept.unit) == kept.world, 'Lua Unit handle or world changed')
            assert(not deps.excluded or not deps.excluded(kept.unit, ref, kept.world), 'Preview-owned Unit refused')
            local live_world = false
            for _, world in ipairs(worlds()) do live_world = live_world or world == kept.world end
            assert(live_world, 'Garment world disappeared')
            return kept.unit, kept.world, proof
        end
        local handle, owner
        for _, world in ipairs(worlds()) do
            local units = W.units(world)
            assert(type(units) == 'table' and #units <= I.MAX_UNITS, 'World Unit list bounds changed')
            for _, unit in ipairs(units) do
                if token(unit) == ref then
                    assert(not handle, 'Ambiguous Unit reference across live worlds')
                    assert(not deps.excluded or not deps.excluded(unit, ref, world), 'Preview-owned Unit refused')
                    handle, owner = unit, world
                end
            end
        end
        assert(handle, 'No live Lua Unit handle matches the local garment')
        local live_world = false
        for _, world in ipairs(worlds()) do
            live_world = live_world or world == owner
        end
        assert(live_world, 'Garment world disappeared')
        assert(U.alive(handle) == true, 'Local garment Unit disappeared')
        return handle, owner, proof
    end
    function self.handle(ref, expected)
        local cached = handles[ref]
        if cached and type(U.world) == 'function' then
            local kept = receipts[cached]
            if (not expected or same(snapshot(expected), kept.identity)) and pcall(self.validate, cached) then
                return cached.unit, cached
            end
            handles[ref] = nil
        end
        local handle, world, proof = scan(ref, expected and snapshot(expected))
        local receipt = { unit = handle, world = world, reference = ref }
        receipts[receipt] = { unit = handle, world = world, reference = ref, identity = proof }
        if type(U.world) == 'function' then
            local count = 0
            for _ in pairs(handles) do count = count + 1 end
            if count >= I.MAX_GARMENTS then handles = {} end
            handles[ref] = receipt
        end
        return handle, receipt
    end
    function self.validate(receipt)
        local kept = receipts[receipt]
        assert(
            kept and receipt.unit == kept.unit and receipt.world == kept.world and receipt.reference == kept.reference,
            'Unknown or altered Lua Unit receipt'
        )
        local handle, world = scan(kept.reference, kept.identity, kept)
        assert(handle == kept.unit and world == kept.world, 'Lua Unit handle or world changed')
        return true
    end
    function self.resource(ref, expected)
        local handle, receipt = self.handle(ref, expected)
        local returned = U.resource_name(handle)
        local printed, value = pcall(tostring, returned)
        local kind, hash = type(returned)
        if printed and kind == 'string' then
            hash = value:match('^#ID%[(%x+)%]$')
        elseif printed and kind == 'userdata' then
            -- Observed live IdString64 rendering includes the same exact ID
            -- twice. Require agreement; do not reinterpret its userdata bytes.
            local named, raw = value:match('^%[IdString64 "#ID%[(%x+)%]" 0x(%x+)%]$')
            if named and raw and #named == 16 and #raw == 16 and named:lower() == raw:lower() then
                hash = named
            end
        end
        if not hash or #hash ~= 16 then
            -- Unknown representations remain bounded diagnostics; no guessed
            -- conversion or numeric64-bit precision loss is permitted.
            local detail = printed and string.format('%q', value:sub(1, 128)) or '<tostring failed>'
            error('Stable Lua Unit resource ID unavailable (type=' .. type(returned) .. ', value=' .. detail .. ')', 0)
        end
        self.validate(receipt)
        return hash:lower(), receipt
    end
    return self
end
return I
