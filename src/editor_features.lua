-- Advanced MCM controls and float-file hotloading; owns only Epic LUT documents/settings.
local ffi=require('ffi')
local X={}
function X.new(m,state,ctx,note)
    local folder=ctx.files_dir or ctx.dir..'/files'
    local self={catalog=nil,document=m.document.new(m.dds),last_poll=0,suppressed=false}
    local function selected()
        local h=state.handle;local lut=self.catalog.luts[h.get('edit_lut') or 1];local row=h.get('edit_row') or 1;local col=h.get('edit_column') or 1
        assert(row<=lut.height,'Selected row exceeds this LUT');return lut,row,col
    end
    local function batch(values)
        self.suppressed=true;state.importing=true
        local called,ok,err=pcall(state.handle.set_many,values)
        state.importing=false;self.suppressed=false;assert(called and ok,tostring(called and err or ok))
    end
    local function activate(lut,row)
        batch({[lut.name..'_r'..row..'_on']=true,enabled=true});state.dirty=true
    end
    function self.sync()
        if self.suppressed then return end
        local candidate=self.catalog.luts[state.handle.get('edit_lut')or 1]
        local corrected={}
        if state.handle.get('edit_row')>candidate.height then corrected.edit_row=1 end
        if state.handle.get('edit_column')>candidate.width then corrected.edit_column=1 end
        if next(corrected)then batch(corrected)end
        local lut,row,col=selected();local d=self.document.documents[lut.name];local base=m.semantics.index(row,col,1,lut.width,lut.height)
        local identity=self.catalog.identity
        local values={edit_row_active=state.handle.get(lut.name..'_r'..row..'_on')};local mod=state.api.mods['dbf_'..(identity.target_kind or 'armor')..'_lut_'..string.format('%08x',identity.target_id or identity.armor)..'_'..identity.body]
        mod.controls.cell_color.disabled=false
        for _,name in ipairs({'r','g','b','a'})do mod.controls['cell_'..name].disabled=false end
        local rows={};for r=1,lut.height do rows[r]='Row '..r end;mod.controls.edit_row.choices=rows
        mod.controls.edit_column.choices=m.semantics.columns_for(lut.width)
        mod.controls.camo_type.disabled=lut.width~=23;mod.controls.debug_rows.disabled=lut.width~=23
        for r=0,lut.height-1 do values[lut.name..'_r'..(r+1)..'_color']=m.palette.hex(d.data,r,lut.width)end
        for ch,name in ipairs({'r','g','b','a'})do
            local v=tonumber(d.data[base+ch-1]);local c=mod.controls['cell_'..name]
            c.min,c.max,c.step=m.semantics.range(col,ch,v);c.description=(m.semantics.hints[col]or 'Research mapping; raw channels are available.')..' Original: '..string.format('%.9g',lut.values[base+ch-1])..'; current: '..string.format('%.9g',v)
            values['cell_'..name]=math.max(c.min,math.min(c.max,v))
        end
        local function byte(v)return math.floor(math.max(0,math.min(1,v))*255+.5)end
        values.cell_color=string.format('#%02X%02X%02X',byte(d.data[base]),byte(d.data[base+1]),byte(d.data[base+2]))
        batch(values)
        local protected=state.handle.get('preserve_effects')
        mod.controls.cell_color.disabled=not m.semantics.is_color(lut.width,col)or(protected and not m.semantics.safe_lookup_cell(lut.width,col,1))
        mod.controls.cell_color.description=mod.controls.cell_color.disabled and 'This field is not an editable RGB color under the current protection policy. Emission R is experimental strength; glow tint can come from Base Color. Other emission channels remain uncertain.'or 'RGB edits preserve alpha. Base RGB can also tint glowing regions.'
        for _,page in ipairs(mod.pages)do if page.id=='colors'then
            page.controls={mod.controls.edit_lut,{type='text',label='Click a current color square to edit. Original colors remain beside it. Rows have no confirmed surface names.',groups={},depth=0}}
            local labels=m.semantics.columns_for(lut.width)
            local function rgb_at(data,index)return {byte(data[index]),byte(data[index+1]),byte(data[index+2])}end
            for column=1,lut.width do if m.semantics.is_color(lut.width,column)then
                local group='color_field_'..column
                page.controls[#page.controls+1]={id=group,type='section',label=labels[column],collapsible=true,collapsed=column~=1,page=page,groups={},depth=0}
                for region=1,lut.height do
                    local target_column,target_row=column,region;local index=m.semantics.index(region,column,1,lut.width,lut.height)
                    page.controls[#page.controls+1]={type='text',label='Row '..region,swatch_label=true,page=page,groups={group},depth=1,swatches={
                        {rgb=rgb_at(d.data,index),row='Now',owner=mod,control=mod.controls.cell_color,prepare=function()batch({edit_row=target_row,edit_column=target_column});self.sync()end},
                        {rgb=rgb_at(lut.values,index),row='Orig'}}}
                end
            end end
        end end
        for ch,name in ipairs({'r','g','b','a'})do
            local c=mod.controls['cell_'..name];c.disabled=protected and not m.semantics.safe_lookup_cell(lut.width,col,ch)
            if c.disabled then c.description=c.description..' Read-only while effect preservation is on.'end
        end
    end
    function self.save_all()
        for name in pairs(self.document.documents)do self.document.save(name)end
    end
    function self.export_originals()
        for _,d in pairs(self.document.documents)do m.dds.write(d.path:gsub('%.dds$','-original.dds'),d.lut.values,d.lut.width,d.lut.height)end
    end
    function self.reset()
        self.document.reset();self.quick_valid=false
        local flags=package.loaded['dbf.epic_lut.quick_valid.v1'];if flags and self.quick_key then flags[self.quick_cache_key]=false end
        self.save_all();self.sync()
    end
    function self.import_documents(documents,values)
        self.document.reset()
        for name,d in pairs(self.document.documents)do
            if documents and documents[name]then self.document.replace(name,documents[name])
            else
                local changes={}
                for row=1,d.lut.height do local id=name..'_r'..row;local hex=values[id..'_color'];local r,g,b=m.palette.rgb(hex);local i=(row-1)*d.lut.width*4
                    changes[i],changes[i+1],changes[i+2]=r,g,b
                end
                self.document.edit(name,changes)
            end
        end
        self.save_all();self.sync()
    end
    function self.primary(lut,row,hex)
        if self.suppressed or state.importing then return end
        local r,g,b=m.palette.rgb(hex);local i=(row-1)*lut.width*4
        self.document.edit(lut.name,{[i]=r,[i+1]=g,[i+2]=b});self.sync()
    end
    local function edits(changes)
        local lut,row=selected();self.document.edit(lut.name,changes);activate(lut,row);self.sync()
    end
    function self.pages(catalog,pages)
        self.catalog=catalog
        self.native=m.native_import and m.native_import.new(folder,catalog.identity.target_kind or 'armor')
        local choices={};for i,lut in ipairs(catalog.luts)do choices[i]='LUT '..i..' ('..(lut.lookup_type or 'material')..') - '..lut.name..' - '..lut.height..' rows' end
        local controls={
            {type='text',label='Semantic fields are research mappings; armor surface meanings remain numbered.'},
            {id='edit_lut',type='choice',label='LUT',choices=choices,default=1,on_change=function()if not self.suppressed then batch({edit_row=1,edit_column=1});self.sync()end end},
            {id='edit_row',type='choice',label='Row / region',choices=(function()local rows={};for row=1,catalog.luts[1].height do rows[row]='Row '..row end;return rows end)(),default=1,validate=function(v)return v<=catalog.luts[state.handle and state.handle.get('edit_lut')or 1].height end,on_change=function()self.sync()end},
            {id='edit_column',type='choice',label='Semantic field / grid column',choices=m.semantics.columns_for(catalog.luts[1].width),default=1,on_change=function()self.sync()end},
            {id='edit_row_active',type='toggle',label='Selected row override',default=false,on_change=function(v)
                if self.suppressed then return end;local lut,row=selected();batch({[lut.name..'_r'..row..'_on']=v,enabled=v or state.handle.get('enabled')});state.dirty=true
            end},
            {id='preserve_effects',type='toggle',label='Preserve emission, modes and unknown effects',default=false,description='Off by default: imports and float edits use their full values, including emission/modes. Turn on to retain original non-color controls while recoloring. Base RGB may still tint glow.',on_change=function()state.dirty=true;self.sync()end},
            {id='cell_color',type='color',label='Selected RGB color',default='#FFFFFF',validate=function()if self.suppressed then return true end;local lut,_,col=selected();return m.semantics.is_color(lut.width,col) and (not state.handle.get('preserve_effects')or m.semantics.safe_lookup_cell(lut.width,col,1))end,
                on_change=function(hex)if self.suppressed then return end;local lut,row,col=selected();local i=m.semantics.index(row,col,1,lut.width,lut.height);local r,g,b=m.palette.rgb(hex);edits({[i]=r,[i+1]=g,[i+2]=b})end}
        }
        for ch,name in ipairs({'r','g','b','a'})do
            controls[#controls+1]={id='cell_'..name,type='slider',label='Channel '..name:upper()..' (float)',min=-1e10,max=1e10,step=.001,default=0,
                validate=function()if self.suppressed then return true end;local lut,_,col=selected();return not state.handle.get('preserve_effects')or m.semantics.safe_lookup_cell(lut.width,col,ch)end,
                on_change=function(v)if self.suppressed then return end;local lut,row,col=selected();edits({[m.semantics.index(row,col,ch,lut.width,lut.height)]=v})end}
        end
        controls[#controls+1]={id='camo_type',type='choice',label='Camo pattern index',choices={'Off','Pattern 0','Pattern 1','Pattern 2','Pattern 3','Pattern 4','Pattern 5'},default=1,on_change=function(v)
            if self.suppressed then return end;local lut,row=selected();local i=m.semantics.index(row,22,1,lut.width,lut.height)
            edits({[i]=v==1 and 0 or 20,[i+1]=v==1 and 0 or 1,[i+2]=v==1 and 0 or 1,[i+3]=v-2})
        end}
        for _,action in ipairs({'undo','redo'})do
            controls[#controls+1]={id=action,type='button',label=action=='undo' and 'Undo document edit'or 'Redo document edit',on_activate=function()
                local name=self.document[action]();if name then state.dirty=true;self.sync()end;return name and 'Document changed'or 'History is empty'
            end}
        end
        controls[#controls+1]={id='copy_row',type='button',label='Copy selected row',on_activate=function()local lut,row=selected();self.document.row_copy(lut.name,row);return 'Row copied'end}
        controls[#controls+1]={id='paste_row',type='button',label='Paste row (all float channels)',on_activate=function()local lut,row=selected();self.document.row_paste(lut.name,row);activate(lut,row);self.sync()end}
        controls[#controls+1]={id='debug_rows',type='button',label='Debug row colors',on_activate=function()
            local lut=selected();local changes={}
            for row=1,lut.height do local i=(row-1)*lut.width*4;local rgb=state.api.hsv_rgb((row-1)/lut.height,1,1);changes[i],changes[i+1],changes[i+2]=rgb[1]/255,rgb[2]/255,rgb[3]/255 end
            self.document.edit(lut.name,changes);local flags={enabled=true};for row=1,lut.height do flags[lut.name..'_r'..row..'_on']=true end;batch(flags);state.dirty=true;self.sync()
        end}
        local color_selector=table.remove(controls,2)
        pages[#pages+1]={id='colors',name='Base Color / regions',require_confirmation=false,controls={color_selector}}
        pages[#pages+1]={id='semantic',name='Advanced / float grid',require_confirmation=false,controls=controls}
        local file_controls={
            {id='native_pick',type='button',label='Import LUT / mod archive',description='Opens a Windows file picker directly. ZIP, RAR, DDS or EXR; results and Apply return here. The bundled service starts automatically. Successful import sets Match Your Colors Off.',on_activate=function()return assert(self.native,'Native importer unavailable').pick()end},
            {id='native_status',type='text',label='Choose a file, then apply its palette here.'},
            {id='native_target',type='choice',label='Imported palette target',choices={'Import a file first'},default=1},
            {id='native_apply',type='button',label='Apply imported palette',on_activate=function()batch({watch_files=true});return assert(self.native,'Native importer unavailable').apply(state.handle.get('native_target'))end},
            {id='open_companion',type='button',label='Advanced editor (local browser)',description='Optional full grid and file editor. Native import above does not open a browser.',on_activate=function()return m.open_companion.open()end},
            {type='text',label='Float DDS loads in game. EXR is converted by the local file service. Files: '..folder},
            {id='watch_files',type='toggle',label='Hotload working LUT files',default=true,description='Validated changes to this armor/LUT working DDS activate its rows. Invalid files retain the previous rendering.'},
            {id='autosave',type='toggle',label='Auto-save working float DDS',default=true},
            {id='file_stem',type='input',label='External filename (without extension)',default='sample'},
            {id='file_type',type='choice',label='External file format',choices={'DDS','EXR (local conversion)'},default=1},
            {id='load_float',type='button',label='Load selected external LUT',on_activate=function()
                local lut=selected();local stem=state.handle.get('file_stem');assert(stem:match('^[%w_-]+$'),'Use a simple filename')
                local path=folder..'/'..stem..(state.handle.get('file_type')==1 and '.dds'or '.exr.converted.dds')
                local data=m.dds.read(path,lut.width,lut.height);self.document.replace(lut.name,data)
                local flags={enabled=true};for row=1,lut.height do flags[lut.name..'_r'..row..'_on']=true end;batch(flags);state.dirty=true;self.sync()
            end},
            {id='quick_save',type='button',label='Quick save selected LUT',on_activate=function()local lut=selected();return 'Saved: '..self.document.save(lut.name)end},
            {id='export_originals',type='button',label='Export original float LUTs',on_activate=function()
                self.export_originals();return 'Original DDS files exported'
            end}
        }
        pages[#pages+1]={id='files',name='Files / hotload',require_confirmation=false,controls=file_controls}
        if (catalog.identity.target_kind or 'armor')=='armor'then
            local cached=package.loaded['dbf.epic_lut.quick_client.R3'];self.quick=(cached and cached.folder==folder and cached)or(m.native_import and m.native_import.new(folder,'quick'));if self.quick then package.loaded['dbf.epic_lut.quick_client.R3']=self.quick end
            local quick_controls={
                {type='text',label='Alpha preview — features, layout, and behavior may change.'},
                {id='quick_pick',type='button',label='Choose LUT / mod archive',description='Native Windows picker: ZIP, RAR, DDS or EXR. Successful import sets Match Your Colors Off; apply the palette below.',on_activate=function()return assert(self.quick,'Native importer unavailable').pick()end},
                {id='quick_status',type='text',label='No palette selected.'},
                {id='quick_file',type='text',text_role='selection',label='Imported file: none'}
            }
            for _,kind in ipairs({'armor','helmet'})do local selected_kind=kind
                quick_controls[#quick_controls+1]={id='quick_apply_'..kind,type='button',label='Apply to '..(kind=='armor'and 'Armor'or 'Helmet'),on_activate=function()
                    local owner=assert(package.loaded['dbf.'..selected_kind..'_lut_editor.owner.v1'],'Equipped target unavailable')
                    assert(owner.features and owner.handle,'Target discovery is incomplete');owner.features.export_originals()
                    assert(owner.handle.set_many({preserve_effects=false,watch_files=true}))
                    return assert(self.quick,'Native importer unavailable').quick_apply(selected_kind,state.handle.get('quick_material'),state.handle.get('quick_emission'))
                end}
            end
            quick_controls[#quick_controls+1]={id='quick_reset_both',type='button',label='Reset Armor and Helmet',description='Restore original bindings and disable both overrides. Custom colors are retained.',on_activate=function()
                for _,kind in ipairs({'armor','helmet'})do
                    local owner=assert(package.loaded['dbf.'..kind..'_lut_editor.owner.v1'],'Target unavailable')
                    assert(owner.handle,'Target discovery is incomplete');assert(owner.handle.activate('reset'))
                end
                return 'Armor and Helmet restored; custom colors retained'
            end}
            quick_controls[#quick_controls+1]={id='quick_extras',type='section',label='Extras',collapsed=true,children={
                {id='quick_material',type='toggle',label='Preserve material properties / semantics',default=false,description='On: retain target non-color controls and color alpha/modes. Off: map known material fields. Unknown fields always retain originals.'},
                {id='quick_emission',type='toggle',label='Preserve emission',default=false,description='Independent of material preservation. On: retain original emission controls. Base color can still tint glow.'},
                {type='text',label='Known-field remap with nearest proportional rows. Unknown fields retain originals. Base RGB may tint glow even with emission preservation.'}

            }}
            pages[#pages+1]={id='quick_load',category='quick_load',name='Quick Load',require_confirmation=false,controls=quick_controls}
        end
    end
    function self.attach(catalog)
        if self.attached~=catalog then
            local prefix=folder..'/'..(catalog.identity.target_kind or 'armor')..'-'..string.format('%08x',catalog.identity.target_id or catalog.identity.armor)..'-'..catalog.identity.body..'-'
            -- Flat profile filenames avoid creating directories from the game callback.
            self.document.attach(catalog,folder,state.handle,prefix)
            for _,d in pairs(self.document.documents)do
                d.path=prefix..d.lut.name..'.dds'
                local f=io.open(d.path,'rb');if f then local bytes=f:read(m.dds.MAX_BYTES+1);f:close();local ok,data=pcall(m.dds.decode,bytes,d.lut.width,d.lut.height)
                    if ok then d.data=data;d.active=true;d.stamp=bytes else note('Working LUT rejected: '..tostring(data))end
                end
            end
            self.attached=catalog
        end
        self.quick_key=(catalog.identity.target_kind or 'armor')..'-'..string.format('%08x',catalog.identity.target_id or catalog.identity.armor)..'-'..catalog.identity.body
        self.quick_cache_key=folder..'|'..self.quick_key
        local valid=package.loaded['dbf.epic_lut.quick_valid.v1']or {};package.loaded['dbf.epic_lut.quick_valid.v1']=valid;self.quick_valid=valid[self.quick_cache_key]==true
        self.sync();self.manifest()
    end
    function self.manifest()
        local rows={}
        for _,lut in ipairs(self.catalog.luts)do local d=self.document.documents[lut.name]
            local kind=self.catalog.identity.target_kind or 'armor';local item=self.catalog.identity.target_id or self.catalog.identity.armor
            rows[#rows+1]=string.format('{"key":"%s-%08x-%s","kind":"%s","hash":"%s","width":%d,"height":%d,"working":"%s","original":"%s"}',kind,item,lut.name,kind,lut.name,lut.width,lut.height,d.path:match('[^/]+$'),d.path:match('[^/]+$'):gsub('%.dds$','-original.dds'))
        end
        local catalogs=package.loaded['dbf.epic_lut.catalog_manifest.v1']or {};package.loaded['dbf.epic_lut.catalog_manifest.v1']=catalogs
        catalogs[self.catalog.identity.target_kind or 'armor']=rows
        local all={};for _,kind in ipairs({'armor','helmet'})do for _,row in ipairs(catalogs[kind]or {})do all[#all+1]=row end end
        local f=io.open(folder..'/current.json','wb');if f then f:write('{"version":2,"luts":['..table.concat(all,',')..']}');f:close()end
    end
    function self.compose()
        local out={}
        for _,lut in ipairs(self.catalog.luts)do local data=self.document.compose(lut.name,state.handle)
            if data then
                if state.handle.get('preserve_effects')then data=m.semantics.protect(lut.values,data,lut.width,lut.height)end
                out[lut.name]=data
            end
        end
        return out
    end
    function self.tick()
        if not self.attached or not state.handle then return end
        local provider_changed=false
        local function imported(metadata)
            if metadata and metadata.imported and m.provider_menu then
                local ok,changed=m.provider_menu.disable_matching(state.api);assert(ok,changed)
                provider_changed=provider_changed or changed
                if changed then note('Import complete; original Match Your Colors switched Off')end
            end
        end
        if self.native then local message,index,metadata=self.native.poll();if message then
            imported(metadata)
            local identity=self.catalog.identity;local mod=state.api.mods['dbf_'..(identity.target_kind or 'armor')..'_lut_'..string.format('%08x',identity.target_id or identity.armor)..'_'..identity.body]
            mod.controls.native_target.choices=self.native.labels;mod.controls.native_target.description=message
            for _,page in ipairs(mod.pages)do for _,control in ipairs(page.controls)do if control.id=='native_status'then control.label=message end end end
            batch({native_target=index});note(message)
        end end
        if self.quick then
            local message,_,metadata=self.quick.poll()
            if message then
                imported(metadata)
                if metadata.applied then local owner=package.loaded['dbf.'..metadata.applied..'_lut_editor.owner.v1']
                    if owner and owner.features and owner.features.quick_key and owner.features.quick_key:match('^(.*)%-[^%-]+$')==metadata.prefix then
                        owner.features.quick_valid=true;package.loaded['dbf.epic_lut.quick_valid.v1'][owner.features.quick_cache_key]=true
                    end
                end
                note(message)
            end
            local identity=self.catalog.identity;local mod=state.api.mods['dbf_armor_lut_'..string.format('%08x',identity.target_id or identity.armor)..'_'..identity.body]
            local page;for _,p in ipairs(mod.pages)do if p.id=='quick_load'then page=p;break end end
            local signature=tostring(self.quick.metadata)
            for _,kind in ipairs({'armor','helmet'})do local owner=package.loaded['dbf.'..kind..'_lut_editor.owner.v1'];signature=signature..tostring(owner and owner.handle)..tostring(owner and owner.features and owner.features.quick_valid)..tostring(owner and owner.handle and owner.handle.get('enabled'))end
            if page and signature~=self.quick_refs then
                self.quick_refs=signature;local controls={}
                for _,control in ipairs(page.controls)do
                    if not control.quick_dynamic then
                        if control.id=='quick_status'then control.label=self.quick.last_message or 'No palette selected.'end
                        if control.id=='quick_file'then local preview=self.quick.metadata;control.label='Imported file: '..(preview and preview.file or 'none')
                            controls[#controls+1]=control
                            if preview and #preview.swatches>0 then
                                controls[#controls+1]={type='text',text_role='selection',label=preview.preview or 'Source row colors',quick_dynamic=true,groups={},depth=0}
                                for first=1,#preview.swatches,8 do local swatches={};for i=first,math.min(first+7,#preview.swatches)do swatches[#swatches+1]=preview.swatches[i]end
                                    controls[#controls+1]={type='text',text_role='selection',label='',swatches=swatches,quick_dynamic=true,groups={},depth=0}
                                end
                            end
                        else
                            if control.id=='quick_extras'then
                                for _,kind in ipairs({'armor','helmet'})do local owner=package.loaded['dbf.'..kind..'_lut_editor.owner.v1']
                                    if owner and owner.handle and owner.result then
                                        local linked={};local owner_id='dbf_'..kind..'_lut_'..string.format('%08x',owner.result.identity.target_id or owner.result.identity.armor)..'_'..owner.result.identity.body
                                        for k,v in pairs(state.api.mods[owner_id].controls.enabled)do linked[k]=v end
                                        linked.id='quick_'..kind..'_enabled';linked.label=(kind=='armor'and 'Armor'or 'Helmet')..' override enabled';linked.description='Off restores original bindings and retains mapped values. On re-enables the retained mapping for this equipped item; apply a palette first for a new item.'
                                        linked.source_mod_id=owner_id;linked.source_control_id='enabled';linked.quick_dynamic=true;linked.groups={};linked.depth=0
                                        linked.disabled=not owner.handle.get('enabled')and not owner.features.quick_valid
                                        controls[#controls+1]=linked
                                    end
                                end
                            end
                            controls[#controls+1]=control
                        end
                    end
                end
                local prefs=state.api.mods.epic_lut_preferences
                if prefs then for _,id in ipairs({'menu_key','reset_key'})do local alias={};for k,v in pairs(prefs.controls[id])do alias[k]=v end;alias.id='quick_'..id;alias.source_mod_id=prefs.id;alias.source_control_id=id;alias.groups={'quick_extras'};alias.depth=1;alias.quick_dynamic=true;controls[#controls+1]=alias end end
                page.controls=controls;state.api.revision=state.api.revision+1
            end
        end
        local function locked()if self.native then return self.native.locked()end;local f=io.open(folder..'/apply.lock','rb');if f then f:close();return true end;return false end
        if locked()then return provider_changed end
        if state.dirty and state.handle.get('autosave')then self.save_all()end
        if not state.handle.get('watch_files')or state.memory.time()-self.last_poll<.25 then return provider_changed end
        self.last_poll=state.memory.time()
        local ok,pending=pcall(self.document.poll_all,locked)
        if not ok then if self.poll_error~=tostring(pending)then self.poll_error=tostring(pending);note('Hotload batch rejected; previous textures retained: '..self.poll_error)end;return provider_changed end
        if #pending>0 then local flags={enabled=true}
            for _,p in ipairs(pending)do local d=self.document.documents[p.name];for row=1,d.lut.height do flags[p.name..'_r'..row..'_on']=true end end
            batch(flags);state.dirty=true;self.sync();note('Validated float LUT batch hotloaded: '..#pending)
        end
        return provider_changed
    end
    return self
end
return X
