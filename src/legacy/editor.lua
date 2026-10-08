local frontend,preferences,bindings
local paths_factory=m.paths
local function create(target)
-- Standalone LLL/MDL lifecycle; The active frontend owns the authoritative settings handle.
local ffi=require('ffi')
local state,ctx
local OWNER=target=='Helmet' and 'dbf.helmet_lut_editor.owner.v1' or 'dbf.armor_lut_editor.owner.v1'
local RETAIN='dbf.armor_lut_editor.retained.v1'
local retained=package.loaded[RETAIN] or {records={},bytes=0};package.loaded[RETAIN]=retained
local function note(message)if ctx then ctx.log('Epic LUT: '..tostring(message))end end
local function key(identity,units)
    local parts={identity.player,identity.avatar,identity.target_id or identity.armor,identity.body,identity.units_at}
    for _,u in ipairs(units)do parts[#parts+1]=u.type..':'..u.slot..':'..u.unit end
    return table.concat(parts,':')
end
local function unregister()
    if state.provider_menu then state.provider_menu.release()end
    if state.handle then state.handle.unregister();state.handle=nil end
    state.api=nil
end
local function register(catalog)
    if m.diagnostic_without_menu then return false end
    local api;if frontend then api=frontend.resolve()else api=rawget(_G,'DBFMCM')end;if not api then return false end
    if state.api==api and state.handle then return true end
    unregister();state.api=api
    if preferences then preferences.mount(api)end
    local pages={{id='session',name='Equipped '..target:lower(),require_confirmation=false,controls={
        {type='text',label=target..' '..string.format('%08x',catalog.identity.target_id or catalog.identity.armor)..' - local equipped target only'},
        {type='text',label='Numbered LUT rows have unknown surface mapping. Primary-color RGB only.'},
        {id='enabled',type='toggle',label='Apply row colors live',default=false,on_change=function()state.dirty=true end},
        {id='reset',type='button',label='Restore original '..target:lower()..' colors',on_activate=function()
            local ok,err=state.handle.set('enabled',false);assert(ok,err);assert(state.session.restore(),'Restoration pending');note('Original bindings restored')
        end},
        {id='reset_rows',type='button',label='Reset Custom LUT Rows',description='Reset stored row colors to each original LUT row and clear all overrides. Restore above keeps custom colors.',on_activate=function()
            assert(type(state.handle.set_many)=='function','MCM batch-settings update required for row reset')
            local values={enabled=false}
            for _,lut in ipairs(catalog.luts)do for row=0,lut.height-1 do
                local id=lut.name..'_r'..(row+1)
                values[id..'_on']=false;values[id..'_color']=m.palette.hex(lut.values,row,lut.width)
            end end
            state.importing=true -- A reset, like import, preserves explicit disabled flags.
            local called,ok,err=pcall(state.handle.set_many,values)
            state.importing=false;assert(called and ok,tostring(called and err or ok))
            state.dirty=true;assert(state.session.restore(),'Original binding restoration pending')
            if state.features then state.features.reset()end
            note('Custom LUT rows reset from preserved originals');return 'Custom LUT rows reset to original colors'
        end},
        {id='refresh',type='button',label='Refresh equipped '..target:lower(),on_activate=function()state.signature=nil end}
    }}}
    pages[1].controls[#pages[1].controls+1]={id='preset_file',type='input',label='Preset filename (without .dbflut)',default='preset',description='Files live in the Epic LUT mod folder / presets. Simple filenames only.'}
    pages[1].controls[#pages[1].controls+1]={id='export',type='button',label='Export '..target:lower()..' preset',on_activate=function()
        local path=m.presets.export(ctx.presets_dir or ctx.dir..'/presets',catalog,state.handle,state.features and state.features.document)
        local name=assert(path:match('/([^/]+)%.dbflut$'));local ok,err=state.handle.set('preset_file',name);assert(ok,err)
        note('Exported preset: '..path);return 'Exported: '..path
    end}
    pages[1].controls[#pages[1].controls+1]={id='import',type='button',label='Import '..target:lower()..' preset',on_activate=function()
        assert(type(state.handle.set_many)=='function','MCM batch-settings update required for atomic import')
        local values,documents=m.presets.read(ctx.presets_dir or ctx.dir..'/presets',state.handle.get('preset_file')..'.dbflut',catalog)
        state.importing=true
        local called,ok,err=pcall(state.handle.set_many,values)
        state.importing=false;assert(called and ok,tostring(called and err or ok))
        if state.features then state.features.import_documents(documents,values)end
        state.dirty=true
        if m.provider_menu then local ok,why=m.provider_menu.disable_matching(state.api);assert(ok,why)end
        note('Validated preset imported in one settings commit');return 'Preset imported'
    end}
    for index,lut in ipairs(catalog.luts)do
        local controls={{type='text',label='LUT '..index..' - '..lut.name..' - '..lut.height..' rows'}}
        for row=0,lut.height-1 do
            local id=lut.name..'_r'..(row+1)
            local target_lut,target_row=lut,row+1
            controls[#controls+1]={id=id..'_on',type='toggle',label='Row '..(row+1)..' override',default=false,on_change=function()state.dirty=true end}
            controls[#controls+1]={id=id..'_color',type='color',label='Row '..(row+1)..' primary RGB',default=m.palette.hex(lut.values,row,lut.width),
                description='USE COLOR enables this row and live application, then updates equipped armor. Cancel leaves activation unchanged. Other LUT columns and alpha are preserved.',
                on_change=function(hex)
                    -- Only committed color changes invoke this callback; picker preview and cancel do not.
                    state.dirty=true
                    if state.importing then return end -- Preserve the preset's explicit row/master enabled values.
                    if state.features then state.features.primary(target_lut,target_row,hex)end
                    if not state.handle.get(id..'_on')then local ok,err=state.handle.set(id..'_on',true);assert(ok,err)end
                    if not state.handle.get('enabled')then local ok,err=state.handle.set('enabled',true);assert(ok,err)end
                end}
        end
        pages[#pages+1]={id='lut_'..index,name='LUT '..index..' rows',require_confirmation=false,controls=controls}
    end
    if state.features then state.features.pages(catalog,pages)end
    for _,page in ipairs(pages)do page.category=page.category or target:lower()end
    if target=='Armor' and preferences then
        local settings={}
        local owner=api.mods.epic_lut_preferences
        for _,id in ipairs({'menu_key','reset_key'})do
            local control={}
            for k,v in pairs(owner.controls[id])do control[k]=v end
            control.id='general_'..id;control.source_mod_id=owner.id;control.source_control_id=id
            settings[#settings+1]=control
        end
        table.insert(pages,1,{id='general_settings',name='General Settings',category='general',require_confirmation=false,controls=settings})
    end
    state.handle=api.register({id='dbf_'..target:lower()..'_lut_'..string.format('%08x',catalog.identity.target_id or catalog.identity.armor)..'_'..catalog.identity.body,
        name=target=='Helmet' and 'Epic LUT - Helmet' or 'Epic LUT',parent_name=target=='Helmet' and 'Epic LUT' or nil,description='Live float LUT editing for the equipped local '..target:lower()..'.',storage=m.paths and m.paths.storage or nil,categories={{id='general',name='General Settings',style=api.category_page_links and 'page' or nil},{id='quick_load',name='Quick Load'},{id='armor',name='Armor'},{id='helmet',name='Helmet'}},pages=pages})
    if bindings and target=='Armor'then bindings.root_id=state.handle.id end
    if frontend and target=='Armor'then frontend.default_mod_id=state.handle.id end
    -- Legacy row fields remain storage-compatible, but no second color-editing page/layer is exposed.
    if state.features then
        local id='dbf_'..target:lower()..'_lut_'..string.format('%08x',catalog.identity.target_id or catalog.identity.armor)..'_'..catalog.identity.body
        local mod=api.mods[id];local visible={}
        for _,page in ipairs(mod.pages)do if not page.id:match('^lut_')then visible[#visible+1]=page end end
        mod.pages=visible;api.revision=api.revision+1
    end
    -- Registration does not invoke callbacks. Read all restored settings through the same handle.
    state.dirty=true;note('MCM registered '..#catalog.luts..' LUT pages')
    if state.features then state.features.attach(catalog)end
    if state.provider_menu then state.provider_menu.poll(api)end
    return true
end
local function matching_conflict()
    local options=rawget(_G,'ModOptionsMenu')
    if options and type(options.get)=='function' then
        local ok,value=pcall(options.get,'cowboybingus.match_your_colors.mode')
        if ok and value==(target=='Helmet' and 2 or 3) then return true end -- Armor Matches Helmet owns armor bindings.
    end
    return false
end
local function snapshot()
    local identity,why=m.avatar.resolve(state.memory,state.game,state.reader)
    if not identity then return nil,why end
    local copy={};for k,v in pairs(identity)do copy[k]=v end;identity=copy
    identity.target_kind=target:lower();identity.target_id=target=='Helmet' and identity.helmet or identity.armor
    local units=m.avatar.units(state.memory,identity,nil,target=='Helmet' and 0 or 2,target=='Helmet' and 0 or 9)
    return {identity=identity,units=units,signature=key(identity,units)}
end
local function update()
    state.frame=state.frame+1
    if state.halted then return end
    local now=snapshot()
    if not now then
        state.job=nil;state.catalog.close();assert(state.session.restore(),'Waiting for restoration');state.signature=nil;unregister();return
    end
    if state.signature~=now.signature then
        assert(state.session.restore(),'Equipment-change restoration pending');state.catalog.close();unregister()
        state.signature=now.signature;state.result=nil
        state.job=coroutine.create(function()return state.catalog.load(now.identity,coroutine.yield)end)
        note('Discovering equipped '..target:lower()..' '..string.format('%08x',now.identity.target_id or now.identity.armor))
    end
    if state.job then
        local started=state.memory.time()
        local resumes=0
        repeat
            if ctx.phase then ctx.phase(target..' discovery: '..(state.catalog.phase or 'begin'))end
            local ok,result=coroutine.resume(state.job);assert(ok,result)
            resumes=resumes+1
            if coroutine.status(state.job)=='dead' then
                state.job=nil;state.result=result;if m.diagnostic_without_menu then note('DIAGNOSTIC: '..target..' catalog complete; menu and native application withheld');if ctx.phase then ctx.phase(target..' no-menu catalog complete')end end;break
            end
        until resumes>=8 or state.memory.time()-started>=0.0015
    end
    if state.result and register(state.result) then
        if state.provider_menu then state.provider_menu.poll(state.api)end
        if state.features and state.features.tick()then state.dirty=true;return end
        if matching_conflict()then
            assert(state.session.restore(),'Writer-conflict restoration pending')
            if not state.blocked_writer then note('Editing paused: Match Your Colors owns the selected target LUTs. Its setting has not been changed.')end
            state.blocked_writer=true;return
        elseif state.blocked_writer then state.blocked_writer=false;state.dirty=true end
    end
    if state.result and state.handle and state.dirty then
        for _,kind in ipairs({'armor','helmet'})do local owner=package.loaded['dbf.'..kind..'_lut_editor.owner.v1'];if not owner or not owner.result then return end end
        if m.diagnostic_discovery_only then
            if not state.diagnostic_reported then
                state.diagnostic_reported=true
                note('DIAGNOSTIC: discovery and menu ready; native binding capture and texture writes withheld')
                if ctx.phase then ctx.phase(target..' discovery-only: menu ready; native application withheld')end
            end
            return
        end
        if state.handle.get('enabled') then
            if #state.session.bindings==0 then state.session.capture(state.result,now.units)end
            state.session.apply(state.handle,state.features and state.features.compose());note('Applied LUT edits; original bindings retained')
        else
            assert(state.session.restore(),'Restoration pending')
            -- Retake original bindings before the next enabled edit.
            state.session.capture(state.result,now.units);note('Original '..target:lower()..' bindings active ('..#state.session.bindings..' material bindings)')
        end
        state.dirty=false
    end
    -- Readback on idle detects a competing writer or regenerated material without continually fighting it.
    if state.frame%30==0 and state.handle and state.handle.get('enabled')then
        for _,b in ipairs(state.session.bindings)do
            if state.native.alive(b.unit)==0 then state.signature=nil;break end
        end
    end

end
local function close()
    if not state then return true end
    state.closing=true;state.job=nil;state.catalog.close()
    local ok,result=pcall(state.session.restore)
    if not ok or result~=true then note('Cleanup restoration pending: '..tostring(result));return false end
    unregister();if package.loaded[OWNER]==state then package.loaded[OWNER]=nil end
    note('Disabled; original bindings restored, immutable resources retained until process exit');state=nil;return true
end
return {name='Epic LUT',author='Goose',
    on_enable=function(context)
        ctx=context;assert(not package.loaded[OWNER],'Armor editor already active or retiring')
        local memory=m.bingus_memory.new(m.bingus_runtime)
        local ok,why=memory.verify_build({exe_sha256='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
            game_sha256='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E'});assert(ok,why)
        local game=memory.address(assert(memory.module('game.dll')));local exe=memory.address(assert(memory.module()))
        local native=assert(m.engine.open(memory,game,exe))
        state={target_kind=target:lower(),memory=memory,game=game,native=native,reader=m.avatar.reader(memory),frame=0,dirty=false}
        state.catalog=m.catalog.new(m,memory,game,target,ctx.phase and function(stage)ctx.phase(target..' discovery: '..stage)end);state.session=m.session.new(m,memory,native,retained);package.loaded[OWNER]=state
        if m.editor_features and not m.diagnostic_without_menu then state.features=m.editor_features.new(m,state,context,note)end
        if m.provider_menu and not m.diagnostic_without_menu and target=='Armor' then state.provider_menu=m.provider_menu.new()end
        context.on_cleanup(close);note('Native contracts verified; waiting for local armor and MCM')
    end,
    on_update=function()
        if not state or state.closing then return end
        local ok,why=pcall(update)
        if not ok then
            state.job=nil;state.catalog.close();local restored=state.session.restore()
            state.halted=true;note('Paused: '..tostring(why)..'; restoration '..tostring(restored))
        end
    end,
    on_disable=close,
    on_cleanup_poll=close}

end
local armor=create('Armor')
local helmet=create('Helmet')
return {name='Epic LUT',author='Goose',
 on_enable=function(ctx)if paths_factory then m.paths=paths_factory.new(m);ctx.settings_dir=m.paths.settings;ctx.files_dir=m.paths.files;ctx.presets_dir=m.paths.presets;preferences=m.preferences.new(m.paths.storage);if m.native_import.configure then m.native_import.configure(m,m.paths.cache,{bundle_dir=ctx.dir})end end;if m.frontend and not m.diagnostic_without_menu then local created=m.frontend.new(m,ctx);frontend=created;ctx.on_cleanup(function()return created.close()end)end;if frontend then frontend.preferences=preferences end;if m.bindings and frontend and preferences and not m.diagnostic_registry_only and not m.diagnostic_readonly_menu and not m.diagnostic_without_binding_adapter and not m.direct_menu_keys then bindings=m.bindings.new(m,frontend,preferences,ctx)end;ctx.log('Epic LUT diagnostic identity: '..(m.grouped_colors and 'grouped-colors' or m.alpha_ui and 'alpha-ui' or m.diagnostic_texture_application and 'direct-f10-textures' or m.diagnostic_without_binding_adapter and 'direct-f10' or m.diagnostic_interactive_menu and 'interactive-menu' or m.diagnostic_readonly_menu and 'readonly-menu' or m.diagnostic_idle_poll and 'idle-poll-only' or m.diagnostic_input_library and 'input-library-only' or m.diagnostic_registry_only and 'registry-only' or m.diagnostic_without_menu and 'discovery-no-menu' or m.diagnostic_discovery_only and 'discovery-only' or m.direct_menu_keys and 'direct-keyboard' or 'full-editor'));armor.on_enable(ctx);helmet.on_enable(ctx)end,
 on_update=function(ctx,dt)armor.on_update(ctx,dt);helmet.on_update(ctx,dt);if frontend then frontend.tick(dt)end;if bindings then bindings.tick()end end,
 on_disable=function(ctx)if bindings then bindings.close()end;if preferences then preferences.close()end;local f=not frontend or frontend.close();local h=helmet.on_disable(ctx);local a=armor.on_disable(ctx);return f and h==true and a==true end,
 on_cleanup_poll=function(ctx)if bindings then bindings.close()end;if preferences then preferences.close()end;local f=not frontend or frontend.close();local h=helmet.on_cleanup_poll(ctx);local a=armor.on_cleanup_poll(ctx);return f and h==true and a==true end}
