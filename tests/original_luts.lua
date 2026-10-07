local ffi=require('ffi');local O=dofile('src/original_luts.lua')
local original={width=23,height=2,data=ffi.new('float[?]',23*2*4)}
local imported={width=23,height=2,data=ffi.new('float[?]',23*2*4)}
for i=0,23*2*4-1 do original.data[i]=0;imported.data[i]=.75 end
original.data[(23+13)*4]=.0125;original.data[23*4+3]=2
local protected=O.preserve(imported,original)
assert(protected.data[13*4]==0,'Game-original zero emission was replaced with imported glow')
assert(protected.data[(23+13)*4]==original.data[(23+13)*4],'Game-original nonzero emissive strength was not preserved')
assert(protected.data[23*4+3]==2 and protected.data[0]==.75 and imported.data[13*4]==.75)
assert(not pcall(O.preserve,imported,nil),'Missing readback was silently converted into a zero value')
local D=dofile('src/dds.lua');D.write('tests/tmp/files/armor-00000001-0-0123456789abcdef-original.dds',original.data,23,2)
local m={dds=D,windows={files=function()return {'armor-00000001-0-0123456789abcdef-original.dds'}end},engine={texture_object=function(_,hash)assert(hash=='0123456789abcdef');return 123 end}}
local resolver=O.new(m,{files='tests/tmp/files'},{});local found=resolver.get(123)
assert(found and found.data[(23+13)*4]==original.data[(23+13)*4] and not resolver.get(456),'Original snapshot was assigned to the wrong live resource')
print('PASS game-original emissives: resource ID/object match, valid zero and nonzero strengths, original mode retained, imported colors untouched and missing-reference rejection')

-- Snapshot worker errors must never escape into the editor update loop.
local closed=0
local fake={dds=D,original_snapshot_script='23',original_snapshot_reader='23',engine=m.engine,windows={
 files=m.windows.files,verify_interface=function()return {},{epic_native_pid=function()return 1 end}end,
 launch_worker=function()return {running=function()error('injected worker polling failure')end,stop=function()error('injected stop failure')end,close=function()closed=closed+1 end}end}}
local safe=O.new(fake,{files='tests/tmp/files',originals='tests/tmp/files',cache='tests/tmp/cache'}, {},function()return {[123]=true}end)
safe.start();assert(pcall(safe.tick),'Snapshot error escaped into editor update')
assert(closed==1 and safe.status:find('paused',1,true),'Snapshot failure did not release ownership and report status')
assert(pcall(safe.close),'Snapshot cleanup failure escaped')
