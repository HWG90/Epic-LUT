-- Only an injected memory driver is used: this never reads/writes the OS clipboard.
local ffi = require('ffi')
local Clipboard = dofile('src/platform/clipboard.lua')
local state = { closed = 0, unlocked = 0, freed = 0, emptied = 0 }
local snow = 'Nova ' .. string.char(226, 152, 131)
local driver = {}
function driver.to_wide(text)
    if text:find(string.char(255), 1, true) then
        return nil
    end
    local count = text == snow and 6 or #text
    local out = ffi.new('uint16_t[?]', count + 1)
    for i = 1, count do
        out[i - 1] = i == 6 and text == snow and 0x2603 or text:byte(i)
    end
    return out, count
end
function driver.from_wide(data, count)
    local out = {}
    for i = 0, count - 1 do
        out[#out + 1] = data[i] == 0x2603 and string.char(226, 152, 131) or string.char(data[i])
    end
    return table.concat(out)
end
function driver.open()
    return not state.busy
end
function driver.close()
    state.closed = state.closed + 1
end
function driver.alloc(bytes)
    if state.alloc_fail then
        return nil
    end
    return { size = bytes, data = ffi.new('uint16_t[?]', bytes / 2) }
end
function driver.free()
    state.freed = state.freed + 1
end
function driver.lock(handle)
    return not state.lock_fail and handle.data or nil
end
function driver.unlock()
    state.unlocked = state.unlocked + 1
end
function driver.size(handle)
    return handle.size
end
function driver.get()
    return state.clip
end
function driver.empty()
    state.emptied = state.emptied + 1
    return true
end
function driver.set(handle)
    if state.set_fail then
        return false
    end
    state.clip = handle
    return true
end
local service = Clipboard.new({
    driver = driver,
    window = function()
        return 1
    end,
})
assert(service.set(snow) and state.clip.data[6] == 0, 'Unicode clipboard lacked a terminator')
assert(service.get() == snow and state.freed == 0, 'Borrowed/transferred clipboard memory was freed')
assert(state.closed == 2 and state.unlocked == 2, 'Clipboard lock/open lifetime leaked')
local empty = state.emptied
assert(
    service.set(string.rep('x', Clipboard.MAX_BYTES + 1)) == false and state.emptied == empty,
    'Oversized text touched clipboard'
)
assert(service.set('A' .. string.char(0) .. 'B') == false, 'Embedded Unicode terminator was accepted')
assert(service.set(string.char(255)) == false and state.emptied == empty, 'Invalid UTF-8 emptied clipboard')
state.busy = true
assert(
    service.get() == nil and service.set('Color') == false and state.freed == 1,
    'Busy clipboard leaked prepared memory'
)
state.busy = false
state.set_fail = true
assert(service.set('Color') == false and state.freed == 2, 'Failed ownership transfer leaked memory')
state.set_fail = false
state.alloc_fail = true
empty = state.emptied
assert(service.set('Color') == false and state.emptied == empty, 'Allocation failure emptied clipboard')
state.alloc_fail = false
state.clip = { size = 4, data = ffi.new('uint16_t[2]', { 65, 66 }) }
local unlock = state.unlocked
assert(service.get() == nil and state.unlocked == unlock + 1, 'Unterminated clipboard read was accepted or left locked')
state.clip = { size = (Clipboard.MAX_UNITS + 2) * 2, data = ffi.new('uint16_t[1]') }
unlock = state.unlocked
assert(service.get() == nil and state.unlocked == unlock, 'Oversized borrowed buffer was read')
assert(service.set('') and service.get() == '', 'Empty Unicode clipboard did not round-trip')
print(
    'PASS clipboard: injected Unicode round-trip, strict size/encoding bounds, terminator checks and borrowed/transferred memory lifetime'
)
