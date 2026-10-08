local ffi=require('ffi')
local f=assert(io.open('prototype/broadcast/runtime.lua','rb')); local source=f:read('*a'); f:close()
local people={{peer='0000000200000001',owned=true,unit=1},{peer='0000000400000003',owned=false,unit=2}}
local current={[101]=1001,[102]=1002,[103]=1003}
local shared=false
local m={remote={list=function() return people end},
    avatar={units=function(_,p) return {{unit=p.unit,slot=1}} end},
    bingus_runtime={},bingus_memory={new=function() return {
        verify_build=function() return true end,module=function() return 65536 end,
        address=function(x) return x end,read_into=function() return true end} end},
    engine={LUT_SLOT=5,at=function(x) return x end,
        open=function() return {commit=function() end} end,
        unit_materials=function(_,unit)
            if unit==1 then return {{material=shared and 102 or 101,mesh=201}} end
            return {{material=102,mesh=202},{material=103,mesh=203}}
        end,
        binding=function(_,material) return current[material] end,
        create_texture=function() return {object=9000} end,
        bind=function(_,material,_,object) current[material]=object end},
    dds={MAX_BYTES=1048576,decode=function(bytes)
        assert(bytes=='DDS fixture','Invalid DDS fixture'); return ffi.new('float[92]'),23,1
    end},binding_session=dofile('src/gear/binding_session.lua')}
local module=assert(loadstring('local m=...\n'..source))(m)
local getenv=os.getenv; os.getenv=function() return 'fixture' end
module.on_enable()
os.getenv=getenv
local function word(n) return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256) end
local packet='ELB1'..word(3)..word(4)..word(1)..word(1)..word(11)..'DDS fixture'
local open=io.open
io.open=function() return {read=function() return packet end,close=function() end} end
local api=EpicLUTBroadcast
assert(not pcall(api.receive,'0000000200000001'))
shared=true
assert(not pcall(api.receive,'0000000400000003'))
assert(current[101]==1001 and current[102]==1002)
shared=false
assert(api.receive('0000000400000003')==2)
assert(current[101]==1001 and current[102]==9000 and current[103]==9000)
assert(api.restore())
assert(current[102]==1002 and current[103]==1003)
packet=packet:sub(1,24)..'BAD fixture'
assert(not pcall(api.receive,'0000000400000003'))
module.on_disable(); assert(EpicLUTBroadcast==nil)
io.open=open
print('Receive: wrong peer, shared-material rejection, remote apply, local isolation, restore and invalid DDS passed')
