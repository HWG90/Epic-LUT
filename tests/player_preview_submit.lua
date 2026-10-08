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
        assert(unused == nil and window == nil and flags == 0 and context == 0)
        calls[#calls + 1] = 'render'
    end,
}
local submit = S.new(memory, game, exe, dependencies)
submit(world, 70000000, 80000000, 90000000)
assert(table.concat(calls, ',') == 'update,render')
pointer(app + 0x28, exe + 0x318151)
assert(not pcall(submit, world, 70000000, 80000000, 90000000) and #calls == 2, 'Changed native dispatch was called')
assert(not pcall(S.new, memory, game, exe, dependencies), 'Changed entry was accepted')
print('PASS native submission signatures, world unboxing, exact arguments and dispatch drift refusal')
