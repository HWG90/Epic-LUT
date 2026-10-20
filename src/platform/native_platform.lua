-- Explicit user-action Windows services through a Lua 5.1-loadable C function.
-- The C callback returns no Lua values and never inspects lua_State/game memory.
local N = { MAX_PAYLOAD = 1024 * 1024 }
local MAX_PAYLOAD = N.MAX_PAYLOAD
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
    assert(type(value)=='string' and #value>0 and #value<=32760 and not value:find('%z'), 'Invalid Windows path')
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
