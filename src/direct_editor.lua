-- DDS -> selected local live LUT. No equipment catalogue or file service.
local ffi=require('ffi')
local ctx,memory,native,game,frontend,preferences,handle,api,paths,palette_editor
local groups,owned={},{}
local imported
local loaded,status=nil,'Load a DDS or ZIP, then refresh the live LUT list.'
local pending,palettes,sequence=nil,{},0
local setup,resume_job,resume_done
local defaults={}
local select_suppressed=false
local import_view
local source_tables,editor_tables={},{}
local index_job
local refresh_needed,next_refresh=false,0
local import_counter=package.loaded['epic.import.counter.v1']or {value=0};package.loaded['epic.import.counter.v1']=import_counter
local small,big=ffi.new('uint8_t[96]'),ffi.new('uint8_t[1024]')
local retain=package.loaded['epic.direct_lut.retained.v1']or {records={},bytes=0,cache={}}
package.loaded['epic.direct_lut.retained.v1']=retain
local function read(a,n,b)return memory.read_into(ffi.cast('const uint8_t *',a),n,b)end
local function binding(b)return m.engine.binding(read,b.material,m.engine.LUT_SLOT,small,big)end
local function present(b)
    if native.alive(b.unit)==0 then return false end
    for _,v in ipairs(m.engine.unit_materials(native,b.unit))do
        if v.mesh==b.mesh and v.material==b.material then return true end
    end
    return false
end
local function material_key(b)return b.unit..':'..b.mesh..':'..b.material end
local function restore()
    local pending={}
    for _,b in ipairs(owned)do
        local current=present(b)and binding(b)
        if current and current~=b.original and (current==b.current or current==b.previous)then
            local ok=pcall(function()m.engine.bind(native,b.material,m.engine.LUT_SLOT,b.original);native.commit(b.mesh)end)
            if not ok or binding(b)~=b.original then pending[#pending+1]=b
            else b.current=b.original;b.previous=nil;b.texture=nil end
        elseif current==b.original then b.current=b.original;b.previous=nil;b.texture=nil
        end
    end
    owned=pending
    return #pending==0
end
local function message(text)status=text;ctx.log('Epic LUT: '..text);return text end
local function disable_matching()
    if m.provider_menu then return m.provider_menu.disable_matching(api)end
    return true,false
end
local function palette_choices(labels)
    api.mods[handle.id].controls.palette.choices=labels
    select_suppressed=true;local ok,why=handle.set('palette',1);select_suppressed=false;assert(ok,why)
end
local function action(fn,recover)
    local ok,why=pcall(fn)
    if not ok then if recover then restore()end;return message(tostring(why))end
    return why
end
local function refresh()
    local identity,why=m.avatar.resolve_live(memory,game);assert(identity,why)
    local found,seen,kept,active={},{},{},{}
    for _,b in ipairs(owned)do if present(b)and binding(b)==b.current then kept[material_key(b)]=b;active[#active+1]=b end end
    owned=active
    for _,u in ipairs(m.avatar.units(memory,identity,nil,0,9))do
        for vi,v in ipairs(m.engine.unit_materials(native,u.unit))do
            local b={unit=u.unit,mesh=v.mesh,material=v.material}
            local existing=kept[material_key(b)]
            local object=existing and existing.original or binding(b)
            if object and object~=0 then
                local key=v.material..':'..v.mesh
                if not seen[key]then
                    local group=found[object]
                    if not group then group={object=object,bindings={},helmet=false,armor=false};found[object]=group end
                    if u.slot==0 then group.helmet=true else group.armor=true end
                    b=existing or b;b.original=object;b.current=existing and existing.current or object
                    b.helmet=u.slot==0;b.armor=not b.helmet
                    b.save_key=(u.type or 0)..':'..(u.slot or 0)..':'..(v.mesh_index or 0)..':'..(v.material_index or vi-1)
                    group.bindings[#group.bindings+1]=b;seen[key]=true
                end
            end
        end
    end
    groups={};for _,group in pairs(found)do groups[#groups+1]=group end
    table.sort(groups,function(a,b)return a.object<b.object end)
    assert(#groups>0,'No local live LUT bindings yet; refresh after loading the character')
    local labels={};for i,g in ipairs(groups)do
        local target=g.helmet and (g.armor and 'Shared Armor / Helmet' or 'Helmet')or 'Armor'
        labels[i]=target..' LUT '..i
    end
    api.mods[handle.id].controls.lut.choices=labels;assert(handle.set('lut',1))
    return message('Found '..#groups..' live LUTs. Select one, then Apply.')
end
local function load_dds(path)
    local f=assert(io.open(path,'rb'),'DDS file not found')
    local bytes=f:read(m.dds.MAX_BYTES+1);f:close()
    local data,w,h=m.dds.decode(bytes)
    assert(w==23,'This simple editor accepts 23-column material LUT DDS files')
    local ok,changed=disable_matching();assert(ok,changed)
    if changed then groups={}end
    imported={data=data,width=w,height=h,source=path}
    source_tables[path]=imported
    refresh_needed=not pcall(refresh)
    return message('DDS imported ('..w..' x '..h..'). Save LUT to Palette to edit; Apply LUT sends it to gear.')
end
local function load(pick)
    assert(not pending,'ZIP import is still pending')
    resume_done=true;resume_job=nil
    local name
    if not pick then
        name=handle.get('file')
        assert(type(name)=='string'and #name>0 and #name<=48 and name:match('^[%w _-]+$'),'Enter the filename without its extension')
        if handle.get('format')==1 then
            palettes={paths.files..'/'..name..'.dds'};palette_choices({name})
            return load_dds(palettes[1])
        end
    end
    local _,kernel=m.native_import.verify_interface()
    assert(not paths.files:find('"',1,true)and not paths.cache:find('"',1,true),'Invalid import path')
    local script=paths.cache..'/import-zip.ps1'
    local f=assert(io.open(script,'wb'));assert(f:write((m.zip_import_script:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end))));assert(f:close())
    import_counter.value=import_counter.value+1
    local pid=tonumber(kernel.epic_native_pid());local base=paths.cache..'/zip-'..pid..'-'..os.time()..'-'..import_counter.value
    local extension=handle.get('format')==3 and '.rar'or '.zip'
    local input=pick and ' -Pick' or ' -Package "'..paths.files..'/'..name..extension..'"'
    local args='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'..script..'"'..input..' -Output "'..base..'" -Result "'..base..'.txt" -OwnerPID '..pid
    local worker=m.native_import.launch_worker(args,paths.cache)
    pending={base=base,started=os.time(),pick=pick,worker=worker,phase='starting',last_beat=os.time()}
    return message(pick and 'Choose a DDS or ZIP in the Windows file picker.' or 'Extracting ZIP palettes. No Python is used.')
end
local function cancel_import(retry)
    if not pending then if retry then return load(true)end;return message('No import is running.')end
    local f=assert(io.open(pending.base..'.cancel','wb'));f:write('cancel');f:close()
    pending.canceling=os.time();pending.retry=retry
    return message(retry and 'Closing the previous picker before retrying...'or 'Canceling import; current palettes stay active.')
end
local function finish_job(job)
    job.worker.close();if pending==job then pending=nil end
    if job.retry then return load(true)end
end
local function poll_job()
    local job=pending;if not job then return end
    local now=os.time()
    local progress=io.open(job.base..'.progress','rb')
    if progress then
        local text=progress:read(513)or '';progress:close()
        local pid,phase,beat=text:match('^(%d+)\t([a-z]+)\t(%d+)$')
        if #text>512 or tonumber(pid)~=job.worker.pid or not ({starting=true,picker=true,reading=true,extracting=true})[phase]or tonumber(beat)>now+2 then
            job.worker.stop();finish_job(job);return message('Invalid picker state. Retry file picker to recover.')
        end
        job.phase=phase;job.last_beat=tonumber(beat);job.reported=true
    end
    if job.canceling then
        if not job.worker.running()or now-job.canceling>=5 then
            job.worker.stop();local retry=job.retry;finish_job(job)
            if not retry then message('Import canceled; current palette retained.')end
        end
        return
    end
    local f=io.open(job.base..'.txt','rb')
    if f then
        local text=f:read(8193)or '';f:close();finish_job(job)
        return action(function()
            assert(#text<=8192,'Archive result exceeds budget')
            local lines={};for line in text:gmatch('[^\r\n]+')do lines[#lines+1]=line end
            if lines[1]=='cancel'then return message('File selection canceled; current palette retained.')end
            assert(lines[1]=='ok',lines[2]or 'Archive extraction failed')
            assert(#lines>=2 and #lines<=257,'Invalid extracted palette count')
            local imported,labels={},{}
            for i=2,#lines do assert(lines[i]:match('^lut%d%d%d%.dds$'),'Invalid extracted palette filename');imported[#imported+1]=job.base..'/'..lines[i];labels[#labels+1]=lines[i]end
            -- Validate the first file before replacing the current import selection.
            load_dds(imported[1]);palettes=imported;palette_choices(labels)
            index_job=coroutine.create(function()
                for _,path in ipairs(palettes)do if not source_tables[path]then
                    local f=assert(io.open(path,'rb'));local bytes=f:read(m.dds.MAX_BYTES+1);f:close()
                    local data,w,h=m.dds.decode(bytes);if w==23 then source_tables[path]={data=data,width=w,height=h,source=path}end
                    coroutine.yield()
                end end
            end)
            return status
        end)
    end
    if not job.worker.running()then finish_job(job);return message('File picker exited without a result. Retry file picker.')end
    local stalled=now-job.last_beat>(job.reported and 10 or 20)
    if stalled or now-job.started>300 then
        message(stalled and 'File picker stopped responding; recovering...'or 'File picker timed out; recovering...')
        return cancel_import(false)
    end
end
local function apply_bindings(document,targets)
    assert(#targets>0,'No matching live LUTs; refresh first')
    for _,b in ipairs(targets)do
        assert(present(b)and binding(b)==b.current,'Live LUT changed; refresh before applying')
    end
    local bytes=document.width*document.height*16
    local key=document.width..':'..document.height..':'..ffi.string(document.data,bytes)
    local texture=retain.cache[key]
    if not texture then
        assert(retain.bytes+bytes<=8*1024*1024 and #retain.records<2048,'Session texture budget reached; restore and restart')
        local data=ffi.new('float[?]',document.width*document.height*4);ffi.copy(data,document.data,bytes)
        local keep={data=data};retain.records[#retain.records+1]=keep;retain.bytes=retain.bytes+bytes
        texture=assert(m.engine.create_texture(native,document.width,document.height,data,read,small))
        keep.texture=texture;retain.cache[key]=texture
    end
    local known={};for _,b in ipairs(owned)do known[material_key(b)]=true end
    local changes={}
    local ok,why=pcall(function()
        for _,b in ipairs(targets)do
            if not known[material_key(b)]then owned[#owned+1]=b;known[material_key(b)]=true end
            if b.current~=texture.object then
                changes[#changes+1]={binding=b,old=b.current}
                b.previous=b.current;b.current=texture.object
                m.engine.bind(native,b.material,m.engine.LUT_SLOT,b.current);native.commit(b.mesh)
                assert(binding(b)==b.current,'LUT binding readback failed');b.previous=nil
            end
        end
    end)
    if not ok then
        -- Roll back only this operation; previously applied targets remain active.
        for i=#changes,1,-1 do
            local b,old=changes[i].binding,changes[i].old
            if present(b)and binding(b)==b.current then
                local restored=pcall(function()m.engine.bind(native,b.material,m.engine.LUT_SLOT,old);native.commit(b.mesh);assert(binding(b)==old)end)
                if restored then b.current=old;b.previous=nil end
            end
        end
        error(why,0)
    end
    for _,b in ipairs(targets)do b.texture=texture;b.document=document end
    return #targets,texture
end
local function apply()
    assert(loaded,'Load a DDS first');resume_done=true;resume_job=nil
    assert(not handle.get('preserve_emissives'),'Original game emissive pixels are unavailable in the direct-binding build. Leave Preserve Original Emissives Off until a verified original LUT reference is supplied.')
    if #groups==0 then refresh()end
    local scope=handle.get('scope');local targets={}
    for index,group in ipairs(groups)do
        if scope==4 or (scope==2 and group.armor)or(scope==3 and group.helmet)or(scope==1 and index==handle.get('lut'))then
            for _,b in ipairs(group.bindings)do if scope==1 or scope==4 or(scope==2 and b.armor)or(scope==3 and b.helmet)then targets[#targets+1]=b end end
        end
    end
    local count,texture=apply_bindings(loaded,targets)
    if scope==2 or scope==4 then defaults.armor=texture end
    if scope==3 or scope==4 then defaults.helmet=texture end
    return message('Palette applied to '..count..' bindings. Other applied LUTs stay active.')
end
local function save_setup()
    local active={}
    for _,b in ipairs(owned)do
        if present(b)and binding(b)==b.current and b.texture and b.current==b.texture.object then active[#active+1]=b end
    end
    return message('Saved '..assert(setup,'Setup storage unavailable').save(active,defaults)..' applied palettes. Armor and helmet will resume on later launches.')
end
local function save_palette()
    local source=assert(imported,'Import a LUT first');local data=ffi.new('float[?]',source.width*source.height*4)
    if editor_tables[source.source]then loaded=editor_tables[source.source]
    else ffi.copy(data,source.data,source.width*source.height*16);loaded={data=data,width=source.width,height=source.height,source=source.source};editor_tables[source.source]=loaded end
    if palette_editor then palette_editor.sync()end
    if api.focus_page then api.focus_page(handle.id,'colors')end
    return message('LUT copied into the palette editor. Apply LUT sends it to the checked targets.')
end
local function apply_checked()
    local armor,helmet=handle.get('target_armor'),handle.get('target_helmet')
    assert(armor or helmet,'Check Armor and/or Helmet first')
    assert(handle.set('scope',armor and(helmet and 4 or 2)or 3));return apply()
end
local function import_state()
    local previews={armor={},helmet={}}
    for index,group in ipairs(groups)do
        local seen={armor={},helmet={}}
        for _,b in ipairs(group.bindings)do
            local kind=b.helmet and 'helmet'or 'armor';local texture=b.texture
            if texture and b.current==texture.object and not seen[kind][texture]then
                seen[kind][texture]=true
                local document=b.document or texture
                previews[kind][#previews[kind]+1]={name=(kind=='armor'and 'Armor'or 'Helmet')..' LUT '..index,index=index,width=document.width,height=document.height,data=document.data,revision=document.revision,edited=(document.revision or 0)>0}
            end
        end
    end
    local tables={}
    for i,path in ipairs(palettes)do local document=editor_tables[path]or source_tables[path];if document then
        tables[#tables+1]={name='Table '..i,index=i,width=document.width,height=document.height,data=document.data,revision=document.revision,edited=(document.revision or 0)>0}
    end end
    if m.table_groups then tables=m.table_groups.collapse(tables);previews.armor=m.table_groups.collapse(previews.armor);previews.helmet=m.table_groups.collapse(previews.helmet)end
    local phase=pending and pending.phase or ''
    local labels={starting='Opening file picker...',picker='Waiting for file selection...',reading='Reading archive...',extracting='Extracting LUTs...'}
    return {tables=tables,armor=previews.armor,helmet=previews.helmet,loaded=imported,status=status,busy=pending~=nil or index_job~=nil,phase=index_job and 'Comparing imported tables...'or pending and pending.canceling and 'Canceling...'or labels[phase]or phase,
        time=memory.time and memory.time()or os.clock(),elapsed=pending and(os.time()-pending.started)or 0,
        armor_checked=handle.get('target_armor'),helmet_checked=handle.get('target_helmet'),palette_name=handle.get('palette_name'),preserve_emissives=handle.get('preserve_emissives')}
end
local function remove_lut()
    resume_done=true;resume_job=nil
    assert(restore(),'Restoration pending');defaults={};if setup then setup.clear()end
    return message('All applied LUTs removed; original bindings restored and saved application cleared.')
end
local function resume_setup()
    if resume_done or not setup then return end
    if not resume_job then
        local identity=m.avatar.resolve_live(memory,game);if not identity then return end
        local valid,plan=pcall(setup.read)
        if not valid then resume_done=true;return message('Saved setup is invalid: '..tostring(plan))end
        if not next(plan)then resume_done=true;return end
        resume_job=coroutine.create(function()
            local documents={};local total=0
            for _,file in pairs(plan)do if not documents[file]then
                local f=assert(io.open(paths.presets..'/'..file,'rb'),'Saved palette missing');local bytes=f:read(m.dds.MAX_BYTES+1);f:close()
                local data,w,h=m.dds.decode(bytes);assert(w==23,'Saved palette is not a material LUT');total=total+w*h*16;assert(total<=8*1024*1024,'Saved palette budget exceeded')
                documents[file]={data=data,width=w,height=h};coroutine.yield()
            end end
            local files={};for file in pairs(documents)do files[#files+1]=file end;table.sort(files)
            palettes={};local labels={}
            for i,file in ipairs(files)do
                palettes[i]=paths.presets..'/'..file
                labels[i]=file==plan['armor-all']and (file==plan['helmet-all']and 'Saved Armor + Helmet'or 'Saved Armor')or file==plan['helmet-all']and 'Saved Helmet'or 'Saved LUT override '..i
            end
            palette_choices(labels)
            if not loaded then loaded=documents[files[1]];if palette_editor then palette_editor.sync()end end
            local ok,changed=disable_matching();assert(ok,changed)
            coroutine.yield();coroutine.yield() -- Let the original provider release its bindings.
            local by_file={};local began=os.time();local expected=0;local next_scan=0
            for key in pairs(plan)do if key~='armor-all'and key~='helmet-all'then expected=expected+1 end end
            repeat
                local now=memory.time and memory.time()or os.clock()
                if now<next_scan then coroutine.yield()else
                next_scan=now+.25
                local scanned=pcall(refresh);local matched=0;by_file={}
                if scanned then for _,group in ipairs(groups)do for _,b in ipairs(group.bindings)do
                    if plan[b.save_key]then matched=matched+1 end
                    local file=plan[b.save_key]or plan[b.armor and 'armor-all'or 'helmet-all']
                    if file then by_file[file]=by_file[file]or {};table.insert(by_file[file],b)end
                end end end
                if scanned and(matched>=expected or os.time()-began>=10)then break end
                assert(os.time()-began<15,'Local LUTs are not ready for the saved setup');coroutine.yield()
                end
            until false
            local applied=0
            for file,targets in pairs(by_file)do
                local count,texture=apply_bindings(documents[file],targets);applied=applied+count
                if file==plan['armor-all']then defaults.armor=texture end
                if file==plan['helmet-all']then defaults.helmet=texture end
                if not loaded then loaded=documents[file];if palette_editor then palette_editor.sync()end end
                coroutine.yield()
            end
            message('Saved setup restored to '..applied..' local bindings. Unmatched slots were skipped.')
        end)
    end
    local ok,why=coroutine.resume(resume_job)
    if not ok then resume_done=true;resume_job=nil;message('Saved setup could not resume: '..tostring(why))
    elseif coroutine.status(resume_job)=='dead'then resume_done=true;resume_job=nil end
end
local function register(current)
    if api==current and handle then return end
    if handle then handle.unregister()end
    api=current
    local pages={{id='direct',name='1. Import / Apply',require_confirmation=false,controls={
        {type='text',label='If Match Your Colors is enabled, turn its color matching Off before applying.'},
        {id='browse',type='button',label='Import DDS / ZIP / RAR...',on_activate=function()return action(function()return load(true)end)end},
        {id='cancel_import',type='button',label='Cancel import',on_activate=function()return action(function()return cancel_import(false)end)end},
        {id='retry_import',type='button',label='Retry file picker',on_activate=function()return action(function()return cancel_import(true)end)end},
        {id='target_helmet',type='toggle',label='Apply LUT to Helmet',default=true},
        {id='target_armor',type='toggle',label='Apply LUT to Armor',default=true},
        {id='palette_name',type='input',label='Palette name',default='my-palette'},
        {id='save_palette',type='button',label='Save LUT to Palette',on_activate=function()return action(save_palette)end},
        {id='apply_checked',type='button',label='Apply LUT',on_activate=function()return action(apply_checked)end},
        {id='preserve_emissives',type='toggle',label='Preserve Original Emissives',default=false,description='Off by default. Preserving game-original values requires verified original LUT pixels, unavailable in this direct-binding build; Apply fails safely when enabled.'},
        {id='palette',type='choice',presentation='combined',label='Imported palette',choices={'Import first'},default=1,on_change=function(index)
            if not select_suppressed and not pending and palettes[index]then action(function()resume_done=true;resume_job=nil;return load_dds(palettes[index])end)end
        end},
        {id='refresh',type='button',label='Refresh live LUTs',on_activate=function()return action(refresh)end},
        {id='lut',type='choice',presentation='combined',label='LUT #',choices={'Refresh first'},default=1},
        {id='scope',type='choice',presentation='combined',label='Apply scope',choices={'Selected LUT','All Armor LUTs','Helmet LUTs','All Armor + Helmet LUTs'},default=4},
        {id='apply',type='button',label='Apply palette',on_activate=function()return action(apply)end},
        {id='apply_armor',type='button',label='Apply Armor',on_activate=function()return action(function()assert(handle.set('scope',2));return apply()end)end},
        {id='apply_helmet',type='button',label='Apply Helmet',on_activate=function()return action(function()assert(handle.set('scope',3));return apply()end)end},
        {id='remove_lut',type='button',label='Remove LUT',on_activate=function()return action(function()remove_lut();loaded=nil;imported=nil;palettes={};if palette_editor then palette_editor.sync()end;return message('LUT removed; original bindings restored.')end)end},
        {id='save_setup',type='button',label='Save applied setup',on_activate=function()return action(save_setup)end},
        {id='restore',type='button',label='Restore Original',on_activate=function()return action(function()remove_lut();return message('Original game bindings restored; imported palette retained.')end)end},
        {id='reset_custom',type='button',label='Reset Custom LUT',on_activate=function()return action(function()assert(palette_editor,'Palette editor unavailable');return palette_editor.reset()end)end},
        {id='restore_imported',type='button',label='Restore Imported LUT',on_activate=function()return action(function()assert(palette_editor,'Save an import to the editor first');return palette_editor.reset()end)end},
        {id='status',type='text',label=status}
    }},{id='manual',name='Manual file fallback',require_confirmation=false,controls={
        {type='text',label='Optional fallback: put your file in %LOCALAPPDATA%/Epic LUT/files.'},
        {id='format',type='choice',label='File type',choices={'DDS','ZIP','RAR'},default=1},
        {id='file',type='input',label='Filename (without extension)',default='palette'},
        {id='load',type='button',label='Import local file',on_activate=function()return action(function()return load(false)end)end}
    }}}
    if palette_editor then
        local manual=table.remove(pages)
        for _,page in ipairs(palette_editor.pages())do
            if page.id=='save'then page.controls[#page.controls+1]={type='section',id='manual_fallback',label='Manual file fallback',collapsible=true,collapsed=true,children=manual.controls}end
            pages[#pages+1]=page
        end
    end
    handle=api.register({id='epic_direct_lut',name='Epic LUT',pages=pages})
    api.mods[handle.id].tabs_top=true
    frontend.default_mod_id=handle.id
    if palette_editor then palette_editor.attach(api,handle)end
    if m.import_view then
        import_view=m.import_view.new(import_state)
        api.mods[handle.id].pages[1].render_layout=import_view.draw;api.mods[handle.id].pages[1].on_wheel=import_view.wheel
    end
    groups={}
end
local function close()
    if pending then
        if not pending.canceling then cancel_import(false)end
        if pending.worker.running()and os.time()-pending.canceling<5 then return false end
        pending.worker.stop();pending.worker.close();pending=nil
    end
    if not restore()then return false end
    if handle then handle.unregister();handle=nil end
    if preferences then preferences.close()end
    return not frontend or frontend.close()
end
return {name='Epic LUT',author='Goose',on_enable=function(context)
    ctx=context;paths=m.paths.new(m);ctx.settings_dir=paths.settings
    memory=m.bingus_memory.new(m.bingus_runtime)
    local ok,why=memory.verify_build({exe_sha256='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',game_sha256='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E'});assert(ok,why)
    game=memory.address(assert(memory.module('game.dll')))
    native=assert(m.engine.open(memory,game,memory.address(assert(memory.module()))))
    preferences=m.preferences.new(paths.storage);frontend=m.frontend.new(m,ctx);frontend.preferences=preferences
    if m.direct_setup then setup=m.direct_setup.new(m,paths)end
    if m.lut_editor then palette_editor=m.lut_editor.new(m,function()return loaded end,message,function(name)
        return action(function()
            assert(loaded,'Import a palette first');assert(name:match('^[%w _-]+$')and #name<=48 and #name>0,'Invalid DDS filename')
            m.dds.write(paths.files..'/'..name..'.dds',loaded.data,loaded.width,loaded.height)
            return message('Saved '..name..'.dds in Epic LUT/files')
        end)
    end,paths.presets)end
    ctx.on_cleanup(close);message('Direct DDS editor ready; no archive discovery or Python')
end,on_update=function(dt_context,dt)
    frontend.tick(dt)
    local current=frontend.resolve();if current then
        register(current)
        if setup then action(resume_setup)end
        if refresh_needed then
            local now=memory.time and memory.time()or os.clock()
            if now>=next_refresh then next_refresh=now+.25;refresh_needed=not pcall(refresh)end
        end
        poll_job()
        if index_job then
            local ok,why=coroutine.resume(index_job)
            if not ok then index_job=nil;message('Could not index all tables: '..tostring(why))
            elseif coroutine.status(index_job)=='dead'then index_job=nil end
        end
        for _,control in ipairs(api.mods[handle.id].pages[1].controls)do if control.id=='status'then control.label=status end end
    end
end,on_disable=close,on_cleanup_poll=close}
