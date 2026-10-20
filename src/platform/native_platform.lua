-- Explicit user-action Windows services through a Lua 5.1-loadable C function.
-- The C callback returns no Lua values and never inspects lua_State/game memory.
local N = { MAX_PAYLOAD = 1024 * 1024 }
local MAX_PAYLOAD = N.MAX_PAYLOAD
local MAX_FILE_BYTES = 64 * 1024 * 1024
local MAX_STREAM_POSITION = 9007199254740991
local MAX_UTF8_PATH_BYTES = 131064 -- Native UTF-16/unit and command limits remain authoritative.
-- The native pipe names belong to this process, including across Lua reloads.
local OWNER_KEY = 'epic_lut.platform.native_owner'
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function number(bytes, at)
    local a,b,c,d = bytes:byte(at,at+3)
    assert(d, 'Truncated platform response')
    return a+b*256+c*65536+d*16777216
end
local function path(value)
    assert(type(value)=='string' and #value>0 and #value<=MAX_UTF8_PATH_BYTES and not value:find('%z'), 'Invalid Windows path')
    return value
end
function N.new(options)
    options=options or {}
    local library=path(assert(options.library, 'Packaged platform library required'))
    local directory=assert(library:match('^(.*)[/\\][^/\\]+$'), 'Absolute platform library path required')
    assert(directory:match('^%a:[/\\]') or directory:match('^[/\\][/\\]'), 'Absolute platform library path required')
    local sr=rawget(_G,'stingray')
    local pid=options.process_id or sr and sr.Application and sr.Application.process_id()
    assert(type(pid)=='number' and pid>0 and pid<4294967296 and pid%1==0, 'Current process identity required')
    local owners=package.loaded[OWNER_KEY]
    if owners==nil then owners={};package.loaded[OWNER_KEY]=owners end
    assert(type(owners)=='table' and not owners.active, 'Windows platform service is already open; close before replacing')
    local function symbol(name)
        local fn,why=package.loadlib(library,name)
        assert(type(fn)=='function',why or ('Platform export unavailable: '..name))
        return fn
    end
    local begin,invoke,finish=symbol('epic_lut_platform_open'),symbol('epic_lut_platform'),symbol('epic_lut_platform_close')
    local base='\\\\.\\pipe\\EpicLutPlatform-'..string.format('%.0f',pid)
    local request,response
    local streams={}
    local hash_leases={}
    local busy,nonce,closed=false,0,false
    local owner={}
    owners.active=owner
    local self={}
    function self.close()
        assert(not busy,'Platform request is active')
        if closed then return true end
        if request then pcall(request.close,request);request=nil end
        if response then pcall(response.close,response);response=nil end
        local stopped,why=pcall(finish)
        closed=true
        for stream,state in pairs(streams) do state.closed=true;streams[stream]=nil end
        for token,state in pairs(hash_leases) do state.cancelled=true;hash_leases[token]=nil end
        if owners.active==owner then owners.active=nil end
        if not stopped then error(why,0) end
        return true
    end
    local function exact(count)
        local bytes=response:read(count)
        assert(type(bytes)=='string' and #bytes==count,'Platform response is truncated')
        return bytes
    end
    local function transact(op,payload)
        payload=payload or ''
        assert(not closed,'Platform service is closed')
        assert(type(payload)=='string' and #payload<=MAX_PAYLOAD,'Platform request exceeds budget')
        assert(not busy,'Platform request is already active')
        busy=true
        local ok,status,result=pcall(function()
            nonce=nonce%2147483647+1
            assert(request:write('ELP1'..word(nonce)..word(op)..word(#payload)..payload))
            assert(request:flush())
            invoke()
            local header=exact(16)
            assert(header:sub(1,4)=='ELR1' and number(header,5)==nonce,'Platform response identity differs')
            local size=number(header,13)
            assert(size<=MAX_PAYLOAD,'Platform response exceeds budget')
            return number(header,9),size>0 and exact(size) or ''
        end)
        busy=false
        if not ok then self.close();error(status,0) end
        return status,result
    end
    local function checked(op,payload)
        local status,result=transact(op,payload)
        assert(status==0,'Windows platform operation '..op..' failed ('..status..')')
        return result
    end
    local ready,reason=pcall(function()
        begin()
        request=assert(io.open(base..'-request','wb'))
        response=assert(io.open(base..'-response','rb'))
        assert(request:setvbuf('no'));assert(response:setvbuf('no'))
        assert(checked(0)=='1', 'Unsupported Windows platform service version')
    end)
    if not ready then self.close();error(reason,0) end
    function self.validate_utf8(text)
        assert(type(text)=='string' and #text<=32768 and not text:find('%z'),'Invalid UTF-8 text bounds')
        return checked(1,text)
    end
    function self.process_id() return pid end
    local function release_digest(token,state)
        if not hash_leases[token] then return true end
        hash_leases[token]=nil;state.cancelled=true
        if not closed then
            local ok,code=pcall(transact,25,token)
            if not ok then return nil,tostring(code) end
            if code~=0 and code~=6 then return nil,'Windows digest cancel failed ('..code..')' end
        end
        return true
    end
    local function reap_digests()
        -- At most eight active leases; only a new explicit digest does this work.
        for token,state in pairs(hash_leases) do
            local thread=state.owner and state.owner[1]
            if state.owner and (not thread or coroutine.status(thread)=='dead') then
                local ok,why=release_digest(token,state);assert(ok,why)
            end
        end
    end
    function self.cancel_digest(thread)
        assert(type(thread)=='thread','Digest owner coroutine required')
        local count=0
        for token,state in pairs(hash_leases) do
            if state.owner and state.owner[1]==thread then
                local ok,why=release_digest(token,state);assert(ok,why);count=count+1
            end
        end
        return count
    end
    function self.digest(input,expected)
        assert(type(input)=='string' or type(input)=='function','Digest bytes or reader required')
        assert(expected==nil or type(expected)=='number' and expected>=0
            and expected<=9007199254740991 and expected%1==0,'Invalid digest length')
        if type(input)=='string' then
            assert(#input<=8*1024*1024,'Digest byte-string budget exceeded')
            assert(expected==nil or expected==#input,'Digest length differs')
        end
        reap_digests()
        local cooperative=m and m.cooperative or require('src.core.cooperative')
        local limit=expected or 512*1024*1024
        local token=checked(22,string.char(expected~=nil and 1 or 0)
            ..word((expected or 0)%4294967296)..word(math.floor((expected or 0)/4294967296)))
        if #token~=4 or number(token,1)==0 then self.close();error('Invalid digest ownership token',0) end
        local thread=coroutine.running()
        local state={owner=thread and setmetatable({thread},{__mode='v'}) or nil}
        hash_leases[token]=state
        local function run()
            local total,at=0,1
            while true do
                assert(not state.cancelled and not closed,'Digest cancelled')
                local bytes
                if type(input)=='string' then
                    if at>#input then break end
                    bytes=input:sub(at,at+65535);at=at+#bytes
                else bytes=input() end
                assert(not state.cancelled and not closed,'Digest cancelled')
                if bytes==nil then break end
                assert(type(bytes)=='string' and #bytes>0 and #bytes<=65536,'Invalid digest reader chunk')
                total=total+#bytes;assert(total<=limit,'Digest length exceeds budget')
                checked(23,token..bytes)
            end
            assert(expected==nil or total==expected,'Digest length differs')
            local digest=checked(24,token)
            hash_leases[token]=nil
            assert(#digest==64 and not digest:find('[^0-9a-f]'),'Invalid SHA256 result')
            return digest
        end
        local ok,value=cooperative.call(run)
        if not ok then release_digest(token,state);error(value,0) end
        return value
    end
    function self.open(name,mode)
        local modes={rb=0,wb=1,ab=2}
        if modes[mode]==nil then return nil,'Unsupported binary file mode' end
        local valid,filename=pcall(path,name)
        if not valid then return nil,tostring(filename) end
        local status,token=transact(16,string.char(modes[mode])..filename)
        if status~=0 then return nil,'Windows open failed ('..status..')',status end
        if #token~=4 or number(token,1)==0 then self.close();error('Invalid file ownership token',0) end
        local stream,state={},{closed=false}
        streams[stream]=state
        local function retire(native)
            if state.closed then return true end
            state.closed=true;streams[stream]=nil
            if not native or closed then return true end
            local ok,code=pcall(transact,21,token)
            if not ok then return nil,tostring(code) end
            if code~=0 then return nil,'Windows close failed ('..code..')' end
            return true
        end
        local function failure(why,native)
            retire(native)
            return nil,why
        end
        local function usable()
            if state.closed or closed then return nil,'File is closed' end
            return true
        end
        local function operation(op,payload)
            local ok,code,bytes=pcall(transact,op,token..(payload or ''))
            if not ok then state.closed=true;streams[stream]=nil;return nil,tostring(code) end
            if code~=0 and not(op==17 and code==38) then
                return failure('Windows file operation '..op..' failed ('..code..')',false)
            end
            return code,bytes
        end
        function stream:close() return retire(true) end
        function stream:read(format)
            local open,why=usable();if not open then return nil,why end
            local all=format=='*a'
            if not all and not(type(format)=='number' and format>=0 and format<=MAX_FILE_BYTES+1 and format%1==0) then
                return failure('Read requires a bounded byte count or *a',true)
            end
            local remaining=all and MAX_FILE_BYTES or format
            local parts,total={},0
            repeat
                local count=math.min(remaining,MAX_PAYLOAD)
                local code,bytes=operation(17,word(count))
                if code==nil then return nil,bytes end
                if code==38 then
                    if all then return table.concat(parts) end
                    return total>0 and table.concat(parts) or nil
                end
                if #bytes>count then return failure('Invalid file read size',true) end
                if #bytes>0 then
                    total=total+#bytes
                    if total>MAX_FILE_BYTES then return failure('File size exceeds 64 MiB',true) end
                    parts[#parts+1]=bytes;remaining=remaining-#bytes
                end
                if count==0 then return total>0 and table.concat(parts) or '' end
                if #bytes==0 then return failure('File read made no progress',true) end
                if not all and remaining==0 then return table.concat(parts) end
                if all and remaining==0 then
                    local eof,eof_error=operation(17,word(0))
                    if eof==38 then return table.concat(parts) end
                    if eof==nil then return nil,eof_error end
                    return failure('File size exceeds 64 MiB',true)
                end
            until false
        end
        function stream:write(...)
            local open,why=usable();if not open then return nil,why end
            local count,total,parts=select('#',...),0,{}
            for index=1,count do
                local bytes=select(index,...)
                if type(bytes)=='number' and bytes==bytes and bytes~=math.huge and bytes~=-math.huge then
                    -- Match stock Lua5.1's default LUA_NUMBER_FMT.
                    bytes=string.format('%.14g',bytes)
                end
                if type(bytes)~='string' or #bytes>MAX_FILE_BYTES-total then
                    return failure('Write requires binary strings or finite numbers up to 64 MiB',true)
                end
                total=total+#bytes;parts[index]=bytes
            end
            -- Validate every argument and the aggregate budget before the first
            -- native write. Keep segments separate instead of copying 64MiB.
            if count>0 and total==0 then parts={''};count=1 end
            for index=1,count do
                local bytes,at=parts[index],1
                if #bytes>0 or total==0 then
                    repeat
                        local part=bytes:sub(at,at+MAX_PAYLOAD-5)
                        local code,receipt=operation(18,part)
                        if code==nil then return nil,receipt end
                        if #receipt~=4 or number(receipt,1)~=#part then return failure('Incomplete file write',true) end
                        at=at+#part
                    until at>#bytes
                end
            end
            return self
        end
        function stream:seek(whence,offset)
            local open,why=usable();if not open then return nil,why end
            whence,offset=whence or 'cur',offset or 0
            local origins={set=0,cur=1,['end']=2}
            if origins[whence]==nil or type(offset)~='number' or offset%1~=0
                or offset < -MAX_STREAM_POSITION or offset>MAX_STREAM_POSITION then
                return failure('Invalid exact file seek',true)
            end
            local code,receipt=operation(28,word(origins[whence])..word(offset%4294967296)
                ..word(math.floor(offset/4294967296)%4294967296))
            if code==nil then return nil,receipt end
            if #receipt~=8 then return failure('Invalid file position',true) end
            local position=number(receipt,1)+number(receipt,5)*4294967296
            if position>MAX_STREAM_POSITION then return failure('Inexact file position',true) end
            return position
        end
        function stream:flush()
            local open,why=usable();if not open then return nil,why end
            local code,error=operation(20)
            if code==nil then return nil,error end
            return true
        end
        return stream
    end
    function self.executable_path() return path(checked(11)) end
    function self.launch_worker(args,folder)
        assert(type(args)=='string' and #args>0 and #args<=MAX_UTF8_PATH_BYTES and not args:find('%z'), 'Invalid worker arguments')
        folder=path(folder)
        local receipt=checked(12,word(#args)..args..folder)
        assert(#receipt==8,'Invalid worker receipt')
        local token,worker_pid=number(receipt,1),number(receipt,5)
        assert(token>0 and worker_pid>0,'Invalid worker identity')
        local worker={pid=worker_pid,handle=token}
        local released=false
        function worker.running()
            if released then return false end
            local bytes=checked(13,word(token))
            assert(#bytes==4,'Invalid worker state')
            local state=number(bytes,1)
            assert(state==0 or state==1,'Invalid worker running state')
            return state==1
        end
        function worker.stop()
            if released then return true end
            local status=transact(14,word(token))
            if status~=0 then return false,'Could not stop owned worker (Windows '..status..')' end
            return true
        end
        function worker.close()
            if released then return true end
            local status=transact(15,word(token))
            if status~=0 then return false,'Could not release owned worker (Windows '..status..')' end
            released,worker.handle=true,nil
            return true
        end
        return worker
    end
    function self.stat(name)
        local status,bytes=transact(5,path(name))
        if status==2 or status==3 then return nil end
        assert(status==0,'Windows stat failed ('..status..')')
        local kind,size,stamp=bytes:match('^([FD])\t(%x+)\t(%x+)$')
        assert(kind and #size==16 and #stamp==16,'Invalid platform file metadata')
        return {directory=kind=='D',size_hex=size,stamp=stamp}
    end
    function self.directory_exists(name)
        local value=self.stat(name)
        return value~=nil and value.directory
    end
    function self.mkdir(name) checked(4,path(name));return true end
    function self.mkdir_new(name) checked(7,path(name));return true end
    function self.rmdir(name)
        local status=transact(8,path(name))
        return status==0,status~=0 and ('Windows rmdir failed ('..status..')') or nil
    end
    function self.replace(source,destination)
        source,destination=path(source),path(destination)
        checked(9,word(#source)..source..destination)
        return true
    end
    function self.rename(source,destination)
        source,destination=path(source),path(destination)
        local status=transact(27,word(#source)..source..destination)
        if status~=0 then return nil,'Windows rename failed ('..status..')' end
        return true
    end
    function self.remove(name)
        local status=transact(26,path(name))
        if status~=0 then return nil,'Windows remove failed ('..status..')' end
        return true
    end
    function self.open_folder(name) checked(10,path(name));return true end
    function self.files(directory,pattern)
        pattern=pattern or '*'
        assert(type(pattern)=='string' and #pattern<=240 and not pattern:find('[/\\%z]'), 'Invalid file pattern')
        local match='^'..pattern:gsub('([%%%.%+%-%^%$%(%)%[%]])','%%%1'):gsub('%*','.*'):gsub('%?','.')..'$'
        local bytes=checked(6,path(directory))
        local files,directories={},{}
        for line in bytes:gmatch('[^\n]+') do
            local kind,name=line:match('^([FD])\t([^\t\r\n]+)$')
            assert(kind and name~='.' and name~='..' and not name:find('[/\\%z]'), 'Invalid directory listing')
            if name:lower():match(match:lower()) then
                local out=kind=='F' and files or directories
                out[#out+1]=name
            end
        end
        table.sort(files);table.sort(directories)
        return files,directories
    end
    self.clipboard={}
    function self.clipboard.get()
        local status,bytes=transact(2)
        if status~=0 then return nil,'Clipboard unavailable (Windows '..status..').' end
        if #bytes>32768 or bytes:find('%z') then return nil,'Clipboard text is invalid.' end
        return bytes
    end
    function self.clipboard.set(text)
        if type(text)~='string' or #text>32768 or text:find('%z') then return false,'Clipboard text is invalid.' end
        local status=transact(3,text)
        if status~=0 then return false,'Clipboard unavailable (Windows '..status..').' end
        return true
    end
    return self
end
return N
