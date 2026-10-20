-- Owned read-only archive worker. Cache game bytes locally, never in presets.
local C = { FOLDER = 'binding-sources', SCHEMA = '1', MAX_PART = 8 * 1024 * 1024, MAX_SET = 256 * 1024 * 1024 }
local function id(value, n)
    assert(type(value) == 'string' and #value == (n or 16) and value:match('^%x+$'), 'Invalid binding cache identity')
    return value:lower()
end
function C.new(m, host)
    host = host or {}
    local paths = host.paths or m.paths.new(m)
    local io_api, now = host.io or m.file_io or io, host.time or os.clock
    local folder, scripts = paths.cache .. '/' .. C.FOLDER, paths.cache .. '/binding-worker'
    local self = { state = 'idle', status = 'Binding source cache not requested', records = {} }
    local loaded_bytes = 0
    local function read(path, limit)
        local f, why = io_api.open(path, 'rb')
        if not f then
            return nil, why
        end
        local value = f:read(limit + 1)
        assert(f:close())
        assert(value and #value <= limit, 'Binding cache file exceeds its limit')
        return value
    end
    local function write(path, data)
        local f = assert(io_api.open(path, 'wb'))
        assert(f:write(data))
        assert(f:close())
    end
    local function hexfile(name, value)
        assert(
            type(value) == 'string'
                and #value > 0
                and #value <= 2 * 1024 * 1024
                and #value % 2 == 0
                and not value:find('[^%x]'),
            'Binding worker source unavailable'
        )
        write(scripts .. '/' .. name, (value:gsub('%x%x', function(pair)
            return string.char(tonumber(pair, 16))
        end)))
    end
    local function heartbeat()
        if self.owner then
            write(folder .. '/owner-heartbeat.txt', tostring(self.owner))
        end
    end
    local function failed(why)
        self.state, self.status, self.error = 'failed', 'Binding provenance unavailable', tostring(why):sub(1, 1024)
        if host.log then
            pcall(host.log, 'binding: ' .. self.error)
        end
    end
    function self.close()
        if self.worker then
            pcall(write, folder .. '/progress.txt.cancel', 'cancel')
            local ok, done = pcall(self.worker.stop)
            if not ok or done == false or self.worker.running() then
                return false
            end
            self.worker.close()
            self.worker = nil
        end
        self.state, self.records, loaded_bytes = 'closed', {}, 0
        return true
    end
    function self.start(units, force)
        assert(type(units) == 'table' and #units > 0 and #units <= 64, 'No bounded current units to capture')
        local list, seen = {}, {}
        for _, u in ipairs(units) do
            local line = id(u.resource) .. '\t' .. id(u.archive)
            if not seen[line] then
                list[#list + 1] = line
                seen[line] = true
            end
        end
        table.sort(list)
        local request = table.concat(list, '\n') .. '\n'
        if self.request == request and (self.state == 'loading' or self.state == 'ready' and not force) then
            return true
        end
        if self.worker and not self.close() then
            return false, 'Previous binding worker cleanup pending'
        end
        self.request, self.state, self.records, loaded_bytes = request, 'loading', {}, 0
        local ok, why = pcall(function()
            for _, path in ipairs({ folder, scripts }) do
                if not paths.directory_exists(path) then
                    paths.mkdir_new(path)
                end
            end
            hexfile('binding_provenance.ps1', m.binding_provenance_script)
            hexfile('binding_provenance_reader.cs', m.binding_provenance_reader)
            hexfile('original_snapshots.cs', m.original_snapshot_reader)
            write(folder .. '/request.tsv', request)
            if m.windows.process_id then self.owner = m.windows.process_id()
            else local _, kernel = m.windows.verify_interface();self.owner = tonumber(kernel.epic_native_pid()) end
            assert(self.owner and self.owner > 0, 'Binding worker owner unavailable')
            heartbeat()
            local game = m.windows.game_data()
            self.game = game
            for _, path in ipairs({ folder, scripts, game }) do
                assert(not path:find('["\r\n]'), 'Invalid binding worker path')
            end
            self.worker = assert(
                m.windows.launch_worker(
                    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'
                        .. scripts
                        .. '/binding_provenance.ps1" -GameData "'
                        .. game
                        .. '" -Output "'
                        .. folder
                        .. '" -Request "'
                        .. folder
                        .. '/request.tsv" -OwnerPID '
                        .. self.owner,
                    scripts
                )
            )
            self.began, self.last_poll = now(), now()
            self.status, self.error = 'Reading exact binding sources', nil
        end)
        if not ok then
            failed(why)
            return false, self.error
        end
        return true
    end
    local function load()
        local marker = assert(read(folder .. '/complete.txt', 8192), 'Binding worker ended without a result')
        local path, schema, stamp = marker:match('^([^\r\n]+)\r?\n([^\r\n]+)\r?\n([^\r\n]+)')
        assert(path and schema == C.SCHEMA, 'Binding cache schema changed')
        stamp = id(stamp, 64)
        local normalized = path:gsub('\\', '/')
        local prefix = folder:gsub('\\', '/') .. '/'
        assert(normalized:sub(1, #prefix):lower() == prefix:lower(), 'Binding cache path escapes its folder')
        local index, request = normalized:sub(#prefix + 1):match('^(%x+)/(%x+)$')
        assert(
            index and #index == 64 and #request == 64 and index:lower() == stamp,
            'Binding cache version identity differs'
        )
        local text = assert(read(path .. '/resources.tsv', 2 * 1024 * 1024), 'Binding source inventory unavailable')
        local records, count = {}, 0
        for line in text:gmatch('[^\r\n]+') do
            local fields = {}
            for value in (line .. '\t'):gmatch('(.-)\t') do
                fields[#fields + 1] = value
            end
            assert(#fields == 10, 'Malformed binding source inventory')
            local kind, resource, archive = id(fields[1]), id(fields[2]), id(fields[3])
            assert(
                kind == m.binding_provenance.UNIT or kind == m.binding_provenance.MATERIAL,
                'Unsupported binding source type'
            )
            local key = kind .. ':' .. resource
            assert(not records[key], 'Duplicate binding source record')
            local stem = resource .. '.' .. kind
            local spec = { resource = resource, archive = archive, index_stamp = stamp }
            for _, part in ipairs({ { 'main', 4, 8 }, { 'gpu', 5, 9 }, { 'stream', 6, 10 } }) do
                local name, at, hash = part[1], part[2], part[3]
                if fields[at] == '-' then
                    assert(name ~= 'main' and fields[hash] == '-', 'Missing binding main source')
                else
                    assert(fields[at] == stem .. '.' .. name, 'Binding source filename differs from resource identity')
                    spec[name .. '_file'], spec[name .. '_sha256'] = fields[at], id(fields[hash], 64)
                end
            end
            assert(fields[7] == stem .. '.toc', 'Binding TOC filename differs')
            spec.toc_file = fields[7]
            records[key] = spec
            count = count + 1
            assert(count <= 4160, 'Binding source record count exceeds its limit')
        end
        assert(count > 0, 'Binding source inventory empty')
        local meta = assert(read(path .. '/collisions.meta', 256), 'Complete binding collision catalog unavailable')
        local rows, digest = meta:match('^(%d+)\r?\n(%x+)')
        rows = tonumber(rows)
        assert(rows and rows >= 1 and rows <= 6000000 and #digest == 64, 'Binding collision catalog metadata invalid')
        local f = assert(io_api.open(path .. '/collisions.tsv', 'rb'))
        local size = f:seek('end')
        assert(f:seek('set', 0))
        local hashed, value = pcall(m.binding_provenance.digest, function()
            local chunk = f:read(65536)
            return chunk and #chunk > 0 and chunk or nil
        end)
        assert(f:close())
        assert(hashed, value)
        assert(size == rows * 34, 'Binding collision catalog is incomplete')
        assert(value == id(digest, 64), 'Binding collision catalog digest differs')
        local scope = assert(read(path .. '/scope.meta', 256), 'Binding cache lacks current loose-patch scope proof')
        local scope_label, scope_count, scope_hash = scope:match('^([^\r\n]+)\r?\n(%d+)\r?\n(%x+)')
        scope_count = tonumber(scope_count)
        assert(
            scope_label == 'top-level-game-data-patches-v1' and scope_count and scope_count <= 4096,
            'Binding patch scope schema invalid'
        )
        self.scope_count, self.scope_sha256 = scope_count, id(scope_hash, 64)
        self.path, self.index_stamp, self.collision_count, self.collision_sha256 = path, stamp, rows, id(digest, 64)
        self.records, self.state, self.status, self.error = records, 'ready', 'Exact binding sources ready', nil
    end
    function self.tick()
        if self.state ~= 'loading' or now() - (self.last_poll or 0) < 0.25 then
            return
        end
        self.last_poll = now()
        local ok, why = pcall(function()
            heartbeat()
            if now() - self.began > 190 then
                assert(self.close(), 'Binding worker cleanup pending')
                error('Binding source worker timed out')
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
            load()
        end)
        if not ok then
            failed(why)
        end
    end
    local function get(kind, resource)
        if self.state ~= 'ready' then
            return nil, self.status
        end
        local spec = self.records[kind .. ':' .. id(resource)]
        if not spec then
            return nil, 'Exact resource is not in the captured set'
        end
        if not spec.main then
            local parts, bytes = {}, 0
            for _, part in ipairs({ 'main', 'gpu', 'stream' }) do
                local data = ''
                local filename = spec[part .. '_file']
                if filename then
                    local why
                    data, why = read(self.path .. '/' .. filename, C.MAX_PART)
                    if not data then
                        self.state = 'stale'
                        self.error = 'Binding source '
                            .. filename
                            .. ' unavailable: '
                            .. tostring(why or 'file could not be opened')
                        self.status = self.error .. '; press Load Current Gear to retry'
                        error(self.status, 0)
                    end
                end
                assert(
                    not spec[part .. '_file'] or m.binding_provenance.digest(data) == spec[part .. '_sha256'],
                    'Pristine binding source digest differs'
                )
                parts[part] = data
                bytes = bytes + #data
            end
            local toc = assert(read(self.path .. '/' .. spec.toc_file, 80), 'Binding TOC unavailable')
            assert(#toc == 80, 'Binding TOC truncated')
            assert(loaded_bytes + bytes <= C.MAX_SET, 'Binding source set exceeds its limit')
            loaded_bytes = loaded_bytes + bytes
            spec.main, spec.gpu, spec.stream, spec.toc = parts.main, parts.gpu, parts.stream, toc
        end
        return spec
    end
    function self.unit(resource)
        return get(m.binding_provenance.UNIT, resource)
    end
    function self.material(resource)
        return get(m.binding_provenance.MATERIAL, resource)
    end
    function self.get()
        return self.state == 'ready' and self or nil
    end
    function self.validate_scope()
        if self.state ~= 'ready' then
            return false, self.status
        end
        local ok, why = pcall(function()
            assert(self.game and m.windows.files, 'Current patch scope enumeration unavailable')
            local names, all = {}, {}
            for _, name in ipairs(m.windows.files(self.game, '*.patch_*')) do
                all[name] = true
                local hash = name:match('^(%x+)%.patch_%d+$')
                if hash and #hash == 16 then
                    names[#names + 1] = name
                end
            end
            table.sort(names)
            assert(#names == self.scope_count, 'Current loose patch scope changed')
            for name in pairs(all) do
                local base = name:match('^(%x+%.patch_%d+)%.gpu_resources$') or name:match('^(%x+%.patch_%d+)%.stream$')
                assert(not base or all[base], 'Current loose patch companion is orphaned')
            end
            local receipt = {}
            for _, name in ipairs(names) do
                receipt[#receipt + 1] = name .. '\t'
                for _, suffix in ipairs({ '', '.gpu_resources', '.stream' }) do
                    local file = io_api.open(self.game .. '/' .. name .. suffix, 'rb')
                    if not file then
                        assert(suffix ~= '', 'Current patch disappeared')
                        receipt[#receipt + 1] = '-\t-\t'
                    else
                        local size = assert(file:seek('end'))
                        assert(file:seek('set', 0))
                        local hashed, digest = pcall(m.binding_provenance.digest, function()
                            local chunk = file:read(65536)
                            return chunk and #chunk > 0 and chunk or nil
                        end, size)
                        assert(file:close())
                        assert(hashed, digest)
                        receipt[#receipt + 1] = tostring(size) .. '\t' .. digest .. '\t'
                    end
                end
                receipt[#receipt + 1] = '\n'
            end
            assert(
                m.binding_provenance.digest(table.concat(receipt)) == self.scope_sha256,
                'Current loose patch payloads changed'
            )
        end)
        if not ok then
            self.state, self.status = 'stale', 'Binding source scope changed; reload current gear'
            return false, tostring(why)
        end
        return true
    end
    function self.id_available(kind, resource)
        assert(self.state == 'ready', 'Complete resource collision catalog unavailable')
        local wanted = id(kind) .. '\t' .. id(resource)
        local f = assert(io_api.open(self.path .. '/collisions.tsv', 'rb'))
        local ok, result = pcall(function()
            assert(f:seek('end') == self.collision_count * 34, 'Binding collision catalog changed')
            local low, high = 0, self.collision_count - 1
            while low <= high do
                local mid = math.floor((low + high) / 2)
                assert(f:seek('set', mid * 34))
                local row = f:read(34)
                assert(row and #row == 34 and row:sub(34) == '\n', 'Malformed binding collision row')
                local a, b = row:sub(1, 33):match('^(%x+)\t(%x+)$')
                assert(a and #a == 16 and #b == 16, 'Malformed binding collision ID')
                row = row:sub(1, 33)
                if row == wanted then
                    return false
                elseif row < wanted then
                    low = mid + 1
                else
                    high = mid - 1
                end
            end
            return true
        end)
        assert(f:close())
        assert(ok, result)
        return result
    end
    return self
end
return C
