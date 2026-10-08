-- Optional documented Bingus action plus one shared, persisted keyboard fallback key.
local B={}
function B.new(m,frontend,preferences,ctx,platform)
    local self={held=false,blocked=false,registered=false,retired=false,intent=0}
    if not platform then
        local ffi=require('ffi');local bit=require('bit');local user,kernel=m.native_import.verify_interface()
        if not pcall(function()return user.epic_binding3_key end)then ffi.cdef('short epic_binding3_key(int) __asm__("GetAsyncKeyState");')end
        local pid=kernel.epic_native_pid();local out=ffi.new('uint32_t[1]')
        platform={focused=function()local hwnd=user.epic_native_foreground();user.epic_native_window_pid(hwnd,out);return out[0]==pid end,
            down=function(code)return code>0 and code<=255 and bit.band(tonumber(user.epic_binding3_key(code)),0x8000)~=0 or false end,
            native_editing=function(api)local sr=rawget(_G,'stingray');return not api.is_open()and sr and sr.Window and sr.Window.mouse_focus and not sr.Window.mouse_focus()end}
    end
    local id='goose.epic_lut.open_menu'
    function self.tick()
        if self.retired then return end
        local provider=not m.native_bindings_disabled and rawget(_G,'ModBindingsMenu')or nil
        if provider~=self.provider then self.provider=provider;self.registered=false end
        if provider and provider.api==1 and (provider.version or 0)>=2 and not self.registered then
            local ok,result=pcall(provider.register_binding,id,'Open Epic LUT',nil,{category='Epic LUT'})
            self.registered=ok and result==true
        end
        local api=frontend.current_api;if not api or not preferences.handle then return end
        local native=false
        if self.registered then local ok,value=pcall(provider.is_down,id);native=ok and value==true end
        local key=preferences.key();local physical=platform.down(key);local down=physical or native
        local status=api.menu_binding_status and api.menu_binding_status()or {editing=false}
        if not platform.focused()or status.editing or(platform.native_editing and platform.native_editing(api))then self.blocked=true;self.held=down;self.intent=0;return end
        if self.blocked then self.blocked=false;self.held=down;return end
        local pressed=down and not self.held;self.held=down
        local own=api==frontend.api
        if pressed then
            if not own and key==121 and physical then
                -- Leave the global F10 open/close edge to MCM; focus only after it opens.
                if not api.is_open()then self.intent=3 end
            elseif own then api.toggle()else
                if api.focus_page and self.root_id then api.focus_page(self.root_id,'quick_load')elseif api.open then api.open()end
            end
        end
        if self.intent>0 then
            self.intent=self.intent-1
            if api.is_open()then if api.focus_page and self.root_id then api.focus_page(self.root_id,'quick_load')end;self.intent=0 end
        end
    end
    function self.close()self.retired=true;self.held=false;self.intent=0 end -- The Bingus API has no unregister; preserve its saved assignments.
    return self
end
return B
