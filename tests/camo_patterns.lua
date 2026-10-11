local Source = dofile('src/preview/camo_patterns.lua')
local output, stamp = 'test/cache/camo-patterns-v1', string.rep('a', 64)
local files, clock, live, stop_ok, starts, closes = {}, 0, true, true, 0, 0
local masks = {}
for layer = 0, 5 do
    local bytes = {}
    for i = 1, 1024 do
        bytes[i] = string.char((i + layer * 19) % 256)
    end
    masks[layer + 1] = table.concat(bytes)
end
local function make()
    files, clock, live, stop_ok = {}, 0, true, true
    local worker = {
        running = function()
            return live
        end,
        stop = function()
            if stop_ok then
                live = false
            end
            return stop_ok
        end,
        close = function()
            assert(not live)
            closes = closes + 1
        end,
    }
    local io_fake = {
        open = function(path, mode)
            if mode == 'rb' and files[path] == nil then
                return nil
            end
            return {
                write = function(_, value)
                    files[path] = value
                    return true
                end,
                read = function(_, limit)
                    return files[path]:sub(1, limit)
                end,
                close = function()
                    return true
                end,
            }
        end,
    }
    local m = {
        camo_preview_script = '2320',
        camo_preview_reader = '2320',
        original_snapshot_reader = '2320',
        windows = {
            verify_interface = function()
                return {}, {
                    epic_native_pid = function()
                        return 123
                    end,
                }
            end,
            game_data = function()
                return 'test/game/data'
            end,
            launch_worker = function(args, working)
                assert(args:find('/camo_preview.ps1', 1, true) and args:find('-OwnerPID 123', 1, true))
                assert(working == 'test/cache/camo-worker')
                starts = starts + 1
                return worker
            end,
        },
    }
    local source = Source.new(m, {
        paths = {
            cache = 'test/cache',
            directory_exists = function()
                return true
            end,
        },
        io = io_fake,
        time = function()
            return clock
        end,
    })
    return source
end
local function complete()
    files[output .. '/complete.txt'] = output .. '/' .. stamp .. '\n1\n'
    for index = 0, 5 do
        files[output .. '/' .. stamp .. '/mask-' .. index .. '.rgba'] = masks[index + 1]
    end
end
local source = make()
assert(source.state == 'idle' and starts == 0, 'Creating camo source started a worker')
source.start()
source.start()
assert(source.state == 'loading' and starts == 1 and files[output .. '/owner-heartbeat.txt'] == '123')
complete()
clock = 0.3
source.tick()
assert(source.get() == nil and source.state == 'loading', 'Read masks while worker was active')
live, clock = false, 0.6
source.tick()
local data = assert(source.get())
assert(data.width == 16 and data.height == 16 and #data.layers == 6 and closes == 1)
for index = 1, 6 do
    assert(data.layers[index] == masks[index], 'Cached mask channels or bytes changed')
end
source.tick()
assert(source.get() == data, 'Stable frame reloaded mask cache')
assert(source.close() and source.get() == nil)
for _, fault in ipairs({ 'escape', 'schema', 'missing', 'short', 'oversize' }) do
    source = make()
    source.start()
    complete()
    if fault == 'escape' then
        files[output .. '/complete.txt'] = 'other/cache/' .. stamp .. '\n1\n'
    elseif fault == 'schema' then
        files[output .. '/complete.txt'] = output .. '/' .. stamp .. '\n2\n'
    elseif fault == 'missing' then
        files[output .. '/' .. stamp .. '/mask-5.rgba'] = nil
    elseif fault == 'short' then
        files[output .. '/' .. stamp .. '/mask-5.rgba'] = 'short'
    else
        files[output .. '/' .. stamp .. '/mask-5.rgba'] = string.rep('x', 1025)
    end
    live, clock = false, 0.3
    source.tick()
    assert(source.state == 'failed' and source.get() == nil, 'Partial or invalid camo data exposed: ' .. fault)
    assert(source.close())
end
source = make()
source.start()
stop_ok = false
assert(not source.close() and source.worker and live, 'Lost refused camo worker ownership')
stop_ok = true
assert(source.close() and not source.worker and files[output .. '/progress.txt.cancel'] == 'cancel')
source = make()
source.start()
clock = 191
source.tick()
assert(source.state == 'failed' and not live and not source.worker, 'Camo timeout leaked worker')
print(
    'PASS camo source: lazy owned worker, exact six RGBA8 masks, versioned/bounded atomic data, cancellation and timeout'
)
