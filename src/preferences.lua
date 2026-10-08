local P={}
function P.new(storage)
    local self={}
    function self.mount(api)
        if self.api==api and self.handle and api.mods.epic_lut_preferences then return self.handle end
        if self.handle then self.handle.unregister()end
        self.api=api;self.handle=api.register({id='epic_lut_preferences',name='Epic LUT preferences',parent_name='Epic LUT',storage=storage,pages={{id='menu',name='Menu controls',require_confirmation=false,controls={
            {id='basic_key',type='keybind',label='Open Basic Mode',default=120,description='F9 opens Basic.'},
            {id='menu_key',type='keybind',label='Open Advanced Mode',default=121,description='Keyboard shortcut for the standalone Epic LUT editor. F10 is the default.'},
            {id='preview_key',type='keybind',label='Toggle Player Preview',default=117,description='F6 by default. Toggles the docked preview in LUT Editor and the pop-out on other pages.'},
            {id='ui_scale',type='slider',label='UI scale (%)',min=70,max=130,step=5,default=100},
            {id='font_size',type='slider',label='Font size',min=10,max=20,step=1,default=12},
            {id='font_bold',type='toggle',label='Bold text',default=true},
            {id='auto_updates',type='toggle',label='Check for updates at launch',default=false},
            {id='window_width',type='slider',label='Window width',min=1420,max=7680,step=1,default=1420},
            {id='window_height',type='slider',label='Window height',min=960,max=4320,step=1,default=960},
            {id='reset_key',type='button',label='Reset menu key to F10',on_activate=function()return self.handle.set('menu_key',121)end}
        }}}})
        api.mods.epic_lut_preferences.pages={} -- Presentation aliases expose the same authoritative controls in Extras.
        return self.handle
    end
    function self.key()return self.handle and self.handle.get('menu_key')or 121 end
    function self.basic_key()return self.handle and self.handle.get('basic_key')or 120 end
    function self.preview_key()return self.handle and self.handle.get('preview_key')or 117 end
    function self.scale()return self.handle and self.handle.get('ui_scale')or 100 end
    function self.font_size()return self.handle and self.handle.get('font_size')or 12 end
    function self.font_bold()return not self.handle or self.handle.get('font_bold')~=false end
    function self.auto_updates()return self.handle and self.handle.get('auto_updates')==true end
    function self.save_auto_updates(value)if self.handle then return self.handle.set('auto_updates',value)end end
    function self.save_scale(value)if self.handle then return self.handle.set('ui_scale',value)end end
    function self.size()return self.handle and self.handle.get('window_width')or 1420,self.handle and self.handle.get('window_height')or 960 end
    function self.save_size(width,height)
        if self.handle then return self.handle.set_many({window_width=math.max(1420,math.floor(width+.5)),window_height=math.max(960,math.floor(height+.5))})end
    end
    function self.close()if self.handle then self.handle.unregister();self.handle=nil end end
    return self
end
return P
