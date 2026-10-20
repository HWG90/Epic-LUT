-- Host contract only: never reads or writes the Windows clipboard.
assert(_VERSION == 'Lua 5.1')
local Clipboard = dofile('src/platform/clipboard.lua')
local reads, writes, text = 0, 0, ''
local fail, result, reason = false, true, nil
local service = {
    get = function()
        reads = reads + 1
        if fail then error('host read failure') end
        return text, reason
    end,
    set = function(value)
        writes = writes + 1
        if fail then error('host write failure') end
        if result then text = value end
        return result, reason
    end,
}
local clip = Clipboard.new({ service = service })
assert(reads == 0 and writes == 0, 'Construction touched clipboard')
for _, value in ipairs({ '', 'ASCII', '\194\162', '\226\152\131', '\240\159\152\128',
    string.rep('x', 16384), string.rep('\194\162', 16384), string.rep('\240\159\152\128', 8192) }) do
    local ok, why = clip.set(value)
    assert(ok == true and why == nil and clip.get() == value, 'Valid Unicode text failed')
end
local invalid = { false, 1, {}, 'a\0b', '\128', '\192\128', '\193\191', '\194', '\194A',
    '\224\159\191', '\237\160\128', '\239\191', '\240\143\191\191', '\244\144\128\128',
    '\245\128\128\128', '\255', string.rep('x', 16385), string.rep('\240\159\152\128', 8193),
    string.rep('x', 32769) }
for _, value in ipairs(invalid) do
    local before = writes
    assert(clip.set(value) == false and writes == before, 'Invalid text reached host')
    text = value
    assert(clip.get() == nil, 'Invalid host text reached editor')
end
local before = writes
assert(clip.set(nil) == false and writes == before)
text, reason = nil, 'Host unavailable'
local value, why = clip.get()
assert(value == nil and why == reason)
result = false
local ok
ok, why = clip.set('valid')
assert(ok == false and why == reason)
fail = true
value, why = clip.get()
assert(value == nil and why == 'Clipboard read failed.')
ok, why = clip.set('valid')
assert(ok == false and why == 'Clipboard write failed.')
assert(not pcall(Clipboard.new, { service = {} }), 'Missing host methods accepted')
print('Portable clipboard contract PASS')
