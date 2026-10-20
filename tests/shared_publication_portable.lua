-- Real stock serialization/compression/publication lifecycle; transport is explicit.
local B=require('src.core.float_buffer')
local Codec=dofile('src/gear/shared_lut_codec.lua')
local Sharing=dofile('src/gear/shared_appearance.lua')
local codec=Codec.new()
local d={width=23,height=8,data=B.new(736)}
for i=0,735 do d.data[i]=(i%13)/16 end
d.data[3]=-1/math.huge
local entries={}
for i=0,154 do entries[i+1]={key='0:0:'..math.floor(i/64)..':'..i%64,document=d} end
local revision,published,scans,polls=1,nil,0,0
local time=0
local deps={defer_publication=true,codec=codec,note=function()end,
 identity=function()return{body=1,armor=2,helmet=3}end,
 identity_key=function()return'same-kit'end,revision=function()return revision end,
 highlighting=function()return false end,
 entries=function()scans=scans+1;return entries end,
 publication_clock=function()time=time+0.003;return time end,
 sync={session=function()return{poll=function(_,packet)polls=polls+1;published=packet;return{}end,clear=function()return true end}end}}
local sharing=Sharing.new(deps)
local bytes_calls=0
local old_bytes=B.bytes
B.bytes=function(...)bytes_calls=bytes_calls+1;return old_bytes(...)end
sharing.tick(2,true)
local steps,worst=0,0
while not published and steps<10000 do
    local started=os.clock();sharing.tick(2,true)
    worst=math.max(worst,os.clock()-started);steps=steps+1
end
B.bytes=old_bytes
assert(published and steps>3,'Real publication did not complete as a sliced Lua5.1 job')
local decoded=codec.decode(published)
for _,entry in ipairs(entries)do
    assert(B.bytes(decoded.entries[entry.key].document.data,736)==B.bytes(d.data,736))
end
assert(scans==1 and bytes_calls<12,'Shared publication repeated binding scans or per-binding palette serialization')
local count=scans
for _=1,1000 do sharing.tick(0,true)end
assert(scans==count,'Unchanged appearance repeated local discovery')
revision=2;sharing.tick(2,true)
sharing.tick(0,false)
local canceled=scans
for _=1,100 do sharing.tick(0,false)end
assert(scans==canceled,'Disabled publication resumed stale work')
sharing.close()
print(string.format('PASS real Lua5.1 sharing publication:155 bindings,%d slices,%d serializations,%.3fms worst offline slice',steps,bytes_calls,worst*1000))
