-- Import workspace: source selection and target previews left; actions right.
local V={}
function V.new(info,tables,select_color,core)
    local self={scroll=0,advanced=false,show_all=false,scratch={255,255,255},hue=0,swatches={}}
    function self.wheel(x,y,delta)
        local b=self.bounds
        if b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then self.scroll=math.max(0,math.min(self.maximum or 0,self.scroll-delta/120*60));return true end
    end
    function self.draw(ui)
        ui.rect(ui.x+ui.w-150,ui.y-24,150,28,{35,62,90})
        ui.bounded(ui.x+ui.w-142,ui.y-16,'Stop Highlight',14,{225,230,235},134)
        ui.hit(ui.x+ui.w-150,ui.y-24,150,28,function()ui.activate('stop_identify')end)
        local state=info();if self.show_all and state.raw then state.tables=state.raw.tables;state.armor=state.raw.armor;state.helmet=state.raw.helmet end;local top=ui.y+ui.h;local gap=18;local lw=math.floor(ui.w*.55);local rx=ui.x+lw+gap;local rw=ui.w-lw-gap
        local white,muted,blue={225,230,235},{155,166,175},{35,62,90}
        local function text(x,y,value)ui.text(x,y,value,14,white)end
        local function button(x,y,w,label,id)
            w=math.max(0,math.min(w,ui.x+ui.w-x-6));if w<20 then return end
            ui.rect(x,y,w,28,blue);ui.bounded(x+9,y+8,label,15,white,w-18);ui.hit(x,y,w,28,function()ui.activate(id)end)
        end
        ui.rect(ui.x,ui.y,lw,ui.h,{20,24,28});ui.rect(rx,ui.y,rw,ui.h,{20,24,28})
        ui.rect(ui.x,top-30,lw,30,blue);ui.rect(rx,top-30,rw,30,blue)
        text(ui.x+12,top-20,'LUTs and colors');text(rx+12,top-20,'Import and apply')
        button(ui.x+12,top-77,lw-24,'Load Current Armor & Helmet','populate_worn')
        local offset=75
        if (state.palette_count or 0)>1 then
            text(ui.x+12,top-83,'Imported LUT - choose a table from this file')
            ui.choice('palette',ui.x+12,top-119,lw-24);offset=135
        elseif state.loaded then
            ui.bounded(ui.x+12,top-83,state.loaded.source or 'One imported LUT',14,muted,lw-24);offset=105
        end
        local ay=top-offset-28
        ui.rect(ui.x+12,ay,lw-24,26,blue)
        text(ui.x+20,ay+6,(self.advanced and 'v'or '>')..' Advanced - individual live LUTs')
        ui.hit(ui.x+12,ay,lw-24,26,function()self.advanced=not self.advanced;self.scroll=0 end)
        if self.advanced then
            text(ui.x+12,ay-24,'Live LUT #: a table used by your currently worn gear.')
            button(ui.x+12,ay-61,lw-24,'Refresh live LUTs','refresh')
            ui.bounded(ui.x+12,ay-123,'Armor / Helmet checkboxes apply to all their LUTs, regardless of this selection.',13,muted,lw-24)
        end
        local cliptop,clipbottom=ay-(self.advanced and 145 or 20),ui.y+14;local cursor=cliptop+self.scroll
        self.bounds={x=ui.x,y=ui.y,w=lw,h=ui.h}
        local function visible(y,h)return y>=clipbottom and y+h<=cliptop end
        local function paint()
            if self.selected and ui.set then ui.set('quick_color',string.format('#%02X%02X%02X',self.scratch[1],self.scratch[2],self.scratch[3]))end
        end
        local function draw_scratch(x,y,width,height)
            local scratchx,scratchw,sh,sy=x,width,height,y;local scratchtop=y+height
        ui.rect(scratchx,sy,scratchw,sh,{25,30,35});ui.rect(scratchx,scratchtop-28,scratchw,28,blue)
        text(scratchx+8,scratchtop-20,'Quick Scratch')
        ui.rect(scratchx+10,scratchtop-60,scratchw-20,22,self.scratch)
        local gx,gy=scratchx+10,sy+110;local gw,gh=scratchw-40,sh-180
        local function choose(key,color)
            self.scratch=color
            -- The scratch area only chooses a color; palette right-click paints it.
        end
        if core then
            for v=0,19 do for sat=0,19 do
                local saturation,value=sat/19,v/19;local x,y=gx+sat*gw/20,gy+v*gh/20
                ui.rect(x,y,gw/20+1,gh/20+1,core.hsv_rgb(self.hue,saturation,value))
                ui.hit(x,y,gw/20,gh/20,function()choose('sv:'..sat..':'..v,core.hsv_rgb(self.hue,saturation,value))end)
            end end
            for i=0,19 do local hue=i/20;local y=gy+i*gh/20
                ui.rect(gx+gw+5,y,12,gh/20+1,core.hsv_rgb(hue,1,1))
                ui.hit(gx+gw+5,y,12,gh/20,function()self.hue=hue;local _,sat,val=core.rgb_hsv(self.scratch);self.scratch=core.hsv_rgb(hue,sat,val)end)
            end
        end
        local bw=(scratchw-25)/2
        ui.rect(scratchx+10,sy+73,bw,28,blue);ui.bounded(scratchx+14,sy+81,'Paint selected RGB',15,white,bw-8)
        ui.hit(scratchx+10,sy+73,bw,28,paint)
        ui.rect(scratchx+15+bw,sy+73,bw,28,blue);ui.bounded(scratchx+19+bw,sy+81,'Save swatch',15,white,bw-8)
        ui.hit(scratchx+15+bw,sy+73,bw,28,function()
            local slot
            for i=1,10 do if not self.swatches[i]then slot=i;break end end
            slot=slot or self.next_slot or 1
            self.swatches[slot]={self.scratch[1],self.scratch[2],self.scratch[3]};self.next_slot=slot%10+1
        end)
        local slotw=(scratchw-20)/5
        for i=1,10 do
            local x=scratchx+10+((i-1)%5)*slotw;local y=sy+12+(1-math.floor((i-1)/5))*26;local color=self.swatches[i]
            ui.rect(x,y,slotw-4,22,{100,110,120});ui.rect(x+2,y+2,slotw-8,18,color or {25,30,35})
            if not color then ui.bounded(x+5,y+7,'Empty '..i,10,muted,slotw-14)end
            local slot=i
            ui.hit(x,y,slotw-4,22,function()
                local saved=self.swatches[slot]
                if saved then self.scratch={saved[1],saved[2],saved[3]};if core then self.hue=core.rgb_hsv(self.scratch)end end
            end)
        end
        end
        local toggle_x=ui.x+lw-152
        ui.rect(toggle_x,cliptop+2,140,26,blue);text(toggle_x+8,cliptop+10,'Quick Scratch')
        ui.hit(toggle_x,cliptop+2,140,26,function()self.scratch_open=not self.scratch_open end)
        if self.scratch_open and ui.floating then ui.floating('quick_scratch',draw_scratch,260,330,function()self.scratch_open=false end)end
        if self.selected then ui.bounded(ui.x+12,cliptop+9,'Editing: '..(self.selected.label or '')..' / Row '..self.selected.row..' / '..(self.selected.field or self.selected.column),13,muted,lw-175)end
        local cols={1,3,6,7,13,15,17,18,19,20}
        local function colors(title,entries)
            cursor=cursor-27
            if visible(cursor,23)then ui.rect(ui.x+10,cursor,338,23,blue);text(ui.x+17,cursor+6,title)end
            if #entries==0 then cursor=cursor-21;if visible(cursor,18)then ui.text(ui.x+17,cursor+4,'No palette applied to this target.',13,muted)end end
            for number,entry in ipairs(entries)do
                local selection_key=title..'/'..tostring(entry.index or entry.ids and entry.ids[1]or entry.source or entry.name)
                cursor=cursor-22;if visible(cursor,18)then
                    text(ui.x+17,cursor+4,entry.name)
                    if number==1 and title~='Imported tables' then ui.choice('basic_'..title:lower()..'_lut',ui.x+210,cursor-2,138)end
                    ui.hit(ui.x+12,cursor,190,18,function()
                        local row=math.min(entry.height,self.selected and self.selected.row or 1)
                        local column=self.selected and self.selected.column or 1
                        if select_color then select_color(entry,row,column)end
                        self.selected={key=selection_key,data=entry.data,row=row,column=column,label=title..' / '..entry.name}
                    end)
                end
                cursor=cursor-18
                if visible(cursor,15)then for i,label in ipairs({'Base','D1','In','Out','Curv','Tint','C1','C2','C3','C4'})do ui.text(ui.x+90+(i-1)*26,cursor+3,label,12,muted)end end
                for row=1,entry.height do
                    cursor=cursor-18
                    if visible(cursor,17)then
                        local pulse=.5+.5*math.sin((state.time or 0)*3)
                        ui.text(ui.x+23,cursor+5,'Row '..row,13,{math.floor(175+69*pulse),math.floor(180+22*pulse),math.floor(140-87*pulse)})
                        local selected_row=row;local selected_entry=entry
                        ui.hit(ui.x+12,cursor,72,17,function()
                            if select_color then select_color(selected_entry,selected_row,1,true,title:lower())end
                            ui.activate('identify_region')
                        end)
                        for i,col in ipairs(cols)do
                            local at=((row-1)*entry.width+col-1)*4;local rgb={}
                            for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,entry.data[at+ch]))*255+.5)end
                            ui.rect(ui.x+90+(i-1)*26,cursor,22,16,rgb)
                            local selected_entry,selected_row,selected_col=entry,row,col
                            local sx=ui.x+90+(i-1)*26
                            if self.selected and self.selected.key==selection_key and self.selected.row==row and self.selected.column==col then ui.rect(sx-2,cursor-2,26,2,{244,202,53});ui.rect(sx-2,cursor+16,26,2,{244,202,53})end
                            local function select()
                                self.selected={key=selection_key,data=selected_entry.data,row=selected_row,column=selected_col,label=title..' / '..entry.name,field=({'Base','Detail','Inner','Outer','Curvature','Tint','Camo 1','Camo 2','Camo 3','Camo 4'})[i]}
                                -- Selecting another table cell keeps the chosen scratch color.
                                if select_color then select_color(selected_entry,selected_row,selected_col)end
                            end
                            ui.hit(sx,cursor,22,16,select,function()select();paint()end)
                        end
                    end
                end
            end
        end
        if state.tables and #state.tables>0 then colors('Imported tables',state.tables)end
        colors('Armor',state.armor);colors('Helmet',state.helmet)
        cursor=cursor-38
        if visible(cursor,28)then
            ui.rect(ui.x+12,cursor,336,28,blue);text(ui.x+20,cursor+8,self.show_all and 'Hide identical LUTs'or 'Show All LUTs')
            ui.hit(ui.x+12,cursor,336,28,function()self.show_all=not self.show_all;self.scroll=0 end)
        end
        local content=cliptop+self.scroll-cursor;local viewport=cliptop-clipbottom;self.maximum=math.max(0,content-viewport);self.scroll=math.min(self.scroll,self.maximum)
        if self.maximum>0 then local thumb=math.max(18,viewport*viewport/content);ui.rect(ui.x+lw-6,clipbottom,4,viewport,{50,60,70});ui.rect(ui.x+lw-7,cliptop-thumb-(viewport-thumb)*self.scroll/self.maximum,6,thumb,{120,135,150})end
        button(rx+12,top-77,rw-24,'Choose file - DDS / ZIP / RAR...','browse')
        local y=top-117
        if state.busy then
            local spin=math.floor(state.time*8)%8
            for i=0,7 do local angle=i*math.pi/4;ui.rect(rx+29+math.cos(angle)*11,y+8+math.sin(angle)*11,4,4,i==spin and {244,202,53}or {75,88,100})end
            ui.text(rx+55,y+5,state.phase..'  ('..state.elapsed..'s)',14,white)
        else ui.bounded(rx+12,y+5,state.status,14,muted,rw-24)end
        if state.busy then button(rx+12,top-161,(rw-29)/2,'Cancel import','cancel_import');button(rx+17+(rw-29)/2,top-161,(rw-29)/2,'Retry file picker','retry_import')end
        button(rx+12,top-203,rw-24,'Save LUT to Palette','save_palette')
        if state.dirty then ui.bounded(rx+12,top-288,'Editor modified - export DDS to keep/share edits.',13,{244,202,53},rw-24)end
        ui.bounded(rx+12,top-224,'Overwrites the editor table; does not apply to gear.',13,muted,rw-24)
        button(rx+12,top-348,(rw-29)/2,'[ '..(state.helmet_checked and 'x'or ' ')..' ] Helmet','target_helmet')
        button(rx+17+(rw-29)/2,top-348,(rw-29)/2,'[ '..(state.armor_checked and 'x'or ' ')..' ] Armor','target_armor')
        text(rx+12,top-309,'Apply LUT to...')
        button(rx+12,top-391,rw-24,'Apply LUT','apply_checked')
        button(rx+12,top-429,rw-24,'[ '..(state.preserve_emissives and 'x'or ' ')..' ] Preserve Original Emissives','preserve_emissives')
        if state.loaded then
            text(rx+12,top-238,'Imported colors - ready for editor or Apply')
            local size=math.min(26,(rw-24)/state.loaded.height)
            for row=1,state.loaded.height do local at=(row-1)*state.loaded.width*4;local rgb={};for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,state.loaded.data[at+ch]))*255+.5)end;ui.rect(rx+12+(row-1)*size,top-270,size-3,24,rgb)end
        end
        button(rx+12,top-473,rw-24,'Restore Original LUT','restore')
        button(rx+12,top-512,rw-24,'Restore Imported LUT (editor)','restore_imported')
        button(rx+12,top-556,(rw-29)/2,'Undo quick edit','undo');button(rx+17+(rw-29)/2,top-556,(rw-29)/2,'Redo quick edit','redo')
        button(rx+12,top-600,rw-24,'Save applied setup','save_setup')
        ui.text(rx+12,top-630,'Save applied setup keeps Armor / Helmet assignments for next launch.',13,muted)
        ui.text(rx+12,ui.y+14,'RAR requires installed 7-Zip. Match Your Colors should be Off.',13,muted)
    end
    return self
end
return V
