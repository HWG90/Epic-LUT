-- Owns one external import worker. Emits events; never edits palettes or native gear.
local J = {}
local function read_file(path, limit)
    local file = io.open(path, 'rb')
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
    local file = assert(io.open(path, 'wb'))
    local ok, why = file:write('cancel')
    file:close()
    assert(ok, why)
end
function J.new(protocol, deps)
    deps = deps or {}
    local clock, read, cancel = deps.clock or os.time, deps.read or read_file, deps.cancel or cancel_file
    local self = { job = nil }
    local function finish(job)
        job.worker.close()
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
        cancel(protocol.paths(job.base).cancel)
        job.canceling, job.retry = clock(), retry
        return true
    end
    function self.poll()
        local job = self.job
        if not job then
            return
        end
        local now = clock()
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
                }
            end
            return
        end
        text = read(paths.result, protocol.MAX_RESULT + 1)
        if text then
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
            job.worker.stop()
            finish(job)
        end
    end
    function self.close()
        local job = self.job
        if not job then
            return true
        end
        if not job.canceling then
            self.cancel(false)
        end
        if job.worker.running() and clock() - job.canceling < 5 then
            return false
        end
        self.abort()
        return true
    end
    return self
end
return J
