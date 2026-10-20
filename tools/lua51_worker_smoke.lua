-- Finite OS-only worker smoke. Call tick only while active, then explicitly
-- close retained cleanup owners. No callback registration or idle polling.
local MIN_INTERVAL,MAX_SECONDS,MAX_CHECKS=0.25,30,128
local Smoke={MIN_INTERVAL=MIN_INTERVAL,MAX_SECONDS=MAX_SECONDS,MAX_CHECKS=MAX_CHECKS}
local BODY='\0Epic LUT worker\255\1\r\n\230\156\141\232\163\133:'
local byte_values={}
for index=1,#BODY do byte_values[index]=tostring(BODY:byte(index))end
local BYTE_VECTOR=table.concat(byte_values,',')
local function literal(text)return "'"..text:gsub("'","''").."'"end
local function arguments(encode,path,delayed)
    local script="$ErrorActionPreference='Stop';"
        ..(delayed and 'Start-Sleep -Seconds 60;' or '')
        ..'$p='..literal(path)..';$b=[byte[]]@('..BYTE_VECTOR..');'
        ..'$t=[Text.Encoding]::ASCII.GetBytes([string]$PID);'
        ..'$v=New-Object byte[] ($b.Length+$t.Length);'
        ..'[Array]::Copy($b,0,$v,0,$b.Length);[Array]::Copy($t,0,$v,$b.Length,$t.Length);'
        ..'[IO.File]::WriteAllBytes($p,$v);exit 0'
    return '-NoLogo -NoProfile -NonInteractive -EncodedCommand '..encode(script)
end
function Smoke.start(modules,host,directory,now)
    assert(type(modules)=='table' and type(host)=='table' and type(now)=='function','Worker smoke dependencies required')
    assert(type(directory)=='string' and #directory>0 and #directory<=4096
        and (directory:match('^%a:[/\\]') or directory:match('^[/\\][/\\]'))
        and not directory:find('[%z\1-\31\127]') and not directory:match('[/\\]$'),'Absolute owned worker directory required')
    local encode=assert(modules.external_platform and modules.external_platform.encode_script,'Portable script encoder required')
    local report={schema=1,runtime=_VERSION,success=false,checks=0,max_checks=MAX_CHECKS,
        max_seconds=MAX_SECONDS,min_interval=MIN_INTERVAL,cleanup_complete=false,platform_closed=false}
    local self={report=report}
    local lease,platform,files,windows,worker,future,owned,cleaned,terminal,delayed_arguments
    local needs_stop,phase,started,last,next_check,outcome=false,'starting'
    local marker=directory..'/worker-\230\156\141\232\163\133.bin'
    local stopped_marker=directory..'/stopped-\230\156\141\232\163\133.bin'
    local function clock()
        local value=now()
        assert(type(value)=='number' and value>=0 and value<math.huge and value==value,'Invalid monotonic clock')
        assert(last==nil or value>=last,'Worker smoke clock moved backward')
        last=value;return value
    end
    local function cleanup()
        if cleaned then return true end
        if future then
            local ok,why=future.cancel()
            if ok~=true then return false,why or 'Owned worker launch cleanup pending' end
            future=nil
        end
        if worker then
            if needs_stop then
                local ok,why=worker.stop();assert(ok==true,why or 'Owned worker stop failed')
                local running=worker.running();assert(type(running)=='boolean','Owned worker status invalid')
                if running then return false,'Owned worker termination pending' end
                needs_stop=false
            end
            local ok,why=worker.close();assert(ok==true,why or 'Owned worker close failed')
            worker=nil
        end
        if owned then
            for _,path in ipairs({marker,stopped_marker})do
                if platform.stat(path) then
                    local ok,why=platform.remove(path);assert(ok==true,why or 'Owned marker removal failed')
                end
            end
            local ok,why=platform.rmdir(directory);assert(ok==true,why or 'Owned worker directory cleanup failed')
            owned=false
        end
        if lease then
            local ok,why=lease.close(true);assert(ok==true,why or 'Worker runtime cleanup pending')
            lease=nil
        end
        cleaned=true
        report.cleanup_complete,report.platform_closed,report.cleanup_pending=true,true,false
        report.cleanup_error=nil
        report.success=outcome==true
        return true
    end
    local function try_cleanup()
        local called,done,why=pcall(cleanup)
        if called and done==true then return true end
        report.cleanup_pending=true
        report.cleanup_error=tostring(called and why or done):sub(1,512)
        return false,report.cleanup_error
    end
    local function finish(success,why)
        terminal,outcome=true,success==true
        report.phase=success and 'complete' or report.cancelled and 'cancelled' or 'failed'
        if why then report.error=tostring(why):sub(1,512)end
        try_cleanup()
        return true,report
    end
    function self.close()
        if not terminal then
            terminal,outcome=true,false;report.cancelled=true;report.phase='cancelled'
        end
        return try_cleanup()
    end
    function self.tick()
        if terminal then return true,report end
        local ok,why=pcall(function()
            local at=clock()
            if at-started>=MAX_SECONDS then error('Worker smoke exceeded 30 seconds',0)end
            if at<next_check then return end
            assert(report.checks<MAX_CHECKS,'Worker smoke exceeded status-check budget')
            next_check=at+MIN_INTERVAL;report.checks=report.checks+1
            if future then
                local state,value=future.status()
                if state=='pending' then return end
                assert(state=='ready',value or 'Owned worker launch '..tostring(state))
                worker,future,needs_stop=value,nil,true
                assert(type(worker)=='table' and type(worker.pid)=='number' and worker.pid>0
                    and worker.pid<4294967296 and worker.pid%1==0,'Owned worker identity unavailable')
                if phase=='launching' then
                    report.first_pid,report.phase=worker.pid,'writing';phase='writing'
                elseif phase=='launching_stop_test' then
                    report.stopped_pid=worker.pid
                    local stopped,reason=worker.stop();assert(stopped==true,reason or 'Delayed worker stop failed')
                    phase='stopping';report.phase=phase
                    return
                else error('Invalid worker launch phase',0)end
            end
            local running=worker.running();assert(type(running)=='boolean','Owned worker status invalid')
            if running then return end
            needs_stop=false
            if phase=='writing' then
                local bytes=files.read(marker,#BODY+10)
                assert(bytes==BODY..string.format('%.0f',worker.pid),'Owned worker marker bytes/PID differ')
                report.marker_bytes,report.pid_verified,report.marker_verified=#bytes,true,true
                report.normal_completion=true
                local closed,reason=worker.close();assert(closed==true,reason or 'Completed worker close failed')
                worker=nil
                future=windows.begin_worker(delayed_arguments,directory)
                phase='launching_stop_test';report.phase=phase
            elseif phase=='stopping' then
                assert(platform.stat(stopped_marker)==nil,'Stopped worker wrote its delayed marker')
                report.stop_verified,report.delayed_marker_absent=true,true
                local closed,reason=worker.close();assert(closed==true,reason or 'Stopped worker close failed')
                worker=nil
                return finish(true)
            else error('Invalid worker smoke phase',0)end
        end)
        if not ok then return finish(false,why)end
        return terminal==true,report
    end
    local ok,why=pcall(function()
        -- Encode both controlled scripts before acquiring any OS resource.
        local first=arguments(encode,marker,false)
        delayed_arguments=arguments(encode,stopped_marker,true)
        local reason
        lease,reason=modules.runtime_services.start(modules,host)
        assert(lease and lease.ready,reason or 'Worker runtime bootstrap cleanup pending')
        platform=assert(lease.platform,'Worker platform unavailable')
        windows=modules.windows.new(platform)
        assert(windows.supports_async_workers(),'Asynchronous worker launch unavailable')
        files=modules.file_io.new(platform)
        assert(platform.mkdir_new(directory)==true,'Worker smoke directory already exists')
        owned=true
        started=clock();next_check=started+MIN_INTERVAL
        future=windows.begin_worker(first,directory)
        report.phase='launching';phase='launching'
    end)
    if not ok then finish(false,why)end
    return self
end
return Smoke
