local ffi=require('ffi')
local P=dofile('src/palette.lua')
local original=ffi.new('float[?]',23*8*4)
for i=0,23*8*4-1 do original[i]=(i%53-12)/7 end
local edited=P.copy(original,23,8,{[2]='#FF0080'},function(n)return ffi.new('float[?]',n)end,ffi.copy)
for i=0,23*8*4-1 do
    if i<2*23*4 or i>2*23*4+2 then assert(edited[i]==original[i],'non-color value changed')end
end
assert(edited[184]==1 and edited[185]==0 and math.abs(edited[186]-128/255)<1e-6)
assert(not pcall(P.copy,original,23,8,{[8]='#FF0000'},function(n)return ffi.new('float[?]',n)end,ffi.copy))
assert(not pcall(P.rgb,'#GG0000'))
local S=dofile('src/session.lua');local bound=100;local alive=true;local membership=true;local failed=false;local committed=0
local lut={name='0123456789abcdef',width=23,height=8,values=original}
local native={alive=function()return alive and 1 or 0 end,commit=function()committed=committed+1 end}
local m={palette=P,avatar={units=function()return {}end},engine={LUT_SLOT=1,
    binding=function()return bound end,unit_materials=function()return membership and {{mesh=2,material=3}}or {}end,
    texture_object=function()return 100 end,create_texture=function(n,w,h,data)return {object=200,data=data}end,
    bind=function(n,material,slot,object)bound=object;if failed then error('bind failed after mutation')end end}}
local retained={records={},bytes=0};local session=S.new(m,{read_into=function()return true end},native,retained)
local cat={luts={lut},pieces={['0:2']=true},identity={}}
session.capture(cat,{{unit=1,type=0,slot=2}})
failed=true
assert(session.restore() and bound==100 and committed==0,'Untouched original binding invoked native restoration')
failed=false;session.capture(cat,{{unit=1,type=0,slot=2}})
failed=true
assert(session.apply({get=function()return false end},{[lut.name]=original})and bound==100 and committed==0 and #retained.records==0,'Unchanged document created or rebound a texture')
failed=false
local handle={get=function(id)if id:match('_on$')then return true else return '#00FF00'end end}
session.apply(handle);assert(bound==200 and committed==1 and #retained.records==1)
assert(session.restore() and bound==100)
assert(not pcall(session.apply,handle),'Empty restored binding set accepted an edit')
session.capture(cat,{{unit=1,type=0,slot=2}});bound=999
assert(not pcall(session.apply,handle));assert(session.restore() and bound==999,'foreign binding overwritten')
bound=100;session.capture(cat,{{unit=1,type=0,slot=2}});session.apply(handle);membership=false
assert(session.restore() and bound==200,'stale material called')
membership=true;bound=100;session.capture(cat,{{unit=1,type=0,slot=2}});failed=true
assert(not pcall(session.apply,handle));failed=false;assert(session.restore() and bound==100,'partial mutation not restored')
print('PASS: non-color preservation, bounds, private copy, binding restore, foreign ownership, stale membership, partial native failure')
-- Exercise the real MCM core with editor registration, saved callbacks and equip/reload lifecycle.
local Core=dofile(assert(os.getenv('MCM_SOURCE_DIR'),'Set MCM_SOURCE_DIR to DBF-MCM source')..'/src/core.lua')
local store={load=function()return {}end,save=function()return true end}
DBFMCM=Core.new(store)
local identity={player=1,avatar=2,armor=123,helmet=234,body=0,units_at=100}
local applied,restores=0,0
local memory={verify_build=function()return true end,module=function()return 65536 end,address=function(a)return a end,time=os.clock}
local Presets=dofile('src/presets.lua')
local fake={presets=Presets,palette=P,bingus_runtime={},bingus_memory={new=function()return memory end},
 engine={open=function()return {alive=function()return 1 end}end},
 avatar={reader=function()return function()end end,resolve=function()return identity end,units=function()return {{unit=1,type=0,slot=2}}end},
 catalog={new=function()return {load=function(i)return {identity=i,luts={lut},pieces={}}end,close=function()end}end},
 session={new=function()return {bindings={},restore=function()restores=restores+1;return true end,capture=function()end,apply=function()applied=applied+1 end}end}}
local f=assert(io.open('src/editor.lua'));local source=f:read('*a');f:close()
local chunk=assert(loadstring('local m=...\n'..source));local editor=chunk(fake)
editor.on_enable({log=function()end,dir='tests',on_cleanup=function()end})
editor.on_update();local id='dbf_armor_lut_0000007b_0';local h=DBFMCM.mods[id].handle
assert(h.get('0123456789abcdef_r1_color') and not h.get('enabled'))
assert(h.edit('0123456789abcdef_r1_color','#001122'));assert(h.get('0123456789abcdef_r1_color')=='#001122','Color unexpectedly staged')
assert(h.get('0123456789abcdef_r1_on') and h.get('enabled'),'Committed color did not activate row and master')
editor.on_update();assert(applied==1)
assert(h.set('enabled',false));assert(h.set('0123456789abcdef_r2_on',false));editor.on_update()
assert(not h.get('enabled') and not h.get('0123456789abcdef_r2_on'),'Disable failed')
assert(h.get('0123456789abcdef_r2_color')) -- Reading/opening a picker is not a commit.
assert(not h.get('enabled') and not h.get('0123456789abcdef_r2_on'),'Picker read activated row')
assert(h.edit('0123456789abcdef_r2_color','#AABBCC'));assert(h.get('enabled') and h.get('0123456789abcdef_r2_on'),'Disabled row did not activate')
editor.on_update();assert(applied==2)
local Menu=dofile(assert(os.getenv('MCM_SOURCE_DIR'))..'/src/menu.lua')
local menu=Menu.new(DBFMCM);menu.visible=true
assert(h.set('enabled',false));assert(h.set('0123456789abcdef_r3_on',false))
local old=h.get('0123456789abcdef_r3_color');local mod=DBFMCM.mods[id];local control=mod.controls['0123456789abcdef_r3_color']
menu.color_picker={mod=mod,control=control,rgb={1,2,3}};menu.key(27)
assert(not menu.color_picker and h.get('0123456789abcdef_r3_color')==old and not h.get('enabled') and not h.get('0123456789abcdef_r3_on'),'Picker cancel altered settings')
menu.color_picker={mod=mod,control=control,rgb={1,2,3}};menu.commit_color()
assert(not menu.color_picker and h.get('0123456789abcdef_r3_color')=='#010203' and h.get('enabled') and h.get('0123456789abcdef_r3_on'),'USE COLOR did not activate')
print('PASS: actual MCM picker cancel is inert; USE COLOR activates a disabled row and master')
-- Complete data-only round trip, malformed rejection and single-write atomic import.
local c={identity=identity,luts={lut}}
assert(h.set('enabled',false));assert(h.set('0123456789abcdef_r2_on',false))
local text=Presets.encode(c,h);local values=Presets.decode(text,c)
assert(Presets.encode(c,{get=function(k)return values[k]end})==text,'Preset round trip changed values')
local malformed={text:gsub('DBF%-ARMOR%-LUT\t1','DBF-ARMOR-LUT\t2'),text:gsub('armor\t0000007b','armor\t0000007c'),text:gsub('#010203','#GG0000'),text..'row\t0123456789abcdef\t1\t1\t#FFFFFF\n',text:gsub('lut\t0123456789abcdef\t23','lut\t0123456789abcdef\t24'),text:sub(1,-2),'return os.execute(\"bad\")\n'}
for _,bad in ipairs(malformed)do assert(not pcall(Presets.decode,bad,c),'Malformed preset accepted')end
assert(not pcall(Presets.filename,'../escape.dbflut'))
local out=assert(io.open('tests/presets/roundtrip.dbflut','wb'));out:write(text);out:close()
assert(h.set('0123456789abcdef_r1_color','#112233'));assert(h.get('enabled'))
assert(h.set('preset_file','roundtrip'));assert(h.activate('import'))
assert(not h.get('enabled') and not h.get('0123456789abcdef_r2_on'),'Import auto-activation overrode preset disable values')
for k,v in pairs(values)do assert(h.get(k)==v,'Imported setting mismatch: '..k)end
local saves=0;store.save=function()saves=saves+1;return false,'simulated disk full'end
local before=h.get('0123456789abcdef_r1_color');local ok=h.set_many({['0123456789abcdef_r1_color']='#998877',enabled=true})
assert(not ok and h.get('0123456789abcdef_r1_color')==before and not h.get('enabled'),'Failed save partially published settings')
local saved=saves;assert(not pcall(h.set_many,{enabled=true,unknown=true}));assert(saves==saved and not h.get('enabled'),'Invalid batch changed state')
store.save=function()saves=saves+1;return true end
assert(h.set('0123456789abcdef_r1_color','#FF0000'));assert(h.get('enabled') and h.get('0123456789abcdef_r1_on'))
local custom=h.get('0123456789abcdef_r1_color');assert(h.activate('reset'))
assert(not h.get('enabled') and h.get('0123456789abcdef_r1_color')==custom,'Restore erased custom colors')
assert(h.activate('reset_rows'))
assert(not h.get('enabled'),'Row reset re-enabled master')
for row=0,lut.height-1 do local k=lut.name..'_r'..(row+1);assert(not h.get(k..'_on') and h.get(k..'_color')==P.hex(original,row,lut.width),'Row reset did not restore per-row original UI values')end
local resettext=Presets.encode(c,h);local resetvalues=Presets.decode(resettext,c);assert(not resetvalues.enabled,'Reset export remained enabled')
print('PASS: Restore retains custom colors; row reset atomically restores original UI/persisted colors without activation; reset preset round trip')
local ex1=Presets.export('tests/presets',c,h);local ex2=Presets.export('tests/presets',c,h);assert(ex1~=ex2,'Export overwrote prior filename')
print('PASS: full preset round trip, strict malformed/path rejection, import disable semantics, atomic save failure and non-overwriting export')
identity={player=1,avatar=2,armor=124,helmet=234,body=0,units_at=100};editor.on_update()
assert(not DBFMCM.mods[id] and DBFMCM.mods['dbf_armor_lut_0000007c_0'])
assert(editor.on_disable() and not DBFMCM.mods['dbf_armor_lut_0000007c_0'] and restores>=3)
print('PASS: real MCM color definitions, authoritative setting callbacks, immediate apply scheduling, equip registration, disable cleanup')
