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
    local self = {}
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
        if not ok or not address or address % 4 ~= 0 or not reference(address / 4) then
            return nil
        end
        return address / 4
    end
    local function worlds()
        local out = A.worlds()
        assert(type(out) == 'table' and #out <= I.MAX_WORLDS, 'World list bounds changed')
        return out
    end
    local function scan(ref, expected)
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
        local handle, world, proof = scan(ref, expected and snapshot(expected))
        local receipt = { unit = handle, world = world, reference = ref }
        receipts[receipt] = { unit = handle, world = world, reference = ref, identity = proof }
        return handle, receipt
    end
    function self.validate(receipt)
        local kept = receipts[receipt]
        assert(
            kept and receipt.unit == kept.unit and receipt.world == kept.world and receipt.reference == kept.reference,
            'Unknown or altered Lua Unit receipt'
        )
        local handle, world = scan(kept.reference, kept.identity)
        assert(handle == kept.unit and world == kept.world, 'Lua Unit handle or world changed')
        return true
    end
    function self.resource(ref, expected)
        local handle, receipt = self.handle(ref, expected)
        local value = tostring(U.resource_name(handle))
        local hash = value:match('^#ID%[(%x+)%]$')
        assert(hash and #hash == 16, 'Stable Lua Unit resource ID unavailable')
        self.validate(receipt)
        return hash:lower(), receipt
    end
    return self
end
return I
