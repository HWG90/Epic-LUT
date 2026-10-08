local core=dofile('vendor/menu/core.lua');local menus=dofile('vendor/menu/menu.lua')
local F=dofile('src/standalone_frontend.lua')
local keys,focused={},true;local draws=0;local pending=false
local capture={active=false}
function capture.sync(visible,focus)capture.active=visible and focus;return true end
function capture.release()capture.active=false;return true end
function capture.shutdown()if pending then return false,'test pending restoration'end;capture.active=false;return true end
local input={poll=function()end,focused=function()return focused end,window=function()return 1 end,down=function(k)return keys[k]or false end,wheel=function()return 0 end,mouse=function()return nil end}
local view={measure=function(s,size)return #s*size*.5 end,draw=function()draws=draws+1 end,release=function()end}
local prior=rawget(_G,'DBFMCM');_G.DBFMCM={register=function()error('External MCM was touched')end}
local storage={load=function()return {}end,save=function()return true end}
local m={ui_core=core,ui_menu=menus,ui_grouping=dofile('vendor/menu/grouping.lua'),ui_store={new=function()return storage end}}
local f=F.new(m,{settings_dir='tests/tmp',log=function()end},{input=input,capture=capture,view=view,resolution=function()return 1920,1080 end})
local api=f.resolve();assert(api~=_G.DBFMCM,'Standalone frontend adopted MCM')
api.register({id='test_editor',name='Epic LUT',pages={{id='direct',name='Import / Apply',controls={}},{id='colors',name='LUT Editor',controls={}}}})
api.mods.test_editor.tabs_top=true;f.default_mod_id='test_editor'
f.preferences=dofile('src/preferences.lua').new(storage)
local h=api.mods.test_editor.handle
-- Dynamic grid controls may be absent from page.controls, but must stay in mod.controls.
api.mods.test_editor.controls.grid_tool={id='grid_tool',type='choice',choices={'Select','Draw'},page=api.mods.test_editor.pages[2]}
api.mods.test_editor.values.grid_tool=1
api.mods.test_editor.pages[2].render_layout=function(ui)ui.choice('grid_tool',ui.x+10,ui.y+40,200)end
keys[121]=true;f.tick(.1);assert(f.menu.visible,'F10 did not open standalone editor')
keys[121]=false;f.tick(.1);assert(capture.active and f.menu.page==1 and draws>0)
assert(api.list()[1]==api.mods.test_editor,'Standalone registry created a lossy grouping composite')
assert(#api.list()==1,'Hidden preferences leaked into standalone navigation')
f.menu.page=2
local rendered=f.menu.compose(1920,1080);local selected=false
for _,c in ipairs(rendered)do if c.full_text=='Select'then selected=true end end
assert(selected,'Hidden preferences caused the live grid-control assertion')
f.menu.page=2;focused=false;keys[121]=true;f.tick(.1);assert(f.menu.visible and not capture.active)
focused=true;f.tick(.1);assert(f.menu.visible,'Focus return replayed F10 and closed the menu')
keys[121]=false;f.tick(.1);keys[121]=true;f.tick(.1);assert(not f.menu.visible and not capture.active)
keys[121]=false;f.tick(.1);keys[121]=true;f.tick(.1);assert(f.menu.visible and f.menu.page==2,'Reopening forgot the last tab')
f.default_mod_id='test_editor'
local basic_page={id='basic',name='Basic',controls={},actions={},pending={},require_confirmation=false,render_layout=function()end}
api.mods.test_editor.pages[#api.mods.test_editor.pages+1]=basic_page
keys[121]=false;f.tick(.1);keys[120]=true;f.tick(.1)
assert(f.menu.visible and f.menu.page==3 and f.basic_mode,'F9 did not open Basic')
assert(f.menu.basic_only,'Basic navigation was not isolated')
f.menu.key(34,false);assert(f.menu.page==3,'Basic reached full editor through page navigation')
f.tick(.1);assert(f.menu.visible,'Held F9 closed Basic')
keys[120]=false;f.tick(.1);keys[121]=true;f.tick(.1)
assert(f.menu.visible and f.menu.page==1 and not f.basic_mode,'F10 did not switch back to full editor')
assert(not f.menu.basic_only,'Full menu retained Basic navigation')
for _,c in ipairs(f.menu.compose(1920,1080))do assert(c.full_text~='Basic','Basic tab leaked into F10 menu')end
keys[121]=false;f.tick(.1)
pending=true;assert(not f.close(),'Cleanup discarded a pending cursor restoration')
pending=false;assert(f.close());assert(package.loaded['dbf.epic_lut.frontend.v1']==nil)
_G.DBFMCM=prior
print('PASS standalone frontend: MCM ignored, own F10 menu, top tabs, blur/held-key safety, capture release and retryable cleanup')
