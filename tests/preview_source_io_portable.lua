-- Production preview-cache controllers composed with the real shared file service.
local function load_module(path, modules)
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable({ m = modules }, { __index = _G }))
    return chunk()
end
local original_open = io.open
local function forbidden() error('Preview controller bypassed the shared file service', 0) end
io.open = forbidden

local function fixture(kind, bound, override, legacy)
    local authored = kind == 'authored'
    local files, denied = {}, {}
    local stats = { opens = 0, handles = 0, closes = 0, starts = 0, stops = 0,
        worker_closes = 0, running = 0, clocks = 0, decoded = 0, overrides = 0 }
    local clock, live, stop_ok = 0, true, true
    local cache = 'C:/LUT-Ω/cache'
    local folder = cache .. (authored and '/authored-poses-v2' or '/camo-patterns-v1')
    local scripts = cache .. (authored and '/authored-worker' or '/camo-worker')
    local stamp, decoded = string.rep('a', 64), { authored = true }
    local worker = { pid = 321 }
    function worker.running() stats.running = stats.running + 1; return live end
    function worker.stop()
        stats.stops = stats.stops + 1
        if stop_ok then live = false end
        return stop_ok
    end
    function worker.close()
        assert(not live, 'Closed a worker that is still running')
        stats.worker_closes = stats.worker_closes + 1
        assert(stats.worker_closes == 1, 'Closed the owned worker twice')
        return true
    end
    local platform = {}
    function platform.open(path, mode)
        stats.opens = stats.opens + 1
        if denied[path] then return nil, 'fixture access/sharing failure', denied[path] end
        assert(mode == 'rb' or mode == 'wb')
        if mode == 'rb' and files[path] == nil then return nil, 'missing fixture file', 2 end
        if mode == 'wb' then files[path] = '' end
        local closed, position = false, 1
        stats.handles = stats.handles + 1
        return {
            read = function(_, count)
                assert(not closed and mode == 'rb' and count > 0)
                if position > #files[path] then return nil end
                local bytes = files[path]:sub(position, position + count - 1)
                position = position + #bytes
                return bytes
            end,
            write = function(self, bytes)
                assert(not closed and mode == 'wb')
                files[path] = files[path] .. bytes
                return self
            end,
            close = function()
                assert(not closed, 'Closed a stream twice')
                closed = true; stats.closes = stats.closes + 1
                return true
            end,
        }
    end
    function platform.process_id() return 123 end
    function platform.executable_path() return 'C:/game/bin/helldivers2.exe' end
    function platform.launch_worker(args, directory)
        assert(directory == scripts and args:find('-OwnerPID 123', 1, true)
            and args:find('-GameData "C:/game/data"', 1, true))
        stats.starts = stats.starts + 1
        return worker
    end
    local modules = {
        platform = platform, camo_preview_script = '2320', camo_preview_reader = '2320',
        authored_preview_script = '2320', authored_preview_reader = '2320', original_snapshot_reader = '2320',
    }
    -- Exercise the production module's dynamic m.platform route, plus its bound-instance API.
    modules.file_io = load_module('src/core/file_io.lua', modules)
    if bound then modules.file_io = modules.file_io.new(platform) end
    modules.windows = load_module('src/platform/windows.lua', modules)
    modules.player_authored_clip = { load = function(path)
        assert(path == folder .. '/' .. stamp, 'Decoded outside the verified authored cache')
        stats.decoded = stats.decoded + 1
        return decoded
    end }
    local host = {
        paths = { cache = cache, directory_exists = function() return true end },
        time = function() stats.clocks = stats.clocks + 1; return clock end,
    }
    if override then
        local shared = modules.file_io
        host.io = { open = function(...)
            stats.overrides = stats.overrides + 1
            return shared.open(...)
        end }
        modules.file_io = { open = function() error('Ignored explicit host.io', 0) end }
    elseif legacy then
        modules.file_io = nil
        io.open = platform.open
    end
    local Source = load_module(authored and 'src/preview/player_authored_source.lua'
        or 'src/preview/camo_patterns.lua', modules)
    local source = Source.new(modules, host)
    local result = { source = source, stats = stats, files = files, denied = denied,
        worker = worker, folder = folder, scripts = scripts, decoded = decoded }
    function result.advance(value) clock = value end
    function result.finished() live = false end
    function result.refuse_stop(value) stop_ok = not value end
    function result.complete()
        files[folder .. '/complete.txt'] = folder .. '/' .. stamp .. '\n' .. (authored and '2' or '1') .. '\n'
        if not authored then
            for index = 0, 5 do files[folder .. '/' .. stamp .. '/mask-' .. index .. '.rgba'] = string.rep(string.char(index), 1024) end
        end
    end
    function result.balanced() assert(stats.handles == stats.closes, 'Preview source leaked a file handle') end
    return result
end

local function idle(f, count)
    local stats = f.stats
    local opens, closes, starts, running, clocks = stats.opens, stats.closes, stats.starts, stats.running, stats.clocks
    for _ = 1, count do f.source.tick() end
    assert(stats.opens == opens and stats.closes == closes and stats.starts == starts
        and stats.running == running and stats.clocks == clocks, 'Inactive preview source performed work')
end

for _, kind in ipairs({ 'camo', 'authored' }) do
    for _, bound in ipairs({ false, true }) do
        local f = fixture(kind, bound)
        idle(f, 1000)
        f.source.start(); f.source.start()
        assert(f.source.state == 'loading' and f.source.worker == f.worker and f.stats.starts == 1)
        assert(f.files[f.folder .. '/owner-heartbeat.txt'] == '123')
        local opens = f.stats.opens
        f.advance(0.24); f.source.tick()
        assert(f.stats.opens == opens and f.stats.running == 0, 'Sampled a worker before the bounded interval')
        f.advance(0.26); f.source.tick()
        assert(f.stats.running == 1 and f.source.get() == nil)
        opens = f.stats.opens
        for _ = 1, 1000 do f.source.tick() end
        assert(f.stats.opens == opens and f.stats.running == 1, 'Repeated work within one active interval')
        f.complete(); f.finished(); f.advance(0.52); f.source.tick()
        assert(f.source.state == 'ready' and f.stats.worker_closes == 1 and f.source.worker == nil)
        if kind == 'authored' then assert(f.source.get() == f.decoded and f.stats.decoded == 1)
        else
            local data = f.source.get()
            assert(data.width == 16 and data.height == 16 and #data.layers == 6)
            for index = 1, 6 do assert(data.layers[index] == string.rep(string.char(index - 1), 1024)) end
        end
        idle(f, 1000)
        assert(f.source.close()); idle(f, 1000); f.balanced()
    end
    for _, code in ipairs({ 5, 32 }) do
        local f = fixture(kind)
        f.source.start(); f.complete(); f.finished()
        f.denied[f.folder .. '/error.txt'] = code
        f.advance(0.3); f.source.tick()
        assert(f.source.state == 'failed' and f.source.get() == nil
            and f.source.error:find('access/sharing', 1, true), 'Treated unreadable worker error as absent')
        idle(f, 1000); assert(f.source.close()); f.balanced()
    end
    do
        local f = fixture(kind)
        f.source.start(); f.refuse_stop(true)
        assert(not f.source.close() and f.source.worker == f.worker and f.stats.worker_closes == 0,
            'Forgot exact worker after refused cancellation')
        f.refuse_stop(false)
        assert(f.source.close() and f.source.worker == nil and f.stats.worker_closes == 1)
        assert(f.files[f.folder .. '/progress.txt.cancel'] == 'cancel')
        idle(f, 1000); f.balanced()
    end
    do
        local f = fixture(kind)
        f.source.start(); f.advance(191); f.source.tick()
        assert(f.source.state == 'failed' and f.source.worker == nil and f.stats.stops == 1 and f.stats.worker_closes == 1)
        idle(f, 1000); assert(f.source.close()); f.balanced()
    end
    do
        local f = fixture(kind, false, true)
        f.source.start(); assert(f.source.state == 'loading' and f.stats.overrides > 0)
        assert(f.source.close()); f.balanced()
    end
    do
        local f = fixture(kind, false, false, true)
        f.source.start(); assert(f.source.state == 'loading', 'Legacy nil-file-service fallback changed')
        assert(f.source.close()); f.balanced()
        io.open = forbidden
    end
end
io.open = original_open
print('PASS preview cache IO: production shared/bound services, Unicode, explicit override/legacy fallback, denied reads, exact worker cleanup and zero idle IO')
