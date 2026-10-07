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
 function s.capture()assert(not(native.ordinal==2 and provider.get('mode')==2),'Captured bindings while the original writer owned helmet');s.bindings={{unit=native.ordinal}}end
 function s.apply(h,docs)calls[#calls+1]={target=native.ordinal,docs=docs};return true end
 return s
end}
local file=assert(io.open('src/editor.lua'));local source=file:read('*a');file:close();local editor=assert(loadstring('local m=...\n'..source))(m)
assert(provider.set('mode',2))
local ctx={dir='tests/tmp',log=function()end,on_cleanup=function()end};editor.on_enable(ctx);editor.on_update(ctx,.016)
local armor=assert(DBFMCM.mods.dbf_armor_lut_00000101_0).handle;local helmet=assert(DBFMCM.mods.dbf_helmet_lut_00000202_0).handle
for _,id in ipairs({'dbf_armor_lut_00000101_0','dbf_helmet_lut_00000202_0'})do for _,page in ipairs(DBFMCM.mods[id].pages)do assert(not page.id:match('^lut_'),'Redundant row tree visible');assert(page.category==(page.id=='quick_load'and 'quick_load'or id:find('helmet')and 'helmet'or 'armor'),'Target category missing')end end
assert(DBFMCM.mods.original.parent_name=='Epic LUT','Original provider submenu did not mount')
assert(not armor.get('enabled') and not helmet.get('enabled'))
assert(provider.set('mode',1));editor.on_update(ctx,.016)
assert(not armor.get('preserve_effects')and not helmet.get('preserve_effects'),'Fresh effect policy must default Off')
assert(armor.set('preserve_effects',true))
assert(armor.set('cell_r',.25));assert(armor.get('1111111111111111_r1_on') and armor.get('enabled'));editor.on_update(ctx,.016)
assert(#calls==1 and calls[1].target==1 and not helmet.get('enabled'),'Armor edit affected helmet activation')
local rendered=calls[1].docs['1111111111111111'];assert(rendered[0]==.25 and rendered[3]==2 and rendered[13*4]==8.5 and rendered[13*4+1]==1000000)
assert(armor.set('edit_column',14));assert(not pcall(armor.set,'cell_r',.1),'Protected emission channel was editable')
assert(DBFMCM.mods.dbf_armor_lut_00000101_0.controls.cell_color.disabled,'Emission incorrectly exposed RGB picker')
assert(armor.set('preserve_effects',false));assert(armor.set('cell_r',.1));editor.on_update(ctx,.016);assert(math.abs(calls[#calls].docs['1111111111111111'][13*4]-.1)<1e-6)
assert(armor.activate('reset_rows'));assert(not armor.get('enabled')and not armor.get('preserve_effects'),'Reset unexpectedly enabled preservation');assert(armor.set('edit_column',1))
assert(helmet.set('2222222222222222_r1_color','#ABCDEF'));editor.on_update(ctx,.016)
assert(calls[#calls].target==2 and not armor.get('enabled'),'Helmet edit affected armor activation')
local prior=#calls;assert(provider.set('mode',2));editor.on_update(ctx,.016);assert(#calls==prior and provider.get('mode')==2,'Helmet competing writer was overridden')
assert(provider.set('mode',1));editor.on_update(ctx,.016);assert(#calls>prior,'Helmet editor did not resume after original writer stopped')
assert(helmet.activate('reset_rows'));assert(not helmet.get('enabled') and not helmet.get('2222222222222222_r1_on'))
local armor_mod=DBFMCM.mods.dbf_armor_lut_00000101_0;local color_page
for _,page in ipairs(armor_mod.pages)do if page.id=='colors'then color_page=page end end
assert(color_page and #color_page.controls==32,'All ten supported color fields and two rows must remain available in groups')
assert(color_page.controls[3].collapsible and not color_page.controls[3].collapsed,'Base Color should start expanded')
assert(color_page.controls[6].collapsed,'Detail Color should start collapsed')
local Menu=dofile(root..'/src/menu.lua');local menu=Menu.new(DBFMCM);menu.visible=true
for at,mod in ipairs(DBFMCM.list())do if mod.id==armor_mod.id then menu.selected=at;for page_at,page in ipairs(mod.pages)do if page.id=='colors'then menu.page=page_at end end end end
local commands=menu.compose(1920,1080);local click
local current_count=0;for _,command in ipairs(commands)do if command.type=='text'and command.text=='Now'then current_count=current_count+1 end end
assert(current_count==2,'Collapsed fields leaked their swatches into the initial palette view')
for _,command in ipairs(commands)do if command.type=='text'and command.text=='Now'then click={command.x+1,command.y+1};break end end
assert(click,'Current swatch was not rendered')
menu.tick({down=function(code)return code==1 end,mouse=function()return click[1],click[2]end,wheel=function()return 0 end})
assert(menu.color_picker and menu.color_picker.mod==armor_mod and menu.color_picker.control==armor_mod.controls.cell_color,'Swatch click did not open the authoritative picker')
menu.color_picker=nil;menu.tick({down=function()return false end,mouse=function()return nil end,wheel=function()return 0 end})
local header
for _,command in ipairs(menu.compose(1920,1080))do if command.type=='text'and command.text:find('> Detail color A',1,true)then header={command.x+10,command.y+2};break end end
assert(header,'Detail Color collapse header missing')
menu.tick({down=function(code)return code==1 end,mouse=function()return header[1],header[2]end,wheel=function()return 0 end})
current_count=0;for _,command in ipairs(menu.compose(1920,1080))do if command.type=='text'and command.text=='Now'then current_count=current_count+1 end end
assert(current_count==4,'Expanding Detail Color did not expose its row swatches')
local square=color_page.controls[5].swatches[1];assert(square.owner==armor_mod and square.control==armor_mod.controls.cell_color)
square.prepare();assert(armor.get('edit_row')==2 and armor.get('edit_column')==1,'Swatch prepared the wrong cell')
assert(armor.set('cell_color','#112233'));assert(armor.get('1111111111111111_r2_on'))
assert(helmet.set('2222222222222222_r1_color','#ABCDEF'))
local retained_color=armor.get('1111111111111111_r2_color')
assert(armor.activate('quick_reset_both'));assert(not armor.get('enabled')and not helmet.get('enabled'))
assert(armor.get('1111111111111111_r2_color')==retained_color,'Combined reset discarded custom colors')
assert(helmet.get('2222222222222222_r1_color')=='#ABCDEF','Combined reset discarded helmet colors')
print('PASS all supported color rows visible, exact-cell authoritative swatches, combined target reset retains edits')
local features=package.loaded['dbf.armor_lut_editor.owner.v1'].features
local saved_native=features.native;local saved_disable=m.provider_menu.disable_matching;local locked=true
m.provider_menu.disable_matching=function()return true,true end
features.native={labels={'Target'},poll=function()return 'Imported',1,{imported=true}end,locked=function()return locked end}
assert(features.tick()==true,'Import ownership transition was lost while a file request was locked')
locked=false;assert(armor.set('watch_files',false));assert(features.tick()==true,'Import ownership transition was lost when watching was disabled')
features.native=saved_native;m.provider_menu.disable_matching=saved_disable
print('PASS import ownership transition survives early-return paths')
assert(editor.on_disable(ctx));assert(not DBFMCM.mods.dbf_armor_lut_00000101_0 and not DBFMCM.mods.dbf_helmet_lut_00000202_0 and DBFMCM.mods.original and not DBFMCM.mods.original.parent_name)
print('PASS: actual MCM semantic controls, protected emission data, deliberate unlock, independent armor/helmet activation/reset, original submenu and competing-writer pause/resume')
