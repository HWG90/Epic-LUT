-- Owns one external import worker. Emits events; never edits palettes or native gear.
local J = {}
local open_file = m and m.file_io and m.file_io.open or io.open
local function read_file(path, limit)
    local file = open_file(path, 'rb')
    if not file then
        return
    end
    local ok, text = pcall(file.read, file, limit)
    file:close()
    if not ok then
        error(text, 0)
    end
    return text or ''
end
local function cancel_file(path)
    local file = assert(open_file(path, 'wb'))
    local ok, why = file:write('cancel')
    file:close()
    assert(ok, why)
end
function J.new(protocol, deps)
    deps = deps or {}
    local clock, read, cancel = deps.clock or os.time, deps.read or read_file, deps.cancel or cancel_file
    local self = { job = nil }
    local function finish(job)
        local done, why
        if job.launch then done, why = job.launch.release()
        elseif job.worker then done, why = job.worker.close() end
        assert(done ~= false, why or 'Import worker cleanup pending')
        if self.job == job then
            self.job = nil
        end
    end
    function self.start(job)
        assert(not self.job, 'ZIP import is still pending')
        local now = clock()
        job.started, job.last_beat, job.phase = now, now, 'starting'
        self.job = job
        return job
    end
    function self.cancel(retry)
        local job = self.job
        if not job then
            return false
        end
        if job.worker then cancel(protocol.paths(job.base).cancel) end
        job.canceling, job.retry = clock(), retry
        return true
    end
    function self.poll()
        local job = self.job
        if not job then
            return
        end
        if job.launch_exhausted then return end
        local now = clock()
        if job.launch and job.launch.async then
            if job.last_poll and now - job.last_poll < 0.25 then return end
            job.last_poll = now
        end
        if job.launch and not job.worker then
            -- Only an active launch is checked; no progress/PID reads until the
            -- helper has returned the actual owned worker. Cap automatic work.
            if job.launch_last and now - job.launch_last < 0.25 then return end
            job.launch_last = now
            job.launch_checks = (job.launch_checks or 0) + 1
            if job.launch_checks > 128 then
                job.launch_exhausted = true
                return { kind = 'error', message = 'Import launch cleanup is still pending; close before retrying.' }
            end
            if now - job.started > 20 and not job.canceling then self.cancel(false) end
            if job.canceling then
                local done = job.launch.cancel()
                if not done then return end
                self.job = nil
                return { kind = job.retry and 'retry' or 'canceled', job = job,
                    message = 'Import canceled; current palette retained.' }
            end
            local state, value = job.launch.advance()
            if state == 'pending' then return end
            if state ~= 'ready' then
                if job.launch.future then return end
                self.job = nil
                return { kind = 'error', message = tostring(value or 'Import worker launch canceled') }
            end
            job.worker = value
            job.last_beat = now
        end
        local paths = protocol.paths(job.base)
        local text = read(paths.progress, protocol.MAX_PROGRESS + 1)
        if text then
            local state = protocol.progress(text, job.worker.pid, now)
            if not state then
                job.worker.stop()
                finish(job)
                return { kind = 'error', message = 'Invalid picker state. Retry file picker to recover.' }
            end
            for key, value in pairs(state) do
                job[key] = value
            end
        end
        if job.canceling then
            if not job.worker.running() or now - job.canceling >= 5 then
                job.worker.stop()
                finish(job)
                return {
                    kind = job.retry and 'retry' or 'canceled',
                    message = 'Import canceled; current palette retained.',
                    job = job,
                }
            end
            return
        end
        text = read(paths.result, protocol.MAX_RESULT + 1)
        if text then
            if job.launch and job.worker.running() then return end
            finish(job)
            return { kind = 'result', text = text, job = job }
        end
        if not job.worker.running() then
            finish(job)
            return { kind = 'error', message = 'File picker exited without a result. Retry file picker.' }
        end
        local stalled = now - job.last_beat > (job.reported and 10 or 20)
        if stalled or now - job.started > 300 then
            self.cancel(false)
            return {
                kind = 'error',
                message = stalled and 'File picker stopped responding; recovering...'
                    or 'File picker timed out; recovering...',
            }
        end
    end
    function self.abort()
        local job = self.job
        if job then
            if job.launch then
                local done = job.launch.cancel()
                if not done then return false end
                self.job = nil
                return true
            end
            job.worker.stop()
            finish(job)
        end
        return true
    end
    function self.close()
        local job = self.job
        if not job then
            return true
        end
        if job.launch and job.launch.async then
            local now = clock()
            if job.cleanup_poll and now - job.cleanup_poll < 0.25 then return false end
            job.cleanup_poll = now
        end
        if job.launch and not job.worker then
            job.canceling = job.canceling or clock()
            -- Explicit cleanup can retry an owner retained after a bounded
            -- active launch; do not lose it on a failed cancellation.
            if job.launch_last and clock() - job.launch_last < 0.25 then return false end
            job.launch_last = clock()
            if not job.launch.cancel() then return false end
            self.job = nil
            return true
        end
        if not job.canceling then
            self.cancel(false)
        end
        if job.worker.running() and clock() - job.canceling < 5 then
            return false
        end
        return self.abort()
    end
    return self
end
return J
