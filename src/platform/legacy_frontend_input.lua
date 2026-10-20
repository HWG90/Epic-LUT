-- Legacy LuaJIT input adapter. Excluded from the stock Lua 5.1 dependency graph.
local L={}
function L.new(m,ctx)
    local result={}
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
            result.capture=m.ui_capture.new(native,assert(sr.Window),ctx.log)
            result.view=m.ui_view.new(sr,nil,ctx.log)
            result.input={poll=function()foreground=user.epic_front_foreground();user.epic_front_window_pid(foreground,process_out);if process_out[0]~=process then foreground=nil end end,
                focused=function()return foreground~=nil end,window=function()return foreground end,
                down=function(code)return foreground and bit.band(tonumber(user.epic_front_key(code)),0x8000)~=0 or false end,
                wheel=function()return tonumber(native.mcm_wheel())end,
                mouse=function()
                    if not foreground or user.epic_front_cursor(point)==0 or user.epic_front_client(foreground,point)==0 or user.epic_front_rect(foreground,rect)==0 then return end
                    local w,h=sr.Gui.resolution();local cw,ch=tonumber(rect[2]),tonumber(rect[3]);if cw<=0 or ch<=0 then return end
                    return tonumber(point[0].x)*w/cw,h-tonumber(point[0].y)*h/ch
                end}
            result.resolution=sr.Gui.resolution
    return result
end
return L
