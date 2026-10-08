local module = dofile('src/platform/update_check.lua')
local folder = 'tests/tmp/cache'
local launched = 0
local running = true
local windows = {
    launch_worker = function()
        launched = launched + 1
        return {
            running = function()
                return running
            end,
            stop = function()
                running = false
            end,
            close = function() end,
        }
    end,
}
local u = module.new(windows, folder, 'R4-rc1')
u.check()
u.check()
assert(launched == 1, 'Duplicate worker')
local f = assert(io.open(folder .. '/update-result.txt', 'wb'))
f:write('R5')
f:close()
u.tick(0.1)
assert(u.status:find('Update available: R5', 1, true))
running = true
u.check()
u.tick(21)
assert(u.status:find('unavailable', 1, true) and not running, 'Timeout not contained')
running = true
u.check()
f = assert(io.open(folder .. '/update-result.txt', 'wb'))
f:write('R3')
f:close()
u.tick(0.1)
assert(u.status:find('No newer release', 1, true), 'Older release prompted update')
running = true
u.check()
u.close()
assert(not running, 'Worker leaked on cleanup')
print('PASS updates: asynchronous single worker, newer/older versions, timeout, cleanup')
