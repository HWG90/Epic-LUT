-- Real packaged native observer over fixture-owned memory, never the game.
jit.off()
local ffi=require('ffi')
local Events=dofile('src/gear/appearance_events.lua')
local binary=dofile('src/gear/appearance_event_binary.lua')
local library,api,closed,wakes=nil,nil,false,0
local engine={PluginManager={load_plugin=function(path)
    library=ffi.load(path);pcall(ffi.cdef,'void *get_plugin_api(unsigned);')
    api=ffi.cast('void **',library.get_plugin_api(0));return binary.name
end,unload_plugin=function(name)assert(name==binary.name);closed=true end}}
local keep={}
local function alloc(n)local b=ffi.new('uint8_t[?]',n);keep[#keep+1]=b;return tonumber(ffi.cast('uintptr_t',b))end
local function ptr(a,v)ffi.cast('uintptr_t *',a)[0]=v end
local function u32(a,v)ffi.cast('uint32_t *',a)[0]=v end
local function map(a,key,value)
    local data=alloc(64);ptr(a,data);u32(a+8,8);u32(a+12,0xffffffff);u32(a+16,1)
    for i=0,7 do u32(data+i*8,0xffffffff)end
    u32(data+key%8*8,key);u32(data+key%8*8+4,value)
end
local game,players,owner,avatars,custom=alloc(0x346bfa0),alloc(0x500),alloc(0xf32f18+24),alloc(5532272+440),alloc(2600)
ptr(game+0x3326468,players);ptr(game+0x346bf98,owner);ptr(game+0x3326d20,avatars);ptr(game+0x33264f8,custom)
local player=alloc(24);ptr(players+0xe8,player);u32(player+8,7);u32(player+20,1)
u32(players+0x84,1);map(players+0xd0,7,0);u32(players+0x3a8,21)
map(owner+0xf22ec8,21,0);ffi.cast('uint64_t *',owner+0xf32f18)[0]=0x4d1c334d294dfa97ULL
u32(owner+0xf32f18+8,10);u32(owner+0xf32f18+20,1)
map(avatars+248,10,0);u32(avatars+0x6c,1);map(custom+2352,7,0)
u32(avatars+5532272+220,123)
local s=Events.new(binary,engine,'tests/tmp/cache',game,function()wakes=wakes+1 end)
assert(s.update==nil and s.tick==nil and api[12]==nil)
local event=ffi.cast('void (*)(void *,void *,unsigned)',api[23])
local function step()assert(api[12]~=nil);ffi.cast('void (*)(float)',api[12])(0);assert(api[12]==nil)end
for _=1,1000 do event(nil,nil,0)end
assert(library.epic_appearance_stat(1)==0 and api[12]==nil)
event(nil,nil,1);event(nil,nil,1);step();assert(wakes==0 and library.epic_appearance_stat(1)==1)
u32(players+0x3a8,0x7fff);event(nil,nil,1);step();assert(wakes==1)
event(nil,nil,1);step();assert(wakes==1,'Unchanged missing actor repeatedly woke Lua')
u32(players+0x3a8,22);map(owner+0xf22ec8,22,0);event(nil,nil,1);step();assert(wakes==2)
u32(avatars+5532272+220,124);event(nil,nil,1);step();assert(wakes==3,'Same-actor garment replacement was missed')
event(nil,nil,1);step();assert(wakes==3 and library.epic_appearance_stat(3)==0)
s.close();s.close();event(nil,nil,1);assert(closed and api[12]==nil)
print('PASS appearance native events: real DLL, death/respawn/garment replacement, no weapons, no idle callbacks, coalescing and teardown')
