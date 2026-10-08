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
function U.new(windows, folder, version)
    local self = { status = 'Updates: not checked', started = false }
    local worker, age
    local script = folder .. '/check-updates.ps1'
    local result = folder .. '/update-result.txt'
    local function quote(s)
        assert(not s:find('"', 1, true))
        return '"' .. s .. '"'
    end
    function self.check()
        if worker then
            return self.status
        end
        os.remove(result)
        self.started = true
        local f = assert(io.open(script, 'wb'))
        f:write([=[param([string]$Output)
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
        f:close()
        local ok, value = pcall(
            windows.launch_worker,
            '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' .. quote(script) .. ' -Output ' .. quote(result),
            folder
        )
        if not ok then
            self.status = 'Update check unavailable'
            return self.status
        end
        worker = value
        age = 0
        self.status = 'Checking GitHub for updates...'
        return self.status
    end
    function self.tick(dt)
        if not worker then
            return
        end
        age = age + math.max(0, tonumber(dt) or 0)
        local f = io.open(result, 'rb')
        local tag
        if f then
            tag = f:read(128)
            f:close()
        end
        if tag or age > 20 or not worker.running() then
            if worker.running() then
                worker.stop()
            end
            worker.close()
            worker = nil
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
        local w = windows.launch_worker(
            '-NoProfile -NonInteractive -Command "Start-Process \'https://github.com/HWG90/Epic-LUT/releases\'"',
            folder
        )
        w.close()
        return 'Opened Epic LUT release page'
    end
    function self.close()
        if worker then
            worker.stop()
            worker.close()
            worker = nil
        end
    end
    return self
end
return U
