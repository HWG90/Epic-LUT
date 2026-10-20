-- Exercise production consumers across the real shared launch owner.
local Launch = dofile('src/platform/worker_launch.lua')
local Update = dofile('src/platform/update_check.lua')
local Job = dofile('src/imports/import_job.lua')
local protocol = dofile('src/imports/import_protocol.lua')
local phases, futures, launches = {}, {}, 0
local function new_worker()
    local w = { pid = 42, alive = true, stopped = 0, closed = 0 }
    function w.running() return w.alive end
    function w.stop() w.alive, w.stopped = false, w.stopped + 1; return true end
    function w.close() w.closed = w.closed + 1; return true end
    return w
end
local windows = { supports_async_workers = function() return true end,
    launch_worker = function() error('Synchronous launch used') end }
function windows.begin_worker()
    launches = launches + 1
    local f = { phase = 'pending', queries = 0, cancels = 0, retired = false }
    function f.status()
        f.queries = f.queries + 1
        if f.throw then error('Transport unavailable') end
        return f.phase, f.value
    end
    function f.cancel()
        f.cancels = f.cancels + 1
        return f.retired, f.retired and nil or 'Cleanup pending'
    end
    futures[#futures + 1] = f
    return f
end
local data, reads, writes = {}, 0, 0
local files = { remove = function(p) data[p] = nil; return true end }
function files.open(p, mode)
    if mode == 'rb' then
        reads = reads + 1
        if not data[p] then return nil end
        return { read = function() return data[p] end, close = function() return true end }
    end
    return { write = function(_, value) writes = writes + 1; data[p] = value; return true end,
        close = function() return true end }
end
local u = Update.new(windows, 'cache', 'R5.9.3', files)
for _ = 1, 1000 do u.tick(1) end
assert(launches == 0 and reads == 0 and writes == 0)
u.check(); u.check()
assert(launches == 1 and writes == 1)
local f, before = futures[1], reads
u.tick(0)
for _ = 1, 1000 do u.tick(0) end
assert(f.queries == 1 and reads == before, 'Pending update launch repeatedly checked or read result')
local w = new_worker()
f.phase, f.value = 'ready', w
data['cache/update-result.txt'] = 'R6'
u.tick(0.25)
assert(u.status:find('Update available', 1, true) and w.closed == 1 and w.stopped == 1)
before = reads
for _ = 1, 1000 do u.tick(1) end
assert(reads == before and f.queries == 2, 'Finished update still performed IO')
u.check(); f = futures[2]
u.tick(21)
assert(not u.close(), 'Unconfirmed future retirement was discarded')
u.check(); assert(launches == 2, 'Uncertain cleanup allowed a duplicate launch')
f.retired = true
assert(u.close())
u.open(); f = futures[3]
assert(f.queries == 0)
u.tick(0); assert(f.queries == 1)
w = new_worker(); f.phase, f.value = 'ready', w
u.tick(0.25)
assert(w.closed == 1 and w.stopped == 0 and u.status:find('Opened', 1, true), 'Browser launch was stopped or detached before real worker existed')
u.check(); f = futures[4]; f.throw = true
u.tick(0)
assert(not u.close(), 'Unknown future transport failure lost its owner')
f.throw, f.retired = false, true
assert(u.close())

local now, cancel_files = 0, 0
local jobs = Job.new(protocol, { clock = function() return now end,
    read = function(path) reads = reads + 1; return data[path] end,
    cancel = function() cancel_files = cancel_files + 1 end })
local owner = Launch.start(windows, 'args', 'cache')
f = futures[#futures]
jobs.start({ base = 'import', launch = owner })
before = reads
jobs.poll()
for _ = 1, 1000 do jobs.poll() end
assert(f.queries == 1 and reads == before and not jobs.job.worker)
w = new_worker(); f.phase, f.value = 'ready', w
now = 0.25
data['import.txt'] = 'ok\nlut001.dds'
assert(not jobs.poll() and jobs.job.worker == w, 'Result accepted before real worker completion')
w.alive = false
now = now + 0.25
local event = jobs.poll()
assert(event.kind == 'result' and event.text == data['import.txt'] and w.closed == 1 and not jobs.job)
before = reads
for _ = 1, 1000 do jobs.poll() end
assert(reads == before)
owner = Launch.start(windows, 'args', 'cache'); f = futures[#futures]
jobs.start({ base = 'cancel', launch = owner })
assert(jobs.cancel(true) and cancel_files == 0, 'Pending launch used a guessed PID or worker file')
assert(not jobs.poll() and jobs.job, 'Cancel ACK was treated as completion')
assert(not jobs.close())
now, f.retired = now + 0.25, true
event = jobs.poll()
assert(event.kind == 'retry' and not jobs.job)
owner = Launch.start(windows, 'args', 'cache'); f = futures[#futures]
jobs.start({ base = 'uncertain', launch = owner }); f.throw = true
jobs.poll()
assert(jobs.job and jobs.job.launch == owner, 'Transport failure discarded pending import owner')
f.throw, f.retired, now = false, true, now + 0.25
assert(jobs.close() and not jobs.job)
owner = Launch.start(windows, 'args', 'cache'); f = futures[#futures]
jobs.start({ base = 'bounded', launch = owner })
for _ = 1, 129 do now = now + 0.25; jobs.poll() end
assert(jobs.job and jobs.job.launch_exhausted, 'Active launch checks were not capped')
local queries, cancels = f.queries, f.cancels
for _ = 1, 1000 do now = now + 1; jobs.poll() end
assert(f.queries == queries and f.cancels == cancels, 'Exhausted launch kept polling')
f.retired = true
assert(jobs.close())
print('PASS asynchronous worker consumers: exact readiness, bounded active checks, retained cancellation and zero idle IO')
