local Picker = dofile('src/imports/import_picker.lua')
local Job = dofile('src/imports/import_job.lua')
local protocol = dofile('src/imports/import_protocol.lua')
local now, files, workers, messages, accepted = 100, {}, {}, {}, {}
local counter = { value = 10 }
local selection, menu, pending = { file = 'My palette', format = 1 }, nil, nil
local reads_fail, accept_fail, verifies, script_writes = false, false, 0, 0
local last_mode, regular_requests, direct_requests = nil, 0, {}
local script_hex = '41420a'
local function worker(args, cwd)
    local w = { pid = 84, alive = true, stopped = 0, closed = 0, args = args, cwd = cwd }
    function w.running()
        return w.alive
    end
    function w.stop()
        w.alive, w.stopped = false, w.stopped + 1
    end
    function w.close()
        if w.close_fail then
            error('Handle close temporarily failed', 0)
        end
        w.closed = w.closed + 1
    end
    workers[#workers + 1] = w
    return w
end
local native_import = {
    verify_interface = function()
        verifies = verifies + 1
        return true, {
            epic_native_pid = function()
                return 42
            end,
        }
    end,
    launch_worker = worker,
}
local jobs = Job.new(protocol, {
    clock = function()
        return now
    end,
    read = function(path)
        if reads_fail then
            error('Result read failed', 0)
        end
        return files[path]
    end,
    cancel = function(path)
        files[path] = 'cancel'
    end,
})
local deps = {
    jobs = jobs,
    paths = { files = 'test files', cache = 'test cache' },
    counter = counter,
    clock = function()
        return now
    end,
    open = function(path, mode)
        assert(path == 'test cache/import-zip.ps1' and mode == 'wb')
        local closed = false
        return {
            write = function(_, bytes)
                assert(not closed)
                files[path], script_writes = bytes, script_writes + 1
                return true
            end,
            close = function()
                closed = true
                return true
            end,
        }
    end,
    get = function(id)
        return selection[id]
    end,
    get_native_import = function()
        return native_import
    end,
    get_script_hex = function()
        return script_hex
    end,
    get_menu = function()
        return menu
    end,
    before_load = function(rows_mode)
        last_mode = rows_mode
        if not rows_mode then
            regular_requests = regular_requests + 1
        end
    end,
    load_direct = function(name)
        direct_requests[#direct_requests + 1] = name
        return 'Direct DDS accepted'
    end,
    accept = function(text, job)
        assert(not jobs.job and not pending, 'Acceptance ran before worker state was cleared')
        assert(job.worker.closed == 1, 'Acceptance ran before the worker handle closed')
        if accept_fail then
            error('Session acceptance failed', 0)
        end
        accepted[#accepted + 1] = { text = text, job = job }
        return 'Result accepted'
    end,
    message = function(text)
        messages[#messages + 1] = text
        return text
    end,
    on_job = function(job)
        assert(job == jobs.job)
        pending = job
    end,
}
local picker = Picker.new(deps)
assert(picker.load() == 'Direct DDS accepted' and direct_requests[1] == 'My palette')
assert(verifies == 0 and #workers == 0 and script_writes == 0 and counter.value == 10)
assert(regular_requests == 1 and last_mode == nil and not picker.info().busy)
selection.file = '../bad'
assert(not pcall(picker.load) and verifies == 0, 'Invalid direct filename launched a worker')
selection.file, selection.format = 'My palette', 3
menu = { visible = true, page = 2 }
assert(picker.load():find('Extracting ZIP', 1, true))
local first = assert(pending)
assert(first == jobs.job and first.base == 'test cache/zip-42-100-11')
assert(files['test cache/import-zip.ps1'] == 'AB\n')
assert(
    first.worker.args
        == '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "test cache/import-zip.ps1" -Package "test files/My palette.rar" -Navigate -Output "test cache/zip-42-100-11" -Result "test cache/zip-42-100-11.txt" -OwnerPID 42'
)
assert(first.worker.cwd == 'test cache' and first.menu_visible and first.menu_page == 2)
local request_count = regular_requests
assert(not pcall(picker.load, true, true) and #workers == 1 and regular_requests == request_count)
menu.visible, menu.page = false, 4
now = 101
files[protocol.paths(first.base).progress] = '84\textracting\t101\t70\tTwo tables'
picker.poll()
local info = picker.info()
assert(
    info.busy
        and info.detail == 'Two tables'
        and info.phase == 'Extracting LUTs...'
        and info.progress == 70
        and info.waiting == false
        and info.elapsed == 1
)
first.worker.alive = false
files[protocol.paths(first.base).result] = 'ok\nlut001.dds'
assert(picker.poll() == 'Result accepted')
assert(#accepted == 1 and accepted[1].job == first and first.worker.closed == 1)
assert(first.menu_visible and first.menu_page == 2, 'Launch menu snapshot changed while picker ran')
picker.poll()
assert(#accepted == 1 and not pending and not picker.info().busy, 'Result was accepted twice')

-- Rows retry preserves the current session's mode, waits for the old worker,
-- and never invokes the regular-import resume reset callback.
request_count = regular_requests
assert(picker.load(true, true):find('Paydex', 1, true))
local row = pending
assert(last_mode == true and regular_requests == request_count)
assert(row.worker.args:find(' -Pick -RowPresets ', 1, true) and not row.worker.args:find(' -Navigate ', 1, true))
assert(picker.cancel(true):find('before retrying', 1, true))
assert(pending == row and picker.info().phase == 'Canceling...')
picker.poll()
assert(pending == row and #workers == 2, 'Retry launched before previous worker closed')
row.worker.alive = false
picker.poll()
local retried = pending
assert(row.worker.closed == 1 and #workers == 3 and retried.rows_mode == true)
assert(retried.worker.args:find(' -RowPresets ', 1, true) and regular_requests == request_count)
picker.cancel(false)
retried.worker.alive = false
picker.poll()
assert(not pending and retried.worker.closed == 1)
picker.cancel(true)
assert(pending.rows_mode == true and regular_requests == request_count, 'Idle retry discarded the last rows mode')
local deferred = pending
assert(not picker.close() and pending == deferred and jobs.job == deferred, 'Pending cleanup lost its job')
now = now + 5
assert(picker.close() and deferred.worker.closed == 1 and not pending)

-- A new activation uses the retained counter, but resolves adapters/script/menu
-- lazily and starts with a fresh retry mode instead of inheriting Rows mode.
picker = Picker.new(deps)
native_import = {
    verify_interface = function()
        return true, {
            epic_native_pid = function()
                return 43
            end,
        }
    end,
    launch_worker = worker,
}
script_hex, menu = '4344', nil
picker.cancel(true)
local lazy = pending
assert(lazy.base == 'test cache/zip-43-106-15' and counter.value == 15)
assert(lazy.rows_mode == nil and lazy.menu_visible == nil and lazy.menu_page == nil)
assert(lazy.worker.args:find(' -Pick -Navigate ', 1, true) and files['test cache/import-zip.ps1'] == 'CD')
reads_fail = true
assert(picker.poll():find('Import stopped safely; editor remains available: Result read failed', 1, true))
assert(lazy.worker.stopped == 1 and lazy.worker.closed == 1 and not pending)
reads_fail = false

picker.load(true)
local failed_accept = pending
failed_accept.worker.alive = false
files[protocol.paths(failed_accept.base).result] = 'ok\nlut002.dds'
accept_fail = true
assert(picker.poll():find('Session acceptance failed', 1, true))
assert(not pending and failed_accept.worker.closed == 1 and #accepted == 1)
accept_fail = false
picker.poll()
assert(#accepted == 1, 'Failed acceptance was replayed')

-- Even if abort cannot close a handle, pending must continue to mirror the
-- worker authority rather than permitting a second launch over leaked cleanup.
picker.load(true)
local failed_close = pending
failed_close.worker.close_fail, reads_fail = true, true
picker.poll()
assert(pending == jobs.job and pending == failed_close and picker.info().busy)
assert(not pcall(picker.load, true), 'Failed abort allowed another worker')
failed_close.worker.close_fail, reads_fail = false, false
assert(picker.close() and not pending and failed_close.worker.closed == 1)
assert(picker.cancel(false) == 'No import is running.')
print(
    'PASS import picker: direct DDS bypass, exact launch flags, lazy dependencies, retained counter, row retry, result acceptance after close, progress, error recovery and deferred cleanup'
)
