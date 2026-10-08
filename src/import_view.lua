-- Import workspace: source selection and target previews left; actions right.
local V={}
function V.new(info,tables,select_color,core)
    local self={scroll=0,advanced=false,show_all=false,scratch={255,255,255},hue=0,swatches={}}
    function self.wheel(x,y,delta)
        local imported=self.import_bounds
        if imported and x>=imported.x and x<=imported.x+imported.w and y>=imported.y and y<=imported.y+imported.h then self.import_scroll=math.max(0,math.min(self.import_max or 0,(self.import_scroll or 0)-delta/120*22));return true end
        local b=self.bounds
        if b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then self.scroll=math.max(0,math.min(self.maximum or 0,self.scroll-delta/120*60));return true end
    end
    function self.draw(ui)
        ui.rect(ui.x+ui.w-150,ui.y-24,150,28,{35,62,90})
        ui.bounded(ui.x+ui.w-142,ui.y-16,'Stop Highlight',14,{225,230,235},134)
        ui.hit(ui.x+ui.w-150,ui.y-24,150,28,function()ui.activate('stop_identify')end)
        local portrait=package.loaded['epic.player_preview.v1']
        if portrait and portrait.toggle then
            ui.rect(ui.x+ui.w-308,ui.y-24,150,28,{35,62,90})
            ui.bounded(ui.x+ui.w-300,ui.y-16,'Player Preview',14,{225,230,235},134)
            ui.hit(ui.x+ui.w-308,ui.y-24,150,28,portrait.toggle)
        end
        local state=info();local top=ui.y+ui.h;local gap=18;local lw=math.floor(ui.w*.55);local rx=ui.x+lw+gap;local rw=ui.w-lw-gap
        local white,muted,blue={225,230,235},{155,166,175},{35,62,90}
        local function text(x,y,value)ui.text(x,y,value,14,white)end
        local guidance={browse='Import a DDS or select one variant from an archive. This does not apply colors to gear.',apply_matching='Match imported resource IDs to worn gear and apply only matching LUTs.',apply_file_armor='Apply the selected imported LUT to all worn Armor LUTs.',apply_file_helmet='Apply the selected imported LUT to all worn Helmet LUTs.',save_palette='Copy the selected imported LUT into the LUT Editor. Gear stays unchanged.',restore='Restore Arrowhead original gear LUTs and refresh the palettes.',restore_imported='Reset editor values to the imported file.',global_undo='Undo the last action, including imports and gear applications.',global_redo='Redo the last undone action.',save_setup='Choose Armor, Helmet, or Both and save a named Armory preset.',preserve_emissives='Keep original game emissive values and shader modes when applying imported colors.'}
        local function button(x,y,w,label,id,enabled)
            w=math.max(0,math.min(w,ui.x+ui.w-x-6));if w<20 then return end
            ui.rect(x,y,w,28,enabled==false and {35,39,43}or blue);ui.bounded(x+9,y+8,label,15,enabled==false and muted or white,w-18);ui.hit(x,y,w,28,function()if enabled~=false then ui.activate(id)end end,nil,nil,guidance[id])
        end
        ui.rect(ui.x,ui.y,lw,ui.h,{20,24,28});ui.rect(rx,ui.y,rw,ui.h,{20,24,28})
        local divider={65,76,85}
        ui.rect(ui.x+lw/2,ui.y+14,1,math.max(0,ui.h-130),divider)
        ui.rect(rx-9,ui.y,1,ui.h,divider)
        for _,offset in ipairs({184})do
            ui.rect(rx+12,top-offset,rw-24,1,divider)
        end
        ui.rect(ui.x,top-30,lw,30,blue);ui.rect(rx,top-30,rw,30,blue)
        text(ui.x+12,top-20,'LUTs and colors');text(rx+12,top-20,'Import and apply')
        button(ui.x+12,top-77,lw-24,'Load Current Armor & Helmet','populate_worn')
        local offset=75
        if (state.palette_count or 0)>1 then
            text(ui.x+12,top-101,'Imported LUT')
            local selector_width=math.min(280,lw*.4)
            ui.choice('palette',ui.x+12,top-139,selector_width);offset=155
            if state.loaded then
                local document=state.loaded;local sx=ui.x+selector_width+24
                local size=math.min(34,(lw-selector_width-40)/document.height)
                for row=1,document.height do
                    local at=(row-1)*document.width*4;local rgb={}
                    for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,document.data[at+ch]))*255+.5)end
                    ui.rect(sx+(row-1)*size,top-139,size-2,26,rgb)
                end
            end
        end
        local cliptop,clipbottom=top-offset-20,ui.y+14;local cursor=cliptop+self.scroll
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
        local function colors(title,entries,offset)
            local ui=setmetatable({x=ui.x+(offset or 0)},{__index=ui})
            cursor=cursor-27
            if visible(cursor,23)then ui.rect(ui.x+10,cursor,338,23,blue);text(ui.x+17,cursor+6,title)end
            if title~='Imported tables'and state.loaded and visible(cursor,23)then
                ui.rect(ui.x+155,cursor,193,23,{24,39,52})
                ui.bounded(ui.x+163,cursor+5,'Apply to '..title..' '..(entries[1]and entries[1].name:match('LUT %d+')or 'LUT'),14,white,177)
                ui.hit(ui.x+155,cursor,193,23,function()ui.activate('apply_import_'..title:lower())end)
            end
            if #entries==0 then cursor=cursor-21;if visible(cursor,18)then ui.text(ui.x+17,cursor+4,'Current colors unavailable or still loading.',13,muted)end end
            for number,entry in ipairs(entries)do
                local selection_key=title..'/'..tostring(entry.index or entry.ids and entry.ids[1]or entry.source or entry.name)
                cursor=cursor-22;if visible(cursor,18)then
                    text(ui.x+17,cursor+4,entry.name)
                    ui.hit(ui.x+12,cursor,190,18,function()
                        local row=math.min(entry.height,self.selected and self.selected.row or 1)
                        local column=self.selected and self.selected.column or 1
                        if select_color then select_color(entry,row,column)end
                        self.selected={key=selection_key,data=entry.data,row=row,column=column,label=title..' / '..entry.name}
                    end)
                end
                cursor=cursor-30
                if visible(cursor,26)then
                    if entry.resource then ui.bounded(ui.x+17,cursor+6,entry.resource,12,{244,202,53},196)end
                    if number==1 and title~='Imported tables'then ui.choice('basic_'..title:lower()..'_lut',ui.x+220,cursor,128)end
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
                                if select_color then select_color(selected_entry,selected_row,selected_col,false,title:lower())end
                            end
                            ui.hit(sx,cursor,22,16,select,function()select();paint()end,function()
                                self.scratch={rgb[1],rgb[2],rgb[3]}
                                if core then self.hue=core.rgb_hsv(self.scratch)end
                                if ui.set then ui.set('scratch_color',string.format('#%02X%02X%02X',rgb[1],rgb[2],rgb[3]))end
                            end,'Left-click selects. Double-click edits color. Right-click paints Scratch. Middle-click copies.',function()select();ui.activate('quick_color')end)
                        end
                    end
                end
            end
        end
        local start=cursor;colors('Armor',state.armor,0);local armor_end=cursor
        cursor=start;colors('Helmet',state.helmet,lw/2);cursor=math.min(cursor,armor_end)
        local content=cliptop+self.scroll-cursor;local viewport=cliptop-clipbottom;self.maximum=math.max(0,content-viewport);self.scroll=math.min(self.scroll,self.maximum)
        if self.maximum>0 then local thumb=math.max(18,viewport*viewport/content);ui.rect(ui.x+lw-6,clipbottom,4,viewport,{50,60,70});ui.rect(ui.x+lw-7,cliptop-thumb-(viewport-thumb)*self.scroll/self.maximum,6,thumb,{120,135,150})end
        button(rx+12,top-77,rw-24,'Choose file - DDS / ZIP / RAR...','browse')
        if state.loaded then
            local path=(state.loaded.source or 'Imported LUT'):gsub('\\','/')
            local relative=path:match('/Epic LUT/(.*)')or path:match('[^/]+$')or path
            ui.bounded(rx+12,top-98,'Imported: '..(state.import_description or relative),12,muted,rw-24)
        end
        local y=top-117
        if state.busy then
            local spin=math.floor(state.time*8)%8
            for i=0,7 do local angle=i*math.pi/4;ui.rect(rx+29+math.cos(angle)*11,y+8+math.sin(angle)*11,4,4,i==spin and {244,202,53}or {75,88,100})end
            ui.text(rx+55,y+5,(state.import_detail and state.import_detail~=''and state.import_detail or state.phase)..(state.waiting and ''or '  '..(state.progress or 0)..'% completed'),14,white)
        else ui.bounded(rx+12,y+5,state.status,14,muted,rw-24)end
        if state.busy then button(rx+12,top-161,(rw-29)/2,'Cancel import','cancel_import');button(rx+17+(rw-29)/2,top-161,(rw-29)/2,'Retry file picker','retry_import')end
        button(rx+12,top-203,rw-24,'Send to LUT Editor','save_palette')
        ui.bounded(rx+12,top-224,'Overwrites the editor table; does not apply to gear.',13,muted,rw-24)
        local preview_height=math.max(44,math.min(200,ui.h-((state.palette_count or 0)>1 and 670 or 570)))
        local preview_top=top-246;local preview_bottom=preview_top-preview_height
        self.import_bounds={x=rx+12,y=preview_bottom,w=rw-24,h=preview_height}
        local imported=state.raw and state.raw.tables or state.tables or {}
        if #imported==0 and state.loaded then imported={{index=1,width=state.loaded.width,height=state.loaded.height,data=state.loaded.data}}end
        text(rx+12,top-238,'Imported file: '..#imported..' LUT'..(#imported==1 and ''or 's')..' / Column 1')
        self.import_max=math.max(0,#imported*22-preview_height);self.import_scroll=math.min(self.import_scroll or 0,self.import_max)
        for i,entry in ipairs(imported)do
            local y=preview_top-i*22+self.import_scroll
            if y>=preview_bottom and y+20<=preview_top then
                ui.bounded(rx+16,y+5,'LUT '..(entry.index or i),12,white,58)
                local size=math.min(24,(rw-94)/entry.height)
                for row=1,entry.height do local at=(row-1)*entry.width*4;local rgb={}
                    for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,entry.data[at+ch]))*255+.5)end
                    ui.rect(rx+82+(row-1)*size,y,size-2,18,rgb)
                end
                local index=entry.index or i
                ui.hit(rx+12,y,rw-24,20,function()if ui.set then ui.set('palette',index)end end)
            end
        end
        if self.import_max>0 then ui.bounded(rx+12,preview_bottom-12,'Scroll for more imported LUTs',10,muted,rw-24)end
        ui.rect(rx+12,preview_bottom-18,rw-24,1,divider)
        local actions=preview_bottom-30
        text(rx+12,actions,'Apply Imported LUT '..(state.palette_index or 1))
        local apply_width=(rw-30)/2
        local matching=state.raw and state.raw.matching
        if (state.palette_count or 0)>1 then
            button(rx+12,actions-36,rw-24,'Apply Matching LUTs','apply_matching',matching and matching.matched>0 and not state.busy)
            local summary=matching and (matching.total..' imported / '..matching.matched..' matched / '..(matching.unmatched+matching.unidentified+matching.ambiguous)..' unmatched or ambiguous')or 'Resource IDs unavailable - target individual LUTs manually.'
            if matching and matching.matched==0 then summary='No matches to worn gear. Select an imported LUT below.'end
            ui.bounded(rx+12,actions-55,summary,13,muted,rw-24)
            ui.choice('palette',rx+12,actions-91,rw-24)
            button(rx+12,actions-125,apply_width,'Apply LUT '..(state.palette_index or 1)..' to All Armor LUTs','apply_file_armor',state.loaded~=nil and not state.busy)
            button(rx+18+apply_width,actions-125,apply_width,'Apply LUT '..(state.palette_index or 1)..' to All Helmet LUTs','apply_file_helmet',state.loaded~=nil and not state.busy)
            actions=actions-70

        else
            button(rx+12,actions-36,apply_width,'Apply to All Armor LUTs','apply_file_armor')
            button(rx+18+apply_width,actions-36,apply_width,'Apply to All Helmet LUTs','apply_file_helmet')
            ui.bounded(rx+12,actions-55,'Applies to every LUT on that gear.',13,muted,rw-24)
        end
        button(rx+12,actions-95,rw-24,'[ '..(state.preserve_emissives and 'x'or ' ')..' ] Preserve Original Emissives','preserve_emissives')
        ui.rect(rx+12,actions-109,rw-24,1,divider)
        button(rx+12,actions-145,(rw-30)/2,'Restore Arrowhead LUT (Original)','restore')
        button(rx+18+(rw-30)/2,actions-145,(rw-30)/2,'Restore Imported LUT (editor)','restore_imported')
        button(rx+12,actions-183,(rw-29)/2,'Undo Last Action','global_undo');button(rx+17+(rw-29)/2,actions-183,(rw-29)/2,'Redo Last Action','global_redo')
        button(rx+12,actions-221,rw-24,'Save applied setup','save_setup')
        ui.text(rx+12,ui.y+14,'RAR requires installed 7-Zip. Match Your Colors should be Off.',13,muted)
    end
    return self
end
return V
