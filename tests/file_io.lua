local F = dofile('src/core/file_io.lua')
local original = io.open
local closed = 0
io.open = function()
    return {
        read = function()
            error('read failure')
        end,
        close = function()
            closed = closed + 1
            return true
        end,
    }
end
local ok, why = pcall(F.read, 'fixture', 8)
assert(not ok and why:find('read failure') and closed == 1, 'Read error leaked handle')
io.open = function()
    return {
        read = function()
            return '123456789'
        end,
        close = function()
            closed = closed + 1
            return true
        end,
    }
end
assert(not pcall(F.read, 'fixture', 8) and closed == 2, 'Oversized read accepted or handle leaked')
io.open = function()
    return {
        write = function()
            return nil, 'write failure'
        end,
        close = function()
            closed = closed + 1
            return true
        end,
    }
end
assert(not pcall(F.write, 'fixture', 'x') and closed == 3, 'Write failure accepted or handle leaked')
io.open = function()
    return nil, 'not found'
end
assert(F.read('fixture', 8, true) == nil and not pcall(F.read, 'fixture', 8), 'Optional/required reads disagree')
io.open = original
local requested, explicit_closed
local portable = F.new({ open = function(path, mode)
    requested = path .. ':' .. mode
    return {
        read = function() return nil, 'stream failure' end,
        close = function() explicit_closed = true; return true end,
    }
end })
ok, why = pcall(portable.read, 'Unicode fixture', 16)
assert(not ok and why:find('stream failure') and explicit_closed and requested == 'Unicode fixture:rb',
    'Portable stream read failure was swallowed as EOF')
for _, code in ipairs({2, 3, 5, 32}) do
    local failed = F.new({open = function() return nil, 'open status ' .. code, code end})
    local accepted = pcall(failed.read, 'fixture', 8, true)
    assert(accepted == (code == 2 or code == 3), 'Optional read mistook access/sharing failure for a missing file')
end
assert(not pcall(F.new, {}), 'Incomplete file service accepted')
print('PASS bounded file IO: closes failed reads/writes, rejects oversized content and handles missing optional files')
