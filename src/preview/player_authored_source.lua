-- Read local authored animation resources through an owned background worker.
-- Game archives are never decoded by the render callback or shipped in ZIPs.
local Source = {}
function Source.new(m, host)
    host = host or {}
    local paths = host.paths or m.paths.new(m)
    local folder = paths.cache .. '/authored-salute'
    local scripts = paths.cache .. '/authored-worker'
    local self = { state = 'idle', status = 'Loading salute', data = nil }
    local io_api = host.io or io
    local now = host.time or os.clock
    local function read(path, limit)
        local file = io_api.open(path, 'rb')
        if not file then
            return nil
        end
        local ok, value = pcall(file.read, file, limit + 1)
        local closed, result = pcall(file.close, file)
        assert(ok and closed and result, 'Authored animation cache read failed')
        assert(value and #value <= limit, 'Authored animation cache marker exceeds its limit')
        return value
    end
    local function write(path, data)
        local file = assert(io_api.open(path, 'wb'), 'Cannot write authored animation helper')
        local ok, value = pcall(file.write, file, data)
        local closed, result = pcall(file.close, file)
        assert(ok and value and closed and result, 'Authored animation helper write failed')
    end
    local function hexfile(name, hex)
        assert(
            type(hex) == 'string' and #hex > 0 and #hex <= 1024 * 1024 and #hex % 2 == 0 and not hex:find('[^%x]'),
            'Authored helper source unavailable'
        )
        write(scripts .. '/' .. name, (hex:gsub('%x%x', function(pair)
            return string.char(tonumber(pair, 16))
        end)))
    end
    local function report(why)
        self.state, self.status = 'failed', 'Salute unavailable'
        self.error = tostring(why):sub(1, 1024)
        if host.log then
            pcall(host.log, 'preview: authored salute unavailable ' .. self.error)
        end
    end
    local function heartbeat()
        if self.owner then
            write(folder .. '/owner-heartbeat.txt', tostring(self.owner))
        end
    end
    function self.start()
        if self.state ~= 'idle' then
            return
        end
        self.state = 'loading'
        local ok, why = pcall(function()
            for _, path in ipairs({ folder, scripts }) do
                if not paths.directory_exists(path) then
                    paths.mkdir_new(path)
                end
            end
            hexfile('authored_preview.ps1', m.authored_preview_script)
            hexfile('authored_preview_reader.cs', m.authored_preview_reader)
            hexfile('original_snapshots.cs', m.original_snapshot_reader)
            local _, kernel = m.windows.verify_interface()
            self.owner = tonumber(kernel.epic_native_pid())
            assert(self.owner and self.owner > 0, 'Authored animation owner unavailable')
            heartbeat()
            local data = m.windows.game_data()
            assert(
                not data:find('["\r\n]') and not folder:find('["\r\n]') and not scripts:find('["\r\n]'),
                'Invalid animation helper path'
            )
            self.worker = assert(
                m.windows.launch_worker(
                    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'
                        .. scripts
                        .. '/authored_preview.ps1" -GameData "'
                        .. data
                        .. '" -Output "'
                        .. folder
                        .. '" -OwnerPID '
                        .. self.owner,
                    scripts
                )
            )
            self.began, self.last_poll = now(), now()
        end)
        if not ok then
            report(why)
        end
    end
    function self.get()
        return self.data
    end
    function self.close()
        if self.worker then
            pcall(write, folder .. '/progress.txt.cancel', 'cancel')
            local ok, done = pcall(self.worker.stop)
            if not ok or done == false then
                return false
            end
            if self.worker.running() then
                return false
            end
            self.worker.close()
            self.worker = nil
        end
        self.state, self.data = 'closed', nil
        return true
    end
    function self.tick()
        if self.state ~= 'loading' then
            return
        end
        local current = now()
        if current - (self.last_poll or 0) < 0.25 then
            return
        end
        self.last_poll = current
        local ok, why = pcall(function()
            heartbeat()
            if current - self.began > 190 then
                assert(self.close(), 'Authored animation worker could not stop')
                error('Authored animation cache timed out')
            end
            if self.worker and self.worker.running() then
                return
            end
            if self.worker then
                self.worker.close()
                self.worker = nil
            end
            local problem = read(folder .. '/error.txt', 4096)
            assert(not problem or problem == '', problem)
            local marker =
                assert(read(folder .. '/complete.txt', 4096), 'Authored animation worker ended without a result')
            local path, schema = marker:match('^([^\r\n]+)\r?\n([^\r\n]+)')
            assert(path and schema == '1', 'Authored animation cache schema changed')
            local normalized = path:gsub('\\', '/')
            local prefix = folder:gsub('\\', '/') .. '/'
            assert(normalized:sub(1, #prefix):lower() == prefix:lower(), 'Authored cache path escapes its folder')
            local stamp = normalized:sub(#prefix + 1)
            assert(#stamp == 64 and not stamp:find('[^%x]'), 'Authored animation cache identity is invalid')
            self.data = assert(m.player_authored_clip.load(normalized), 'Authored animation cache is empty')
            self.state, self.status, self.error = 'ready', 'Salute ready', nil
            if host.log then
                pcall(host.log, 'preview: authored salute resources decoded from local game cache')
            end
        end)
        if not ok then
            report(why)
        end
    end
    return self
end
return Source
