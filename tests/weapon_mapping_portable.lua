local B = require('src.core.float_buffer')
local M = dofile('src/editor/weapon_mapping.lua')
local I = dofile('src/weapons/weapon_intent.lua')
local d={width=23,height=2,data=B.new(184),original=B.new(184),kind='weapon',weapon_slot=1}
for i=0,183 do d.data[i]=(i-90)/8;d.original[i]=i/8 end
d.data[3]=-1/math.huge
local original=M.bytes(d)
local copy=M.copy(d)
assert(copy.data~=d.data and copy.original~=d.original and M.bytes(copy)==original)
local fit=M.fit(d,23,5)
for row=0,4 do assert(B.bytes(fit.data,92,row*92)==B.bytes(d.data,92,(row%2)*92)) end
assert(not pcall(M.fit,d,3,1))
assert(not pcall(M.bytes,{width=23,height=2,data={_float_count=184}}))
local restores=0
local ready={}
local intent=I.new({weapon_mapping=M},{restore_slot=function(saved,slot)
    restores=restores+1
    assert(M.bytes(saved.entries[slot].document)==original)
    if ready[slot] then return 1 end
end,message=function()end})
local entries={}
for slot=1,3 do entries[slot]={kind='weapon',weapon_slot=slot,key='weapon:'..slot,document=d} end
intent.start({entries=entries})
for _=1,3 do intent.tick() end
assert(restores==3 and not intent.pending() and intent.recovering())
for _=1,1000 do intent.tick() end
assert(restores==3,'Idle restart recovery polled or reapplied')
ready[2]=true;intent.wake(2);intent.tick()
assert(restores==4 and not intent.pending())
ready[1],ready[3]=true,true;intent.wake(8);intent.tick();intent.tick()
assert(restores==6 and not intent.recovering())
assert(M.bytes(d)==original)
print('PASS portable weapon palette fit/copy and event-only three-slot restart intent')
