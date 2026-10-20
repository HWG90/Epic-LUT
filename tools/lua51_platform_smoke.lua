-- Explicit one-shot OS-service check. No update callback, LUT, input, clipboard,
-- dialog, shell, worker launch, game-memory read, or renderer operation.
local Smoke = {}
function Smoke.close(modules)
    local lease = modules.platform_probe_lease
    if not lease then return true end
    local done, why = lease.close(true)
    if done == true then modules.platform_probe_lease = nil end
    return done, why
end
function Smoke.run(modules, host, directory)
    assert(_VERSION == 'Lua 5.1' and rawget(_G, 'jit') == nil, 'Stock Lua 5.1 required')
    assert(type(directory) == 'string' and #directory > 0, 'Owned probe directory required')
    local lease, reason = modules.runtime_services.start(modules, host)
    modules.platform_probe_lease = lease
    if not lease.ready then
        local closed = Smoke.close(modules)
        assert(closed, reason or 'Probe bootstrap cleanup pending')
        error(reason or 'Probe bootstrap failed', 0)
    end
    local platform = assert(lease.platform, 'Probe Windows service unavailable')
    local files = modules.file_io.new(platform)
    local owned, report = false, { schema = 1, runtime = _VERSION }
    local names = { directory .. '/palette-\230\156\141\232\163\133.bin', directory .. '/pending.bin', directory .. '/renamed.bin' }
    local ok, why = pcall(function()
        assert(platform.mkdir_new(directory) == true, 'Probe directory already exists or cannot be created')
        owned = true
        local bytes = string.rep('\0Epic LUT Lua 5.1\255\r\n', 64)
        assert(#bytes == 1280, 'Probe vector length differs')
        assert(files.write(names[1], bytes) and files.read(names[1], #bytes) == bytes)
        local digest = platform.digest(bytes, #bytes)
        assert(digest == '631fcc8b07826fc8fd9f48913968865ac099962543b2aadf52e1f2e239961d52', 'Independent SHA256 vector differs')
        assert(files.write(names[2], 'updated\0' .. bytes))
        assert(platform.replace(names[2], names[1]) == true)
        assert(files.read(names[1], #bytes + 8) == 'updated\0' .. bytes, 'Atomic replacement bytes differ')
        assert(platform.rename(names[1], names[3]) == true)
        local listed = platform.files(directory, '*.bin')
        assert(#listed == 1 and listed[1] == 'renamed.bin', 'Probe file listing differs')
        local storage = assert(lease.storage, 'Probe loader storage unavailable')
        local state = { bytes = #bytes, marker = 'roundtrip' }
        assert(storage.save('runtime_probe', state) == true)
        assert(storage.load('runtime_probe').marker == state.marker, 'Loader storage roundtrip differs')
        report.bytes, report.sha256 = #bytes, digest
        report.unicode, report.atomic_replace, report.rename, report.loader_store = true, true, true, true
    end)
    local cleaned = true
    if owned then
        for _, name in ipairs(names) do
            local worked = pcall(function()
                if platform.stat(name) then assert(platform.remove(name) == true) end
            end)
            cleaned = worked and cleaned
        end
        local worked, done = pcall(platform.rmdir, directory)
        cleaned = worked and done == true and cleaned
    end
    local closed, done, close_error = pcall(Smoke.close, modules)
    assert(closed and done == true, close_error or done or 'Probe service cleanup pending')
    assert(cleaned, 'Owned probe directory cleanup failed')
    assert(ok, why)
    report.cleanup_complete, report.platform_closed = true, true
    return report
end
return Smoke
