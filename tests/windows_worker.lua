local ffi = require('ffi')
local root = assert(os.getenv('EPIC_LUT_TEST_ROOT'))
local folder = root .. '/tests/tmp/cache'
local output = folder .. '/worker launch.txt'
os.remove(output)
local calls = 0
local kernel = ffi.load('kernel32')
local proxy = setmetatable({}, { __index = ffi })
proxy.load = function(name)
    assert(name ~= 'shell32', 'Background workers must not enter the Windows shell')
    local library = ffi.load(name)
    if name ~= 'kernel32' then return library end
    return setmetatable({}, { __index = function(_, key)
        if key ~= 'epic_process_create2' then return library[key] end
        return function(file, line, process_security, thread_security, inherit, flags, env, directory, startup, info)
            calls = calls + 1
            assert(ffi.sizeof(startup) == 104 and startup.size == 104)
            assert(ffi.sizeof(info) == 24)
            assert(process_security == nil and thread_security == nil and inherit == 0)
            assert(flags == 0x08000000 and env == nil and directory ~= nil)
            assert(startup.flags == 1 and startup.show == 0)
            assert(file[0] ~= 34 and line[0] == 34)
            return library[key](file, line, process_security, thread_security, inherit, flags, env, directory, startup, info)
        end
    end })
end
local function module()
    local chunk = assert(loadfile('src/platform/windows.lua'))
    setfenv(chunk, setmetatable({ require = function(name)
        return name == 'ffi' and proxy or require(name)
    end }, { __index = _G }))
    return chunk()
end
if not pcall(function() return kernel.epic_worker_test_sleep end) then
    ffi.cdef('void epic_worker_test_sleep(uint32_t) __asm__("Sleep");')
end
local function wait(worker)
    for _ = 1, 500 do
        if not worker.running() then return end
        kernel.epic_worker_test_sleep(10)
    end
    worker.stop()
    error('Worker did not exit within five seconds')
end
local W = module()
local worker = W.launch_worker('-NoProfile -NonInteractive -Command "[IO.File]::WriteAllText(\'worker launch.txt\',\'Unicode: Ω & literal arguments\')"', folder)
assert(worker.pid > 0 and worker.handle ~= nil)
wait(worker)
worker.close()
worker.close()
assert(worker.handle == nil and not worker.running() and worker.stop())
local f = assert(io.open(output, 'rb'))
assert(f:read('*a') == 'Unicode: Ω & literal arguments')
f:close()
os.remove(output)
local sleeper = module().launch_worker('-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"', folder)
assert(sleeper.running() and sleeper.stop())
wait(sleeper)
sleeper.close()
local ok, why = pcall(W.launch_worker, '-NoProfile -Command "exit 0"', folder .. '/missing-worker-directory')
assert(not ok and tostring(why):find('Windows could not start worker:', 1, true))
assert(calls == 3)
print('Direct Windows worker launch, arguments, reload, termination and failure passed')
