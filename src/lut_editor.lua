-- Imported palette editing. Source pixels are distinct from retained GPU buffers.
local E={}
function E.new(m,document,note,save,presets)
    local ffi=require('ffi');local self={undo={},redo={},busy=false,value_scroll=0}
    local color_columns={1,3,6,7,13,15,17,18,19,20}
    local color_labels={};for _,column in ipairs(color_columns)do color_labels[#color_labels+1]=m.semantics.columns[column]end
    function self.refresh_presets()
        if not self.handle then return end
        self.preset_names=m.windows and m.windows.row_presets(presets)or {}
        local choices={'New preset...'};for _,name in ipairs(self.preset_names)do choices[#choices+1]=name end
        self.api.mods[self.handle.id].controls.row_preset_select.choices=choices
        local current=self.handle.get('row_preset');local selected=1
        for i,name in ipairs(self.preset_names)do if name==current then selected=i+1 end end
        self.busy=true;assert(self.handle.set('row_preset_select',selected));self.busy=false
    end
    local function snapshot(d)return ffi.string(d.data,d.width*d.height*16)end
    local function remember()
        local d=assert(document(),'Import a palette first')
        d.revision=(d.revision or 0)+1
        self.undo[#self.undo+1]=snapshot(d);if #self.undo>64 then table.remove(self.undo,1)end;self.redo={}
        return d
    end
    local function rgb(data,i)
        local values={};for ch=0,2 do values[#values+1]=math.floor(math.max(0,math.min(1,data[i+ch]))*255+.5)end
        return values
    end
    local function change(column,channel,value)
        if self.busy then return end
        local d=remember();local i=m.semantics.index(self.handle.get('edit_row'),column,channel,d.width,d.height)
        d.data[i]=value;self.sync();note('Palette edited. Apply to update the selected live LUT.')
    end
    function self.sync()
        if not self.handle or self.busy then return end
        local d=document();local mod=self.api.mods[self.handle.id]
        for _,id in ipairs({'edit_row','advanced_row','color_field','cell_color','edit_column','cell_r','cell_g','cell_b','cell_a','unlock','shader_mode','detail_texture','camo_pattern','grid_tool','grid_channel'})do mod.controls[id].disabled=not d end
        if not d then return end
        if self.document~=d then
            self.document=d;self.undo={};self.redo={}
            self.open_row=nil;self.value_scroll=0;self.selection=nil
            if not d.original then d.original=ffi.new('float[?]',d.width*d.height*4);ffi.copy(d.original,d.data,d.width*d.height*16)end
        end
        local h=self.handle;local row=math.min(h.get('edit_row'),d.height);local column=h.get('edit_column')
        local rows={};for i=1,d.height do rows[i]='Row '..i end;mod.controls.edit_row.choices=rows;mod.controls.advanced_row.choices=rows
        local color_column=color_columns[h.get('color_field')]
        local i=m.semantics.index(row,color_column,1,d.width,d.height);local values={edit_row=row,advanced_row=row}
        local r=rgb(d.data,i);values.cell_color=string.format('#%02X%02X%02X',r[1],r[2],r[3])
        for ch,name in ipairs({'r','g','b','a'})do
            local index=m.semantics.index(row,column,ch,d.width,d.height);local value=tonumber(d.data[index]);local control=mod.controls['cell_'..name]
            control.min,control.max,control.step=m.semantics.range(column,ch,value)
            control.description=(m.semantics.hints[column]or 'Unconfirmed shader meaning.')..' Imported value: '..string.format('%.8g',d.original[index])
            values['cell_'..name]=value
        end
        for _,spec in ipairs({{'shader_mode',1,4,0,3},{'detail_texture',2,1,0,25},{'camo_pattern',22,4,-1,5}})do
            local id,col,ch,lo,hi=unpack(spec);local value=tonumber(d.data[m.semantics.index(row,col,ch,d.width,d.height)])
            local choices={};for v=lo,hi do
                local label=id=='shader_mode'and (v==0 and 'Off / default'or 'Shader mode '..v)or id=='detail_texture'and 'Bump map '..v or (v==-1 and 'Off'or 'Pattern '..v)
                choices[#choices+1]=label
            end
            local selected=value%1==0 and value>=lo and value<=hi and value-lo+1
            if not selected then choices[#choices+1]='Custom: '..string.format('%.7g',value);selected=#choices end
            mod.controls[id].choices=choices;values[id]=selected
        end
        self.busy=true;local ok,why=h.set_many(values);self.busy=false;assert(ok,why)
        for ch,name in ipairs({'r','g','b','a'})do mod.controls['cell_'..name].disabled=not(h.get('unlock')or(m.semantics.is_color(d.width,column)and ch<=3))end
        for _,id in ipairs({'shader_mode','detail_texture','camo_pattern'})do mod.controls[id].disabled=not h.get('unlock')end
        for _,page in ipairs(mod.pages)do if page.id=='colors'then
            page.controls={mod.controls.edit_row,mod.controls.color_field,mod.controls.cell_color}
            for region=1,d.height do
                local selected=region;local index=m.semantics.index(region,color_column,1,d.width,d.height)
                page.controls[#page.controls+1]={type='text',label='Row '..region,swatch_label=true,page=page,groups={},depth=0,swatches={
                    {rgb=rgb(d.data,index),row='Now',owner=mod,control=mod.controls.cell_color,prepare=function()assert(h.set('edit_row',selected));self.sync()end},
                    {rgb=rgb(d.original,index),row='Imported'}}}
            end
            page.controls[#page.controls+1]=mod.controls.reset_color
        end end
    end
    local function history(from,to)
        local d=assert(document(),'Import first');local value=table.remove(from);if not value then return note('No more history')end
        to[#to+1]=snapshot(d);ffi.copy(d.data,value,#value);d.revision=(d.revision or 0)+1;self.sync();return note('Palette history updated. Apply to update the live LUT.')
    end
    function self.attach(api,handle)
        self.api=api;self.handle=handle;self.sync()
        self.refresh_presets()
        for _,page in ipairs(api.mods[handle.id].pages)do if page.id=='colors'then page.render_layout=self.layout;page.on_wheel=self.wheel end end
    end
    function self.reset()
        local d=remember();ffi.copy(d.data,d.original,d.width*d.height*16);self.sync()
        return note('Custom edits reset to the imported palette. Apply to update the live LUTs.')
    end
    function self.wheel(x,y,delta)
        local b=self.value_bounds
        if b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
            self.value_scroll=math.max(0,math.min(self.value_max or 0,self.value_scroll-delta/120*90));return true
        end
    end
    local channels={{1,2,3},{1,2,3,4},{1},{2},{3},{4}}
    local function editable(d,column,channel)return self.handle.get('unlock')or(m.semantics.is_color(d.width,column)and channel<=3)end
    local function paint(row,column)
        local d=assert(document(),'Import first');local selected=channels[self.handle.get('grid_channel')]
        for _,ch in ipairs(selected)do assert(editable(d,column,ch),'Unlock advanced edits to paint non-color channels')end
        d=remember();local r,g,b=m.palette.rgb(self.handle.get('scratch_color'));local values={r,g,b,self.handle.get('scratch_alpha')}
        for _,ch in ipairs(selected)do d.data[m.semantics.index(row,column,ch,d.width,d.height)]=values[ch]end
        self.sync();return note('Pixel painted. Apply to update live LUTs.')
    end
    function self.copy_selection()
        local d=assert(document(),'Import first');local s=self.selection or {r1=self.handle.get('edit_row'),r2=self.handle.get('edit_row'),c1=self.handle.get('edit_column'),c2=self.handle.get('edit_column')}
        local w,h=s.c2-s.c1+1,s.r2-s.r1+1;local data=ffi.new('float[?]',w*h*4)
        for r=0,h-1 do ffi.copy(data+r*w*4,d.data+m.semantics.index(s.r1+r,s.c1,1,d.width,d.height),w*16)end
        self.clip={width=w,height=h,data=data};return note('Copied '..w..' x '..h..' pixels')
    end
    function self.paste_selection()
        local d=assert(document(),'Import first');local clip=assert(self.clip,'Copy a selection first')
        local row,column=self.handle.get('edit_row'),self.handle.get('edit_column');assert(row+clip.height-1<=d.height and column+clip.width-1<=d.width,'Clipboard does not fit here')
        local selected=channels[self.handle.get('grid_channel')]
        for c=column,column+clip.width-1 do for _,ch in ipairs(selected)do assert(editable(d,c,ch),'Unlock advanced edits to paste non-color channels')end end
        d=remember()
        for r=0,clip.height-1 do for c=0,clip.width-1 do for _,ch in ipairs(selected)do
            d.data[m.semantics.index(row+r,column+c,ch,d.width,d.height)]=clip.data[(r*clip.width+c)*4+ch-1]
        end end end
        self.sync();return note('Selection pasted. Apply to update live LUTs.')
    end
    function self.move_selection(row,column)
        local d=assert(document(),'Import first');local s=assert(self.selection,'Select pixels first')
        local w,h=s.c2-s.c1+1,s.r2-s.r1+1;assert(row+h-1<=d.height and column+w-1<=d.width,'Selection does not fit here')
        local selected=channels[self.handle.get('grid_channel')]
        for c=0,w-1 do for _,ch in ipairs(selected)do
            assert(editable(d,s.c1+c,ch)and editable(d,column+c,ch),'Unlock advanced edits to move non-color channels')
        end end
        self.copy_selection();local clip=self.clip;d=remember()
        for r=s.r1,s.r2 do for c=s.c1,s.c2 do for _,ch in ipairs(selected)do d.data[m.semantics.index(r,c,ch,d.width,d.height)]=0 end end end
        for r=0,h-1 do for c=0,w-1 do for _,ch in ipairs(selected)do d.data[m.semantics.index(row+r,column+c,ch,d.width,d.height)]=clip.data[(r*w+c)*4+ch-1]end end end
        self.selection={r1=row,r2=row+h-1,c1=column,c2=column+w-1};self.sync();return note('Selection moved. Apply to update live LUTs.')
    end
    function self.layout(ui)
        local d=document();local h=self.handle;local mod=self.api.mods[h.id]
        local dark={17,18,20};local blue={35,62,90};local white={224,230,234};local muted={145,156,165}
        local left=math.floor(ui.w*.66);local right=ui.x+left+12;local rightw=ui.w-left-12
        local top=ui.y+ui.h;local bottomh=math.floor(ui.h*.43);local gridbottom=ui.y+bottomh+12
        local function panel(x,y,w,height,title)
            ui.rect(x,y,w,height,dark);ui.rect(x,y+height-27,w,27,blue);ui.text(x+8,y+height-21,title,17,white)
        end
        local function button(x,y,w,label,id)
            ui.rect(x,y,w,26,blue);ui.bounded(x+6,y+5,label,15,white,w-12);ui.hit(x,y,w,26,function()ui.activate(id)end)
        end
        panel(ui.x,gridbottom,left,ui.h-bottomh-12,'Pixel Grid')
        panel(right,ui.y,rightw,ui.h,'Value Editor - grouped by rows')
        panel(ui.x,ui.y,left*.40-6,bottomh,'Options')
        panel(ui.x+left*.40,ui.y,left*.30-6,bottomh,'Row Presets')
        panel(ui.x+left*.70,ui.y,left*.30,bottomh,'Scratch Pixel')
        if not d then
            ui.text(ui.x+12,top-58,'Choose a DDS or ZIP to begin.',18,white)
            button(ui.x+12,top-102,180,'Choose file...', 'browse');return
        end
        ui.text(ui.x+10,top-49,d.height..' rows x '..d.width..' columns. Display clamps RGB; file values stay intact.',14,muted)
        if ui.choice then ui.choice('grid_tool',ui.x+10,top-82,170);ui.choice('grid_channel',ui.x+190,top-82,150)end
        button(ui.x+350,top-82,70,'Copy','copy_selection');button(ui.x+425,top-82,70,'Paste','paste_selection');button(ui.x+500,top-82,115,'Clear selection','clear_selection')
        local cell=math.min((left-22)/d.width,(ui.h-bottomh-116)/d.height)
        local row=h.get('edit_row');local column=h.get('edit_column')
        for r=1,d.height do for c=1,d.width do
            local selected_row,selected_col=r,c
            local index=m.semantics.index(r,c,1,d.width,d.height)
            local x=ui.x+10+(c-1)*cell;local y=top-96-r*cell
            local s=self.selection;local selected=s and r>=s.r1 and r<=s.r2 and c>=s.c1 and c<=s.c2
            local color=rgb(d.data,index);local channel=h.get('grid_channel')
            if channel==2 then local alpha=math.max(0,math.min(1,d.data[index+3]));local background=(r+c)%2==0 and 80 or 130;for ch=1,3 do color[ch]=math.floor(color[ch]*alpha+background*(1-alpha)+.5)end end
            if channel>=3 then local value=math.floor(math.max(0,math.min(1,d.data[index+channel-3]))*255+.5);color={value,value,value}end
            ui.rect(x,y,cell,cell,(selected or(r==row and c==column))and {244,202,53}or {75,78,82})
            ui.rect(x+1,y+1,cell-2,cell-2,color)
            ui.hit(x,y,cell,cell,function()
                local ok,why=pcall(function()
                    local tool=h.get('grid_tool')
                    if tool==3 then self.move_selection(selected_row,selected_col)
                    elseif tool==2 then paint(selected_row,selected_col)
                    elseif self.selection and ui.shift and ui.shift()then
                        local anchor_row,anchor_col=self.selection.anchor_row or self.selection.r1,self.selection.anchor_col or self.selection.c1
                        self.selection={anchor_row=anchor_row,anchor_col=anchor_col,r1=math.min(anchor_row,selected_row),r2=math.max(anchor_row,selected_row),c1=math.min(anchor_col,selected_col),c2=math.max(anchor_col,selected_col)}
                    else self.selection={r1=selected_row,r2=selected_row,c1=selected_col,c2=selected_col}end
                    self.open_row=selected_row;assert(h.set('edit_row',selected_row));assert(h.set('edit_column',selected_col));self.focus_column=selected_col
                    for i,col in ipairs(color_columns)do if col==selected_col then assert(h.set('color_field',i));break end end
                    self.sync()
                end)
                if not ok then note(tostring(why))end
            end)
        end end
        if ui.choice then ui.choice('edit_row',right+8,top-57,rightw-16)end
        button(right+8,top-86,(rightw-21)/2,h.get('group_rows')and 'Group by rows: ON'or 'Selected row only','group_rows')
        button(right+13+(rightw-21)/2,top-86,(rightw-21)/2,h.get('unlock')and 'Advanced: ON'or 'Unlock advanced edits','unlock')
        local clip_top,clip_bottom=top-96,ui.y+12
        self.value_bounds={x=right,y=ui.y,w=rightw,h=ui.h}
        local scroll=self.value_scroll;local cursor=clip_top+scroll
        local function visible(y,height)return y>=clip_bottom and y+height<=clip_top end
        local function words(value)
            local lines,line={},'';local limit=math.max(24,math.floor((rightw-36)/6))
            for word in tostring(value):gmatch('%S+')do
                if #line>0 and #line+#word+1>limit then lines[#lines+1]=line;line=word
                else line=line==''and word or line..' '..word end
            end
            if #line>0 then lines[#lines+1]=line end;return lines
        end
        for r=1,d.height do if h.get('group_rows')or r==row then
            local selected_row=r;cursor=cursor-25
            if visible(cursor,23)then
                ui.rect(right+8,cursor,rightw-20,23,r==row and {49,82,115}or blue)
                ui.text(right+13,cursor+6,(self.open_row==r and 'v 'or '> ')..'Row '..r,14,white)
                ui.hit(right+8,cursor,rightw-20,23,function()
                    self.open_row=self.open_row==selected_row and nil or selected_row
                    assert(h.set('edit_row',selected_row));self.value_scroll=0;self.sync()
                end)
            end
            if self.open_row==r then
                for c=1,d.width do
                    local selected_col=c
                    if self.focus_column==c then self.value_scroll=math.max(0,clip_top+scroll-cursor);self.focus_column=nil end
                    local function prepare()
                        assert(h.set('edit_row',selected_row));assert(h.set('edit_column',selected_col))
                        for i,col in ipairs(color_columns)do if col==selected_col then assert(h.set('color_field',i));break end end
                        self.sync()
                    end
                    cursor=cursor-21
                    if visible(cursor,17)then
                        ui.bounded(right+12,cursor+3,'Column '..c..': '..m.semantics.columns[c],14,white,rightw-58)
                        if m.semantics.is_color(d.width,c)then
                            local index=m.semantics.index(r,c,1,d.width,d.height)
                            ui.rect(right+rightw-40,cursor-1,24,18,rgb(d.data,index))
                            ui.hit(right+rightw-40,cursor-1,24,18,function()prepare();ui.activate('cell_color')end)
                        end
                    end
                    for _,line in ipairs(words(m.semantics.hints[c]or 'Unconfirmed shader meaning. Raw values are retained.'))do
                        cursor=cursor-14;if visible(cursor,12)then ui.text(right+12,cursor+2,line,13,muted)end
                    end
                    for ch,name in ipairs({'r','g','b','a'})do
                        local enum=(c==1 and ch==4 and 'shader_mode')or(c==2 and ch==1 and 'detail_texture')or(c==22 and ch==4 and 'camo_pattern')
                        cursor=cursor-(enum and 30 or 24)
                        if visible(cursor,enum and 26 or 21)then
                            local value=tonumber(d.data[m.semantics.index(r,c,ch,d.width,d.height)])
                            ui.text(right+12,cursor+6,name:upper(),13,muted)
                            if enum and ui.choice then
                                ui.choice(enum,right+29,cursor,rightw-46,prepare)
                            elseif ui.number then
                                local lo,hi=m.semantics.range(c,ch,value)
                                ui.number('cell_'..name,right+29,cursor,rightw-46,value,prepare,editable(d,c,ch),lo,hi,r==h.get('edit_row')and c==h.get('edit_column'))
                            else ui.text(right+29,cursor+5,string.format('%.7g',value),13,white)end
                        end
                    end
                    cursor=cursor-10
                    if visible(cursor,1)then ui.rect(right+10,cursor,rightw-22,1,{65,70,75})end
                end
            end
        end end
        local content=clip_top+scroll-cursor;local viewport=clip_top-clip_bottom
        self.value_max=math.max(0,content-viewport);self.value_scroll=math.min(self.value_scroll,self.value_max)
        if self.value_max>0 then
            local thumb=math.max(18,viewport*viewport/content)
            ui.rect(right+rightw-6,clip_bottom,4,viewport,{50,55,60})
            ui.rect(right+rightw-7,clip_top-thumb-(viewport-thumb)*self.value_scroll/self.value_max,6,thumb,{120,135,150})
        end
        local optionsy=ui.y+bottomh-55
        local step=math.min(32,(bottomh-65)/7);local optionw=left*.4-20
        button(ui.x+10,optionsy,(optionw-5)/2,'Import file','browse');button(ui.x+15+(optionw-5)/2,optionsy,(optionw-5)/2,'Save LUT to Palette','save_palette')
        if ui.choice then
            ui.choice('palette',ui.x+10,optionsy-step,optionw)
            ui.choice('lut',ui.x+10,optionsy-step*2,optionw)
        end
        button(ui.x+10,optionsy-step*3,(optionw-5)/2,'Restore Original','restore')
        button(ui.x+15+(optionw-5)/2,optionsy-step*3,(optionw-5)/2,'Reset Custom LUT','reset_custom')
        button(ui.x+10,optionsy-step*4,(optionw-5)/2,'Undo','undo');button(ui.x+15+(optionw-5)/2,optionsy-step*4,(optionw-5)/2,'Redo','redo')
        button(ui.x+10,optionsy-step*5,optionw,'Save applied setup','save_setup')
        button(ui.x+10,optionsy-step*6,optionw,'Apply LUT to checked targets','apply_checked')
        button(ui.x+10,optionsy-step*7,(optionw-5)/2,'[ '..(h.get('target_helmet')and 'x'or ' ')..' ] Helmet','target_helmet')
        button(ui.x+15+(optionw-5)/2,optionsy-step*7,(optionw-5)/2,'[ '..(h.get('target_armor')and 'x'or ' ')..' ] Armor','target_armor')
        local presetx=ui.x+left*.40+10;local panelw=left*.30-20
        ui.text(presetx,optionsy,'Selected row: '..row,15,white)
        if ui.preset then ui.preset('row_preset','row_preset_select',presetx,optionsy-38,panelw)
        else button(presetx,optionsy-38,panelw,'Preset: '..h.get('row_preset'),'row_preset')end
        button(presetx,optionsy-72,panelw,'Save selected row','save_row')
        button(presetx,optionsy-106,panelw,'Apply preset to row','load_row')
        button(presetx,optionsy-146,(panelw-5)/2,'Copy row','copy_row')
        button(presetx+(panelw+5)/2,optionsy-146,(panelw-5)/2,'Paste row','paste_row')
        local scratchx=ui.x+left*.70+10
        local hue=m.ui_core.rgb_hsv(self.scratch or {255,255,255})
        local gh=math.min(180,bottomh-140);local gw=panelw-18
        for vy=0,19 do for sx=0,19 do
            local saturation,value=sx/19,vy/19
            local x,y=scratchx+sx*gw/20,optionsy-35-gh+vy*gh/20
            ui.rect(x,y,gw/20+1,gh/20+1,m.ui_core.hsv_rgb(hue,saturation,value))
            ui.hit(x,y,gw/20,gh/20,function()
                local color=m.ui_core.hsv_rgb(hue,saturation,value)
                assert(h.set('scratch_color',string.format('#%02X%02X%02X',color[1],color[2],color[3])))
            end)
        end end
        for i=0,19 do
            local chosen=i/20;local y=optionsy-35-gh+i*gh/20
            ui.rect(scratchx+gw+5,y,12,gh/20+1,m.ui_core.hsv_rgb(chosen,1,1))
            ui.hit(scratchx+gw+5,y,12,gh/20,function()
                local color=m.ui_core.hsv_rgb(chosen,1,1);assert(h.set('scratch_color',string.format('#%02X%02X%02X',color[1],color[2],color[3])))
            end)
        end
        ui.rect(scratchx,optionsy-24,panelw,24,self.scratch or {255,255,255})
        ui.hit(scratchx,optionsy-24,panelw,24,function()ui.activate('scratch_color')end)
        button(scratchx,ui.y+15,panelw,'Paint selected RGB','paint_scratch')
    end
    function self.pages()
        local advanced={
            {type='text',label='Material, camo and raw RGBA values. Unknown meanings stay marked unknown.'},
            {id='advanced_row',type='choice',label='Palette row',choices={'Import first'},default=1,on_change=function(value)if not self.busy then assert(self.handle.set('edit_row',value));self.sync()end end},
            {id='edit_column',type='choice',label='Material / camo field',choices=m.semantics.columns,default=1,on_change=function()self.sync()end},
            {id='unlock',type='toggle',label='Enable advanced float editing',default=false,on_change=function()self.sync()end}}
        for _,spec in ipairs({{'shader_mode','Shader mode',1,4,0,3},{'detail_texture','Bump map',2,1,0,25},{'camo_pattern','Camo pattern',22,4,-1,5}})do
            local id,label,col,ch,lo,hi=unpack(spec)
            local choices={};for v=lo,hi do choices[#choices+1]=tostring(v)end
            advanced[#advanced+1]={id=id,type='choice',presentation='combined',label=label,choices=choices,default=1,on_change=function(value)
                if self.busy or value>hi-lo+1 then return end;change(col,ch,value+lo-1)
            end}
        end
        for ch,name in ipairs({'r','g','b','a'})do
            local channel=ch
            advanced[#advanced+1]={id='cell_'..name,type='slider',label=name:upper(),min=-1e10,max=1e10,step=.001,default=0,on_change=function(value)change(self.handle.get('edit_column'),channel,value)end}
        end
        return {
            {id='colors',name='2. LUT Editor',require_confirmation=false,controls={
                {id='grid_tool',type='choice',presentation='combined',label='Grid tool',choices={'Select','Draw','Move selection'},default=1},
                {id='grid_channel',type='choice',presentation='combined',label='Channels',choices={'RGB','RGBA','Red','Green','Blue','Alpha'},default=1},
                {id='group_rows',type='toggle',label='Group by rows',default=true},
                {id='copy_selection',type='button',label='Copy pixels',on_activate=self.copy_selection},
                {id='paste_selection',type='button',label='Paste pixels',on_activate=self.paste_selection},
                {id='clear_selection',type='button',label='Clear selection',on_activate=function()self.selection=nil;return note('Selection cleared')end},
                {id='edit_row',type='choice',presentation='combined',label='Palette row',choices={'Import first'},default=1,on_change=function(value)if not self.busy then self.open_row=value;self.value_scroll=0;self.sync()end end},
                {id='color_field',type='choice',label='Color field',choices=color_labels,default=1,on_change=function()self.sync()end},
                {id='cell_color',type='color',label='Selected color',default='#FFFFFF',on_change=function(hex)
                    if self.busy then return end
                    local d=remember();local column=color_columns[self.handle.get('color_field')]
                    local i=m.semantics.index(self.handle.get('edit_row'),column,1,d.width,d.height)
                    local r,g,b=m.palette.rgb(hex);d.data[i],d.data[i+1],d.data[i+2]=r,g,b;self.sync();note('Color edited. Apply to update the live LUT.')
                end},
                {id='reset_color',type='button',label='Reset selected color to imported',on_activate=function()
                    local d=remember();local i=m.semantics.index(self.handle.get('edit_row'),color_columns[self.handle.get('color_field')],1,d.width,d.height)
                    for ch=0,2 do d.data[i+ch]=d.original[i+ch]end;self.sync();return note('Selected RGB restored; alpha unchanged.')
                end}}},
            {id='advanced',name='3. Material / camo',require_confirmation=false,controls=advanced},
            {id='save',name='4. Save / history',require_confirmation=false,controls={
                {id='scratch_color',type='color',label='Scratch color',default='#FFFFFF',on_change=function(hex)local r,g,b=m.palette.rgb(hex);self.scratch={r*255,g*255,b*255}end},
                {id='scratch_alpha',type='slider',label='Scratch alpha',min=0,max=1,step=.001,default=1},
                {id='paint_scratch',type='button',label='Paint selected RGB',on_activate=function()assert(m.semantics.is_color(23,self.handle.get('edit_column')),'Select a color column');return self.handle.set('cell_color',self.handle.get('scratch_color'))end},
                {id='copy_row',type='button',label='Copy selected row',on_activate=function()local d=assert(document(),'Import first');self.row_clip=ffi.string(d.data+(self.handle.get('edit_row')-1)*d.width*4,d.width*16);return note('Row copied')end},
                {id='paste_row',type='button',label='Paste row',on_activate=function()assert(self.row_clip,'Copy a row first');local d=remember();ffi.copy(d.data+(self.handle.get('edit_row')-1)*d.width*4,self.row_clip,#self.row_clip);self.sync();return note('Row pasted. Apply to update the live LUT.')end},
                {id='row_preset',type='input',label='Row preset name',default='my-row'},
                {id='row_preset_select',type='choice',presentation='combined',label='Saved row presets',choices={'New preset...'},default=1,on_change=function(index)
                    if not self.busy and index>1 then assert(self.handle.set('row_preset',self.preset_names[index-1]))end
                end},
                {id='save_row',type='button',label='Save row preset',on_activate=function()
                    local d=assert(document(),'Import first');local name=self.handle.get('row_preset');assert(presets and name:match('^[%w _-]+$')and #name>0,'Invalid preset name')
                    m.dds.write(presets..'/row-'..name..'.dds',d.data+(self.handle.get('edit_row')-1)*d.width*4,d.width,1);self.refresh_presets();return note('Row preset saved: '..name)
                end},
                {id='load_row',type='button',label='Apply row preset',on_activate=function()
                    local name=self.handle.get('row_preset');assert(presets and name:match('^[%w _-]+$')and #name>0,'Invalid preset name')
                    local f=assert(io.open(presets..'/row-'..name..'.dds','rb'),'Preset not found');local bytes=f:read(m.dds.MAX_BYTES+1);f:close()
                    local data=m.dds.decode(bytes,23,1);local d=remember();ffi.copy(d.data+(self.handle.get('edit_row')-1)*d.width*4,data,d.width*16);self.sync();return note('Row preset applied. Apply to update the live LUT.')
                end},
                {id='undo',type='button',label='Undo',on_activate=function()return history(self.undo,self.redo)end},
                {id='redo',type='button',label='Redo',on_activate=function()return history(self.redo,self.undo)end},
                {id='save_name',type='input',label='Save DDS as (without extension)',default='Epic-LUT-edited'},
                {id='save_dds',type='button',label='Export DDS preset to share',on_activate=function()return save(self.handle.get('save_name'))end}
            }}}
    end
    return self
end
return E
