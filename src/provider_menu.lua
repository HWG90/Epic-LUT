-- Presentation mount only: original options retain their provider's handles, callbacks and persistence.
local M={}
function M.new()
    local self={api=nil,owner=nil,prior_parent=nil,pages={}}
    function self.release()
        local api,owner=self.api,self.owner
        if api and owner and api.mods[owner.id]==owner then
            if owner.parent_name=='Epic LUT'then owner.parent_name=self.prior_parent end
            for page,name in pairs(self.pages)do if page.name=='CowboyBingus - Match Your Colors'then page.name=name end end
            api.revision=api.revision+1
        end
        self.api=nil;self.owner=nil;self.pages={}
    end
    function self.poll(api)
        local found
        for _,mod in pairs(api.mods or {})do
            if mod.legacy and type(mod.name)=='string' and mod.name:lower():gsub('[^%w]','')=='matchyourcolors' then found=mod;break end
        end
        if self.api==api and self.owner==found then return found~=nil end
        self.release()
        if not found or type(api.mount)~='function'then return false end
        self.api=api;self.owner=found;self.prior_parent=found.parent_name
        for _,page in ipairs(found.pages)do self.pages[page]=page.name;page.name='CowboyBingus - Match Your Colors'end
        api.mount(found.id,'Epic LUT')
        return true
    end
    return self
end
return M
