-- Real loader service/capture modules with an explicit platform fixture.
-- EPIC_LUT_LLL_SOURCE_DIR can point to a separate checkout for offline testing.
local Adapter = dofile('src/platform/loader_input.lua')
local loader_root = os.getenv('EPIC_LUT_LLL_SOURCE_DIR') or '../DBF-Suite/LLL'
local Broker = assert(loadfile(loader_root .. '/src/steam/input_service.lua'))()
local Cursor = assert(loadfile(loader_root .. '/src/steam/capture.lua'))()
local function fixture()
    DBFMCM = nil
    local f = { focused=true, mouse_focus=true, cursor=false, clip=false, fail_restore=false,
        fail_activate=false, release_ok=true, samples=0, releases=0, acquisitions=0, keyboard_reads=0,
        manager_busy=false, keys={}, ids={}, id_calls={}, cursor_sets=0 }
    f.pointer = { valid=true, x=200, y=150, width=800, height=600, buttons=3, wheel=120, dx=0, dy=0 }
    local window = {
        has_focus=function() return f.focused end,
        mouse_focus=function() return f.mouse_focus end,
        show_cursor=function() return f.cursor end,
        clip_cursor=function() return f.clip end,
        set_mouse_focus=function(value)
            f.cursor_sets=f.cursor_sets+1
            if value and f.fail_restore then return false end
            f.mouse_focus=value; return true
        end,
        set_show_cursor=function(value) f.cursor_sets=f.cursor_sets+1; f.cursor=value; return true end,
        set_clip_cursor=function(value)
            f.cursor_sets=f.cursor_sets+1
            if value and f.fail_activate then return false end
            f.clip=value; return true
        end,
    }
    local sr = { Window=window, Gui={ resolution=function() return 1600, 900 end }, Keyboard={
        button_id=function(name)
            f.id_calls[name]=(f.id_calls[name] or 0)+1
            if not f.ids[name] then f.ids[name]=#f.ids+1; f.ids[#f.ids+1]=name end
            return f.ids[name]
        end,
        button=function(id) f.keyboard_reads=f.keyboard_reads+1; return f.keys[f.ids[id]] or 0 end,
    } }
    local platform = {
        pointer_snapshot=function() f.samples=f.samples+1; return f.pointer end,
        release_pointer=function() f.releases=f.releases+1; return f.release_ok end,
    }
    local service, driver = Broker.new(platform, window, Cursor.new({}, window, function() end))
    driver.set_manager_busy(function() return f.manager_busy end)
    local acquire = service.acquire
    f.original_acquire = acquire
    service.acquire = function(owner, mode, ...)
        assert(owner == 'epic_lut' and mode == 'menu', 'Adapter requested a foreign owner/mode')
        f.acquisitions=f.acquisitions+1
        return acquire(owner, mode, ...)
    end
    local snapshot = service.snapshot
    service.snapshot = function(...)
        local value, why = snapshot(...)
        f.last_sample = value
        return value, why
    end
    f.sr = sr
    f.adapter, f.service, f.driver = Adapter.new(sr, service), service, driver
    f.input, f.capture = f.adapter.input, f.adapter.capture
    function f.frame() driver.begin_frame(); f.input.poll() end
    return f
end
do
    local f = fixture()
    for _=1,1000 do
        f.frame(); assert(f.capture.sync(false,true)); f.input.mouse(); assert(f.input.wheel()==0 and not f.input.down(1))
    end
    assert(f.samples==0 and f.releases==0 and f.acquisitions==0 and f.cursor_sets==0, 'Closed UI sampled/acquired/restored input')
    assert(f.input.window()==nil and f.adapter.capabilities.keyboard_isolation==false)
    f.keys.f10=1
    assert(f.input.down(121) and f.input.down(121) and f.keyboard_reads==1 and f.id_calls.f10==1)
    f.keys['right shift']=true
    assert(f.input.down(16), 'Right shift did not reach the modifier facade')
    assert(not f.input.down(0) and not f.input.down('121'))
    assert(f.capture.sync(true,true) and f.capture.active and f.acquisitions==1)
    assert(f.samples==0, 'Opening eagerly sampled the helper')
    assert(f.input.down(1) and f.input.down(2) and not f.input.down(4))
    local x,y=f.input.mouse(); assert(x==400 and y==675, 'Client top-left coordinates were mapped incorrectly')
    assert(f.input.wheel()==120 and f.input.wheel()==0 and f.samples==1, 'Wheel/sample delivered more than once')
    -- Another broker consumer mutates the reused service sample; our scalars stay stable.
    assert(f.service.status().owner=='epic_lut')
    f.last_sample.x=12345; f.last_sample.wheel=999
    f.pointer.x=700; f.pointer.wheel=240
    x,y=f.input.mouse(); assert(x==400 and y==675 and f.samples==1)
    local setters=f.cursor_sets
    for _=1,1000 do f.frame(); assert(f.capture.sync(true,true)) end
    assert(f.samples==1 and f.cursor_sets==setters and f.acquisitions==1, 'Unchanged active state sampled or rewrote cursor flags')
    f.frame(); assert(f.input.wheel()==240 and f.input.wheel()==0 and f.samples==2)
    assert(f.capture.sync(false,true) and not f.capture.active and f.releases==1)
    assert(f.mouse_focus and not f.cursor and not f.clip, 'Menu release failed to restore cursor state')
    assert(f.capture.release() and f.capture.shutdown() and f.releases==1, 'Released cleanup touched the helper again')
    for _=1,1000 do f.frame(); assert(f.capture.sync(false,true)); f.input.mouse() end
    assert(f.samples==2 and f.releases==1 and f.acquisitions==1)
end
do
    local f=fixture(); f.frame(); f.manager_busy=true
    assert(not f.capture.sync(true,true) and not f.capture.active)
    for _=1,1000 do f.frame(); assert(not f.capture.sync(true,true)) end
    assert(f.acquisitions==1 and f.samples==0, 'Conflicted menu retried acquisition every frame')
    f.manager_busy=false; assert(f.capture.sync(false,true)); assert(f.capture.sync(true,true))
    f.frame(); f.input.mouse(); f.release_ok=false
    assert(not f.capture.release() and f.capture.status().pending_restore and f.capture.status().owner=='epic_lut')
    local releases=f.releases
    for _=1,1000 do f.frame(); assert(not f.capture.sync(false,true)); f.input.mouse() end
    assert(f.releases==releases and f.samples==1, 'Pending cleanup ran an idle retry/sample loop')
    assert(not f.capture.sync(true,true) and f.acquisitions==2, 'Pending token was replaced')
    f.release_ok=true; assert(f.capture.release() and not f.capture.status().pending_restore)
    assert(f.capture.sync(true,true) and f.acquisitions==3 and f.capture.release())
end
do
    local f=fixture(); f.frame(); f.fail_activate=true; f.fail_restore=true
    assert(not f.capture.sync(true,true) and not f.capture.active and f.capture.status().pending_restore,
        'Failed-activation cleanup token was discarded')
    local setters=f.cursor_sets
    for _=1,1000 do f.frame(); assert(not f.capture.sync(true,true)) end
    assert(f.acquisitions==1 and f.cursor_sets==setters and f.samples==0, 'Failed activation retried without explicit recovery')
    f.fail_activate=false; f.fail_restore=false
    assert(f.capture.release() and f.capture.sync(true,true) and f.capture.release())
end
do
    local f=fixture(); f.frame(); assert(f.capture.sync(true,true)); f.input.mouse()
    f.focused=false; f.frame()
    assert(not f.capture.active and not f.input.focused() and f.input.mouse()==nil and not f.input.down(1))
    assert(f.capture.sync(true,false) and not f.capture.status().pending_restore)
    assert(f.releases==1 and f.samples==1, 'Foreground loss kept a reader or retried completed cleanup')
    f.focused=true; f.frame(); assert(f.capture.sync(true,true)); f.input.mouse()
    f.release_ok=false; DBFMCM={ is_open=function() return true end }
    f.frame(); assert(not f.capture.active and f.capture.status().pending_restore)
    local releases=f.releases
    for _=1,1000 do f.frame(); assert(not f.capture.sync(true,true)); f.input.mouse() end
    assert(f.releases==releases and f.samples==2, 'Conflict revocation retried cleanup or sampled')
    f.release_ok=true; assert(f.capture.release()); DBFMCM=nil
    assert(f.capture.sync(true,true) and f.capture.release())
end
do
    local f=fixture(); f.frame(); assert(f.capture.sync(true,true))
    f.pointer.width=0; assert(f.input.mouse()==nil and not f.capture.active)
    local acquisitions=f.acquisitions
    for _=1,1000 do f.frame(); assert(not f.capture.sync(true,true)); f.input.mouse() end
    assert(f.samples==1 and f.acquisitions==acquisitions, 'Malformed samples caused a reacquisition loop')
    assert(f.capture.release()); f.pointer.width=800
    assert(f.capture.sync(true,true) and f.capture.release())
end
do
    local f=fixture(); f.frame(); assert(f.capture.sync(true,true)); f.input.mouse()
    -- The loader completed revocation and another consumer acquired before our tick.
    f.focused=false; f.driver.begin_frame(); f.focused=true
    local foreign=assert(f.original_acquire('Another menu','menu'))
    f.input.poll()
    local releases=f.releases
    assert(not f.capture.active and f.capture.release() and f.service.owns(foreign))
    assert(f.releases==releases and f.service.status().owner=='Another menu', 'Stale cleanup released another owner')
    assert(f.service.release(foreign))
end
print('PASS loader input: real shared-service contract, zero hidden sampling, coordinates/wheel, exclusive leases and retained explicit cleanup')

return fixture
