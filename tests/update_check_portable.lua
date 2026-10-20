-- Production async update controller with an explicit owned file/worker service.
local chunk = assert(loadfile('src/platform/update_check.lua'))
local function forbidden() error('Global IO must not be used') end
setfenv(chunk, setmetatable({ io = { open = forbidden }, os = { remove = forbidden } }, { __index = _G }))
local Update = chunk()
local contents, opens, removals = {}, 0, 0
local workers, launches = {}, 0
local files = {
    open = function(path, mode)
        opens = opens + 1
        if mode == 'rb' and not contents[path] then return nil end
        local closed = false
        if mode == 'wb' then contents[path] = '' end
        return {
            write = function(_, bytes) assert(not closed); contents[path] = contents[path] .. bytes; return true end,
            read = function(_, count) assert(not closed); return contents[path]:sub(1, count) end,
            close = function() assert(not closed); closed = true; return true end,
        }
    end,
    remove = function(path) removals = removals + 1; contents[path] = nil; return true end,
}
local windows = {
    launch_worker = function(args, folder)
        assert(folder == 'private/cache')
        assert(args:find('check-updates.ps1', 1, true) or args:find('Start-Process', 1, true))
        launches = launches + 1
        local state = { running = true, stops = 0, closed = false }
        workers[#workers + 1] = state
        return {
            running = function() assert(not state.closed); return state.running end,
            stop = function() assert(not state.closed); state.running = false; state.stops = state.stops + 1 end,
            close = function() state.closed = true end,
        }
    end,
}
local u = Update.new(windows, 'private/cache', 'R5.9.3', files)
for _ = 1, 1000 do u.tick(1) end
assert(opens == 0 and removals == 0 and launches == 0, 'Idle controller performed file/worker IO')
u.check(); u.check()
assert(launches == 1 and removals == 1 and contents['private/cache/check-updates.ps1']:find('Invoke-RestMethod', 1, true))
contents['private/cache/update-result.txt'] = 'R6'
u.tick(0.01)
assert(u.status:find('Update available: R6', 1, true) and workers[1].closed and workers[1].stops == 1)
local prior_opens, prior_removals = opens, removals
for _ = 1, 1000 do u.tick(1) end
assert(opens == prior_opens and removals == prior_removals and launches == 1, 'Finished controller kept polling')
u.check(); u.tick(21)
assert(u.status:find('unavailable', 1, true) and workers[2].closed and workers[2].stops == 1)
u.check(); u.close()
assert(workers[3].closed and workers[3].stops == 1)
u.open()
assert(workers[4].closed and workers[4].stops == 0, 'Opening release page terminated the detached worker')
for _, failure in ipairs({ 'write', 'close' }) do
    local closed, before = false, launches
    local failing_files = { remove = function() return true end, open = function()
        return { write = function() return failure ~= 'write' and true or nil, 'Write failed' end,
            close = function() closed = true; return failure ~= 'close' and true or nil, 'Close failed' end }
    end }
    local failed = Update.new(windows, 'private/cache', 'R5.9.3', failing_files)
    assert(not pcall(failed.check) and closed and launches == before, 'Incomplete worker script was launched')
end
print('PASS portable update check: injected files, bounded owned worker, timeout, cleanup and zero idle IO')
