-- One active frontend. Both registries use the same generated specs and settings files.
local F={}
function F.new(m,ctx,deps)
    local self={active=false};deps=deps or {}
    local prior=package.loaded['dbf.epic_lut.frontend.v1'];assert(not prior or prior.closed,'Another Epic LUT frontend still owns its lifecycle')
    package.loaded['dbf.epic_lut.frontend.v1']=self
    local function usable(api)return type(api)=='table'and api.storage_per_mod==true and api.presentation_links==true and type(api.register)=='function'and type(api.list)=='function'and type(api.mods)=='table'and type(api.color_rgb)=='function'end
    if m.diagnostic_registry_only then
        if m.diagnostic_input_library then
            local ffi=require('ffi')
            pcall(ffi.cdef,[[int mcm_install(void *);int mcm_capture(int);int mcm_captured(void);void mcm_release(void);int mcm_wheel(void);]])
            self.input_library=ffi.load(ctx.dir..'/'..assert(m.frontend_native_name))
            for _,name in ipairs({'mcm_install','mcm_capture','mcm_captured','mcm_release','mcm_wheel'})do assert(self.input_library[name],'Input runtime interface missing '..name)end
            ctx.log('DIAGNOSTIC: native input DLL loaded and symbols validated; no input functions invoked')
            if m.diagnostic_idle_poll then
                if deps.input then self.idle_poll=deps.input.poll else
                    pcall(ffi.cdef,[[void *epic_front_foreground(void) __asm__("GetForegroundWindow");uint32_t epic_front_window_pid(void *,uint32_t *) __asm__("GetWindowThreadProcessId");]])
                    local user=ffi.load('user32');local process_out=ffi.new('uint32_t[1]')
                    self.idle_poll=function()local foreground=user.epic_front_foreground();user.epic_front_window_pid(foreground,process_out)end
                end
                ctx.log('DIAGNOSTIC: foreground-window polling enabled; capture and rendering withheld')
            end
        end
        self.api=m.ui_core.new(m.ui_store.new(assert(ctx.settings_dir)),ctx.log,m.ui_grouping)
        self.legacy=m.ui_legacy.new(self.api,ctx.log,m.ui_core,function(name)return name:lower():gsub('[^%w]','')=='matchyourcolors'end)
        self.api.open=function()return false end;self.api.close=function()return true end
        self.api.is_open=function()return false end;self.api.toggle=function()return false end
        self.api.focus_page=function()return false end
        function self.resolve()return self.api end
        function self.tick()if self.idle_poll then self.idle_poll()end;self.legacy.poll(rawget(_G,'ModOptionsMenu'))end
        function self.close()self.legacy.release();self.closed=true;if package.loaded['dbf.epic_lut.frontend.v1']==self then package.loaded['dbf.epic_lut.frontend.v1']=nil end;return true end
        ctx.log('DIAGNOSTIC: registry-only frontend; capture, menu controller, and renderer withheld; input DLL '..(m.diagnostic_input_library and 'loaded' or 'withheld'))
        return self
    end
    local function initialize()
        if self.api then return end
        local folder=deps.folder or assert(ctx.settings_dir,'Epic LUT settings folder unavailable')
        if not deps.input then
            local ffi=require('ffi');local bit=require('bit')
            if not pcall(ffi.typeof,'epic_front_point')then ffi.cdef([[typedef struct {long x;long y;} epic_front_point;]])end
            pcall(ffi.cdef,[[
                short epic_front_key(int) __asm__("GetAsyncKeyState");
                void *epic_front_foreground(void) __asm__("GetForegroundWindow");
                int epic_front_cursor(epic_front_point *) __asm__("GetCursorPos");
                int epic_front_client(void *,epic_front_point *) __asm__("ScreenToClient");
                int epic_front_rect(void *,long *) __asm__("GetClientRect");
                uint32_t epic_front_window_pid(void *,uint32_t *) __asm__("GetWindowThreadProcessId");
                uint32_t epic_front_pid(void) __asm__("GetCurrentProcessId");
                int epic_front_mkdir(const uint16_t *,void *) __asm__("CreateDirectoryW");
                int mcm_install(void *);int mcm_capture(int);int mcm_captured(void);void mcm_release(void);int mcm_wheel(void);
            ]])
            local user=ffi.load('user32');local kernel=ffi.load('kernel32');local _,native_kernel=m.native_import.verify_interface()
            local function wide(text)local n=native_kernel.epic_native_wide(65001,8,text,-1,nil,0);assert(n>0);local out=ffi.new('uint16_t[?]',n);assert(native_kernel.epic_native_wide(65001,8,text,-1,out,n)==n);return out end
            local native=ffi.load(ctx.dir..'/'..assert(m.frontend_native_name,'Packaged input runtime missing'))
            for _,name in ipairs({'mcm_install','mcm_capture','mcm_captured','mcm_release','mcm_wheel'})do assert(native[name],'Input runtime interface missing '..name)end
            local sr=assert(rawget(_G,'stingray'));local process=kernel.epic_front_pid();local foreground;local process_out=ffi.new('uint32_t[1]');local point=ffi.new('epic_front_point[1]');local rect=ffi.new('long[4]')
            if m.diagnostic_readonly_menu then
                self.capture={status=function()return {pending_restore=false}end,shutdown=function()return true end,release=function()return true end}
            else self.capture=m.ui_capture.new(native,assert(sr.Window),ctx.log)end
            self.view=m.ui_view.new(sr,nil,ctx.log)
            self.input={poll=function()foreground=user.epic_front_foreground();user.epic_front_window_pid(foreground,process_out);if process_out[0]~=process then foreground=nil end end,
                focused=function()return foreground~=nil end,window=function()return foreground end,
                down=function(code)return foreground and bit.band(tonumber(user.epic_front_key(code)),0x8000)~=0 or false end,
                wheel=function()return tonumber(native.mcm_wheel())end,
                mouse=function()
                    if not foreground or user.epic_front_cursor(point)==0 or user.epic_front_client(foreground,point)==0 or user.epic_front_rect(foreground,rect)==0 then return end
                    local w,h=sr.Gui.resolution();local cw,ch=tonumber(rect[2]),tonumber(rect[3]);if cw<=0 or ch<=0 then return end
                    return tonumber(point[0].x)*w/cw,h-tonumber(point[0].y)*h/ch
                end}
            self.resolution=sr.Gui.resolution
        else self.input=deps.input;self.capture=deps.capture;self.view=deps.view;self.resolution=deps.resolution end
        self.api=m.ui_core.new(m.ui_store.new(folder),ctx.log,m.ui_grouping)
        self.menu=m.ui_menu.new(self.api,self.view.measure)
        self.legacy=m.ui_legacy.new(self.api,ctx.log,m.ui_core,function(name)return name:lower():gsub('[^%w]','')=='matchyourcolors'end)
        if m.direct_menu_keys or m.diagnostic_without_binding_adapter then
            self.menu.toggle_key=121
            ctx.log('Direct menu keyboard handler; separate binding adapter and Bingus registration withheld')
        elseif not deps.keep_physical_hotkey then self.menu.toggle_key=0 end
        self.api.open=function()self.menu.visible=true end
        self.api.close=function()self.menu.visible=false;return self.capture.release()end
        self.api.is_open=function()return self.menu.visible end
        self.api.toggle=function()if self.menu.visible then return self.api.close()end;self.menu.visible=true;return true end
        self.api.menu_binding_status=function()return {focused=self.input.focused(),editing=self.menu.capture~=false or self.menu.text_edit~=nil or self.menu.color_picker~=nil,global_key=0}end
        self.api.focus_page=function(id,page_id)
            for index,mod in ipairs(self.api.list())do if mod.id==id then for at,page in ipairs(mod.pages)do if page.id==page_id then self.menu.selected=index;self.menu.page=at;self.menu.visible=true;self.menu.focus='settings';return true end end end end
            return false
        end
        ctx.log('Epic LUT own in-game menu ready; F10. MCM is absent; shared settings/runtime remain authoritative.')
    end
    function self.suspend()
        if not self.api then self.active=false;return true end
        if not self.active and not self.capture.status().pending_restore then return true end
        local ok,why=self.capture.shutdown()
        if not ok then ctx.log('Epic LUT frontend restoration pending: '..tostring(why));return false end
        self.menu.visible=false;self.view.release();self.active=false;return true
    end
    function self.resolve()
        local api=rawget(_G,'DBFMCM')
        if usable(api)then if self.suspend()then self.current_api=api;return api end;return nil end
        if api then if not self.reported_incompatible then ctx.log('An incompatible MCM instance is present; update or disable it before using the fallback menu.');self.reported_incompatible=true end;return nil end
        initialize();self.active=true;self.current_api=self.api;return self.api
    end
    function self.tick(dt)
        if not self.active then return end
        if usable(rawget(_G,'DBFMCM'))then self.suspend();return end
        local ok,why=pcall(function()
            self.input.poll();self.legacy.poll(rawget(_G,'ModOptionsMenu'))
            if (m.direct_menu_keys or m.diagnostic_without_binding_adapter) and self.preferences then self.menu.toggle_key=self.preferences.key()end
            if m.diagnostic_readonly_menu then
                self.menu.visible=true;self.menu.advance(dt)
                local w,h=self.resolution();self.view.draw(self.menu.compose(w,h))
                if not self.readonly_reported then self.readonly_reported=true;ctx.log('DIAGNOSTIC: full menu rendered read-only; no menu input or capture')end
                return
            end
            local focused=self.input.focused();local process_input=self.menu.input_focus(focused,self.input)
            if focused and self.menu.visible and not self.capture.active then
                local loader=rawget(_G,'LiveLuaLoader')
                if loader and type(loader.close_manager)=='function'then assert(loader.close_manager()~=false,'Loader cursor restoration pending')end
            end
            local acquired,reason=self.capture.sync(self.menu.visible,focused,self.input.window())
            if not acquired and (tostring(reason):find('Cannot acquire input capture',1,true)or tostring(reason):find('Input capture lost',1,true)or tostring(reason):find('Window capture unavailable',1,true))then
                if not self.waiting_capture then ctx.log('Epic LUT waiting for game input after focus return');self.waiting_capture=true end
                self.view.release();return
            end
            assert(acquired,reason);self.waiting_capture=false
            if process_input then self.menu.tick(self.input)end
            if not self.menu.visible and self.capture.active then assert(self.capture.release())end
            if self.menu.visible and not self.was_visible and self.default_mod_id then self.api.focus_page(self.default_mod_id,'quick_load')end
            self.was_visible=self.menu.visible
            if self.preferences then local key=self.preferences.key();self.menu.menu_key_label=key>=112 and key<=135 and ('F'..(key-111))or key>=65 and key<=90 and string.char(key)or ('VK '..key)end
            self.menu.advance(dt);local w,h=self.resolution();self.view.draw(self.menu.compose(w,h))
        end)
        if not ok then self.menu.recover();self.capture.release();self.view.release();ctx.log('Epic LUT own menu closed safely: '..tostring(why))end
    end
    function self.close()
        if not self.suspend()then return false end
        if self.legacy then self.legacy.release()end
        self.closed=true;if package.loaded['dbf.epic_lut.frontend.v1']==self then package.loaded['dbf.epic_lut.frontend.v1']=nil end
        return true
    end
    return self
end
return F
