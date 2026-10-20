-- Explicit platform services; old raw Win32/FFI operations remain legacy-only.
local W = {}
local MAX_FILES, MAX_NAME_BYTES = 100000, 1024 * 1024
local function text(value, allow_empty)
    assert(type(value) == 'string' and (allow_empty or #value > 0) and #value <= 131064, 'Invalid Windows text bounds')
    local at, units = 1, 0
    while at <= #value do
        local a, b, c, d = value:byte(at, at + 3)
        local width = 1
        if a >= 194 and a <= 223 then width = 2
        elseif a >= 224 and a <= 239 then width = 3
        elseif a >= 240 and a <= 244 then width = 4
        else assert(a >= 1 and a <= 127, 'Invalid Windows UTF-8 text') end
        if width >= 2 then assert(b and b >= 128 and b <= 191, 'Invalid Windows UTF-8 continuation') end
        if width >= 3 then
            assert(c and c >= 128 and c <= 191 and (a ~= 224 or b >= 160) and (a ~= 237 or b < 160), 'Invalid Windows UTF-8 scalar')
        end
        if width == 4 then
            assert(d and d >= 128 and d <= 191 and (a ~= 240 or b >= 144) and (a ~= 244 or b <= 143), 'Invalid Windows UTF-8 scalar')
        end
        units, at = units + (width == 4 and 2 or 1), at + width
        assert(units <= 32766, 'Windows text exceeds UTF-16 limit')
    end
    return value
end
local function operation(platform, name)
    return assert(type(platform[name]) == 'function' and platform[name], 'Portable Windows service unavailable: ' .. name)
end
function W.new(platform)
    assert(type(platform) == 'table', 'Explicit Windows platform service required')
    local self = {}
    function self.verify_interface()
        error('Raw Win32 FFI interface is unavailable with the portable service; use process_id/replace and owned worker APIs', 0)
    end
    function self.process_id()
        local pid = operation(platform, 'process_id')()
        assert(type(pid) == 'number' and pid % 1 == 0 and pid > 0 and pid < 4294967296, 'Current process identity unavailable')
        return pid
    end
    function self.game_data()
        local exe = text(operation(platform, 'executable_path')()):gsub('\\', '/')
        assert(exe:match('^%a:/') or exe:match('^//'), 'Absolute executable path required')
        local parent = assert(exe:match('^(.*)/[^/]+$'), 'Game executable path unavailable')
        if parent:lower():match('/bin$') then parent = parent:sub(1, -5) end
        return parent .. '/data'
    end
    function self.launch_worker(args, folder)
        args, folder = text(args, true), text(folder)
        -- The service also validates the complete executable + argument line.
        local worker, why = operation(platform, 'launch_worker')(args, folder)
        assert(type(worker) == 'table', why or 'Owned Windows worker unavailable')
        assert(type(worker.pid) == 'number' and worker.pid % 1 == 0 and worker.pid > 0 and worker.pid < 4294967296,
            'Owned Windows worker identity unavailable')
        for _, name in ipairs({ 'running', 'stop', 'close' }) do
            assert(type(worker[name]) == 'function', 'Owned Windows worker interface missing ' .. name)
        end
        -- Keep the service's opaque ownership and async lifecycle object intact.
        -- In particular, close releases handles; only explicit stop terminates it.
        return worker
    end
    function self.replace(source, destination)
        local ok, why = operation(platform, 'replace')(text(source), text(destination))
        return ok == true, why
    end
    local function listing(folder, filter, metadata)
        folder = text(folder)
        assert(type(filter) == 'string' and #filter > 0 and #filter <= 240 and not filter:find('[/\\%c]'), 'Invalid Windows file filter')
        local files, directories, supplied = operation(platform, 'files')(folder, filter)
        assert(type(files) == 'table' and (directories == nil or type(directories) == 'table'), 'Invalid Windows file listing')
        local names, receipts, seen, size = {}, {}, {}, 0
        for _, array in ipairs({ files, directories or {} }) do
            assert(type(array) == 'table' and getmetatable(array) == nil, 'Invalid Windows file listing')
            local count = #array
            for index in pairs(array) do
                assert(type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= count, 'Non-dense Windows file listing')
            end
            for index = 1, count do
                local name = text(array[index])
                assert(name ~= '.' and name ~= '..' and not name:find('[/\\%c]') and not seen[name], 'Ambiguous or foreign Windows child path')
                seen[name], size = true, size + #name
                names[#names + 1] = name
                assert(#names <= MAX_FILES and size <= MAX_NAME_BYTES, 'Windows listing exceeds budget')
                if metadata then
                    local receipt = type(supplied) == 'table' and supplied[name] or nil
                    if receipt == nil then
                        local stat = operation(platform, 'stat')(folder .. '/' .. name)
                        assert(type(stat) == 'table' and type(stat.directory) == 'boolean'
                            and type(stat.size_hex) == 'string' and #stat.size_hex == 16 and stat.size_hex:match('^%x+$')
                            and type(stat.stamp) == 'string' and #stat.stamp == 16 and stat.stamp:match('^%x+$'), 'Windows file metadata disappeared')
                        receipt = (stat.directory and 'D:' or 'F:') .. stat.size_hex .. ':' .. stat.stamp
                    end
                    assert(type(receipt) == 'string' and #receipt > 0 and #receipt <= 256 and not receipt:find('%c'), 'Invalid Windows file receipt')
                    receipts[name] = receipt
                end
            end
        end
        table.sort(names)
        return names, receipts
    end
    function self.files(folder, filter) return listing(folder, filter, true) end
    function self.row_presets(folder)
        local rows = {}
        for _, file in ipairs(listing(folder, 'row-*.dds', false)) do
            local name = file:match('^row%-([%w _-]+)%.dds$')
            if name then rows[#rows + 1] = name end
        end
        return rows
    end
    return self
end
local cached_platform, cached_service, legacy
local function current()
    local platform = m and m.platform
    if platform then
        if cached_platform ~= platform then cached_platform, cached_service = platform, W.new(platform) end
        return cached_service
    end
    if m and m.legacy_windows then return m.legacy_windows end
    if not legacy then legacy = require('src.platform.legacy_windows') end
    return legacy
end
for _, name in ipairs({ 'verify_interface', 'game_data', 'files', 'row_presets', 'launch_worker', 'replace' }) do
    W[name] = function(...) return current()[name](...) end
end
function W.process_id()
    local target = current()
    if target.process_id then return target.process_id() end
    local _, kernel = target.verify_interface()
    return tonumber(kernel.epic_native_pid())
end
return W
