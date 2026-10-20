-- Read installed-source snapshots and match resource IDs to the original live object.
-- No identity guesses, zero-value guesses, GPU probing or archive decoding on the game thread.
local O = {}
local buffers = m and m.float_buffer or require('src.core.float_buffer')
function O.new(m, paths, native, targets)
    local remove_file = m.file_io and m.file_io.remove or os.remove
    local open_file = m.file_io and m.file_io.open or io.open
    local self = {
        snapshots = {},
        loaded = false,
        status = 'Original LUT snapshots not requested',
        attempted = {},
        requested = {},
    }
    local folder = paths.originals or paths.files
    local advancing = false
    local function exists(path)
        local f = open_file(path, 'rb')
        if not f then
            return nil
        end
        local s = f:read(4096)
        f:close()
        return s
    end
    local function begin_scan()
        self.job = coroutine.create(function()
            local snapshots = {}
            local stamp = exists(folder .. '/index-complete.txt') or exists(folder .. '/complete.txt')
            stamp = stamp and stamp:match('^([%x]+)')
            if m.original_snapshot_script then
                assert(
                    self.validated_stamp and stamp == self.validated_stamp,
                    'Installed LUT sources have not been validated'
                )
            end
            if self.snapshot_stamp == stamp then
                for object, document in pairs(self.snapshots or {}) do
                    snapshots[object] = document
                end
            end
            local snapshot_folder = m.original_snapshot_script and stamp and #stamp == 64 and folder .. '/' .. stamp
                or folder
            local files = m.windows.files(snapshot_folder, '*-original.dds')
            if self.wanted then
                local keep = {}
                for _, hash in ipairs(self.wanted) do
                    keep[hash] = true
                end
                local filtered = {}
                for _, file in ipairs(files) do
                    if keep[file:match('%-([%x]+)%-original%.dds$')] then
                        filtered[#filtered + 1] = file
                    end
                end
                files = filtered
            end
            for index, name in ipairs(files) do
                self.status = 'Matching original LUTs to live resources: '
                    .. math.floor(index * 100 / math.max(1, #files))
                    .. '%'
                local hash = name:match('%-([%x]+)%-original%.dds$')
                if hash and #hash == 16 then
                    local object = m.engine.texture_object(native, hash)
                    if object then
                        local ok, document = pcall(function()
                            local f = assert(open_file(snapshot_folder .. '/' .. name, 'rb'))
                            local bytes = f:read(m.dds.MAX_BYTES + 1)
                            f:close()
                            local data, w, h = m.dds.decode(bytes)
                            assert(w == 23 or (w == 3 and h == 1))
                            local source_file =
                                open_file(snapshot_folder .. '/' .. name:gsub('%.dds$', '.patch-source'), 'rb')
                            local patch_source
                            if source_file then
                                patch_source = source_file:read(358)
                                source_file:close()
                                if #patch_source ~= 357 then
                                    patch_source = nil
                                end
                            end
                            local source_archives =
                                exists(snapshot_folder .. '/' .. name:gsub('%.dds$', '.source-archives'))
                            local arrowhead
                            local base = open_file(snapshot_folder .. '/arrowhead/' .. name, 'rb')
                            if base then
                                local raw = base:read(m.dds.MAX_BYTES + 1)
                                base:close()
                                local valid, pixels, bw, bh = pcall(m.dds.decode, raw)
                                if valid then
                                    arrowhead = { data = pixels, width = bw, height = bh, resource = hash }
                                end
                            end
                            return {
                                arrowhead = arrowhead,
                                data = data,
                                width = w,
                                height = h,
                                resource = hash,
                                patch_source = patch_source,
                                source_archives = source_archives,
                            }
                        end)
                        if ok then
                            snapshots[object] = document
                        end
                    end
                end
                coroutine.yield()
            end
            self.snapshots = snapshots
            self.snapshot_stamp = stamp
            self.loaded = true
            self.status = 'Installed LUT snapshots ready: 100%'
            if targets then
                for object in pairs(targets() or {}) do
                    self.attempted[object] = true
                end
            end
        end)
    end
    local function start()
        if self.worker or self.started or not m.original_snapshot_script then
            return
        end
        self.started = true
        self.loaded = false
        local function write(name, hex)
            local f = assert(open_file(paths.cache .. '/' .. name, 'wb'))
            assert(f:write((hex:gsub('%x%x', function(pair)
                return string.char(tonumber(pair, 16))
            end))))
            f:close()
        end
        write('original_snapshots.ps1', m.original_snapshot_script)
        write('original_snapshots.cs', m.original_snapshot_reader)
        remove_file(folder .. '/error.txt')
        self.launch(true)
        -- A previous base-only cache is not proof of the installed mod scope.
        -- Wait for this index worker before exposing any cached pixels.
    end
    function self.start()
        local ok, why = pcall(start)
        if not ok then
            self.status = 'Original snapshot startup failed: ' .. tostring(why)
        end
    end
    local function cancel_worker()
        local f = open_file(folder .. '/progress.txt.cancel', 'wb')
        if f then
            f:write('cancel')
            f:close()
        end
        if self.worker then
            pcall(self.worker.stop)
            pcall(self.worker.close)
            self.worker = nil
        end
    end
    local function heartbeat()
        if self.owner and os.time() ~= (self.last_heartbeat or 0) then
            local f = assert(open_file(folder .. '/owner-heartbeat.txt', 'wb'))
            assert(f:write(tostring(self.owner)))
            assert(f:close())
            self.last_heartbeat = os.time()
        end
    end
    function self.launch(index)
        remove_file(folder .. '/error.txt')
        remove_file(folder .. '/progress.txt')
        local pid
        if m.windows.process_id then pid = m.windows.process_id()
        else local _, kernel = m.windows.verify_interface();pid = tonumber(kernel.epic_native_pid()) end
        self.owner = pid
        self.last_heartbeat = nil
        heartbeat()
        self.phase = index and 'index' or 'capture'
        local extra = index and ' -IndexOnly' or ' -Wanted "' .. folder .. '/wanted.txt"'
        self.worker = m.windows.launch_worker(
            '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'
                .. paths.cache
                .. '/original_snapshots.ps1" -Output "'
                .. folder
                .. '" -OwnerPID '
                .. pid
                .. extra
                .. (m.windows.game_data and ' -GameData "' .. m.windows.game_data() .. '"' or ''),
            paths.cache
        )
        self.began = os.time()
        self.status = index and 'Indexing original LUT resources: 0%' or 'Reading equipped original LUTs: 0%'
    end
    local function match_equipped()
        if not targets then
            return false
        end
        local wanted = targets()
        wanted = wanted or {}
        for object in pairs(self.requested) do
            wanted[object] = true
        end
        if not wanted or next(wanted) == nil then
            self.status = 'Waiting for equipped Armor / Helmet LUTs'
            return false
        end
        local stamp =
            assert(exists(folder .. '/index-complete.txt'), 'Original resource index missing'):match('^([%x]+)')
        assert(stamp and #stamp == 64)
        local f = assert(open_file(folder .. '/' .. stamp .. '/catalog.txt', 'rb'))
        local text = f:read(1024 * 1024 + 1)
        f:close()
        assert(#text <= 1024 * 1024, 'Original index budget exceeded')
        local hashes = {}
        for hash in text:gmatch('[^\r\n]+') do
            assert(hash:match('^[%x]+$') and #hash == 16)
            hashes[#hashes + 1] = hash
        end
        self.job = coroutine.create(function()
            local matched = {}
            for i, hash in ipairs(hashes) do
                self.status = 'Matching equipped LUT resources: ' .. math.floor(i * 100 / math.max(1, #hashes)) .. '%'
                local object = m.engine.texture_object(native, hash)
                if object and wanted[object] then
                    matched[#matched + 1] = hash
                end
                coroutine.yield()
            end
            assert(#matched > 0, 'No equipped LUT resource IDs matched the installed source index')
            self.wanted = matched
            local out = assert(open_file(folder .. '/wanted.txt', 'wb'))
            assert(out:write(table.concat(matched, '\n')))
            out:close()
            self.launch(false)
        end)
        return true
    end
    local function tick()
        if self.worker then
            heartbeat()
            self.status = exists(folder .. '/progress.txt')
                or (self.phase == 'index' and 'Starting resource index worker...' or 'Starting equipped LUT capture...')
            if os.time() - self.began > 120 then
                cancel_worker()
                self.status = 'Original snapshot reader timed out; editor remains available'
                return
            end
            if not self.worker.running() then
                self.worker.close()
                self.worker = nil
                local error = exists(folder .. '/error.txt')
                if error then
                    self.status = 'Original snapshot failed: ' .. error
                elseif self.phase == 'index' and exists(folder .. '/index-complete.txt') then
                    local stamp = exists(folder .. '/index-complete.txt'):match('^([%x]+)')
                    assert(stamp and #stamp == 64, 'Installed LUT source stamp invalid')
                    self.validated_stamp = stamp
                    if self.snapshot_stamp ~= stamp then
                        self.snapshots, self.attempted = {}, {}
                    end
                    self.waiting_match = true
                elseif self.phase == 'capture' and exists(folder .. '/complete.txt') then
                    begin_scan()
                else
                    self.status = 'Original snapshot worker ended without a result'
                end
            end
        end
        if self.waiting_match and not self.job and not self.worker then
            self.waiting_match = not match_equipped()
        end
        if self.job then
            for i = 1, 32 do
                local ok, why = coroutine.resume(self.job)
                if not ok then
                    self.status = tostring(why)
                    self.job = nil
                    break
                end
                if coroutine.status(self.job) == 'dead' then
                    self.job = nil
                    break
                end
            end
        end
    end
    function self.tick()
        if advancing then return end
        advancing = true
        local ok, why = pcall(tick)
        advancing = false
        if not ok then
            self.status = 'Original snapshot feature paused: ' .. tostring(why)
            self.job = nil
            cancel_worker()
        end
    end
    function self.scan()
        -- Matching refreshes the gear list. Its Cape availability check reads
        -- this resolver again; that read must remain pending, not start another
        -- matching pass or replace the coroutine/worker currently advancing.
        if advancing then return end
        if m.original_snapshot_script then
            self.start()
            if self.loaded and not self.job then
                begin_scan()
            end
            self.tick()
        else
            begin_scan()
            while self.job do
                self.tick()
            end
        end
    end
    function self.get(object)
        if not self.loaded then
            self.scan()
        elseif
            not self.snapshots[object]
            and not self.attempted[object]
            and m.original_snapshot_script
            and not self.job
            and not self.worker
        then
            self.attempted[object] = true
            self.waiting_match = true
        end
        return self.loaded and self.snapshots[object] or nil
    end
    function self.get_resource(resource)
        assert(
            type(resource) == 'string' and #resource == 16 and resource:match('^%x+$'),
            'Invalid original resource request'
        )
        local object = m.engine.texture_object(native, resource)
        if not object then
            return nil
        end
        self.requested[object] = true
        return self.get(object)
    end
    function self.retry()
        self.attempted = {}
        if not self.worker and not self.job then
            if m.original_snapshot_script then
                self.started, self.loaded, self.waiting_match, self.validated_stamp = true, false, false, nil
                self.launch(true)
            else
                self.scan()
            end
        end
    end
    function self.close()
        cancel_worker()
    end
    return self
end
function O.preserve(document, original, retain_rows)
    assert(
        original,
        'Original game LUT snapshot not found for this live resource. Unavailable pixels are not zero values.'
    )
    assert(original.width == document.width, 'Original game LUT columns do not match the imported LUT')
    assert(
        document.height >= original.height,
        'Imported LUT has fewer rows than this original game LUT; cannot preserve missing color rows'
    )
    local height = retain_rows and document.height or original.height
    local data = buffers.new(document.width * height * 4)
    buffers.copy(data, document.data, document.width * height * 4)
    for row = 0, original.height - 1 do
        data[row * document.width * 4 + 3] = original.data[row * original.width * 4 + 3]
        for ch = 0, 3 do
            data[(row * document.width + 13) * 4 + ch] = original.data[(row * original.width + 13) * 4 + ch]
        end
    end
    return { data = data, width = document.width, height = height, source = document.source }
end
return O
