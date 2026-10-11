-- Read local camo preview resources through an owned background worker.
-- Game archives are never decoded by the render callback or shipped in ZIPs.
local Source = { CACHE_FOLDER = 'camo-patterns-v1', SCHEMA = '1' }
function Source.new(m, host)
    host = host or {}
    local paths = host.paths or m.paths.new(m)
    local folder = paths.cache .. '/' .. Source.CACHE_FOLDER
    local scripts = paths.cache .. '/camo-worker'
    local self = { state = 'idle', status = 'Loading camo previews', data = nil }
    local io_api = host.io or io
    local now = host.time or os.clock
    local function read(path, limit)
        local file = io_api.open(path, 'rb')
        if not file then
            return nil
        end
        local ok, value = pcall(file.read, file, limit + 1)
        local closed, result = pcall(file.close, file)
        assert(ok and closed and result, 'Camo preview cache read failed')
        assert(value and #value <= limit, 'Camo preview cache marker exceeds its limit')
        return value
    end
    local function write(path, data)
        local file = assert(io_api.open(path, 'wb'), 'Cannot write camo preview helper')
        local ok, value = pcall(file.write, file, data)
        local closed, result = pcall(file.close, file)
        assert(ok and value and closed and result, 'Camo preview helper write failed')
    end
    local function hexfile(name, hex)
        assert(
            type(hex) == 'string' and #hex > 0 and #hex <= 1024 * 1024 and #hex % 2 == 0 and not hex:find('[^%x]'),
            'Camo helper source unavailable'
        )
        write(scripts .. '/' .. name, (hex:gsub('%x%x', function(pair)
            return string.char(tonumber(pair, 16))
        end)))
    end
    local function report(why)
        self.state, self.status = 'failed', 'Camo previews unavailable'
        self.error = tostring(why):sub(1, 1024)
        if host.log then
            pcall(host.log, 'preview: camo patterns unavailable ' .. self.error)
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
            hexfile('camo_preview.ps1', m.camo_preview_script)
            hexfile('camo_preview_reader.cs', m.camo_preview_reader)
            hexfile('original_snapshots.cs', m.original_snapshot_reader)
            local _, kernel = m.windows.verify_interface()
            self.owner = tonumber(kernel.epic_native_pid())
            assert(self.owner and self.owner > 0, 'Camo preview owner unavailable')
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
                        .. '/camo_preview.ps1" -GameData "'
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
                assert(self.close(), 'Camo preview worker could not stop')
                error('Camo preview cache timed out')
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
            local marker = assert(read(folder .. '/complete.txt', 4096), 'Camo preview worker ended without a result')
            local path, schema = marker:match('^([^\r\n]+)\r?\n([^\r\n]+)')
            assert(path and schema == Source.SCHEMA, 'Camo preview cache schema changed')
            local normalized = path:gsub('\\', '/')
            local prefix = folder:gsub('\\', '/') .. '/'
            assert(normalized:sub(1, #prefix):lower() == prefix:lower(), 'Camo cache path escapes its folder')
            local stamp = normalized:sub(#prefix + 1)
            assert(#stamp == 64 and not stamp:find('[^%x]'), 'Camo preview cache identity is invalid')
            local dataset = { width = 16, height = 16, layers = {} }
            for index = 0, 5 do
                local mask =
                    assert(read(normalized .. '/mask-' .. index .. '.rgba', 1024), 'Camo mask cache incomplete')
                assert(#mask == 1024, 'Camo mask cache length changed')
                dataset.layers[index + 1] = mask
            end
            self.data = dataset
            self.state, self.status, self.error = 'ready', 'Camo previews ready', nil
            if host.log then
                pcall(host.log, 'preview: camo mask resources decoded from local game cache')
            end
        end)
        if not ok then
            report(why)
        end
    end
    return self
end
return Source
