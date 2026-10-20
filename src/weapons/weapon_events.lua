-- Native lifecycle subscription. There is deliberately no tick/update method.
-- The engine schedules one deferred native check per nonempty unit-event burst.
local E = {}
function E.new(binary, engine, directory, notify)
    assert(engine and engine.PluginManager, 'Engine plugin manager unavailable')
    local ffi = require('ffi')
    if not pcall(ffi.typeof, 'epic_weapon_event_fn') then
        ffi.cdef[[
            typedef void (*epic_weapon_event_fn)(unsigned);
            int epic_watch(uintptr_t,uintptr_t,uintptr_t,uint32_t,uint32_t,uint32_t);
            void epic_subscribe(epic_weapon_event_fn);
            void epic_stop(void);
            uint64_t epic_stat(unsigned);
        ]]
    end
    pcall(ffi.cdef, 'int epic_watch_actor(uintptr_t,uintptr_t,uintptr_t,uint32_t,uint32_t,uint32_t,uintptr_t,uint32_t,uint32_t);')
    local bytes = (binary.hex:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end))
    local path = directory .. '/weapon-events-' .. binary.sha256 .. '.dll'
    local file = io.open(path, 'rb')
    local existing = file and file:read('*a')
    if file then file:close() end
    if existing ~= bytes then
        assert(not existing, 'Native event cache content differs from packaged binary')
        file = assert(io.open(path, 'wb')); assert(file:write(bytes)); assert(file:close())
    end
    local library = ffi.load(path)
    local callback = ffi.cast('epic_weapon_event_fn', function(mask)
        -- No native writes or discovery inside an engine callback.
        notify(tonumber(mask))
    end)
    local name = assert(engine.PluginManager.load_plugin(path), 'Engine rejected weapon event plugin')
    assert(name == binary.name, 'Unexpected weapon event plugin identity')
    library.epic_subscribe(callback)
    local self, last, closed = {}, nil, false
    function self.watch(receipt)
        if closed then return end
        local key = table.concat({receipt.game, receipt.owner, receipt.inventory,
            receipt.avatar, receipt.avatar_ref, receipt.inventory_index,
            receipt.players or 0, receipt.player_id or 0, receipt.player_index or 0}, ':')
        if key == last and library.epic_stat(4) ~= 0 then return end
        local armed
        if receipt.players then
            armed = library.epic_watch_actor(receipt.game, receipt.owner, receipt.inventory,
                receipt.avatar, receipt.avatar_ref, receipt.inventory_index,
                receipt.players, receipt.player_id, receipt.player_index)
        else
            armed = library.epic_watch(receipt.game, receipt.owner, receipt.inventory,
                receipt.avatar, receipt.avatar_ref, receipt.inventory_index)
        end
        assert(armed == 1,
            'Weapon event ownership receipt expired')
        last = key
    end
    function self.close()
        if closed then return end
        library.epic_stop()
        engine.PluginManager.unload_plugin(name)
        callback:free()
        closed = true
    end
    return self
end
return E
