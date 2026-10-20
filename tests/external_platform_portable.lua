-- Constructor/launcher failures must stay side-effect free under stock Lua5.1.
assert(_VERSION=='Lua 5.1')
ffi,bit,jit=nil,nil,nil
local E=dofile('src/platform/external_platform.lua')
local R=dofile('src/platform/runtime_services.lua')
local old_open,old_popen,old_getenv=io.open,io.popen,os.getenv
local launches,opens,closes=0,0,0
os.getenv=function(name)if name=='SystemRoot'then return 'C:/Windows'end;return old_getenv(name)end
io.popen=function()launches=launches+1;error('Unexpected OS launch')end
io.open=function()opens=opens+1;error('Unexpected pipe open')end
local options={backend='external',service="C:/private SERVICE HASH CLIENT @{HASH}/David's \232\183\175\229\190\132/service.exe",sha256=string.rep('a',64)}
local command=E.command(options,123)
assert(type(command)=='string' and command:find(' -EncodedCommand ',1,true) and #command<=32766)
assert(launches==0 and opens==0,'Pure command construction launched work')
assert(not pcall(E.command,{service='C:/'..string.rep('x',20000)..'.exe',sha256=options.sha256},123))
assert(not pcall(E.command,{service='relative.exe',sha256=options.sha256},123))
assert(not pcall(E.command,{service=options.service,sha256='bad'},123))
for _,image in ipairs({'a','00','61',string.rep('aa',131065)})do
    io.popen=function()launches=launches+1;return {
        read=function()return 'ELX1 123 456 '..string.rep('b',64)..' '..image end,
        close=function()closes=closes+1;return true end}end
    assert(not pcall(E.start,options,123),'Malformed launcher image was accepted')
    assert(opens==0,'Malformed receipt acquired pipe ownership')
end
assert(closes==4 and launches==4)
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
