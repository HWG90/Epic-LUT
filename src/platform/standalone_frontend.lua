-- Standalone editor frontend with an optional MCM settings bridge.
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
                int mcm_set_cursor_mode(int);int mcm_install(void *);int mcm_capture(int);int mcm_captured(void);void mcm_release(void);int mcm_wheel(void);
            ]])
            local user=ffi.load('user32');local kernel=ffi.load('kernel32')
            local native=ffi.load(ctx.dir..'/'..assert(m.frontend_native_name,'Packaged input runtime missing'))
            for _,name in ipairs({'mcm_set_cursor_mode','mcm_install','mcm_capture','mcm_captured','mcm_release','mcm_wheel'})do assert(native[name],'Input runtime interface missing '..name)end
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
    if m.ui_font and deps.memory and deps.game and self.view.set_font_source then
        self.view.set_font_source(m.ui_font.new(deps.memory,deps.game,m.engine and m.engine.at))
    end
    self.api=m.ui_core.new(m.ui_store.new(assert(ctx.settings_dir)),ctx.log)
    self.menu=m.ui_menu.new(self.api,self.view.measure,m.text_editor)
    self.menu.text_metrics=self.view.text_metrics
    self.menu.on_dropdown_open=function(id,count)ctx.log('Epic LUT dropdown opened: '..tostring(id)..' ('..tostring(count)..' choices)')end
    if self.view.refresh_font then self.menu.measure_text=self.view.measure end
    self.clipboard=deps.clipboard or (m.clipboard and m.clipboard.new({window=function()return self.input.window()end}))
    self.api.clipboard=self.clipboard;self.menu.clipboard=self.clipboard
    self.menu.window_width=1420;self.menu.window_height=960;self.menu.toggle_key=121
    self.menu.compact_fonts=true
    self.menu.epic_typography=true
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
        self.menu.window_width=1100;self.menu.window_height=m.basic_view and m.basic_view.minimum_height or 1000
        self.api.focus_page(self.default_mod_id,'basic')
        self.menu.redraw_revision=(self.menu.redraw_revision or 0)+1
        return true
    end
    self.menu.open_basic=self.open_basic
    self.menu.open_advanced=self.open_advanced
    self.menu.font_size=12;self.menu.font_bold=true
    function self.render_ready()
        if self.closed or not self.input.focused()then return false end
        local w,h=self.resolution()
        local valid=type(w)=='number'and type(h)=='number'and w>0 and h>0 and w<math.huge and h<math.huge
        return valid,w,h
    end
    local function release_capture()
        local called,ready,why=pcall(self.capture.release)
        if not called then return false,tostring(ready)end
        if ready~=true then return false,why or 'Epic LUT input restoration is pending'end
        if self.capture.active then return false,'Epic LUT input capture is still active'end
        if self.capture.status then
            local checked,status=pcall(self.capture.status)
            if not checked or type(status)~='table' then return false,'Epic LUT input status is unavailable'end
            if status.active or status.pending_restore or status.owner then return false,'Epic LUT cursor restoration is pending'end
        end
        return true
    end
    local function release_input()
        self.input_cleanup_pending=true
        local ready,why=release_capture()
        if ready and self.photo_input_bridge then
            local called,ack,reason=pcall(self.photo_input_release,'Epic LUT')
            if not called then ready,why=false,tostring(ack)
            elseif ack~=true then ready,why=false,reason or 'Photo input handoff is pending'
            else self.photo_input_bridge=nil;self.photo_input_release=nil;self.photo_input_acquire=nil end
        end
        self.input_cleanup_reason=why
        if ready then self.input_cleanup_pending=nil end
        return ready,why
    end
    local function borrow_photo(photo)
        if self.photo_input_bridge and (self.photo_input_bridge~=photo or self.photo_input_release~=photo.release or self.photo_input_acquire~=photo.acquire)then
            local ready,why=release_input();if not ready then return false,why end
        end
        if self.photo_input_bridge or photo==nil then return true end
        if type(photo)~='table' or type(photo.acquire)~='function' or type(photo.release)~='function'then return false,'Photo input handoff is unavailable'end
        -- A late Photo provider must yield before this editor captures again.
        -- Release only our own snapshot; never force another owner's flags.
        local ready,why=release_capture();if not ready then self.input_cleanup_pending=true;self.input_cleanup_reason=why;return false,why end
        local acquire,release=photo.acquire,photo.release
        local called,ack,reason=pcall(acquire,'Epic LUT')
        if not called then return false,tostring(ack)end
        if ack~=true then return false,reason or 'Photo input restoration is pending'end
        self.photo_input_bridge=photo;self.photo_input_release=release;self.photo_input_acquire=acquire
        return true
    end
    function self.is_open()return not self.closed and self.menu.visible==true end
    function self.input_status()
        local status={};local ready=true
        if self.capture.status then ready,status=pcall(self.capture.status)end
        if not ready or type(status)~='table'then status={pending_restore=true}end
        return {open=self.menu.visible==true,active=self.capture.active==true,
            pending_restore=self.input_cleanup_pending==true or status.pending_restore==true,
            photo_borrowed=self.photo_input_bridge~=nil,owner=status.owner,
            reason=self.input_cleanup_reason,closed=self.closed==true}
    end
    self.api.focus_page=function(id,page_id)
        for index,mod in ipairs(self.api.list())do if mod.id==id then
            for at,page in ipairs(mod.pages)do if page.id==page_id then self.menu.selected=index;self.menu.page=at;self.menu.focus='settings';return true end end
        end end
        return false
    end
    function self.resolve()return self.api end
    if m.mcm_settings then
        self.mcm_settings=m.mcm_settings.new({api=self.api,source_mod_id='epic_direct_lut',version=m.version,
            open_basic=self.open_basic,open_advanced=self.open_advanced,log=ctx.log})
    end
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
            if self.mcm_settings then self.mcm_settings.tick(dt) end
            self.input.poll();local focused=self.input.focused()
            if self.input_cleanup_pending then
                local ready,reason=release_input();if not ready then self.menu.notice=tostring(reason);return end
            end
            local can_draw,w,h=self.render_ready();self.view.suspended=not can_draw
            local process_input=self.menu.input_focus(focused and can_draw,self.input)
            if not can_draw then
                -- Keep the open page and retained GUI intact while Windows is
                -- switching/minimizing. Native text and renderer cleanup wait.
                if self.menu.visible then self.capture.sync(true,false,self.input.window())
                else release_input()end
                return
            end
            local basic_key=self.preferences and self.preferences.basic_key and self.preferences.basic_key()or 120
            local basic_down=self.input.down(basic_key)
            if focused and process_input and basic_down and not self.basic_held and not self.menu.text_edit and not self.menu.capture then
                if self.basic_mode and self.menu.visible then self.menu.visible=false
                elseif self.default_mod_id and self.api.focus_page(self.default_mod_id,'basic')then
                    if not self.basic_mode then self.full_size={self.menu.window_width,self.menu.window_height}end;self.menu.window_width=1100;self.menu.window_height=m.basic_view and m.basic_view.minimum_height or 1000
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
            local photo=rawget(_G,'DBF_PHOTO_EDITOR_INPUT')
            local opening=focused and process_input and (full_down or basic_down)
            if self.menu.visible or opening then
                local ready,why=borrow_photo(photo)
                if not ready then self.menu.notice=tostring(why);return end
            elseif self.photo_input_bridge and not self.capture.active then
                local ready,why=release_input();if not ready then self.menu.notice=tostring(why);return end
            end
            local acquired,reason=self.capture.sync(self.menu.visible,focused,self.input.window(),self.preferences and self.preferences.cursor_mode and self.preferences.cursor_mode()or 'hardware')
            if not acquired then
                local text=tostring(reason)
                if text:find('Cannot acquire input capture',1,true)or text:find('Input capture lost',1,true)or text:find('Window capture unavailable',1,true)then self.view.release();return end
                error(text,0)
            end
            if process_input then self.menu.tick(self.input,dt)end
            if self.menu.visible and self.view.refresh_font then
                if self.view.refresh_font()then self.menu.redraw_revision=(self.menu.redraw_revision or 0)+1 end
                self.menu.font_metric_key=self.view.metric_key or self.view.font_key
                if self.font_logged_key~=self.view.font_key then
                    self.font_logged_key=self.view.font_key
                    ctx.log('Epic LUT UI font: '..(self.view.font_key=='core/performance_hud/debug'and 'stock debug' or 'game HUD'))
                end
            end
            if self.rendered_revision~=self.menu.redraw_revision then
                if self.view.invalidate then self.view.invalidate()else self.view.clear()end
                self.rendered_revision=self.menu.redraw_revision;self.draw_elapsed=1
            end
            if not self.menu.visible and (self.capture.active or self.was_visible)then self.preview_close_pending=true end
            if self.preview_close_pending then
                local portrait=package.loaded['epic.player_preview.v1']
                local ok,ready=true,true
                if portrait and portrait.before_editor_close then ok,ready=pcall(portrait.before_editor_close)end
                if ok and ready then self.preview_close_pending=nil;self.preview_close_error=nil
                elseif not ok and self.preview_close_error~=tostring(ready)then
                    self.preview_close_error=tostring(ready);ctx.log('Player Preview cleanup pending: '..self.preview_close_error)
                end
            end
            -- Retiring preview resources keep their own receipt. They must not
            -- reopen the editor or hold its cursor lease after a close shortcut.
            if not self.menu.visible and (self.capture.active or self.photo_input_bridge)then
                local ready,why=release_input();if not ready then self.menu.notice=tostring(why);return end
            end
            if self.menu.visible and not self.was_visible and self.default_mod_id and not self.opened_once then
                self.api.focus_page(self.default_mod_id,'direct');self.opened_once=true
            end
            if self.was_visible and not self.menu.visible and self.preferences and self.preferences.save_size then self.preferences.save_size(self.basic_mode and self.full_size and self.full_size[1]or self.menu.window_width,self.basic_mode and self.full_size and self.full_size[2]or self.menu.window_height)end
            self.was_visible=self.menu.visible
            -- Shortcuts, preview retirement and cursor restoration above remain
            -- live while closed; rendering is retired once per close transition.
            if not self.menu.visible then
                if not self.idle_render_clean then
                    self.menu.advance(dt)
                    self.menu.compose(w,h)
                    self.view.release()
                    self.idle_render_clean=true
                end
                return
            end
            self.idle_render_clean=false
            local key=self.menu.toggle_key;self.menu.menu_key_label=m.ui_menu.key_name(key)
            self.menu.advance(dt)
            self.view.draw(self.menu.compose(w,h))
        end)
        if not ok then
            pcall(self.menu.recover);release_input()
            local checked,ready=pcall(self.render_ready);if checked and ready then pcall(self.view.release)end
            ctx.log('Epic LUT menu closed safely: '..tostring(why))
        end
    end
    function self.dismiss()
        if self.closed then return true end
        local was_visible=self.menu.visible or self.was_visible
        self.menu.visible=false;self.menu.capture=false;self.was_visible=false
        if was_visible and self.preferences and self.preferences.save_size then
            local saved,why=pcall(self.preferences.save_size,self.basic_mode and self.full_size and self.full_size[1]or self.menu.window_width,self.basic_mode and self.full_size and self.full_size[2]or self.menu.window_height)
            if not saved then ctx.log('Menu size save failed: '..tostring(why))end
        end
        local polled,poll_error=pcall(self.input.poll)
        local released,why=release_input()
        local checked,can_draw,w,h=pcall(self.render_ready)
        can_draw=polled and checked and can_draw;self.view.suspended=not can_draw
        local cleared=false
        if can_draw then
            local composed,reason=pcall(self.menu.compose,w,h)
            local retired,result=pcall(self.view.release)
            cleared=retired and result~=false
            if not composed then return false,reason end
            if not retired then return false,result end
        end
        if not released then return false,why end
        if not polled then return false,poll_error end
        if not cleared then return false,'Menu GUI retirement waits for game focus and valid display dimensions'end
        -- Keep the frontend registered and render-ready until the preview and
        -- material cleanup stages acknowledge their native resource retirement.
        return true
    end
    function self.recover_input()
        -- Seed the menu's existing held-key latch on its next focused tick.
        -- Ctrl+Shift+F10 must not immediately replay the normal F10 opener;
        -- the same rule covers a rebound Basic shortcut and repeated recovery.
        self.menu.input_focus(false,self.input)
        local ready,why=self.dismiss()
        local status=self.input_status()
        if not status.active and not status.pending_restore and not status.photo_borrowed and not status.owner then return true end
        return false,why or self.input_cleanup_reason or 'Epic LUT input restoration is pending'
    end
    function self.close()
        if self.closed then return true end
        local dismissed,reason=self.dismiss()
        if self.mcm_settings then self.mcm_settings.close() end
        local ok,why=self.capture.shutdown();if not ok then ctx.log('Cursor restoration pending: '..tostring(why));return false end
        if not dismissed then return false,reason end
        self.closed=true
        if package.loaded['dbf.epic_lut.frontend.v1']==self then package.loaded['dbf.epic_lut.frontend.v1']=nil end
        return true
    end
    ctx.log('Epic LUT frontend ready; optional MCM settings bridge')
    return self
end
return F
