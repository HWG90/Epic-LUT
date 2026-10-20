-- Explicit owned worker launch state. The caller supplies its active-tick budget.
-- No timers, retry loop, provisional PID, or work while the caller is idle.
local L = {}
local function worker(value)
    assert(type(value) == 'table', 'Owned worker launch returned no worker')
    for _, name in ipairs({ 'running', 'stop', 'close' }) do
        assert(type(value[name]) == 'function', 'Owned worker interface missing ' .. name)
    end
    return value
end
function L.start(windows, args, folder)
    local self = { phase = 'pending', async = windows.supports_async_workers
        and windows.supports_async_workers() == true or false }
    if self.async then
        self.future = assert(windows.begin_worker(args, folder), 'Owned worker launch unavailable')
        assert(type(self.future) == 'table' and self.future.pid == nil
            and type(self.future.status) == 'function' and type(self.future.cancel) == 'function',
            'Invalid owned worker launch interface')
    else
        self.worker, self.phase = worker(windows.launch_worker(args, folder)), 'ready'
    end
    function self.advance()
        if self.future then
            local ok, phase, value = pcall(self.future.status)
            if not ok then self.error = tostring(phase); return 'pending', self.error end -- Cleanup is uncertain.
            if phase == 'ready' then
                local valid, exact = pcall(worker, value)
                if not valid then self.error = tostring(exact); return 'pending', self.error end
                self.worker, self.future, self.phase, self.error = exact, nil, 'ready', nil
            elseif phase == 'pending' then return 'pending'
            elseif phase == 'error' or phase == 'cancelled' then
                self.future, self.phase, self.error = nil, phase, value
            else self.error = 'Invalid owned worker launch status'; return 'pending', self.error end
        end
        return self.phase, self.phase == 'ready' and self.worker or self.error
    end
    function self.detach()
        if self.future then return false, 'Owned worker launch is pending' end
        if not self.worker then return true end
        local ok, done, why = pcall(self.worker.close)
        if not ok or done == false then return false, tostring(ok and why or done) end
        self.worker, self.phase = nil, 'released'
        return true
    end
    function self.release()
        if self.future then return false, 'Owned worker launch is pending' end
        if self.worker then
            local ok, running = pcall(self.worker.running)
            if not ok or running then return false, ok and 'Owned worker is still running' or tostring(running) end
        end
        return self.detach()
    end
    function self.cancel()
        if self.future then
            local ok, done, why = pcall(self.future.cancel)
            if ok and done == true then
                self.future, self.phase = nil, 'cancelled'
                return true
            end
            -- A launch may have completed just before cancellation. Adopt that
            -- exact ready worker and stop it; never discard an uncertain future.
            local phase, detail = self.advance()
            if self.future then return false, tostring(ok and why or done) end
            if phase == 'error' or phase == 'cancelled' then return true end
            if phase ~= 'ready' then return false, detail or 'Owned worker launch cleanup pending' end
        end
        if self.worker then
            local ok, done, why = pcall(self.worker.stop)
            if not ok or done == false then return false, tostring(ok and why or done) end
            return self.release()
        end
        return true
    end
    return self
end
return L
