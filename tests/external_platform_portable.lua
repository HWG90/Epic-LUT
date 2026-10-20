-- Constructor/launcher failures must stay side-effect free under stock Lua5.1.
assert(_VERSION=='Lua 5.1')
ffi,bit,jit=nil,nil,nil
local E=dofile('src/platform/external_platform.lua')
local R=dofile('src/platform/runtime_services.lua')
local old_open,old_popen,old_getenv=io.open,io.popen,os.getenv
local launches,opens,closes=0,0,0
local unicode='\230\156\141\232\163\133'
local system='C:/Windows '..unicode
os.getenv=function(name)if name=='SystemRoot'then return system end;return old_getenv(name)end
io.popen=function()launches=launches+1;error('Unexpected OS launch')end
io.open=function()opens=opens+1;error('Unexpected pipe open')end
local options={backend='external',service="C:/private SERVICE HASH CLIENT @{HASH}/David's "..unicode.." \232\183\175\229\190\132/service.exe",sha256=string.rep('a',64)}
local command=E.command(options,123)
assert(type(command)=='string' and command:find(' -EncodedCommand ',1,true) and #command<=32766)
assert(command:find('"'..system..'\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"',1,true),
    'Unicode Windows system path was not preserved')
assert(launches==0 and opens==0,'Pure command construction launched work')
-- Independent UTF-16LE/base64 vector, including a supplementary scalar.
assert(E.encode_script('A\195\169\230\176\180\240\159\166\134')=='QQDpADRsPtiG3Q==')
for _,value in ipairs({'','x\0y','\192\175','\237\160\128','\244\144\128\128',string.rep('x',20000),string.rep('x',131065),false,12,{}})do
    assert(not pcall(E.encode_script,value),'Invalid/oversized script was encoded')
end
assert(not pcall(E.encode_script,nil) and launches==0 and opens==0)
assert(not pcall(E.command,{service='C:/'..string.rep('x',20000)..'.exe',sha256=options.sha256},123))
assert(not pcall(E.command,{service='relative.exe',sha256=options.sha256},123))
assert(not pcall(E.command,{service=options.service,sha256='bad'},123))
for _,byte in ipairs({0,1,9,10,13,31,127,34})do
    assert(not pcall(E.command,{service='C:/private'..string.char(byte)..'/service.exe',sha256=options.sha256},123),
        'ASCII path control or quote was accepted')
    local previous=system;system='C:/Windows'..string.char(byte)
    assert(not pcall(E.command,options,123),'ASCII system-path control or quote was accepted')
    system=previous
end
assert(not pcall(E.command,{service='C:/invalid-\192\175/service.exe',sha256=options.sha256},123),
    'Invalid UTF-8 service path was accepted')
local function hex(value)return (value:gsub('.',function(byte)return string.format('%02x',byte:byte())end))end
for _,image in ipairs({'a','00','61',string.rep('aa',131065)})do
    io.popen=function()launches=launches+1;return {
        read=function()return 'ELX1 123 456 '..string.rep('b',64)..' '..image end,
        close=function()closes=closes+1;return true end}end
    assert(not pcall(E.start,options,123),'Malformed launcher image was accepted')
    assert(opens==0,'Malformed receipt acquired pipe ownership')
end
assert(closes==4 and launches==4)
for _,byte in ipairs({0,1,9,10,13,31,127})do
    local image=hex('C:/client'..string.char(byte)..'/game.exe')
    io.popen=function()return {read=function()return 'ELX1 123 456 '..string.rep('b',64)..' '..image end,
        close=function()return true end}end
    assert(not pcall(E.start,options,123),'ASCII image-path control was accepted')
    assert(opens==0,'Malformed receipt acquired pipe ownership')
end
local image='C:/client '..unicode..'/game.exe'
local pipes={}
io.popen=function()return {read=function()return 'ELX1 123 456 '..string.rep('b',64)..' '..hex(image) end,
    close=function()return true end}end
io.open=function(path,mode)
    opens=opens+1
    assert(path=='\\\\.\\pipe\\EpicLutExternal-123-'..string.rep('b',64)..(mode=='wb' and '-request' or '-response'))
    local pipe={setvbuf=function(_,value)assert(value=='no');return true end,
        close=function(self)assert(not self.closed);self.closed=true;return true end}
    pipes[#pipes+1]=pipe;return pipe
end
local transport=E.start(options,123)
assert(opens==2 and transport.image==image and transport.server_pid==456,
    'Valid Unicode image path did not acquire the expected transport')
assert(transport.request:close() and transport.response:close() and pipes[1].closed and pipes[2].closed)
local received,retired
local model={platform_backend='external',native_platform_name='exact-service.exe',native_platform_sha256=options.sha256,
    native_platform={new=function(value)received=value;return {close=function()retired=true;return true end}end}}
local ctx={dir='C:/explicit package'}
local lease=R.start(model,ctx)
assert(lease.ready and received.backend=='external' and received.service=='C:/explicit package/exact-service.exe'
    and received.sha256==options.sha256 and received.library==nil)
assert(not retired and lease.close(true) and retired and model.platform==nil and ctx.platform==nil)
io.open,io.popen,os.getenv=old_open,old_popen,old_getenv
print('PASS explicit external launcher/bootstrap: no eager work, validated command bounds/identity receipts, zero acquired pipes on malformed receipts')
