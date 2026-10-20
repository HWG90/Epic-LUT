-- Protected calls that may yield, supported by stock Lua 5.1.
-- Used only by explicitly scheduled jobs; no timers or background polling.
local C = {}
local function pack(...) return { n = select('#', ...), ... } end
function C.call(fn, ...)
    assert(type(fn) == 'function', 'Cooperative function required')
    local thread = coroutine.create(fn)
    local values = pack(coroutine.resume(thread, ...))
    while values[1] and coroutine.status(thread) ~= 'dead' do
        -- Match pcall failure when a yielding operation is used synchronously.
        if not coroutine.running() then return false, 'Cooperative call requires a scheduled coroutine' end
        local resumed = pack(coroutine.yield(unpack(values, 2, values.n)))
        values = pack(coroutine.resume(thread, unpack(resumed, 1, resumed.n)))
    end
    return unpack(values, 1, values.n)
end
return C
