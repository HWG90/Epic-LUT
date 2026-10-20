-- Production frontend + actual loader broker; host window/input effects are explicit fixtures.
local fixture=assert(loadfile('tests/loader_input_portable.lua'))()
local Frontend=dofile('src/platform/standalone_frontend.lua')
local Core=dofile('vendor/menu/core.lua')
local Menu=dofile('vendor/menu/menu.lua')
local f=fixture()
local previous_sr,previous_loader,previous_photo=stingray,LiveLuaLoader,DBF_PHOTO_EDITOR_INPUT
stingray=f.sr
LiveLuaLoader={capabilities={shared_input=true},input_service=f.service,
    close_manager=function()error('Shared frontend closed another owner')end}
DBF_PHOTO_EDITOR_INPUT={acquire=function()error('Shared frontend borrowed legacy Photo input')end}
local view={measure=function(text,size)return #text*size*0.5 end,draw=function()end,
    release=function()return true end,invalidate=function()end}
local storage={load=function()return{}end,save=function()return true end}
local m={loader_input=dofile('src/platform/loader_input.lua'),ui_core=Core,ui_menu=Menu}
local clipboard={get=function()return''end,set=function()return true end}
local front=Frontend.new(m,{log=function()end},{storage=storage,view=view,clipboard=clipboard})
assert(front.shared_input_service==f.service)
front.default_mod_id='portable'
front.api.register({id='portable',name='Portable',pages={{id='direct',name='Editor',controls={
    {id='enabled',type='toggle',label='Enabled',default=false}}}}})
local function frame()
    f.driver.begin_frame()
    front.tick(0.016)
end
for _=1,1000 do frame()end
assert(f.samples==0 and f.acquisitions==0 and f.releases==0,'Hidden frontend polled pointer/capture')
front.open_advanced();frame()
assert(front.capture.active and front.menu.visible and f.acquisitions==1)
f.release_ok=false
assert(not front.dismiss() and front.input_cleanup_pending)
local releases=f.releases
for _=1,1000 do frame()end
assert(f.releases==releases,'Frontend polled failed restoration every frame')
f.release_ok=true
assert(front.recover_input() and not front.input_status().pending_restore)
f.manager_busy=true
front.open_advanced();frame()
assert(front.menu.visible and not front.capture.active and front.menu.notice,'Conflict closed/crashed the menu')
local attempts=f.acquisitions
for _=1,20 do frame()end
assert(f.acquisitions==attempts,'Frontend reacquired conflicted shared input every frame')
f.keys.esc=1;frame()
assert(not front.menu.visible,'Conflict prevented Escape from closing the editor')
f.keys.esc=0;f.manager_busy=false
front.open_advanced();frame()
assert(front.capture.active)
assert(front.close())
assert(package.loaded['dbf.epic_lut.frontend.v1']==nil)
local ok=pcall(Frontend.new,m,{log=function()end},{view=view,clipboard=clipboard})
assert(not ok and package.loaded['dbf.epic_lut.frontend.v1']==nil,'Failed constructor retained an unreopenable frontend')
stingray,LiveLuaLoader,DBF_PHOTO_EDITOR_INPUT=previous_sr,previous_loader,previous_photo
print('PASS stock frontend composition: shared ownership, open/close/reopen, no hidden sampling or cleanup polling, conflict Escape and failed-constructor recovery')
