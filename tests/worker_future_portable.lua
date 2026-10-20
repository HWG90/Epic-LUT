-- Exercise the production future/worker facade against exact wire receipts.
-- No OS process, pipe, DLL, timer or scheduler is created by this fixture.
assert(_VERSION=='Lua 5.1')
ffi,bit,jit=nil,nil,nil
local Native=dofile('src/platform/native_platform.lua')
local previous=m
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function number(bytes,at)
    local a,b,c,d=bytes:byte(at,at+3);assert(d);return a+b*256+c*65536+d*16777216
end
local function fixture(steps)
    local self={calls=0,closed=0,index=0}
    local output=''
    local request={}
    function request:write(bytes)
        self.bytes=bytes;return self
    end
    -- Keep protocol state on this fixture, not on either stream.
    local state=self
    request.flush=function(stream)
        local bytes=stream.bytes;assert(bytes:sub(1,4)=='ELP1' and #bytes==16+number(bytes,13))
        local nonce,operation,payload=number(bytes,5),number(bytes,9),bytes:sub(17)
        stream.bytes=nil
        local code,reply,step=0,''
        if operation==29 then reply=word(123)..word(456)..'C:/client.exe'
        elseif operation==0 then reply='1'
        elseif operation~=30 then
            state.index=state.index+1;step=assert(steps[state.index],'Unexpected protocol request '..operation)
            assert(step.op==operation,'Unexpected worker operation '..operation..' instead of '..step.op)
            if step.payload then assert(payload==step.payload,'Worker request payload differs')end
            if step.check then step.check(payload)end
            code,reply=step.code or 0,step.bytes or ''
        end
        state.calls=state.calls+1
        output='ELR1'..word(nonce)..word(code)..word(#reply)..reply
        if step and step.truncate then output=output:sub(1,10)end
        return true
    end
    function request:close()state.closed=state.closed+1;return true end
    local response={read=function(_,count)local bytes=output:sub(1,count);output=output:sub(count+1);return bytes end,
        close=function()state.closed=state.closed+1;return true end}
    m={external_platform={start=function()return {request=request,response=response,token=string.rep('a',64),
        server_pid=456,image='C:/client.exe'}end}}
    self.platform=Native.new({backend='external',process_id=123})
    function self.finish()
        self.platform.close();assert(self.index==#steps and self.closed==2,'Protocol/transport owners were not retired')
    end
    return self
end
local args,folder='-NoProfile -EncodedCommand QQAAAA==','C:/owned/\230\156\141\232\163\133'
local token=word(77)
local begin={op=31,bytes=token,payload=word(#args)..args..folder}
local f=fixture({begin,{op=32,bytes=word(0),payload=token},
    {op=32,bytes=word(1)..word(9)..word(4567),payload=token},
    {op=13,bytes=word(1),payload=word(9)},{op=14,payload=word(9)},
    {op=15,code=5,payload=word(9)},{op=15,payload=word(9)}})
local future=f.platform.begin_worker(args,folder)
assert(future.pid==nil and future.handle==nil and future.status()=='pending')
local phase,worker=future.status();assert(phase=='ready' and worker.pid==4567 and worker.handle==9)
local before=f.calls
for _=1,1000 do local state,same=future.status();assert(state=='ready' and same==worker)end
assert(f.calls==before and not future.cancel(),'Ready future performed work or stole returned worker ownership')
assert(worker.running() and worker.stop() and not worker.close() and worker.handle==9)
assert(worker.close() and worker.handle==nil and worker.close())
f.finish()

f=fixture({begin,{op=32,bytes=word(2)..word(5),payload=token}})
future=f.platform.begin_worker(args,folder)
local state,why=future.status();assert(state=='error' and why:find('Windows 5',1,true))
before=f.calls
for _=1,1000 do assert(future.status()=='error' and future.cancel())end
assert(f.calls==before);f.finish()

f=fixture({begin,{op=33,payload=token},{op=32,bytes=word(0),payload=token},
    {op=32,bytes=word(0),payload=token},{op=32,bytes=word(3),payload=token}})
future=f.platform.begin_worker(args,folder)
assert(not future.cancel(),'Cancel request ACK was mistaken for completed cleanup')
assert(not future.cancel(),'Pending cancellation dropped ownership')
assert(future.cancel() and future.status()=='cancelled')
before=f.calls
for _=1,1000 do assert(future.cancel() and future.status()=='cancelled')end
assert(f.calls==before);f.finish()

f=fixture({begin,{op=33,payload=token},{op=32,bytes=word(1)..word(9)..word(4567),payload=token},
    {op=14,payload=word(9)},{op=15,payload=word(9)}})
future=f.platform.begin_worker(args,folder)
local cancelled,reason=future.cancel()
assert(not cancelled and type(reason)=='string','A raced worker became cancellation success or an invalid reason')
phase,worker=future.status();assert(phase=='ready' and worker.pid==4567)
assert(worker.stop() and worker.close());f.finish()

for _,bytes in ipairs({'',word(0)..'x',word(1)..word(0)..word(123),word(1)..word(3)..word(0),
    word(2)..word(0),word(3)..'x',word(4)})do
    f=fixture({begin,{op=32,bytes=bytes,payload=token}})
    future=f.platform.begin_worker(args,folder)
    assert(not pcall(future.status) and f.closed==2,'Malformed state left its service active')
    assert(not future.cancel(),'Malformed ownership receipt claimed successful cleanup')
    f.finish()
end
for _,bytes in ipairs({'',word(0),'abc'})do
    f=fixture({{op=31,bytes=bytes}})
    assert(not pcall(f.platform.begin_worker,args,folder) and f.closed==2,'Invalid future token remained active')
    f.finish()
end
f=fixture({begin,{op=33,code=6,payload=token},{op=32,code=6,payload=token}})
future=f.platform.begin_worker(args,folder)
assert(not future.cancel() and not pcall(future.status),'Unknown/stale ownership became cancellation success')
f.finish()
f=fixture({begin,{op=33,bytes='bad',payload=token}})
future=f.platform.begin_worker(args,folder)
assert(not future.cancel() and not future.cancel() and f.closed==2,'Malformed cancellation ACK dropped owner')
f.finish()
f=fixture({begin,{op=32,truncate=true,payload=token}})
future=f.platform.begin_worker(args,folder)
assert(not pcall(future.status) and not future.cancel() and f.closed==2,'Transport loss became successful retirement')
f.finish()
m=previous
print('PASS worker futures: production wire facade, exact identity, bounded receipts, confirmed cancellation, uncertain-owner retention and inert terminal states')
