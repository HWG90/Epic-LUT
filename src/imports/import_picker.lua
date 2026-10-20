-- Request orchestration around import_job. Session acceptance and gear writes
-- remain in the editor; jobs.job is the sole authority for worker lifetime.
local P = {}
local phases = {
    starting = 'Opening file picker...',
    picker = 'Waiting for file selection...',
    reading = 'Reading archive...',
    extracting = 'Extracting LUTs...',
}
function P.new(deps)
    local jobs, paths = deps.jobs, deps.paths
    local launches = deps.worker_launch or (m and m.worker_launch) or require('src.platform.worker_launch')
    local clock, open = deps.clock or os.time, deps.open or (m and m.file_io and m.file_io.open) or io.open
    local self, last_rows_mode = {}, nil
    local function sync()
        deps.on_job(jobs.job)
    end
    function self.load(pick, rows_mode)
        assert(not jobs.job, 'ZIP import is still pending')
        last_rows_mode = rows_mode
        deps.before_load(rows_mode)
        local name
        if not pick then
            name = deps.get('file')
            assert(
                type(name) == 'string' and #name > 0 and #name <= 48 and name:match('^[%w _-]+$'),
                'Enter the filename without its extension'
            )
            if deps.get('format') == 1 then
                return deps.load_direct(name)
            end
        end
        local native_import = deps.get_native_import()
        local pid
        if native_import.process_id then pid = native_import.process_id()
        else local _, kernel = native_import.verify_interface();pid = tonumber(kernel.epic_native_pid()) end
        assert(not paths.files:find('"', 1, true) and not paths.cache:find('"', 1, true), 'Invalid import path')
        local script = paths.cache .. '/import-zip.ps1'
        local f = assert(open(script, 'wb'))
        assert(f:write((deps.get_script_hex():gsub('%x%x', function(pair)
            return string.char(tonumber(pair, 16))
        end))))
        assert(f:close())
        deps.counter.value = deps.counter.value + 1
        local base = paths.cache .. '/zip-' .. pid .. '-' .. clock() .. '-' .. deps.counter.value
        local extension = deps.get('format') == 3 and '.rar' or '.zip'
        local input = pick and ' -Pick' or ' -Package "' .. paths.files .. '/' .. name .. extension .. '"'
        local args = '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'
            .. script
            .. '"'
            .. input
            .. (rows_mode and ' -RowPresets' or ' -Navigate')
            .. ' -Output "'
            .. base
            .. '" -Result "'
            .. base
            .. '.txt" -OwnerPID '
            .. pid
        local launch = launches.start(native_import, args, paths.cache)
        local menu = deps.get_menu()
        jobs.start({
            base = base,
            pick = pick,
            rows_mode = rows_mode,
            launch = launch,
            worker = launch.worker,
            menu_visible = menu and menu.visible,
            menu_page = menu and menu.page,
        })
        sync()
        return deps.message(
            rows_mode and 'Choose a Paydex row-presets JSON file.'
                or (
                    pick and 'Choose a DDS, ZIP, RAR or patch in the Windows file picker.'
                    or 'Extracting ZIP palettes. No Python is used.'
                )
        )
    end
    function self.cancel(retry)
        if not jobs.cancel(retry) then
            if retry then
                return self.load(true, last_rows_mode)
            end
            return deps.message('No import is running.')
        end
        sync()
        return deps.message(
            retry and 'Closing the previous picker before retrying...'
                or 'Canceling import; current palettes stay active.'
        )
    end
    local function poll()
        local event = jobs.poll()
        sync()
        if not event then
            return
        end
        if event.kind == 'result' then
            return deps.accept(event.text, event.job)
        end
        if event.kind == 'retry' then
            return self.load(true, event.job and event.job.rows_mode)
        end
        return deps.message(event.message)
    end
    function self.poll()
        local ok, result = pcall(poll)
        if not ok then
            pcall(jobs.abort)
            sync()
            return deps.message('Import stopped safely; editor remains available: ' .. tostring(result))
        end
        return result
    end
    function self.info()
        local job = jobs.job
        local phase = job and job.phase or ''
        return {
            busy = job ~= nil,
            detail = job and job.detail,
            phase = job and job.canceling and 'Canceling...' or phases[phase] or phase,
            progress = job and job.percent or 0,
            waiting = job and (job.phase == 'picker' or job.phase == 'starting'),
            elapsed = job and (clock() - job.started) or 0,
        }
    end
    function self.close()
        local closed = jobs.close()
        sync()
        return closed
    end
    return self
end
return P
