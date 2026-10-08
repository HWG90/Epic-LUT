local ffi=require('ffi')
local R=dofile('prototype/broadcast/remote.lua')
local values={}
local function put(address,...)
    local data=ffi.new('uint32_t[?]',select('#',...),{...})
    values[address]=ffi.string(data,select('#',...)*4)
end
local game,manager,entities,avatars=0x100000,0x200000,0x300000,0x400000
local avatar={PLAYERS=1,ENTITIES=2,AVATARS=3}
put(game+1,manager,0); put(game+2,entities,0); put(game+3,avatars,0)
put(manager+132,2); put(avatars+0x6c,2)
for i=0,1 do
    put(manager+232+8*i,0x500000+100*i,0)
    put(0x500000+100*i,0,0,10+i,0,0,i==0 and 1 or 0)
    put(manager+712+56*i,100+i,200+i)
    put(manager+936+32*i,20+i)
    put(entities+0xF32F18+24*i,0x294dfa97,0x4d1c334d,30+i,0,0,i==0 and 1 or 0)
end
function avatar.u32(b,o) return tonumber(ffi.cast('const uint32_t*',b+o)[0]) end
function avatar.reader()
    return function(address,size)
        local data=values[address]
        if not data or #data<size then return nil end
        return ffi.cast('const uint8_t*',data)
    end
end
function avatar.lookup(_,address,key)
    if address==manager+208 then return key-10 end
    if address==entities+0xF22EC8 then return key-20 end
    if address==avatars+248 then return key-30 end
end
local roster=R.list({},game,avatar)
assert(#roster==2 and roster[1].owned and not roster[2].owned)
assert(roster[2].peer=='000000c900000065')
assert(roster[2].units_at==avatars+5532272+440+220)
put(manager+132,9)
assert(not pcall(R.list,{},game,avatar))
put(manager+132,2); values[manager+936+32]=nil
assert(not pcall(R.list,{},game,avatar))
print('Remote roster: local/remote ownership, peer identity, bounds and incomplete roster passed')
