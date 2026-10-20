-- Actual setup/DDs persistence + portable atomic publication, no native interface.
assert(_VERSION == 'Lua 5.1')
local previous_require, previous_open, previous_remove, previous_rename = require, io.open, os.remove, os.rename
ffi, bit, jit = nil, nil, nil
require = function(name)
    assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
    return previous_require(name)
end
local bytes = {}
io.open = function(path, mode)
    if mode == 'wb' then
        bytes[path] = ''
        local closed = false
        return {
            write = function(self, ...)
                assert(not closed)
                bytes[path] = bytes[path] .. table.concat({ ... })
                return self
            end,
            close = function() closed = true;return true end,
        }
    end
    assert(mode == 'rb')
    if bytes[path] == nil then return nil, 'not found' end
    return {
        read = function(_, count) return count == '*a' and bytes[path] or bytes[path]:sub(1, count) end,
        close = function() return true end,
    }
end
os.remove = function(path) bytes[path] = nil;return true end
os.rename = function(source, destination)
    if bytes[source] == nil or bytes[destination] ~= nil then return false, 'rename failed' end
    bytes[destination], bytes[source] = bytes[source], nil
    return true
end
local B = dofile('src/core/float_buffer.lua')
local D = dofile('src/core/dds.lua')
local fail_replace, replacements = false, 0
local windows = dofile('src/platform/windows.lua').new({
    replace = function(source, destination)
        replacements = replacements + 1
        assert(bytes[source] and source == destination .. '.pending')
        if fail_replace then return false, 'Atomic publish failed' end
        bytes[destination], bytes[source] = bytes[source], nil
        return true
    end,
})
local paths = { settings = 'test settings', presets = 'test palettes' }
local m = { dds = D, file_io = dofile('src/core/file_io.lua'), native_import = windows, windows = windows }
local setup = dofile('src/gear/direct_setup.lua').new(m, paths)
local armor = { width = 23, height = 1, data = B.new(92) }
local pattern = { width = 3, height = 1, data = B.new(12) }
armor.data[0], armor.data[91], pattern.data[11] = -1.25, 2.375, 0.5
local bindings = {
    { save_key = '0:1:0:0', texture = armor }, { save_key = 'p:0:1:0:0', texture = pattern },
}
assert(setup.save(bindings, {}) == 2 and replacements == 1)
local plan = setup.read()
assert(plan['0:1:0:0'] and plan['p:0:1:0:0'])
for _, key in ipairs({ '0:1:0:0', 'p:0:1:0:0' }) do
    local payload = bytes[paths.presets .. '/' .. plan[key]]
    local data, width, height = D.decode(payload)
    local expected = key:sub(1, 2) == 'p:' and pattern or armor
    assert(width == expected.width and height == 1 and B.bytes(data, width * height * 4) == B.bytes(expected.data, width * height * 4))
end
local manifest = paths.settings .. '/direct-applied.tsv'
local original = bytes[manifest]
fail_replace = true
assert(not pcall(setup.save, { bindings[1] }, {}) and replacements == 2)
assert(bytes[manifest] == original, 'Failed atomic setup publication replaced previous manifest')
assert(setup.read()['p:0:1:0:0'], 'Failed setup publication discarded the prior pattern')
setup.clear()
assert(next(setup.read()) == nil)
io.open, os.remove, os.rename, require = previous_open, previous_remove, previous_rename, previous_require
print('PASS portable applied setup: production DDS snapshots, exact floats, Windows.replace publication and retained previous manifest on failure')
