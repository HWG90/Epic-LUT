-- The engine coalesces Unit event bursts into one deferred native snapshot.
-- No Lua update/tick, recurring timer, process hook, or material write.
local E={}
function E.new(binary,engine,directory,game,notify)
    local ffi=require('ffi')
    if not pcall(ffi.typeof,'epic_appearance_event_fn') then ffi.cdef[[
        typedef void (*epic_appearance_event_fn)(void);
        int epic_appearance_start(uintptr_t);
        void epic_appearance_subscribe(epic_appearance_event_fn);
        void epic_appearance_stop(void);
        uint64_t epic_appearance_stat(unsigned);
    ]] end
    local bytes=binary.hex:gsub('..',function(pair)return string.char(tonumber(pair,16))end)
    local path=directory..'/appearance-events-'..binary.sha256..'.dll'
    local file=io.open(path,'rb');local existing=file and file:read(#bytes+1)
    if file then file:close() end
    if existing~=bytes then
        assert(not existing,'Appearance event cache differs from packaged bytes')
        file=assert(io.open(path,'wb'));assert(file:write(bytes));assert(file:close())
    end
    local library=ffi.load(path)
    local callback=ffi.cast('epic_appearance_event_fn',notify)
    local name=assert(engine.PluginManager.load_plugin(path),'Engine rejected appearance lifecycle plugin')
    assert(name==binary.name,'Unexpected appearance lifecycle plugin')
    library.epic_appearance_subscribe(callback)
    assert(library.epic_appearance_start(game)==1,'Appearance subscription unavailable')
    local self,closed={},false
    function self.close()
        if closed then return end
        library.epic_appearance_stop()
        engine.PluginManager.unload_plugin(name)
        callback:free();closed=true
    end
    return self
end
return E
