local P = dofile('src/weapons/weapon_private_config.lua')
local function fixture()
    local bytes, calls = {}, 0
    local function put(at, text)
        for i = 1, #text do
            bytes[at + i - 1] = text:byte(i)
        end
    end
    local function number(at, value, size)
        for i = 0, (size or 4) - 1 do
            bytes[at + i] = value % 256
            value = math.floor(value / 256)
        end
    end
    local function read(at, size)
        local out = {}
        for i = 0, size - 1 do
            out[#out + 1] = string.char(bytes[at + i] or 0)
        end
        return table.concat(out)
    end
    local game, manager, owner, storage, database = 0x100000, 0x200000, 0x300000, 0x400000, 0x900000
    number(game + 0x3326a38, manager, 8)
    number(game + 0x346bf98, 0x800000, 8)
    number(0x800000 + 0xf12cf0, database, 8)
    number(manager + 0x2b8, 0x700000, 8)
    number(manager + 0x2c0, 4)
    number(manager + 0x2c4, 0xffffffff)
    for row = 0, 3 do
        number(0x700000 + row * 8, 0xffffffff)
    end
    number(0x700000, 248)
    number(0x700004, 0)
    number(manager + 0x2f0, 1)
    number(manager + 0x25c, 8)
    number(manager + 0x2f8, storage, 8)
    put(owner, string.rep('\1', 8))
    number(owner + 8, 249)
    put(database, string.rep('\1', 8))
    number(database + 8, 0)
    local baseline = string.rep('\3', 0x1308)
    put(database + 0x17e0, baseline)
    for _, row in ipairs({
        { 0x7512e0, '48895c240848896c2410488974241848897c242041564883ec408b4208498be83b051e29d3024c8bf2488bd90f848600' },
        { 0x515540, '48895c240848896c24104889742418574883ec208b5a04498bf0448b4a08488bfa4403cb488be9413bd973320f1f4000' },
    }) do
        put(
            game + row[1],
            row[2]:gsub('..', function(pair)
                return string.char(tonumber(pair, 16))
            end)
        )
    end
    local deps = {
        module = function()
            return game
        end,
        read = read,
        clone = function(address, m, o)
            assert(address == game + 0x7512e0 and m == manager and o == owner)
            calls = calls + 1
            put(storage + 0x1308, read(database + 0x17e0, 0x1308))
            number(0x700008, 249)
            number(0x70000c, 1)
            number(manager + 0x2f0, 2)
        end,
    }
    return P.new(deps),
        { weapon_entity = 249 },
        manager,
        owner,
        read(owner, 24),
        number,
        read,
        deps,
        function()
            return calls
        end
end
do
    local create, id, m, o, b, _, read, _, calls = fixture()
    assert(create(id, m, o, b) and calls() == 1)
    assert(create(id, m, o, b) and calls() == 1, 'Existing private configuration recreated')
    assert(read(0x401308, 0x1308) == string.rep('\3', 0x1308))
    assert(read(0x9017e0, 0x1308) == string.rep('\3', 0x1308), 'Shared defaults changed')
end
do
    local create, id, m, o, b, number, _, _, calls = fixture()
    number(0x100000 + 0x7512e0, 0)
    assert(not pcall(create, id, m, o, b) and calls() == 0, 'Unknown allocator called')
end
do
    local create, id, m, o, b, number, _, _, calls = fixture()
    number(m + 0x25c, 1)
    assert(not pcall(create, id, m, o, b) and calls() == 0, 'Full storage called allocator')
end
do
    local create, id, m, o, b, number, _, deps = fixture()
    local clone = deps.clone
    deps.clone = function(...)
        clone(...)
        number(0x401308, 17)
    end
    assert(not pcall(create, id, m, o, b), 'Modified gameplay bytes accepted')
end
print(
    'PASS private weapon configuration: exact game-owned clone, existing no-op, shared defaults, signature/capacity refusal and readback'
)
