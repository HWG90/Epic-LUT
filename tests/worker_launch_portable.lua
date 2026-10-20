-- Real shared ownership helper + production cache controllers under stock Lua 5.1.
local Launch = dofile('src/platform/worker_launch.lua')
local function worker()
    local w = { pid = 345, live = true, stop_ok = true, close_ok = true, stops = 0, closes = 0 }
    function w.running() return w.live end
    function w.stop() w.stops = w.stops + 1; if w.stop_ok then w.live = false end; return w.stop_ok end
    function w.close() w.closes = w.closes + 1; return w.close_ok end
    return w
end
local function future()
    local f = { phase = 'pending', checks = 0, cancels = 0, retired = false, exact = worker() }
    function f.status()
        f.checks = f.checks + 1
        if f.throw then error('injected status transport failure') end
        return f.phase, f.phase == 'ready' and f.exact or f.reason
    end
    function f.cancel()
        f.cancels = f.cancels + 1
        if f.retired then return true end
        return false, 'cleanup pending'
    end
    return f
end
local function windows(f)
    return { supports_async_workers = function() return true end,
        begin_worker = function() return f end,
        launch_worker = function() error('Async host used synchronous worker launch') end }
end
-- Pending, malformed or thrown replies never become terminal ownership receipts.
for _, fault in ipairs({ 'throw', 'malformed', 'bad-worker' }) do
    local f = future()
    if fault == 'throw' then f.throw = true
    elseif fault == 'malformed' then f.phase = 'foreign'
    else f.phase, f.exact = 'ready', {} end
    local owner = Launch.start(windows(f), 'args', 'folder')
    assert(owner.worker == nil and owner.future == f and owner.future.pid == nil)
    local phase, why = owner.advance()
    assert(phase == 'pending' and type(why) == 'string' and owner.error and owner.future == f)
    assert(not owner.cancel() and owner.future == f, 'Forgot uncertain pending ownership')
    f.retired = true
    assert(owner.cancel() and owner.future == nil)
end
local f = future()
local owner = Launch.start(windows(f), 'args', 'folder')
f.phase = 'ready' -- Cancellation races a completed launch; adopt only this worker.
assert(owner.cancel() and f.exact.stops == 1 and f.exact.closes == 1 and not owner.worker)
f = future(); owner = Launch.start(windows(f), 'args', 'folder'); f.phase = 'ready'
local phase, exact = owner.advance()
assert(phase == 'ready' and exact == f.exact and owner.worker == exact and not owner.future)
assert(not owner.release() and exact.stops == 0 and exact.closes == 0)
exact.close_ok = false
assert(not owner.detach() and owner.worker == exact and exact.stops == 0)
exact.close_ok = true
assert(owner.detach() and exact.live and exact.stops == 0, 'Intentional detach terminated the worker')
local legacy = worker()
owner = Launch.start({ launch_worker = function() return legacy end }, 'args', 'folder')
assert(not owner.async and owner.worker == legacy and owner.advance() == 'ready')
assert(owner.cancel() and legacy.stops == 1 and legacy.closes == 1)

-- Explicit host SHA surface with known independent SHA256 vectors; no native import.
local sha_vectors = {
    [''] = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    ['bytes'] = '277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9',
    ['e0a48d0be9a7453f\t0000000000000111\n'] = '24f8e56da340b41662afc3a5ef8ce8bd6002eee156104ba39b54c2ae5d67c174',
}
local provenance = assert(loadfile('src/presets/binding_provenance.lua'))
setfenv(provenance, setmetatable({ m = { platform = { digest = function(value)
    if type(value) == 'function' then
        local parts = {}
        while true do local chunk = value(); if chunk == nil then break end; parts[#parts + 1] = chunk end
        value = table.concat(parts)
    end
    return assert(sha_vectors[value], 'Unexpected SHA fixture input')
end } } }, { __index = _G }))
local P = provenance()
local DDS = dofile('src/core/dds.lua')
local Buffer = require('src.core.float_buffer')
local function fixture(kind)
    local clock, files, stats, launched = 0, {}, { reads = 0, writes = 0, starts = 0 }, {}
    local root, stamp, request = 'C:/fixture', string.rep('a', 64), string.rep('b', 64)
    local folder = root .. (kind == 'camo' and '/camo-patterns-v1'
        or kind == 'authored' and '/authored-poses-v2' or kind == 'binding' and '/binding-sources' or '/originals')
    local file_io = { remove = function(path) files[path] = nil; return true end }
    function file_io.open(path, mode)
        local at = 1
        if mode == 'rb' then
            stats.reads = stats.reads + 1
            if files[path] == nil then return nil, 'fixture missing', 2 end
        else stats.writes = stats.writes + 1; files[path] = '' end
        return {
            read = function(_, count)
                local bytes = files[path]:sub(at, at + count - 1); at = at + #bytes; return bytes
            end,
            write = function(_, bytes) files[path] = files[path] .. bytes; return true end,
            close = function() return true end,
            seek = function(_, mode, offset)
                at = mode == 'end' and #files[path] + 1 + (offset or 0)
                    or mode == 'set' and 1 + (offset or 0) or at + (offset or 0)
                return at - 1
            end,
        }
    end
    local m = { file_io = file_io, worker_launch = Launch, dds = DDS, binding_provenance = P,
        original_snapshot_script = '23', original_snapshot_reader = '23',
        binding_provenance_script = '23', binding_provenance_reader = '23',
        camo_preview_script = '23', camo_preview_reader = '23',
        authored_preview_script = '23', authored_preview_reader = '23',
        player_authored_clip = { load = function(path) assert(path == folder .. '/' .. stamp); return { exact = path } end },
        engine = { texture_object = function(_, hash) assert(hash == '0123456789abcdef'); return 123456 end } }
    m.windows = {
        process_id = function() return 123 end, game_data = function() return 'C:/game/data' end,
        supports_async_workers = function() return true end,
        launch_worker = function() error('Cache blocked on synchronous launch') end,
        begin_worker = function(args, scripts)
            assert(args:find('-OwnerPID 123', 1, true) and scripts:sub(1, #root) == root)
            stats.starts = stats.starts + 1
            local f = future(); launched[#launched + 1] = f; return f
        end,
        files = function() return { 'armor-00000001-0-0123456789abcdef-original.dds' } end,
    }
    local host = { paths = { cache = root, originals = folder, directory_exists = function() return true end },
        time = function() return clock end }
    local source
    if kind == 'camo' then source = dofile('src/preview/camo_patterns.lua').new(m, host)
    elseif kind == 'authored' then source = dofile('src/preview/player_authored_source.lua').new(m, host)
    elseif kind == 'binding' then source = dofile('src/presets/binding_source_cache.lua').new(m, host)
    else source = dofile('src/gear/original_luts.lua').new(m, host.paths, {}, function() return { [123456] = true } end) end
    local units = { { resource = '0000000000000111', archive = '1234567890abcdef' } }
    local function start()
        if kind == 'binding' then assert(source.start(units)) else source.start() end
    end
    local function tick(delta)
        clock = clock + (delta or 0.25)
        source.tick()
    end
    local function complete()
        if kind == 'camo' or kind == 'authored' then
            files[folder .. '/complete.txt'] = folder .. '/' .. stamp .. '\n' .. (kind == 'camo' and '1' or '2') .. '\n'
            for i = 0, 5 do files[folder .. '/' .. stamp .. '/mask-' .. i .. '.rgba'] = string.rep(string.char(i), 1024) end
        elseif kind == 'binding' then
            local out, resource, archive = folder .. '/' .. stamp .. '/' .. request, units[1].resource, units[1].archive
            local stem = resource .. '.' .. P.UNIT
            files[folder .. '/complete.txt'] = out .. '\n1\n' .. stamp .. '\n'
            files[out .. '/resources.tsv'] = table.concat({ P.UNIT, resource, archive, stem .. '.main', '-', '-',
                stem .. '.toc', P.digest('bytes'), '-', '-' }, '\t') .. '\n'
            files[out .. '/' .. stem .. '.main'], files[out .. '/' .. stem .. '.toc'] = 'bytes', string.rep('t', 80)
            files[out .. '/collisions.tsv'] = P.UNIT .. '\t' .. resource .. '\n'
            files[out .. '/collisions.meta'] = '1\n' .. P.digest(files[out .. '/collisions.tsv']) .. '\n'
            files[out .. '/scope.meta'] = 'top-level-game-data-patches-v1\n0\n' .. P.digest('') .. '\n'
        else
            files[folder .. '/index-complete.txt'] = stamp .. '\n'
            files[folder .. '/' .. stamp .. '/catalog.txt'] = '0123456789abcdef\n'
            files[folder .. '/complete.txt'] = stamp .. '\n'
            files[folder .. '/' .. stamp .. '/armor-00000001-0-0123456789abcdef-original.dds'] = DDS.encode(Buffer.new(23 * 4), 23, 1)
        end
    end
    return { source = source, start = start, tick = tick, complete = complete,
        stats = stats, files = files, launched = launched, units = units,
        set_clock = function(value) clock = value end, clock = function() return clock end }
end
local saved_clock, saved_time = os.clock, os.time
for _, kind in ipairs({ 'camo', 'authored', 'binding', 'original' }) do
    local fx
    os.clock, os.time = function() return fx and fx.clock() or 0 end, function() return fx and math.floor(fx.clock()) or 0 end
    fx = fixture(kind)
    for _ = 1, 1000 do fx.source.tick() end
    assert(fx.stats.reads == 0 and fx.stats.writes == 0 and fx.stats.starts == 0, kind .. ' did idle work')
    fx.start()
    local f, owner = fx.launched[1], fx.source.launch_owner
    assert(owner and owner.future == f and not fx.source.worker and f.pid == nil and f.checks == 0)
    local reads = fx.stats.reads
    for _ = 1, 1000 do fx.source.tick() end
    assert(f.checks == 0 and fx.stats.reads == reads, kind .. ' checked before its active budget')
    fx.tick()
    assert(f.checks == 1 and not fx.source.worker and fx.stats.reads == reads, kind .. ' read unfinished cache')
    fx.complete(); f.phase = 'ready'
    fx.tick()
    assert(fx.source.worker == f.exact and fx.stats.reads == reads + (kind == 'original' and 1 or 0))
    f.exact.live = false
    fx.tick()
    if kind == 'original' then
        assert(fx.stats.starts == 2 and fx.source.launch_owner.future == fx.launched[2])
        fx.launched[2].phase, fx.launched[2].exact.live = 'ready', false
        fx.tick()
        assert(fx.source.loaded and fx.source.get(123456), 'Original cache lost its matched production DDS')
    else
        assert(fx.source.state == 'ready', kind .. ': ' .. tostring(fx.source.error))
    end
    reads = fx.stats.reads; local writes = fx.stats.writes
    for _ = 1, 1000 do fx.source.tick() end
    assert(fx.stats.reads == reads and fx.stats.writes == writes, kind .. ' sampled a ready cache')
    assert(fx.source.close())

    fx = fixture(kind); fx.start(); f, owner = fx.launched[1], fx.source.launch_owner
    assert(not fx.source.close() and fx.source.launch_owner == owner and owner.future == f)
    if kind == 'binding' then
        assert(not fx.source.start({ { resource = '0000000000000222', archive = '1234567890abcdef' } }, true))
        assert(fx.stats.starts == 1, 'Replacement overlapped an unretired launch')
    else fx.source.start(); assert(fx.stats.starts == 1) end
    f.retired = true
    fx.tick()
    assert(not fx.source.launch_owner and not fx.source.worker, kind .. ' retained a confirmed retired launch')
    local checks, cancels = f.checks, f.cancels; reads, writes = fx.stats.reads, fx.stats.writes
    for _ = 1, 1000 do fx.source.tick() end
    assert(f.checks == checks and f.cancels == cancels and fx.stats.reads == reads and fx.stats.writes == writes,
        kind .. ' polled after closed retirement')

    -- A known terminal error/cancellation owns no worker and must not inspect
    -- stale completion markers left by a prior request.
    for _, terminal in ipairs({ 'error', 'cancelled' }) do
        fx = fixture(kind); fx.start(); f = fx.launched[1]
        local before = fx.stats.reads
        f.phase, f.reason = terminal, 'injected terminal launch failure'
        fx.tick()
        assert(not fx.source.launch_owner and not fx.source.worker and fx.stats.reads == before,
            kind .. ' read stale output after terminal launch failure')
        assert(kind == 'original' and fx.source.status:find('paused', 1, true)
            or kind ~= 'original' and fx.source.state == 'failed')
    end

    -- A broken cancellation transport gets a bounded retirement window, then
    -- retains its exact owner without any automatic IO/native/status work.
    fx = fixture(kind); fx.start(); f = fx.launched[1]; f.throw = true
    assert(not fx.source.close())
    for _ = 1, 32 do fx.tick() end
    assert(fx.source.cleanup_exhausted and fx.source.launch_owner.future == f,
        kind .. ' did not retain its exhausted cleanup owner')
    local checks, cancels = f.checks, f.cancels
    reads, writes = fx.stats.reads, fx.stats.writes
    for _ = 1, 1000 do fx.tick() end
    assert(f.checks == checks and f.cancels == cancels and fx.stats.reads == reads and fx.stats.writes == writes,
        kind .. ' polled a failed cleanup without a fresh explicit request')
    f.retired = true
    assert(fx.source.close() and not fx.source.launch_owner and not fx.source.cleanup_exhausted)

    -- Failed ready-worker cancellation also retains the exact owned worker.
    fx = fixture(kind); fx.start(); f = fx.launched[1]; f.phase = 'ready'; fx.tick()
    f.exact.stop_ok = false
    assert(not fx.source.close() and fx.source.worker == f.exact and f.exact.closes == 0)
    f.exact.stop_ok = true; fx.tick()
    assert(not fx.source.worker and f.exact.closes == 1)

    fx = fixture(kind); fx.start(); f = fx.launched[1]
    fx.tick(kind == 'original' and 121 or 191)
    assert(fx.source.launch_owner and fx.source.launch_owner.future == f,
        kind .. ' forgot a timed-out launch before cancellation acknowledgement')
    f.retired = true; fx.tick()
    assert(not fx.source.launch_owner)
end
os.clock, os.time = saved_clock, saved_time
print('PASS shared worker launch + four cache controllers: capped active launch/ready phases, exact ownership, cancellation race, timeout retirement, idle no-I/O and legacy sync')
