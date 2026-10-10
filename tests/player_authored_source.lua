local Source = dofile('src/preview/player_authored_source.lua')
local clock, live, stop_ok, decode_ok = 0, true, true, true
local files, closes, starts, decoded = {}, 0, 0, 0
local stamp = string.rep('a', 64)
local output = 'test/cache/authored-salute'
local data = { authored = true }
local function make()
    files, clock, live, stop_ok, decode_ok = {}, 0, true, true, true
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
            assert(not live, 'Closed a live worker handle')
            closes = closes + 1
        end,
    }
    local m = {
        authored_preview_script = '2320',
        authored_preview_reader = '2320',
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
                assert(args:find('-OwnerPID 123', 1, true) and args:find('-GameData "test/game/data"', 1, true))
                assert(working == 'test/cache/authored-worker')
                starts = starts + 1
                return worker
            end,
        },
        player_authored_clip = {
            load = function(path)
                assert(path == output .. '/' .. stamp, 'Decoder read outside the verified cache')
                assert(decode_ok, 'Malformed authored clip')
                decoded = decoded + 1
                return data
            end,
        },
    }
    local io_fake = {
        open = function(path, mode)
            if mode == 'rb' and not files[path] then
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
    return Source.new(m, {
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
    }),
        m
end
local source = make()
source.start()
assert(source.state == 'loading' and starts == 1 and files[output .. '/owner-heartbeat.txt'] == '123')
source.start()
assert(starts == 1, 'Started overlapping authored workers')
files[output .. '/complete.txt'] = output .. '/' .. stamp .. '\n1\n'
clock = 0.3
source.tick()
assert(source.state == 'loading' and not source.get() and decoded == 0, 'Read a marker while its writer was active')
live, clock = false, 0.6
source.tick()
assert(source.state == 'ready' and source.get() == data and closes == 1 and decoded == 1)
source.tick()
assert(decoded == 1, 'Decoded cache again on a stable frame')
assert(source.close() and source.get() == nil)
for _, marker in ipairs({ 'elsewhere/' .. stamp .. '\n1\n', output .. '/..\n1\n', output .. '/' .. stamp .. '\n2\n' }) do
    source = make()
    source.start()
    files[output .. '/complete.txt'] = marker
    live, clock = false, 0.3
    source.tick()
    assert(source.state == 'failed' and not source.get(), 'Accepted an escaped or incompatible cache marker')
    assert(source.close())
end
source = make()
source.start()
stop_ok = false
assert(not source.close() and source.worker and live, 'Forgot a worker whose cancellation was refused')
stop_ok = true
assert(source.close() and not source.worker and files[output .. '/progress.txt.cancel'] == 'cancel')
source = make()
source.start()
files[output .. '/complete.txt'] = output .. '/' .. stamp .. '\n1\n'
decode_ok, live, clock = false, false, 0.3
source.tick()
assert(source.state == 'failed' and source.error:find('Malformed authored clip', 1, true))
assert(source.close())
source = make()
source.start()
clock = 191
source.tick()
assert(source.state == 'failed' and not live and not source.worker, 'Timeout leaked the authored resource worker')
print('PASS authored source: owned worker lifecycle, verified markers, bounded decode, cancellation and timeout')
