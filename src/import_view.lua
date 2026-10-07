-- Import workspace: source selection and target previews left; actions right.
local V={}
function V.new(info)
    local self={scroll=0}
    function self.wheel(x,y,delta)
        local b=self.bounds
        if b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then self.scroll=math.max(0,math.min(self.maximum or 0,self.scroll-delta/120*60));return true end
    end
    function self.draw(ui)
        local state=info();local top=ui.y+ui.h;local gap=18;local lw=math.floor(ui.w*.55);local rx=ui.x+lw+gap;local rw=ui.w-lw-gap
        local white,muted,blue={225,230,235},{155,166,175},{35,62,90}
        local function text(x,y,value)ui.text(x,y,value,14,white)end
        local function button(x,y,w,label,id)
            ui.rect(x,y,w,28,blue);ui.bounded(x+9,y+8,label,15,white,w-18);ui.hit(x,y,w,28,function()ui.activate(id)end)
        end
        ui.rect(ui.x,ui.y,lw,ui.h,{20,24,28});ui.rect(rx,ui.y,rw,ui.h,{20,24,28})
        ui.rect(ui.x,top-30,lw,30,blue);ui.rect(rx,top-30,rw,30,blue)
        text(ui.x+12,top-20,'LUTs and colors');text(rx+12,top-20,'Import and apply')
        text(ui.x+12,top-57,'Imported LUT: a color/material table from the file you chose.')
        ui.choice('palette',ui.x+12,top-97,lw-24)
        text(ui.x+12,top-124,'Live LUT #: a lookup table used by your current local gear.')
        ui.choice('lut',ui.x+12,top-164,lw-24)
        button(ui.x+12,top-207,180,'Refresh live LUTs','refresh')
        text(ui.x+12,top-235,'Color swatches are grouped by target, LUT and row.')
        local cliptop,clipbottom=top-257,ui.y+14;local cursor=cliptop+self.scroll
        self.bounds={x=ui.x,y=ui.y,w=lw,h=ui.h}
        local function visible(y,h)return y>=clipbottom and y+h<=cliptop end
        local cols={1,3,6,7,13,15,17,18,19,20}
        local function colors(title,entries)
            cursor=cursor-27
            if visible(cursor,23)then ui.rect(ui.x+10,cursor,lw-24,23,blue);text(ui.x+17,cursor+6,title)end
            if #entries==0 then cursor=cursor-21;if visible(cursor,18)then ui.text(ui.x+17,cursor+4,'No palette applied to this target.',13,muted)end end
            for _,entry in ipairs(entries)do
                cursor=cursor-22;if visible(cursor,18)then text(ui.x+17,cursor+4,entry.name)end
                cursor=cursor-18
                if visible(cursor,15)then for i,label in ipairs({'Base','D1','In','Out','Curv','Tint','C1','C2','C3','C4'})do ui.text(ui.x+90+(i-1)*26,cursor+3,label,12,muted)end end
                for row=1,entry.height do
                    cursor=cursor-18
                    if visible(cursor,17)then
                        ui.text(ui.x+23,cursor+5,'Row '..row,13,muted)
                        for i,col in ipairs(cols)do
                            local at=((row-1)*entry.width+col-1)*4;local rgb={}
                            for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,entry.data[at+ch]))*255+.5)end
                            ui.rect(ui.x+90+(i-1)*26,cursor,22,16,rgb)
                        end
                    end
                end
            end
        end
        if state.tables and #state.tables>0 then colors('Imported tables',state.tables)end
        colors('Armor',state.armor);colors('Helmet',state.helmet)
        local content=cliptop+self.scroll-cursor;local viewport=cliptop-clipbottom;self.maximum=math.max(0,content-viewport);self.scroll=math.min(self.scroll,self.maximum)
        if self.maximum>0 then local thumb=math.max(18,viewport*viewport/content);ui.rect(ui.x+lw-6,clipbottom,4,viewport,{50,60,70});ui.rect(ui.x+lw-7,cliptop-thumb-(viewport-thumb)*self.scroll/self.maximum,6,thumb,{120,135,150})end
        button(rx+12,top-77,rw-24,'Import DDS / ZIP / RAR...','browse')
        local y=top-117
        if state.busy then
            local spin=math.floor(state.time*8)%8
            for i=0,7 do local angle=i*math.pi/4;ui.rect(rx+29+math.cos(angle)*11,y+8+math.sin(angle)*11,4,4,i==spin and {244,202,53}or {75,88,100})end
            ui.text(rx+55,y+5,state.phase..'  ('..state.elapsed..'s)',14,white)
        else ui.bounded(rx+12,y+5,state.status,14,muted,rw-24)end
        button(rx+12,top-161,(rw-29)/2,'Cancel import','cancel_import');button(rx+17+(rw-29)/2,top-161,(rw-29)/2,'Retry file picker','retry_import')
        button(rx+12,top-203,rw-24,'Save LUT to Palette','save_palette')
        button(rx+12,top-348,(rw-29)/2,'[ '..(state.helmet_checked and 'x'or ' ')..' ] Helmet','target_helmet')
        button(rx+17+(rw-29)/2,top-348,(rw-29)/2,'[ '..(state.armor_checked and 'x'or ' ')..' ] Armor','target_armor')
        text(rx+12,top-309,'Apply LUT to...')
        button(rx+12,top-391,rw-24,'Apply LUT','apply_checked')
        button(rx+12,top-429,rw-24,'[ '..(state.preserve_emissives and 'x'or ' ')..' ] Preserve Original Emissives','preserve_emissives')
        if state.loaded then
            text(rx+12,top-238,'Imported colors (primary color by row)')
            local size=math.min(26,(rw-24)/state.loaded.height)
            for row=1,state.loaded.height do local at=(row-1)*state.loaded.width*4;local rgb={};for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,state.loaded.data[at+ch]))*255+.5)end;ui.rect(rx+12+(row-1)*size,top-270,size-3,24,rgb)end
        end
        button(rx+12,top-473,rw-24,'Restore Original LUT','restore')
        button(rx+12,top-512,rw-24,'Restore Imported LUT','restore_imported')
        button(rx+12,top-556,rw-24,'Save applied setup','save_setup')
        ui.text(rx+12,top-585,'Save applied setup keeps Armor / Helmet assignments for next launch.',13,muted)
        ui.text(rx+12,ui.y+14,'RAR requires installed 7-Zip. Match Your Colors should be Off.',13,muted)
    end
    return self
end
return V
