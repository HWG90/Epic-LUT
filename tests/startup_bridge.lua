local B=dofile('src/startup_bridge.lua');local frames=0;local attempts=0;local cleanups=0;local calls={};local original=function(dt,...)calls[#calls+1]={dt,...};return 'first',nil,'third',...end
update=original;shutdown=function(...)return 'shutdown',...end
local ctx={cleanups={},globals={},log=function()end}
ctx.cleanups[1]=function()cleanups=cleanups+1;return true end
local d={on_enable=function()end,on_update=function(_,dt)frames=frames+1;assert(dt==.25)end,on_cleanup_poll=function()attempts=attempts+1;return attempts>1 end}
local instance=B.install(d,ctx);local a,b,c,n=update(.25,17);assert(a=='first'and b==nil and c=='third'and n==17 and frames==1 and calls[1][2]==17)
assert(not instance.close());update(.25,18);assert(frames==1 and cleanups==1 and attempts==2)
local s,code=shutdown(7);assert(s=='shutdown'and code==7 and update==original)
package.loaded['dbf.armor_lut_editor.owner.v1']={};local before=update;assert(B.install(d,ctx).duplicate and update==before);package.loaded['dbf.armor_lut_editor.owner.v1']=nil
print('PASS: BSL bridge forwards all arguments/return tuples, runs one model, defers cleanup until true, restores owned callbacks, and rejects duplicate startup')
local queued;local made=0;local enabled=0
CowboyBingusModLoader={after_startup=function(fn)queued=fn;return true end}
update=original;local deferred=B.after_startup(function()made=made+1;return {on_enable=function()enabled=enabled+1 end,on_update=function()end,on_cleanup_poll=function()return true end}end,{log=function()end,cleanups={},globals={}})
assert(deferred.pending and made==0 and enabled==0 and update==original,'Initialization ran during module loading')
assert(B.after_startup(function()error('Duplicate factory')end,ctx).duplicate)
queued();assert(made==1 and enabled==1 and not deferred.pending);queued();assert(made==1)
shutdown();CowboyBingusModLoader=nil
print('PASS: supported after_startup defers the complete editor factory, preserves the game update until ready, and initializes once')
