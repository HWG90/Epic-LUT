-- Execute the packaged DLL against owned memory, never a running game.
jit.off()
local ffi = require('ffi')
local Events = dofile('src/weapons/weapon_events.lua')
local binary = dofile('src/weapons/weapon_event_binary.lua')
local callback_count, mask, unloaded, library, api = 0, 0, false
local engine = {PluginManager = {
    load_plugin = function(path)
        library = ffi.load(path)
        ffi.cdef[[void *get_plugin_api(unsigned);]]
        api = ffi.cast('void **', library.get_plugin_api(0))
        return binary.name
    end,
    unload_plugin = function(name) assert(name == binary.name); unloaded = true end,
}}
local service = Events.new(binary, engine, 'tests/tmp/cache', function(changed)
    callback_count, mask = callback_count + 1, changed
end)
assert(service.tick == nil and service.update == nil, 'Native subscription gained a polling interface')
local keep = {}
local function alloc(size)
    local b = ffi.new('uint8_t[?]', size); keep[#keep + 1] = b
    return tonumber(ffi.cast('uintptr_t', b))
end
local function u32(at, value) ffi.cast('uint32_t *', at)[0] = value end
local function ptr(at, value) ffi.cast('uintptr_t *', at)[0] = value end
local function map(at, key, index)
    local data = alloc(64); ptr(at, data); u32(at + 8, 8); u32(at + 12, 0xffffffff); u32(at + 16, 1)
    for n=0,7 do u32(data+n*8, 0xffffffff) end
    u32(data+(key%8)*8,key); u32(data+(key%8)*8+4,index)
end
local game, owner, inv = alloc(0x346bfa0), alloc(0xf32f18+240), alloc(0x60)
local avatar, registry, inventory = alloc(24), alloc(8), alloc(48)
ptr(game+0x346bf98,owner); ptr(game+0x3326738,inv)
u32(inv+0x14,1); map(inv+0x28,10,0); ptr(inv+0x40,registry); ptr(registry,avatar); ptr(inv+0x50,inventory)
ffi.cast('uint64_t *',avatar)[0] = 0x4d1c334d294dfa97ULL
u32(avatar+8,10); u32(avatar+16,20); u32(avatar+20,1)
service.watch({game=game,owner=owner,inventory=inv,avatar=10,avatar_ref=20,inventory_index=0})
local event = ffi.cast('void (*)(void *,void *,unsigned)',api[23])
for n=1,100 do event(nil,nil,0) end
assert(api[12] == nil and library.epic_stat(0) == 0 and callback_count == 0)
event(nil,nil,1)
assert(api[12] ~= nil)
ffi.cast('void (*)(float)', api[12])(0)
assert(api[12] == nil and library.epic_stat(1) == 1 and callback_count == 0)
u32(inventory,33); map(owner+0xf1aeb0,33,1)
local record=owner+0xf32f18+24
ptr(record,123); u32(record+8,33); u32(record+12,999); u32(record+20,1)
event(nil,nil,1); event(nil,nil,1)
ffi.cast('void (*)(float)',api[12])(0)
assert(api[12] == nil and callback_count == 1 and mask == 1 and library.epic_stat(1) == 2)
-- Death invalidates the old receipt, but must not unsubscribe from respawn.
u32(avatar+20,0)
event(nil,nil,1);ffi.cast('void (*)(float)',api[12])(0)
assert(callback_count==2 and mask==15 and library.epic_stat(4)==0 and api[12]==nil)
local checks=library.epic_stat(1)
assert(api[12]==nil and library.epic_stat(1)==checks, 'Missing actor enabled continuous checking')
event(nil,nil,1);event(nil,nil,1)
ffi.cast('void (*)(float)',api[12])(0)
assert(callback_count==3 and mask==15 and api[12]==nil, 'Respawn event could not wake the expired watch')
u32(avatar+20,1);u32(avatar+16,21)
service.watch({game=game,owner=owner,inventory=inv,avatar=10,avatar_ref=21,inventory_index=0})
assert(library.epic_stat(4)==1)
event(nil,nil,1);ffi.cast('void (*)(float)',api[12])(0)
assert(callback_count==3 and api[12]==nil, 'Rearmed unchanged actor did not become idle')
local players=alloc(0x500)
ptr(game+0x3326468,players);u32(players+0x84,1);map(players+0xd0,7,0);u32(players+0x3a8,21)
service.watch({game=game,owner=owner,inventory=inv,avatar=10,avatar_ref=21,inventory_index=0,
    players=players,player_id=7,player_index=0})
-- Old inventory/actor stays perfectly valid after the current player respawns.
u32(players+0x3a8,22)
event(nil,nil,1);ffi.cast('void (*)(float)',api[12])(0)
assert(callback_count==4 and mask==15 and library.epic_stat(4)==0,
    'Still-live old avatar inventory hid the current player respawn')
service.close(); service.close(); event(nil,nil,1)
assert(unloaded and api[12] == nil and callback_count == 4)
print('PASS packaged native events: empty batches idle, coalesced one-shot check, changed-slot callback and inert cleanup')
