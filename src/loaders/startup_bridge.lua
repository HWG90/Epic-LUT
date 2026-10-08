-- Cooperative BSL adapter: preserve callback arguments/return tuples and defer cleanup.
local B={}
function B.after_startup(factory,ctx)
    local key='dbf.epic_lut.startup.pending.v1'
    if package.loaded[key]then return {duplicate=true}end
    local pending={pending=true};package.loaded[key]=pending
    local function start()
        if not pending.pending then return end
        pending.pending=false;package.loaded[key]=nil
        ctx.log('Epic LUT loader startup complete; initializing editor')
        pending.runtime=B.install(factory(),ctx)
    end
    local loader=rawget(_G,'CowboyBingusModLoader')
    if loader and type(loader.after_startup)=='function'then
        local ok,why=loader.after_startup(start);assert(ok~=false,why)
        ctx.log('Epic LUT initialization queued after loader startup')
    else
        local previous=assert(rawget(_G,'update'))
        local function after(...)start();return ... end
        local deferred=function(...)return after(previous(...))end
        rawset(_G,'update',deferred)
        ctx.log('Epic LUT waiting for first completed game update; loader has no after_startup API')
    end
    return pending
end
function B.install(descriptor,ctx)
    if package.loaded['dbf.armor_lut_editor.owner.v1']or package.loaded['dbf.epic_lut.frontend.v1']then
        ctx.log('Epic LUT already active; duplicate startup skipped');return {duplicate=true}
    end
    local original_update=assert(rawget(_G,'update'),'Game update callback unavailable')
    local original_shutdown=rawget(_G,'shutdown');local active=true;local retiring=false;local closed=false
    local self={}
    local function phase(message)if ctx.phase then ctx.phase(message)end end
    local function close()
        retiring=true
        if closed then return true end
        local callback=descriptor.on_cleanup_poll or descriptor.on_disable
        local ok,result=pcall(callback,ctx)
        if not ok or result~=true then ctx.log('Epic LUT cleanup pending: '..tostring(result));return false end
        for i=#ctx.cleanups,1,-1 do local worked,done=pcall(ctx.cleanups[i]);if not worked or done~=true then return false end end
        for name,record in pairs(ctx.globals)do if rawget(_G,name)==record.owned then rawset(_G,name,record.previous)end end
        active=false;closed=true;return true
    end
    phase('editor initialization begin')
    local ok,why=pcall(descriptor.on_enable,ctx)
    if not ok then close();error('Epic LUT startup failed: '..tostring(why))end
    phase('editor initialization complete')
    local function after(dt,...)
        phase('previous update returned')
        if active then
            if retiring then close()else phase('editor update begin');local worked,err=pcall(descriptor.on_update,ctx,dt);if not worked then ctx.log(err);close()end end
        end
        phase('editor update complete')
        return ...
    end
    local wrapper=function(dt,...)phase('previous update begin');return after(dt,original_update(dt,...))end
    local shutdown
    shutdown=function(...)
        close()
        if rawget(_G,'update')==wrapper then rawset(_G,'update',original_update)end
        if rawget(_G,'shutdown')==shutdown then rawset(_G,'shutdown',original_shutdown)end
        if type(original_shutdown)=='function'then return original_shutdown(...)end
    end
    rawset(_G,'update',wrapper);rawset(_G,'shutdown',shutdown)
    self.close=close;self.descriptor=descriptor
    ctx.log('Epic LUT / Goose started under Bingus Shared Loader; MCM is optional. Do not enable a second loose copy.')
    return self
end
return B
