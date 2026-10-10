local ffi = require('ffi')
local S = dofile('src/preview/player_preview_submit.lua')
local game, exe = 0x10000000, 0x20000000
local api, app, world, real = 0x30000000, 0x40000000, 0x50000000, 0x60000000
local bytes = {}
local function pointer(at, value)
    local data = ffi.new('uint64_t[1]', value)
    bytes[at] = ffi.string(data, 8)
end
pointer(game + 0x3326308, api)
pointer(api + 0x10, app)
pointer(app + 0x30, exe + 0x318090)
pointer(app + 0x28, exe + 0x318150)
pointer(world, real)
local function unhex(value)
    return (value:gsub('..', function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
bytes[exe + 0x318090] = unhex('48895c2408574883ec30488bf9488b0d64816f01488b9938030000488b93101c')
bytes[exe + 0x318150] = unhex('48895c240848896c2410488974241848897c242041564883ec604c8b9c249800')
bytes[game + 0x1390778] = unhex('c7442438a8b7431a')
bytes[game + 0x139079f] = unhex('c74424300f800000')
local memory = {
    read = function(at, n)
        local b = bytes[tonumber(ffi.cast('uintptr_t', at))]
        assert(b and #b == n)
        return b
    end,
}
local calls = {}
local function addr(value)
    return tonumber(ffi.cast('uintptr_t', value))
end
local dependencies = {
    address = function(value)
        return value
    end,
    update = function(w)
        assert(addr(w) == real)
        calls[#calls + 1] = 'update'
    end,
    render = function(w, c, v, unused, e, window, flags, context)
        assert(addr(w) == real and addr(c) == 70000000 and addr(v) == 80000000 and addr(e) == 90000000)
        assert(unused == nil and window == nil and flags == 0x800f and context == 0x1a43b7a8)
        calls[#calls + 1] = 'render'
    end,
}
local submit = S.new(memory, game, exe, dependencies)
submit(world, 70000000, 80000000, 90000000)
assert(table.concat(calls, ',') == 'update,render')
pointer(app + 0x28, exe + 0x318151)
assert(not pcall(submit, world, 70000000, 80000000, 90000000) and #calls == 2, 'Changed native dispatch was called')
assert(not pcall(S.new, memory, game, exe, dependencies), 'Changed entry was accepted')
pointer(app + 0x28, exe + 0x318150)
bytes[game + 0x139079f] = string.rep('\0', 8)
assert(not pcall(S.new, memory, game, exe, dependencies), 'Changed UI flags were accepted')
bytes[game + 0x139079f] = unhex('c74424300f800000')

-- Native casts use the same named ctypes on every initialization and module
-- reload. Only create pointers here: fixture addresses must never be called.
local cast, cdef = ffi.cast, ffi.cdef
local declarations, anonymous, named = 0, 0, 0
ffi.cdef = function(value)
    declarations = declarations + 1
    return cdef(value)
end
ffi.cast = function(ct, value)
    if type(ct) == 'string' and ct:find('%(%s*%*') then
        anonymous = anonymous + 1
    elseif type(ct) == 'cdata' then
        assert(
            ct == ffi.typeof('epic_preview_submit1_update') or ct == ffi.typeof('epic_preview_submit1_render'),
            'Unexpected cached native function type'
        )
        named = named + 1
    end
    return cast(ct, value)
end
local ok, why = pcall(function()
    for i = 1, 32 do
        local reloaded = dofile('src/preview/player_preview_submit.lua')
        assert(type(reloaded.new(memory, game, exe)) == 'function')
        assert(type(reloaded.new(memory, game, exe)) == 'function')
    end
end)
ffi.cast, ffi.cdef = cast, cdef
assert(ok, why)
assert(
    declarations == 1 and named == 128 and anonymous == 0,
    'Reloads created anonymous function types or redeclared named types'
)
assert(#calls == 2, 'Constructing native function pointers called a fixture address')
-- Injected dispatch remains unchanged after initializing the native type cache.
local final = dofile('src/preview/player_preview_submit.lua').new(memory, game, exe, dependencies)
final(world, 70000000, 80000000, 90000000)
assert(table.concat(calls, ',') == 'update,render,update,render', 'Named cache changed native dispatch arguments/order')
print(
    'PASS native submission signatures, exact dispatch arguments/guards and one named type declaration across32module reloads/64initializations'
)
