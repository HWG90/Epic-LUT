local P={}
function P.new(storage)
    local self={}
    function self.mount(api)
        if self.api==api and self.handle and api.mods.epic_lut_preferences then return self.handle end
        if self.handle then self.handle.unregister()end
        self.api=api;self.handle=api.register({id='epic_lut_preferences',name='Epic LUT preferences',parent_name='Epic LUT',storage=storage,pages={{id='menu',name='Menu controls',require_confirmation=false,controls={
            {id='menu_key',type='keybind',label='Epic LUT menu key',default=121,description='Keyboard shortcut; F10 defaults to MCM ownership when MCM is present. A different key opens/focuses Epic LUT. Bingus MODS binding is optional and game-owned.'},
            {id='reset_key',type='button',label='Reset menu key to F10',on_activate=function()return self.handle.set('menu_key',121)end}
        }}}})
        api.mods.epic_lut_preferences.pages={} -- Presentation aliases expose the same authoritative controls in Extras.
        return self.handle
    end
    function self.key()return self.handle and self.handle.get('menu_key')or 121 end
    function self.close()if self.handle then self.handle.unregister();self.handle=nil end end
    return self
end
return P
