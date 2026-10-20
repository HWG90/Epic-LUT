-- Controller fixture with actual runtime/windows/file facades and owned in-memory
-- OS effects. Real EXE/PowerShell acceptance is deliberately a separate check.
assert(_VERSION=='Lua 5.1')
ffi,bit,jit=nil,nil,nil
local Smoke=dofile('tools/lua51_worker_smoke.lua')
local Runtime=dofile('src/platform/runtime_services.lua')
local Windows=dofile('src/platform/windows.lua')
local Files=dofile('src/core/file_io.lua')
local Encoding=dofile('src/platform/external_platform.lua')
local Store=dofile('src/platform/loader_store.lua')
local BODY='\0Epic LUT worker\255\1\r\n\230\156\141\232\163\133:'
local original_open,original_remove,original_rename,original_execute,original_popen=io.open,os.remove,os.rename,os.execute,io.popen
local function foreign()error('Foreign/global IO forbidden')end
io.open,os.remove,os.rename,os.execute,io.popen=foreign,foreign,foreign,foreign,foreign
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function decode64(text)
    assert(#text%4==0 and not text:find('[^%w+/=]'))
    local out={}
    for at=1,#text,4 do
        local values={}
        for index=0,3 do
            local char=text:sub(at+index,at+index)
            values[index+1]=char=='=' and 0 or assert(alphabet:find(char,1,true))-1
        end
        local word=values[1]*262144+values[2]*4096+values[3]*64+values[4]
        out[#out+1]=string.char(math.floor(word/65536)%256)
        if text:sub(at+2,at+2)~='=' then out[#out+1]=string.char(math.floor(word/256)%256)end
        if text:sub(at+3,at+3)~='=' then out[#out+1]=string.char(word%256)end
    end
    return table.concat(out)
end
local function decode_script(args)
    local encoded=assert(args:match('^%-NoLogo %-NoProfile %-NonInteractive %-EncodedCommand ([%w+/=]+)$'))
    local bytes=decode64(encoded);assert(#bytes%2==0)
    local out,at={},1
    while at<=#bytes do
        local a,b=bytes:byte(at,at+1);local value=a+b*256;at=at+2
        if value>=55296 and value<=56319 then
            a,b=bytes:byte(at,at+1);local low=a+b*256;assert(low>=56320 and low<=57343)
            value=65536+(value-55296)*1024+low-56320;at=at+2
        end
        if value<128 then out[#out+1]=string.char(value)
        elseif value<2048 then out[#out+1]=string.char(192+math.floor(value/64),128+value%64)
        elseif value<65536 then out[#out+1]=string.char(224+math.floor(value/4096),128+math.floor(value/64)%64,128+value%64)
        else out[#out+1]=string.char(240+math.floor(value/262144),128+math.floor(value/4096)%64,128+math.floor(value/64)%64,128+value%64)end
    end
    return table.concat(out)
end
local serial=0
local function fixture()
    serial=serial+1
    local directory='C:/private worker \230\156\141\232\163\133 \240\159\166\134/case'..serial
    local state={time=0,calls=0,clock=0,jobs={},files={},closed=0,directory=directory}
    local platform={}
    local function call()state.calls=state.calls+1;assert(state.closed==0,'Closed platform used')end
    local function path(value)
        assert(value==directory or value==directory..'/worker-\230\156\141\232\163\133.bin'
            or value==directory..'/stopped-\230\156\141\232\163\133.bin','Foreign path '..tostring(value))
    end
    function platform.mkdir_new(value)
        call();path(value)
        if state.collision then return false end
        state.owned=true;return true
    end
    function platform.stat(value)call();path(value);return state.files[value] and {directory=false} or nil end
    function platform.remove(value)
        call();path(value);assert(state.owned)
        if state.fail_remove then return false,'remove failed'end
        assert(state.files[value]);state.files[value]=nil;return true
    end
    function platform.rmdir(value)
        call();path(value);assert(state.owned and next(state.files)==nil)
        state.owned=false;return true
    end
    function platform.open(value,mode)
        call();path(value);assert(state.owned and mode=='rb')
        if not state.files[value] then return nil,'Missing owned marker',2 end
        local closed=false
        return {read=function(_,count)call();assert(not closed and count<=#BODY+11);return state.files[value]:sub(1,count)end,
            close=function()call();assert(not closed);closed=true;return true end}
    end
    function platform.launch_worker(args,folder)
        call();assert(folder==directory and state.owned)
        local script=decode_script(args)
        assert(not script:find('ExecutionPolicy',1,true) and script:find('[IO.File]::WriteAllBytes($p,$v);exit 0',1,true))
        local delayed=#state.jobs==1
        assert(not delayed or script:find('Start-Sleep -Seconds 60;',1,true))
        local marker=directory..(delayed and '/stopped-' or '/worker-')..'\230\156\141\232\163\133.bin'
        assert(script:find('$p=\''..marker:gsub("'","''")..'\';',1,true),'Encoded script lost Unicode owned path')
        local vector=assert(script:match('%$b=%[byte%[%]%]@%(([^)]+)%)'));local data={}
        for byte in vector:gmatch('%d+')do data[#data+1]=string.char(tonumber(byte))end
        assert(table.concat(data)==BODY and script:find('[string]$PID',1,true),'Worker binary/PID vector differs')
        local record={pid=1000+#state.jobs,running=true,marker=marker,status=0,stops=0,closes=0}
        state.jobs[#state.jobs+1]=record
        return {pid=record.pid,
            running=function()call();record.status=record.status+1;assert(not record.closed);return record.running end,
            stop=function()
                call();assert(not record.closed);record.stops=record.stops+1
                if state.stop_throws then error('Sidecar transport is closed')end
                if state.fail_stop then return false,'stop failed'end
                if not state.stop_pending then record.running=false end
                return true
            end,
            close=function()
                call();assert(not record.closed and not record.running,'Detached live worker')
                record.closes=record.closes+1
                if state.fail_close then return false,'close failed'end
                record.closed=true;return true
            end}
    end
    function platform.close()
        state.calls=state.calls+1
        if state.fail_platform_close then return false,'platform cleanup pending'end
        for _,job in ipairs(state.jobs)do assert(job.closed,'Runtime closed before owned worker')end
        assert(not state.owned,'Runtime closed before owned directory')
        state.closed=state.closed+1;assert(state.closed==1);return true
    end
    local modules={external_platform=Encoding,runtime_services=Runtime,windows=Windows,file_io=Files,loader_store=Store,
        platform_backend='external',native_platform_name='fixture.exe',native_platform_sha256=string.rep('a',64),
        native_platform={new=function(options)
            assert(options.backend=='external' and options.service=='C:/fixture/fixture.exe')
            return platform
        end}}
    state.start=function(candidate)
        local host={dir='C:/fixture'}
        if state.bad_schema then host.config={epic_lut_ui={version=999,stores={}}};host.set=foreign end
        return Smoke.start(modules,host,candidate==nil and directory or candidate,function()state.clock=state.clock+1;return state.time end)
    end
    state.finish_first=function(payload)
        local job=assert(state.jobs[1]);job.running=false
        if payload~=false then state.files[job.marker]=payload or BODY..job.pid end
    end
    state.inert=function(controller)
        local before,clock=state.calls,state.clock
        for _=1,1000 do assert(controller.tick())end
        assert(state.calls==before and state.clock==clock,'Finished tick performed IO/status/time work')
    end
    return state
end

for _,byte in ipairs({0,1,9,10,13,31,127})do
    local invalid=fixture()
    assert(not pcall(invalid.start,'C:/private'..string.char(byte)..'/worker'),
        'ASCII worker-directory control was accepted')
    assert(invalid.calls==0 and invalid.clock==0 and #invalid.jobs==0,'Invalid directory acquired OS owners')
end
local invalid=fixture()
local rejected=invalid.start('C:/private-\192\175/worker')
local invalid_done,invalid_report=rejected.tick()
assert(invalid_done and not invalid_report.success and invalid_report.error:find('Invalid launcher UTF-8',1,true),
    'Invalid UTF-8 worker directory was accepted')
assert(invalid.calls==0 and invalid.clock==0 and #invalid.jobs==0,'Invalid UTF-8 acquired OS owners')

local s=fixture();local c=s.start();assert(not c.tick() and #s.jobs==1 and s.jobs[1].status==0)
s.time=0.24;assert(not c.tick() and s.jobs[1].status==0)
s.finish_first();s.time=0.25;assert(not c.tick() and #s.jobs==2 and s.jobs[1].closed and s.jobs[2].stops==1)
s.time=0.49;assert(not c.tick() and s.jobs[2].status==0)
s.time=0.5;local done,report=c.tick()
assert(done and report.success and report.pid_verified and report.marker_verified and report.normal_completion
    and report.stop_verified and report.delayed_marker_absent and report.cleanup_complete and report.platform_closed
    and report.checks==2 and s.closed==1 and not s.owned and next(s.files)==nil)
s.inert(c);assert(c.close() and s.closed==1)

for _,payload in ipairs({'wrong-marker',BODY..'999',false})do
    s=fixture();c=s.start();s.finish_first(payload);s.time=0.25
    done,report=c.tick();assert(done and not report.success and report.error and report.cleanup_complete and #s.jobs==1)
    s.inert(c)
end
s=fixture();c=s.start();assert(c.close() and c.report.cancelled and not c.report.success and s.jobs[1].stops==1)
s.inert(c)

s=fixture();c=s.start();s.finish_first();s.time=0.25;assert(not c.tick())
s.files[s.jobs[2].marker]=BODY..s.jobs[2].pid;s.time=0.5;done,report=c.tick()
assert(done and not report.success and report.error:find('delayed marker',1,true) and report.cleanup_complete)
s.inert(c)

s=fixture();c=s.start();s.fail_stop=true
assert(not c.close() and c.report.cleanup_pending and s.closed==0 and s.owned and not s.jobs[1].closed)
s.inert(c);s.fail_stop=false;assert(c.close() and s.closed==1 and c.report.cleanup_complete)

s=fixture();c=s.start();s.stop_throws=true
assert(not c.close() and c.report.cleanup_pending and not c.report.cleanup_complete
    and not c.report.platform_closed and not c.report.success and s.closed==0 and not s.jobs[1].closed)
s.inert(c);assert(not c.close() and s.closed==0,'Broken service ownership was silently discarded')
s.stop_throws=false;assert(c.close() and s.closed==1)

s=fixture();c=s.start();s.finish_first();s.time=0.25;assert(not c.tick())
s.fail_close=true;s.time=0.5;done,report=c.tick()
assert(done and not report.success and report.cleanup_pending and not s.jobs[2].closed and s.closed==0)
s.inert(c);s.fail_close=false;assert(c.close() and s.closed==1)

s=fixture();c=s.start();s.finish_first();s.time=0.25;assert(not c.tick());s.time=0.5;s.fail_remove=true
done,report=c.tick();assert(done and not report.success and report.cleanup_pending and s.closed==0 and s.owned)
s.inert(c);s.fail_remove=false;assert(c.close() and s.closed==1)

s=fixture();c=s.start();s.stop_pending=true;assert(not c.close() and c.report.cleanup_pending and s.closed==0)
s.inert(c);s.stop_pending=false;assert(c.close() and s.closed==1)

s=fixture();c=s.start()
for i=1,119 do s.time=i*0.25;assert(not c.tick())end
s.time=30;done,report=c.tick();assert(done and not report.success and report.checks==119 and report.cleanup_complete)
s.inert(c)

local interval,seconds,checks=Smoke.MIN_INTERVAL,Smoke.MAX_SECONDS,Smoke.MAX_CHECKS
Smoke.MIN_INTERVAL,Smoke.MAX_SECONDS,Smoke.MAX_CHECKS=0,100000,100000
s=fixture();c=s.start();assert(not c.tick() and s.jobs[1].status==0)
s.time=30;done,report=c.tick();assert(done and report.max_seconds==30 and not report.success and report.cleanup_complete)
Smoke.MIN_INTERVAL,Smoke.MAX_SECONDS,Smoke.MAX_CHECKS=interval,seconds,checks

s=fixture();c=s.start();s.finish_first();s.time=0.25;assert(not c.tick())
s.fail_platform_close=true;s.time=0.5;done,report=c.tick()
assert(done and not report.success and report.cleanup_pending and s.closed==0 and not s.owned)
s.inert(c);s.fail_platform_close=false;assert(c.close() and c.report.success and s.closed==1)

s=fixture();s.collision=true;c=s.start();done,report=c.tick()
assert(done and not report.success and #s.jobs==0 and s.closed==1 and not s.owned)
s.inert(c)

s=fixture();s.bad_schema=true;s.fail_platform_close=true;c=s.start();done,report=c.tick()
assert(done and not report.success and report.cleanup_pending and not report.platform_closed and s.closed==0 and #s.jobs==0)
s.inert(c);s.fail_platform_close=false;assert(c.close() and s.closed==1 and report.cleanup_complete)
io.open,os.remove,os.rename,os.execute,io.popen=original_open,original_remove,original_rename,original_execute,original_popen
print('PASS worker smoke controller: actual runtime/windows/file facades; independent Unicode/script decode, binary+PID checks, bounded completion/stop, cancel/failure retention and 1000 inert terminal ticks')
