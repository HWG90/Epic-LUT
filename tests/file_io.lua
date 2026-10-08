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
print('PASS bounded file IO: closes failed reads/writes, rejects oversized content and handles missing optional files')
