-- Standalone LLL/MDL lifecycle; MCM is the sole authoritative settings owner.
local ffi=require('ffi')
local state,ctx
local OWNER='dbf.armor_lut_editor.owner.v1'
local RETAIN='dbf.armor_lut_editor.retained.v1'
local retained=package.loaded[RETAIN] or {records={},bytes=0};package.loaded[RETAIN]=retained
local function note(message)if ctx then ctx.log('Epic LUT: '..tostring(message))end end
local function key(identity,units)
    local parts={identity.player,identity.avatar,identity.armor,identity.body,identity.units_at}
    for _,u in ipairs(units)do parts[#parts+1]=u.type..':'..u.slot..':'..u.unit end
    return table.concat(parts,':')
end
local function unregister()
    if state.handle then state.handle.unregister();state.handle=nil end
    state.api=nil
end
local function register(catalog)
    local api=rawget(_G,'DBFMCM');if not api then return false end
    if state.api==api and state.handle then return true end
    unregister();state.api=api
    local pages={{id='session',name='Equipped armor',require_confirmation=false,controls={
        {type='text',label='Armor '..string.format('%08x',catalog.identity.armor)..' - local equipped armor only'},
        {type='text',label='Numbered LUT rows have unknown surface mapping. Primary-color RGB only.'},
        {id='enabled',type='toggle',label='Apply row colors live',default=false,on_change=function()state.dirty=true end},
        {id='reset',type='button',label='Restore original armor colors',on_activate=function()
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
            note('Custom LUT rows reset from preserved originals');return 'Custom LUT rows reset to original colors'
        end},
        {id='refresh',type='button',label='Refresh equipped armor',on_activate=function()state.signature=nil end}
    }}}
    pages[1].controls[#pages[1].controls+1]={id='preset_file',type='input',label='Preset filename (without .dbflut)',default='preset',description='Files live in the Epic LUT mod folder / presets. Simple filenames only.'}
    pages[1].controls[#pages[1].controls+1]={id='export',type='button',label='Export armor preset',on_activate=function()
        local path=m.presets.export(ctx.dir..'/presets',catalog,state.handle)
        local name=assert(path:match('/([^/]+)%.dbflut$'));local ok,err=state.handle.set('preset_file',name);assert(ok,err)
        note('Exported preset: '..path);return 'Exported: '..path
    end}
    pages[1].controls[#pages[1].controls+1]={id='import',type='button',label='Import armor preset',on_activate=function()
        assert(type(state.handle.set_many)=='function','MCM batch-settings update required for atomic import')
        local values=m.presets.read(ctx.dir..'/presets',state.handle.get('preset_file')..'.dbflut',catalog)
        state.importing=true
        local called,ok,err=pcall(state.handle.set_many,values)
        state.importing=false;assert(called and ok,tostring(called and err or ok))
        state.dirty=true;note('Validated preset imported in one settings commit');return 'Preset imported'
    end}
    for index,lut in ipairs(catalog.luts)do
        local controls={{type='text',label='LUT '..index..' - '..lut.name..' - '..lut.height..' rows'}}
        for row=0,lut.height-1 do
            local id=lut.name..'_r'..(row+1)
            controls[#controls+1]={id=id..'_on',type='toggle',label='Row '..(row+1)..' override',default=false,on_change=function()state.dirty=true end}
            controls[#controls+1]={id=id..'_color',type='color',label='Row '..(row+1)..' primary RGB',default=m.palette.hex(lut.values,row,lut.width),
                description='USE COLOR enables this row and live application, then updates equipped armor. Cancel leaves activation unchanged. Other LUT columns and alpha are preserved.',
                on_change=function()
                    -- Only committed color changes invoke this callback; picker preview and cancel do not.
                    state.dirty=true
                    if state.importing then return end -- Preserve the preset's explicit row/master enabled values.
                    if not state.handle.get(id..'_on')then local ok,err=state.handle.set(id..'_on',true);assert(ok,err)end
                    if not state.handle.get('enabled')then local ok,err=state.handle.set('enabled',true);assert(ok,err)end
                end}
        end
        pages[#pages+1]={id='lut_'..index,name='LUT '..index..' rows',require_confirmation=false,controls=controls}
    end
    state.handle=api.register({id='dbf_armor_lut_'..string.format('%08x',catalog.identity.armor)..'_'..catalog.identity.body,
        name='Epic LUT',description='Live numbered primary-color rows for currently equipped armor.',pages=pages})
    -- Registration does not invoke callbacks. Read all restored settings through the same handle.
    state.dirty=true;note('MCM registered '..#catalog.luts..' LUT pages')
    return true
end
local function matching_conflict()
    local options=rawget(_G,'ModOptionsMenu')
    if options and type(options.get)=='function' then
        local ok,value=pcall(options.get,'cowboybingus.match_your_colors.mode')
        if ok and value==3 then return true end -- Armor Matches Helmet owns armor bindings.
    end
    return false
end
local function snapshot()
    local identity,why=m.avatar.resolve(state.memory,state.game,state.reader)
    if not identity then return nil,why end
    local units=m.avatar.units(state.memory,identity,nil,2,9)
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
        note('Discovering equipped armor '..string.format('%08x',now.identity.armor))
    end
    if state.job then
        local started=state.memory.time()
        repeat
            local ok,result=coroutine.resume(state.job);assert(ok,result)
            if coroutine.status(state.job)=='dead' then
                state.job=nil;state.result=result;state.session.capture(result,now.units);note('Captured '..#state.session.bindings..' armor material bindings');break
            end
        until state.memory.time()-started>=0.0015
    end
    if state.result and register(state.result) and state.dirty then
        assert(not matching_conflict(),'Match Your Colors Armor Matches Helmet is active; set Color Matching to Off or Helmet Matches Armor first')
        if state.handle.get('enabled') then
            if #state.session.bindings==0 then state.session.capture(state.result,now.units)end
            state.session.apply(state.handle);note('Applied row colors; original bindings retained')
        else
            assert(state.session.restore(),'Restoration pending')
            -- Retake original bindings before the next enabled edit.
            state.session.capture(state.result,now.units);note('Original armor bindings active')
        end
        state.dirty=false
    end
    -- Readback on idle detects a competing writer or regenerated material without continually fighting it.
    if state.frame%30==0 and state.handle and state.handle.get('enabled')then
        for _,b in ipairs(state.session.bindings)do
            if state.native.alive(b.unit)==0 then state.signature=nil;break end
        end
    end
    -- Explicit bounded live-test command, issued only by the deployment operator.
    local file=io.open(ctx.dir..'/TEST-ONCE.txt','rb')
    if file and state.result and state.handle then
        local command=file:read('*a');file:close();os.remove(ctx.dir..'/TEST-ONCE.txt')
        if command:match('^restore') then assert(state.handle.set('enabled',false));state.dirty=true
        elseif command:match('^roundtrip') then
            local before=m.presets.encode(state.result,state.handle)
            assert(state.handle.activate('export'));assert(state.handle.activate('reset_rows'));assert(state.handle.activate('import'))
            assert(m.presets.encode(state.result,state.handle)==before,'Live preset round trip mismatch')
            note('Live export/reset/import round trip verified all row colors and activation flags')
        elseif command:match('^export') then assert(state.handle.activate('export'))
        elseif command:match('^import') then assert(state.handle.activate('import'))
        elseif command:match('^reset_rows') then assert(state.handle.activate('reset_rows'))
        elseif command:match('^test') then
            local lut=state.result.luts[1];local id=lut.name..'_r1'
            assert(state.handle.set(id..'_color','#FF00FF'));assert(state.handle.set(id..'_on',true));assert(state.handle.set('enabled',true));state.dirty=true
            note('Bounded magenta row 1 test queued; issue restore after visual inspection')
        end
    elseif file then file:close()end
end
local function close()
    if not state then return true end
    state.closing=true;state.job=nil;state.catalog.close()
    local ok,result=pcall(state.session.restore)
    if not ok or result~=true then note('Cleanup restoration pending: '..tostring(result));return false end
    unregister();if package.loaded[OWNER]==state then package.loaded[OWNER]=nil end
    note('Disabled; original bindings restored, immutable resources retained until process exit');state=nil;return true
end
return {name='Epic LUT',author='David / Nova; LUT discovery and native adapters by CowboyBingus',
    on_enable=function(context)
        ctx=context;assert(not package.loaded[OWNER],'Armor editor already active or retiring')
        local memory=m.bingus_memory.new(m.bingus_runtime)
        local ok,why=memory.verify_build({exe_sha256='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
            game_sha256='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E'});assert(ok,why)
        local game=memory.address(assert(memory.module('game.dll')));local exe=memory.address(assert(memory.module()))
        local native=assert(m.engine.open(memory,game,exe))
        state={memory=memory,game=game,native=native,reader=m.avatar.reader(memory),frame=0,dirty=false}
        state.catalog=m.catalog.new(m,memory,game);state.session=m.session.new(m,memory,native,retained);package.loaded[OWNER]=state
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
