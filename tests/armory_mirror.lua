local ffi=require('ffi')
local A=dofile('src/gear/armory_mirror.lua')
local doc={width=23,height=8,data=ffi.new('float[736]')}
local applied,restored=0,0
local preview_helmet=999
local preview_exists=true
local mirror=A.new({identity=function()return {ui_slot=0,body=1,armor=2,helmet=3}end,
    locate=function(slot)assert(slot==0);return {}end,
    watch=function()return {poll=function()return preview_exists and 'kits' or 'absent'end,kits=function()return preview_helmet,2,1 end}end,
    units=function()return {{unit=11,type=0,slot=1},{unit=12,type=0,slot=0}}end,
    materials=function(unit)return {{mesh=unit,material=unit,mesh_index=0,material_index=0}}end,
    is_cape=function()return false end,slot=function(pattern)return pattern and 2 or 1 end,
    binding=function()return 100 end,
    entries=function()return {['0:1:0:0']={document=doc,helmet=false},['0:0:0:0']={document=doc,helmet=true}}end,
    session=function()return {restore=function()restored=restored+1;return true end,apply=function(_,targets)
        for _,b in ipairs(targets)do assert(b.unit==11 or preview_helmet==3,'Unrelated hovered helmet recolored')end
        applied=applied+1
    end}end})
mirror.tick(.1)
assert(applied==1)
mirror.tick(.1)
assert(applied==1,'Unchanged Armory preview was rebound')
preview_helmet=3
mirror.tick(.1)
assert(applied==2)
preview_exists=false
mirror.tick(.1)
assert(mirror.close() and restored>=3)
print('PASS Armory mirror: only matching local preview kits, unchanged no-op, absence and cleanup')
