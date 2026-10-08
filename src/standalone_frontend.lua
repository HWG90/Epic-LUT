-- Standalone editor frontend. No MCM detection, compatibility registry or binding adapter.
local F={}
function F.new(m,ctx,deps)
    deps=deps or {};local self={preview_cleanup_guard=true}
    local prior=package.loaded['dbf.epic_lut.frontend.v1'];assert(not prior or prior.closed,'Another Epic LUT frontend is active')
    package.loaded['dbf.epic_lut.frontend.v1']=self
    if deps.input then
        self.input=deps.input;self.capture=deps.capture;self.view=deps.view;self.resolution=deps.resolution
    else
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
                int mcm_install(void *);int mcm_capture(int);int mcm_captured(void);void mcm_release(void);int mcm_wheel(void);
            ]])
            local user=ffi.load('user32');local kernel=ffi.load('kernel32')
            local native=ffi.load(ctx.dir..'/'..assert(m.frontend_native_name,'Packaged input runtime missing'))
            for _,name in ipairs({'mcm_install','mcm_capture','mcm_captured','mcm_release','mcm_wheel'})do assert(native[name],'Input runtime interface missing '..name)end
            local sr=assert(rawget(_G,'stingray'));local process=kernel.epic_front_pid();local foreground;local process_out=ffi.new('uint32_t[1]');local point=ffi.new('epic_front_point[1]');local rect=ffi.new('long[4]')
            self.capture=m.ui_capture.new(native,assert(sr.Window),ctx.log)
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
    end
    self.api=m.ui_core.new(m.ui_store.new(assert(ctx.settings_dir)),ctx.log)
    self.menu=m.ui_menu.new(self.api,self.view.measure)
    self.menu.window_width=1420;self.menu.window_height=960;self.menu.toggle_key=121
    self.menu.compact_fonts=true
    function self.open_advanced()
        self.basic_mode=false;self.menu.basic_only=false;self.menu.visible=true;self.opened_once=true
        if self.full_size then self.menu.window_width,self.menu.window_height=unpack(self.full_size)end
        if self.default_mod_id then
            if not self.api.focus_page(self.default_mod_id,'colors')then self.api.focus_page(self.default_mod_id,'direct')end
        end
        self.menu.redraw_revision=(self.menu.redraw_revision or 0)+1
        return true
    end
    function self.open_basic()
        if not self.basic_mode then self.full_size={self.menu.window_width,self.menu.window_height}end
        self.basic_mode=true;self.menu.basic_only=true;self.menu.visible=true;self.opened_once=true
        self.menu.window_width=1100;self.menu.window_height=780
        self.api.focus_page(self.default_mod_id,'basic')
        self.menu.redraw_revision=(self.menu.redraw_revision or 0)+1
        return true
    end
    self.menu.open_basic=self.open_basic
    self.menu.open_advanced=self.open_advanced
    self.menu.font_size=12;self.menu.font_bold=true
    self.api.focus_page=function(id,page_id)
        for index,mod in ipairs(self.api.list())do if mod.id==id then
            for at,page in ipairs(mod.pages)do if page.id==page_id then self.menu.selected=index;self.menu.page=at;self.menu.focus='settings';return true end end
        end end
        return false
    end
    function self.resolve()return self.api end
    function self.tick(dt)
        if self.closed then return end
        local ok,why=pcall(function()
            if self.preferences then
                self.preferences.mount(self.api)
                self.api.mods.epic_lut_preferences.hidden=true
                self.menu.toggle_key=self.preferences.key()
                if self.preferences.scale then self.menu.ui_scale=self.preferences.scale()/100 end
                if self.preferences.font_size then self.menu.font_size=self.preferences.font_size()end
                if self.preferences.font_bold then self.menu.font_bold=self.preferences.font_bold()end
                if not self.size_loaded and self.preferences.size then self.menu.window_width,self.menu.window_height=self.preferences.size();self.size_loaded=true end
            end
            self.input.poll();local focused=self.input.focused()
            local process_input=self.menu.input_focus(focused,self.input)
            local basic_key=self.preferences and self.preferences.basic_key and self.preferences.basic_key()or 120
            local basic_down=self.input.down(basic_key)
            if focused and process_input and basic_down and not self.basic_held and not self.menu.text_edit and not self.menu.capture then
                if self.basic_mode and self.menu.visible then self.menu.visible=false
                elseif self.default_mod_id and self.api.focus_page(self.default_mod_id,'basic')then
                    if not self.basic_mode then self.full_size={self.menu.window_width,self.menu.window_height}end;self.menu.window_width=1100;self.menu.window_height=780
                    self.menu.visible=true;self.basic_mode=true;self.menu.basic_only=true;self.opened_once=true
                end
            end
            self.basic_held=basic_down
            local full_down=self.input.down(self.menu.toggle_key)
            if focused and process_input and full_down and not self.full_held and self.basic_mode and not self.menu.capture then
                self.basic_mode=false;self.menu.basic_only=false
                if self.full_size then self.menu.window_width,self.menu.window_height=unpack(self.full_size)end
                self.api.focus_page(self.default_mod_id,'direct')
                self.menu.visible=false -- Standard F10 edge handling opens it below.
            end
            self.full_held=full_down

            if focused and self.menu.visible and not self.capture.active then
                local loader=rawget(_G,'LiveLuaLoader')
                if loader and type(loader.close_manager)=='function'then assert(loader.close_manager()~=false,'Loader cursor restoration pending')end
            end
            local acquired,reason=self.capture.sync(self.menu.visible,focused,self.input.window())
            if not acquired then
                local text=tostring(reason)
                if text:find('Cannot acquire input capture',1,true)or text:find('Input capture lost',1,true)or text:find('Window capture unavailable',1,true)then self.view.release();return end
                error(text,0)
            end
            if self.preview_close_pending then self.menu.visible=false end
            if process_input then self.menu.tick(self.input)end
            if self.rendered_revision~=self.menu.redraw_revision then
                if self.view.invalidate then self.view.invalidate()else self.view.clear()end
                self.rendered_revision=self.menu.redraw_revision
            end
            if not self.menu.visible and self.capture.active then
                local portrait=package.loaded['epic.player_preview.v1']
                local ready=not portrait or not portrait.before_editor_close or portrait.before_editor_close()
                if ready then self.preview_close_pending=nil;assert(self.capture.release())
                else self.preview_close_pending=true;self.menu.visible=true end
            end
            if self.menu.visible and not self.was_visible and self.default_mod_id and not self.opened_once then
                self.api.focus_page(self.default_mod_id,'direct');self.opened_once=true
            end
            if self.was_visible and not self.menu.visible and self.preferences and self.preferences.save_size then self.preferences.save_size(self.basic_mode and self.full_size and self.full_size[1]or self.menu.window_width,self.basic_mode and self.full_size and self.full_size[2]or self.menu.window_height)end
            self.was_visible=self.menu.visible
            local key=self.menu.toggle_key;self.menu.menu_key_label=m.ui_menu.key_name(key)
            self.menu.advance(dt);local w,h=self.resolution();self.view.draw(self.menu.compose(w,h))
        end)
        if not ok then self.menu.recover();self.capture.release();self.view.release();ctx.log('Epic LUT menu closed safely: '..tostring(why))end
    end
    function self.close()
        if self.preferences and self.preferences.save_size then self.preferences.save_size(self.basic_mode and self.full_size and self.full_size[1]or self.menu.window_width,self.basic_mode and self.full_size and self.full_size[2]or self.menu.window_height)end
        self.menu.visible=false
        local ok,why=self.capture.shutdown();if not ok then ctx.log('Cursor restoration pending: '..tostring(why));return false end
        self.view.release();self.closed=true
        if package.loaded['dbf.epic_lut.frontend.v1']==self then package.loaded['dbf.epic_lut.frontend.v1']=nil end
        return true
    end
    ctx.log('Epic LUT standalone frontend ready; no MCM integration')
    return self
end
return F
