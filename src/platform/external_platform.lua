-- Explicit OS-only external service transport. No DLL loading or game API calls.
-- Launch once, use requests only for active work, close both pipes on retirement.
local E = {}
local digits = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(bytes)
    local out = {}
    for at = 1, #bytes, 3 do
        local a,b,c = bytes:byte(at, at+2)
        local value = a*65536 + (b or 0)*256 + (c or 0)
        out[#out+1] = digits:sub(math.floor(value/262144)%64+1, math.floor(value/262144)%64+1)
            ..digits:sub(math.floor(value/4096)%64+1, math.floor(value/4096)%64+1)
            ..(b and digits:sub(math.floor(value/64)%64+1, math.floor(value/64)%64+1) or '=')
            ..(c and digits:sub(value%64+1, value%64+1) or '=')
    end
    return table.concat(out)
end
local function utf16(bytes)
    local out, at = {}, 1
    while at <= #bytes do
        local a,b,c,d = bytes:byte(at,at+3)
        local n,width = a,1
        if a>=194 and a<=223 then n,width=(a-192)*64+(b or 0)-128,2
        elseif a>=224 and a<=239 then n,width=(a-224)*4096+((b or 0)-128)*64+(c or 0)-128,3
        elseif a>=240 and a<=244 then n,width=(a-240)*262144+((b or 0)-128)*4096+((c or 0)-128)*64+(d or 0)-128,4
        else assert(a>=32 and a<=127 or a==9 or a==10 or a==13,'Invalid launcher UTF-8') end
        for index=2,width do local v=bytes:byte(at+index-1);assert(v and v>=128 and v<=191,'Invalid launcher UTF-8') end
        assert(n>=0 and n<=1114111 and not(n>=55296 and n<=57343)
            and (width~=3 or n>=2048) and (width~=4 or n>=65536),'Invalid launcher scalar')
        if n>65535 then
            n=n-65536
            local high,low=55296+math.floor(n/1024),56320+n%1024
            out[#out+1]=string.char(high%256,math.floor(high/256),low%256,math.floor(low/256))
        else out[#out+1]=string.char(n%256,math.floor(n/256)) end
        at=at+width
    end
    return table.concat(out)
end
local function literal(value) return "'"..value:gsub("'","''").."'" end
local function unhex(value)
    assert(#value>0 and #value%2==0 and #value<=262128 and not value:find('[^0-9a-f]'),'Invalid launcher image receipt')
    return (value:gsub('..',function(pair)return string.char(tonumber(pair,16))end))
end
function E.encode_script(script)
    assert(type(script)=='string' and #script>0 and #script<=131064,'Bounded UTF-8 script required')
    local encoded=base64(utf16(script))
    assert(#encoded<=32766,'Encoded script exceeds Windows command-line limit')
    return encoded
end
function E.command(options,pid)
    local service,hash=options.service,options.sha256
    assert(type(service)=='string' and #service>0 and #service<=131064
        and (service:match('^%a:[/\\]') or service:match('^[/\\][/\\]'))
        and not service:find('[%z\1-\31\127"]'),'Absolute external service path required')
    assert(type(hash)=='string' and #hash==64 and not hash:find('[^0-9a-f]'),'Exact external service SHA256 required')
    assert(type(pid)=='number' and pid>0 and pid<4294967296 and pid%1==0,'Actual client PID required')
    assert(type(io.popen)=='function','Public Lua process launch is unavailable')
    local script=[=[$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$child=$null;$ready=$null;$exited=$null;$source=$null
try {
 $service=@{SERVICE};$expected=@{HASH};$client=@{CLIENT}
 $algorithm=[Security.Cryptography.SHA256]::Create();$source=[IO.File]::OpenRead($service)
 try {$actual=[BitConverter]::ToString($algorithm.ComputeHash($source)).Replace('-','').ToLowerInvariant()}
 finally {$algorithm.Dispose()}
 if($actual -ne $expected){throw 'External service hash differs'}
 $image=(& $service --describe $client | Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $image -notmatch '^[0-9a-f]+$'){throw 'Cannot identify client executable'}
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create();$bytes=New-Object byte[] 32
 try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}
 $token=[BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant()
 $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,('Local\EpicLutExternal-'+$token))
 $child=Start-Process -FilePath $service -ArgumentList @('--client',[string]$client,'--token',$token,'--image',$image) -WindowStyle Hidden -PassThru
 $exited=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset)
 $exited.SafeWaitHandle=[Microsoft.Win32.SafeHandles.SafeWaitHandle]::new($child.Handle,$false)
 if([Threading.WaitHandle]::WaitAny([Threading.WaitHandle[]]@($ready,$exited),8000) -ne 0){throw 'External service readiness failed'}
 [Console]::Out.WriteLine(('ELX1 '+$client+' '+$child.Id+' '+$token+' '+$image))
} catch {
 if($child -and -not $child.HasExited){$child.Kill()}
 [Console]::Out.WriteLine(('ELX_ERROR '+$_.Exception.Message));exit 1
} finally {
 if($exited){$exited.Dispose()};if($ready){$ready.Dispose()};if($child){$child.Dispose()};if($source){$source.Dispose()}
}
]=]
    local values={SERVICE=literal(service),HASH=literal(hash),CLIENT=string.format('%.0f',pid)}
    script=script:gsub('@{([A-Z]+)}',function(key)return assert(values[key])end)
    -- Only the known system PowerShell executable is launched; no policy flags.
    local system=assert(os.getenv('SystemRoot'),'Windows SystemRoot unavailable')
    assert(not system:find('[%z\1-\31\127"]'),'Invalid Windows system path')
    local command='"'..system..'\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
        ..E.encode_script(script)
    assert(#command<=32766,'External launcher exceeds Windows command-line limit')
    return command
end
function E.start(options,pid)
    local command=E.command(options,pid)
    local launcher=assert(io.popen(command,'r'),'Cannot start external OS-service launcher')
    -- Read the readiness line, never the inherited child stream through EOF.
    local line=launcher:read('*l')
    launcher:close()
    assert(type(line)=='string' and #line<=262400,'External launcher returned no receipt')
    local client,server,token,image=line:match('^ELX1 (%d+) (%d+) ([0-9a-f]+) ([0-9a-f]+)%s*$')
    assert(client and tonumber(client)==pid and tonumber(server)>0 and tonumber(server)<4294967296
        and tonumber(server)~=pid and #token==64,'External launcher failed: '..line:sub(1,240))
    local image_bytes=unhex(image)
    assert(not image_bytes:find('[%z\1-\31\127]')
        and (image_bytes:match('^%a:[/\\]') or image_bytes:match('^[/\\][/\\]')),
        'Invalid launcher executable path')
    local prefix='\\\\.\\pipe\\EpicLutExternal-'..client..'-'..token
    local request,response
    local ok,why=pcall(function()
        request=assert(io.open(prefix..'-request','wb'),'External request pipe unavailable')
        response=assert(io.open(prefix..'-response','rb'),'External response pipe unavailable')
        assert(request:setvbuf('no'));assert(response:setvbuf('no'))
    end)
    if not ok then if request then request:close()end;if response then response:close()end;error(why,0)end
    return {request=request,response=response,token=token,server_pid=tonumber(server),image=image_bytes}
end
return E
