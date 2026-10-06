local ffi=require('ffi');local root=assert(os.getenv('MCM_SOURCE_DIR'))
local Core=dofile(root..'/src/core.lua');local Grouping=dofile(root..'/src/grouping.lua');DBFMCM=Core.new(nil,nil,Grouping)
local provider=DBFMCM.register({id='original',name='MATCH YOUR COLORS',pages={{id='settings',name='Settings',controls={{id='mode',type='choice',label='Color Matching',choices={'Off','Helmet Matches Armor','Armor Matches Helmet'},default=1}}}}});DBFMCM.mods.original.legacy=true
ModOptionsMenu={get=function()return provider.get('mode')end}
local m={};for _,name in ipairs({'palette','dds','semantics','document','provider_menu','editor_features','presets'})do m[name]=dofile('src/'..name..'.lua')end
local data=ffi.new('float[?]',23*2*4);for i=0,23*2*4-1 do data[i]=(i%11)/10 end;data[3]=2;data[13*4]=8.5;data[13*4+1]=1000000;data[13*4+2]=-12.5
local clock=0;local memory={verify_build=function()return true end,module=function()return 65536 end,address=function(a)return a end,time=function()clock=clock+.002;return clock end}
m.bingus_runtime={};m.bingus_memory={new=function()return memory end}
local identity={player=1,unit=2,avatar=3,armor=0x101,helmet=0x202,body=0,units_at=10000}
m.avatar={reader=function()return function()end end,resolve=function()return identity end,units=function(_,_,_,first)return {{unit=first==0 and 20 or 10,type=0,slot=first}}end}
local ordinal=0;m.engine={open=function()ordinal=ordinal+1;return {ordinal=ordinal,alive=function()return 1 end}end}
m.catalog={new=function(_,_,_,target)return {close=function()end,load=function(id)return {identity=id,pieces={},luts={{name=target=='Helmet' and '2222222222222222'or '1111111111111111',width=23,height=2,values=data}}}end}end}
local calls={};m.session={new=function(_,_,native)
 local s={bindings={}}
 function s.restore()s.bindings={};return true end
 function s.capture()s.bindings={{unit=native.ordinal}}end
 function s.apply(h,docs)calls[#calls+1]={target=native.ordinal,docs=docs};return true end
 return s
end}
local file=assert(io.open('src/editor.lua'));local source=file:read('*a');file:close();local editor=assert(loadstring('local m=...\n'..source))(m)
local ctx={dir='tests/tmp',log=function()end,on_cleanup=function()end};editor.on_enable(ctx);editor.on_update(ctx,.016)
local armor=assert(DBFMCM.mods.dbf_armor_lut_00000101_0).handle;local helmet=assert(DBFMCM.mods.dbf_helmet_lut_00000202_0).handle
for _,id in ipairs({'dbf_armor_lut_00000101_0','dbf_helmet_lut_00000202_0'})do for _,page in ipairs(DBFMCM.mods[id].pages)do assert(not page.id:match('^lut_'),'Redundant row tree visible')end end
assert(DBFMCM.mods.original.parent_name=='Epic LUT','Original provider submenu did not mount')
assert(not armor.get('enabled') and not helmet.get('enabled'))
assert(armor.set('cell_r',.25));assert(armor.get('1111111111111111_r1_on') and armor.get('enabled'));editor.on_update(ctx,.016)
assert(#calls==1 and calls[1].target==1 and not helmet.get('enabled'),'Armor edit affected helmet activation')
local rendered=calls[1].docs['1111111111111111'];assert(rendered[0]==.25 and rendered[3]==2 and rendered[13*4]==8.5 and rendered[13*4+1]==1000000)
assert(armor.set('edit_column',14));assert(not pcall(armor.set,'cell_r',.1),'Protected emission channel was editable')
assert(DBFMCM.mods.dbf_armor_lut_00000101_0.controls.cell_color.disabled,'Emission incorrectly exposed RGB picker')
assert(armor.set('preserve_effects',false));assert(armor.set('cell_r',.1));editor.on_update(ctx,.016);assert(math.abs(calls[#calls].docs['1111111111111111'][13*4]-.1)<1e-6)
assert(armor.activate('reset_rows'));assert(not armor.get('enabled'));assert(armor.set('edit_column',1))
assert(helmet.set('2222222222222222_r1_color','#ABCDEF'));editor.on_update(ctx,.016)
assert(calls[#calls].target==2 and not armor.get('enabled'),'Helmet edit affected armor activation')
local prior=#calls;assert(provider.set('mode',2));editor.on_update(ctx,.016);assert(#calls==prior and provider.get('mode')==2,'Helmet competing writer was overridden')
assert(provider.set('mode',1));editor.on_update(ctx,.016);assert(#calls>prior,'Helmet editor did not resume after original writer stopped')
assert(helmet.activate('reset_rows'));assert(not helmet.get('enabled') and not helmet.get('2222222222222222_r1_on'))
assert(editor.on_disable(ctx));assert(not DBFMCM.mods.dbf_armor_lut_00000101_0 and not DBFMCM.mods.dbf_helmet_lut_00000202_0 and DBFMCM.mods.original and not DBFMCM.mods.original.parent_name)
print('PASS: actual MCM semantic controls, protected emission data, deliberate unlock, independent armor/helmet activation/reset, original submenu and competing-writer pause/resume')
