-- Network I/O stays in a short-lived worker, never on the game thread.
local U = {}
local function parse_version(tag)
    local numbers, suffix = tag:match('^R(%d[%d%.]*)(.*)$')
    if not numbers or numbers:find('..', 1, true) or numbers:sub(-1) == '.' then return nil end
    local rank, revision = 3, 0
    if suffix == '-alpha' then rank = 1
    elseif suffix:match('^-rc%d+$') then rank, revision = 2, tonumber(suffix:match('%d+'))
    elseif suffix ~= '' then return nil end
    local parts = {}
    for n in numbers:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    return { parts = parts, rank = rank, revision = revision }
end
local function newer(a, b)
    for i = 1, math.max(#a.parts, #b.parts) do
        local x, y = a.parts[i] or 0, b.parts[i] or 0
        if x ~= y then return x > y end
    end
    if a.rank ~= b.rank then return a.rank > b.rank end
    return a.revision > b.revision
end
function U.new(windows, folder, version, files)
    local launches = (m and m.worker_launch) or require('src.platform.worker_launch')
    files = files or (m and m.file_io)
    local open_file = files and files.open or io.open
    local remove_file = files and files.remove or os.remove
    local self = { status = 'Updates: not checked', started = false }
    local worker, launch, age, check_after, checks
    local opening, open_age, open_after, open_checks
    local script = folder .. '/check-updates.ps1'
    local result = folder .. '/update-result.txt'
    local function quote(s)
        assert(not s:find('"', 1, true))
        return '"' .. s .. '"'
    end
    function self.check()
        if launch then
            return self.status
        end
        remove_file(result)
        self.started = true
        local f = assert(open_file(script, 'wb'))
        local wrote, write_error = f:write([=[param([string]$Output)
$ErrorActionPreference='Stop'
try {
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $r=Invoke-RestMethod -Uri 'https://api.github.com/repos/HWG90/Epic-LUT/releases?per_page=100' -Headers @{'User-Agent'='Epic-LUT-update-check';Accept='application/vnd.github+json'} -TimeoutSec 12
 $r=$r | Where-Object { -not $_.draft -and $_.tag_name -match '^R[0-9]+(\.[0-9]+)*(-rc[0-9]+|-alpha)?$' } | Select-Object -First 1
 if (-not $r) { throw 'No supported release' }
 [IO.File]::WriteAllText($Output+'.tmp',[string]$r.tag_name)
} catch { [IO.File]::WriteAllText($Output+'.tmp','ERROR') }
Move-Item -LiteralPath ($Output+'.tmp') -Destination $Output -Force
]=])
        local closed, close_error = f:close()
        assert(wrote, write_error)
        assert(closed, close_error)
        local ok, value = pcall(
            launches.start, windows,
            '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' .. quote(script) .. ' -Output ' .. quote(result),
            folder
        )
        if not ok then
            self.status = 'Update check unavailable'
            return self.status
        end
        launch, worker = value, value.worker
        age, check_after, checks = 0, 0, 0
        self.status = 'Checking GitHub for updates...'
        return self.status
    end
    function self.tick(dt)
        if not launch and not opening then return end
        dt = math.max(0, tonumber(dt) or 0)
        if opening then
            open_age, open_after = open_age + dt, open_after - dt
            if open_after <= 0 and open_checks < 128 then
                open_after, open_checks = 0.25, open_checks + 1
                if open_age > 20 then
                    if opening.cancel() then opening = nil end
                else
                    local state, why = opening.advance()
                    if state == 'ready' then
                        if opening.detach() then
                            opening = nil
                            self.status = 'Opened Epic LUT release page'
                        end
                    elseif state ~= 'pending' then
                        if not opening.future then
                            opening = nil
                            self.status = 'Could not open release page: ' .. tostring(why or state)
                        end
                    end
                end
            end
        end
        if not launch then return end
        age, check_after = age + dt, check_after - dt
        if check_after > 0 or checks >= 128 then return end
        check_after, checks = 0.25, checks + 1
        if not worker then
            if age > 20 then
                if launch.cancel() then launch = nil end
                self.status = 'Update check unavailable; try again later'
                return
            end
            local state, value = launch.advance()
            if state == 'pending' then return end
            if state ~= 'ready' then
                if launch.future then return end
                launch = nil
                self.status = 'Update check unavailable; try again later'
                return
            end
            worker = value
        end
        local f = open_file(result, 'rb')
        local tag
        if f then
            tag = f:read(128)
            f:close()
        end
        if tag or age > 20 or not worker.running() then
            if not launch.cancel() then return end
            worker, launch = nil, nil
            local latest = tag and parse_version(tag)
            local current = parse_version(version)
            if not latest or not current then
                self.status = 'Update check unavailable; try again later'
            elseif newer(latest, current) then
                self.status = 'Update available: ' .. tag .. ' (installed ' .. version .. ')'
            else
                self.status = 'No newer release found (installed ' .. version .. ')'
            end
        end
    end
    function self.open()
        if opening then return 'Opening Epic LUT release page...' end
        opening = launches.start(windows,
            '-NoProfile -NonInteractive -Command "Start-Process \'https://github.com/HWG90/Epic-LUT/releases\'"',
            folder
        )
        open_age, open_after, open_checks = 0, 0, 0
        if opening.worker and opening.detach() then
            opening = nil
            return 'Opened Epic LUT release page'
        end
        return 'Opening Epic LUT release page...'
    end
    function self.close()
        if launch then
            if not launch.cancel() then return false end
            launch, worker = nil, nil
        end
        if opening then
            if not opening.cancel() then return false end
            opening = nil
        end
        return true
    end
    return self
end
return U
