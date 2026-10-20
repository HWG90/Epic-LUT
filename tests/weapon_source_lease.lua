local Source = dofile('src/weapons/weapon_source_lease.lua')
local function fixture()
    local bytes, writes = {}, 0
    local function put(address, text)
        for i = 1, #text do
            bytes[address + i - 1] = text:byte(i)
        end
    end
    local function number(address, value, width)
        for i = 0, (width or 4) - 1 do
            bytes[address + i] = value % 256
            value = math.floor(value / 256)
        end
    end
    local function read(address, size)
        local out = {}
        for i = 0, size - 1 do
            out[#out + 1] = string.char(bytes[address + i] or 0)
        end
        return table.concat(out)
    end
    local game, manager, owner, config, mesh, names = 0x100000, 0x200000, 0x300000, 0x400000, 0x500000, 0x600000
    number(game + 0x3326a38, manager, 8)
    local function map(address, data)
        number(address, data, 8)
        number(address + 8, 2)
        number(address + 12, 0xffffffff)
        number(data, 249)
        number(data + 4, 0)
        number(data + 8, 0xffffffff)
    end
    map(manager + 0x278, 0x700000)
    map(manager + 0x2b8, 0x710000)
    number(manager + 0x290, 0x720000, 8)
    number(0x720000, owner, 8)
    number(owner + 8, 249)
    number(manager + 0x2f8, config, 8)
    number(mesh + 0x58, 1)
    number(mesh + 0x60, names, 8)
    number(names, 123)
    local address = config + 0xc8
    number(address, 123)
    local b = { weapon_slot = 1, unit = 100, mesh = mesh, material_index = 0, current = 10 }
    local deps = {
        identity = {
            snapshot = function()
                return { weapon_entity = 249, weapon_unit_ref = 100 }
            end,
        },
        module = function()
            return game
        end,
        read = read,
        discovery = {
            prove_private = function()
                return true
            end,
            present = function()
                return true
            end,
            binding = function(v)
                return v.current
            end,
        },
        write = function(at, expected, replacement)
            assert(read(at, #expected) == expected)
            put(at, replacement)
            writes = writes + 1
        end,
    }
    return Source.new(deps), b, number, read, address, deps, function()
        return writes
    end
end
do
    local s, b, _, read, at, _, writes = fixture()
    local original = read(at, 40)
    s.sync({ b })
    assert(read(at, 4) == string.rep('\0', 4) and writes() == 1)
    s.sync({ b, b })
    assert(writes() == 1, 'Unchanged assignment rewrote source')
    s.sync({})
    assert(read(at, 40) == original and writes() == 2 and not s.pending())
end
do
    local s, b, number, read, at, _, writes = fixture()
    number(at + 8, 7)
    local original = read(at, 40)
    assert(s.sync({ b }) and read(at + 8, 8) == original:sub(9, 16), 'Selected LUT override blocked or overwritten')
    s.sync({})
    assert(read(at, 40) == original and writes() == 2, 'Explicit LUT source did not restore exactly')
end
for _, offset in ipairs({4, 16, 24, 32}) do
    local s, b, number, _, at, _, writes = fixture()
    number(at + offset, 7)
    assert(not pcall(s.sync, { b }) and writes() == 0, 'Unselected texture override or padding was suppressed')
end
do
    local s, b, number, read, at = fixture()
    number(at + 24, 9)
    b.slot = 0x81d4c49d
    local original = read(at,40)
    assert(s.sync({b}) and read(at+24,8)==original:sub(25,32))
    s.sync({})
    assert(read(at,40)==original, 'Selected Pattern override did not restore exactly')
end
do
    local s, b, number, _, _, _, writes = fixture()
    number(0x710008, 250)
    number(0x71000c, 0)
    assert(not pcall(s.sync, { b }) and writes() == 0, 'Shared source was mutated')
end
do
    local s, b, number, read, at, _, writes = fixture()
    s.sync({ b })
    number(at, 456)
    assert(
        not pcall(s.sync, {}) and read(at, 4) ~= string.rep('\0', 4) and writes() == 1 and s.pending(),
        'Foreign selector change was overwritten or lost cleanup ownership'
    )
end
do
    local s, b, number, _, at, _, writes = fixture()
    s.sync({ b })
    number(0x300008, 250)
    s.sync({})
    assert(writes() == 1 and not s.pending(), 'Reused entity received stale restoration')
end
do
    local s, b, _, read, at, deps = fixture()
    local original, write = read(at, 40), deps.write
    local first = true
    deps.write = function(...)
        write(...)
        if first then
            first = false
            error('Injected failure after data write')
        end
    end
    assert(
        not pcall(s.sync, { b }) and read(at, 40) == original and not s.pending(),
        'Partial acquisition did not roll back'
    )
end
print(
    'PASS weapon source leases: exact restore, no repeat writes, skin/shared refusal, foreign/reused owner and rollback'
)

do
    local s, b, number, _, _, deps = fixture()
    for _, map in ipairs({{0x278,0x700000},{0x2b8,0x710000}}) do
        number(0x200000+map[1]+8,256)
        for row=1,255 do number(map[2]+row*8,0xffffffff) end
    end
    local read, calls = deps.read, 0
    deps.read=function(address,size) calls=calls+1;return read(address,size) end
    assert(s.sync({b}))
    assert(calls<120, 'Source proof made a native read for every hash bucket')
    number(0x710000+255*8,250)
    number(0x710000+255*8+4,0)
    assert(not pcall(s.sync,{b}), 'Batched proof missed an alias in the last bucket')
end

do
    local s, b, number, _, at, _, writes = fixture()
    number(at, 0)
    assert(s.sync({ b }) and writes() == 0 and not s.pending(), 'No-reset material was blocked')
end
do
    local s, b, number, read, at, _, writes = fixture()
    s.sync({ b })
    -- Engine relocates the private configuration while retaining its exact owner.
    number(0x200000 + 0x2f8, 0x800000, 8)
    s.sync({ b })
    s.sync({})
    assert(
        read(0x800000 + 0xc8, 4) == string.char(123, 0, 0, 0) and writes() == 2,
        'Relocated private source did not restore'
    )
end

do
    local s, b, number, read, at, deps, writes = fixture()
    s.sync({b})
    number(0x300008,250)
    number(0x700000,250)
    number(0x710000,250)
    number(at,123)
    deps.identity.snapshot=function() return {weapon_entity=250,weapon_unit_ref=100} end
    assert(s.sync({b}) and writes()==2, 'Retired journal blocked replacement at reused address')
    s.sync({})
    assert(read(at,4)==string.char(123,0,0,0) and writes()==3)
end
