local protocol = dofile('src/imports/import_protocol.lua')
local now = 0
local files = {}
local cancellations = {}
local jobs = dofile('src/imports/import_job.lua').new(protocol, {
    clock = function()
        return now
    end,
    read = function(path)
        return files[path]
    end,
    cancel = function(path)
        cancellations[path] = true
    end,
})
local function worker()
    local w = { pid = 42, alive = true, stopped = 0, closed = 0 }
    w.running = function()
        return w.alive
    end
    w.stop = function()
        w.alive = false
        w.stopped = w.stopped + 1
    end
    w.close = function()
        w.closed = w.closed + 1
    end
    return w
end
local first = worker()
jobs.start({ base = 'one', worker = first })
assert(not pcall(jobs.start, { base = 'second', worker = worker() }), 'Concurrent import allowed')
files['one.txt.progress'] = '42\textracting\t0\t30'
now = 1
assert(not jobs.poll() and jobs.job.percent == 30)
assert(jobs.cancel(true) and cancellations['one.txt.cancel'])
assert(not jobs.poll(), 'Retry emitted before old worker closed')
first.alive = false
assert(jobs.poll().kind == 'retry' and first.closed == 1 and not jobs.job)
jobs.close()
assert(first.closed == 1, 'Closed handle twice')
local second = worker()
jobs.start({ base = 'two', worker = second })
files['two.txt'] = 'ok\nlut001.dds'
local result = jobs.poll()
assert(result.kind == 'result' and result.text == 'ok\nlut001.dds' and second.closed == 1)
local third = worker()
jobs.start({ base = 'three', worker = third })
now = 22
assert(jobs.poll().kind == 'error' and jobs.job.canceling == 22, 'Stalled worker not canceled')
assert(not jobs.close(), 'Active cancellation did not wait')
now = 27
assert(jobs.close() and third.stopped == 1 and third.closed == 1)
local fourth = worker()
jobs.start({ base = 'four', worker = fourth })
files['four.txt.progress'] = '77\tpicker\t27'
assert(jobs.poll().kind == 'error' and not jobs.job and fourth.closed == 1, 'Wrong worker heartbeat retained')
print('PASS import job: serialized workers, canonical cancellation, timeout, retry, results and close ownership')
