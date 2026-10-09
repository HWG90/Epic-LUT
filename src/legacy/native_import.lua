-- Fixed local file IPC; native dialog runs outside the game/render thread.
local N={}
local requests=package.loaded['dbf.epic_lut.requests.v1']or {sequence=0};package.loaded['dbf.epic_lut.requests.v1']=requests
local function json(value,depth)
    depth=depth or 0;assert(depth<16,'Discovery metadata nesting exceeded')
    if type(value)=='string'then return '"'..value:gsub('[%z\1-\31\\"]',function(c)if c=='"'then return '\\"'elseif c=='\\'then return '\\\\'end;return string.format('\\u%04x',c:byte())end)..'"'end
    if type(value)=='number'then assert(value==value and math.abs(value)<2^53);return string.format('%.0f',value)end
    if type(value)=='table'then local parts={};if #value>0 then for _,v in ipairs(value)do parts[#parts+1]=json(v,depth+1)end;return '['..table.concat(parts,',')..']'end
        for key,v in pairs(value)do assert(type(key)=='string');parts[#parts+1]=json(key,depth+1)..':'..json(v,depth+1)end;return '{'..table.concat(parts,',')..'}'end
    error('Unsupported discovery metadata',0)
end
function N.configure(model,cache,options)N.model=model;N.cache=cache;N.options=options or {};N.port=N.options.port or 8765;assert(type(N.port)=='number'and N.port%1==0 and N.port>0 and N.port<65536)end
N.verify_interface=(m and m.windows or dofile('src/platform/windows.lua')).verify_interface
function N.new(folder,kind)
    local self={folder=folder,choices={},labels={'Import a file first'},session=nil,last=nil,sequence=0}
    local ffi=require('ffi')
    local user,kernel=N.verify_interface()
    local path=folder..'/apply.lock';local count=kernel.epic_native_wide(65001,8,path,-1,nil,0);assert(count>0,'Invalid native import folder')
    local wide=ffi.new('uint16_t[?]',count);assert(kernel.epic_native_wide(65001,8,path,-1,wide,count)==count)
    function self.locked()return tonumber(kernel.epic_native_attributes(wide))~=4294967295 end
    local function path_wide(text)local n=kernel.epic_native_wide(65001,8,text,-1,nil,0);assert(n>0);local value=ffi.new('uint16_t[?]',n);assert(kernel.epic_native_wide(65001,8,text,-1,value,n)==n);return value end
    local function game_data_folder()
        local data,count=N.model.files.game_data_folder()
        local length=kernel.epic_native_utf8(65001,0,data,count,nil,0,nil,nil);assert(length>0)
        local bytes=ffi.new('char[?]',length)
        assert(kernel.epic_native_utf8(65001,0,data,count,bytes,length,nil,nil)==length)
        return ffi.string(bytes,length)
    end
    local function read(path)local f=io.open(path,'rb');if not f then return nil end;local s=f:read(8193)or '';f:close();assert(#s<=8192,'Native import result too large');return s end
    local function ready()local value=tonumber(read(folder..'/native-ready.txt'));return value and math.abs(os.time()-value)<5 and (not N.model or not N.model.service_files or read(folder..'/native-version.txt')=='archive-worker-v4')end
    local function launch()
        if ready()then return end
        assert(N.model and N.cache,'Automatic file service is unavailable in this build')
        self.start_error=N.cache..'/file-service/dist/companion/startup-error.log'
        if N.started and os.time()-N.started<30 then return end
        local root=N.cache..'/file-service'
        kernel.epic_native_mkdir(path_wide(root),nil)
        for _,sub in ipairs({'tools','companion','dist','dist/companion'})do kernel.epic_native_mkdir(path_wide(root..'/'..sub),nil)end
        for name,hex in pairs(N.model.service_files)do
            local f=assert(io.open(root..'/'..name,'wb'));assert(f:write((hex:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end))));assert(f:close())
        end
        os.remove(self.start_error)
        local shell=ffi.load('shell32')
        if not pcall(function()return shell.epic_native_launch end)then ffi.cdef('void *epic_native_launch(void *,const uint16_t *,const uint16_t *,const uint16_t *,const uint16_t *,int) __asm__("ShellExecuteW");')end
        assert(not root:find('"',1,true)and not folder:find('"',1,true),'Invalid file service path')
        local args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'..root..'/start_editor.ps1" -Workspace "'..folder..'" -Port '..N.port
        if N.model.runtime_hash then
            assert(N.model.runtime_hash:match('^[a-f0-9]+$')and #N.model.runtime_hash==64,'Invalid bundled runtime identity')
            local game_data=N.options.game_data or ''
            if game_data==''and N.model.files then
                game_data=game_data_folder():gsub('\\','/'):gsub('/+$','')
            end
            local bundle=N.options.bundle_dir or ''
            assert(not game_data:find('"',1,true)and not bundle:find('"',1,true),'Invalid bundled runtime path')
            args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'..root..'/tools/start_bundled.ps1" -RuntimeHash '..N.model.runtime_hash..' -BundleDirectory "'..bundle..'" -GameData "'..game_data..'" -Workspace "'..folder..'" -Port '..N.port
            if N.model.flat_manifest_hash then assert(N.model.flat_manifest_hash:match('^[a-f0-9]+$')and #N.model.flat_manifest_hash==64);args=args..' -FlatManifestHash '..N.model.flat_manifest_hash end
        end
        local protocol=read(folder..'/native-version.txt');if protocol and protocol~='archive-worker-v4'then args=args..' -RestartOwn'end
        args=args..' -OwnerPID '..tostring(N.options.owner_pid or tonumber(kernel.epic_native_pid()))
        local result=shell.epic_native_launch(nil,path_wide('open'),path_wide('powershell.exe'),path_wide(args),path_wide(root),0)
        assert(tonumber(ffi.cast('uintptr_t',result))>32,'Windows could not start the file service')
        N.started=os.time()
    end
    local function send()
        if not self.queued then return end
        if not ready()then return end
        local helper=tonumber(read(folder..'/native-pid.txt'));if helper then self.helper_pid=helper;if self.queued.action=='pick'then user.epic_native_allow_foreground(helper)end end
        if kernel.epic_native_move(self.queued.temp,self.queued.path,1)~=0 then self.queued=nil end
    end
    local function request(action,extra)
        launch();requests.sequence=requests.sequence+1;local id=tostring(os.time())..kind..tostring(requests.sequence)
        local path=folder..'/native-'..kind..'.request';local f=assert(io.open(path..'.tmp','wb'));assert(f:write('{"id":"'..id..'","action":"'..action..'"'..(extra or '')..'}'));assert(f:close());self.queued={temp=path_wide(path..'.tmp'),path=path_wide(path),started=os.time(),action=action};self.pending=id;self.helper_pid=tonumber(read(folder..'/native-pid.txt'));send();return id
    end
    function self.discover(kit,body,target)
        assert(not self.pending,'Previous discovery is still pending')
        return request('catalog',',"data_folder":'..json(game_data_folder())..',"kit":'..json(kit)..',"body":'..json(body)..',"kind":'..json(target))
    end
    function self.pick()
        assert(not self.pending,'The previous native import is still pending')
        local hwnd=user.epic_native_foreground();local pid=tonumber(kernel.epic_native_pid());local actual=ffi.new('uint32_t[1]');user.epic_native_window_pid(hwnd,actual)
        assert(actual[0]==pid,'Keep the game focused and open the picker again')
        local helper=tonumber(read(folder..'/native-pid.txt'));if helper then user.epic_native_allow_foreground(helper)end
        request('pick',',"owner":'..string.format('%.0f',tonumber(ffi.cast('uintptr_t',hwnd)))..',"pid":'..pid)
        return 'Windows file picker opening. Choose a file or Cancel; no palette is applied yet.'
    end
    function self.apply(index)
        assert(not self.pending,'The previous native import is still pending');local key=assert(self.choices[index],'Import a file and choose a target first')
        assert(key:match('^[%w_-]+$')and self.session,'Invalid import target')
        request('apply',',"session":"'..self.session..'","target":"'..key..'"')
        return 'Applying validated palette to '..self.labels[index]
    end
    function self.quick_apply(target,material,emission)
        assert(not self.pending,'The previous import is still pending');assert(self.session,'Choose a file in Quick Load first');assert(target=='armor'or target=='helmet')
        request('quick_apply',',"session":"'..self.session..'","kind":"'..target..'","preserve_material":'..tostring(material==true)..',"preserve_emission":'..tostring(emission==true))
        return 'Quick Load preparing all equipped '..target..' LUTs; unsupported fields will retain originals.'
    end
    function self.poll()
        if self.queued and not ready() and self.start_error then
            local failure=read(self.start_error)
            if failure then
                self.queued=nil;self.pending=nil;N.started=nil
                return (N.model and N.model.system_python and 'System Python service failed to start. Install 64-bit non-Store Python and run setup_companion.ps1 once. Check startup-error.log in Epic LUT cache/file-service/dist/companion.'or 'Bundled file runtime failed to start. Check startup-error.log in Epic LUT cache/file-service/dist/companion; reinstall the complete package if runtime files are missing.'),1,{swatches={}}
            end
        end
        send();if self.queued and os.time()-self.queued.started>30 then self.queued=nil;self.pending=nil;return 'File service could not start. Check Python dependencies and the file-service logs in Epic LUT cache.',1,{swatches={}}end
        local helper=tonumber(read(folder..'/native-pid.txt'))
        if self.helper_pid and helper and self.helper_pid~=helper then self.pending=nil;self.queued=nil;self.did_resume=false;self.helper_pid=helper end
        if kind=='quick'and not self.did_resume and not self.pending and ready()then local ok=pcall(request,'resume');self.did_resume=ok end
        local raw=read(folder..'/native-'..kind..'.result');if not raw or raw==self.last then return nil end;raw=raw:gsub('\r\n','\n')
        local id,message=raw:match('^([^\t\n]+)\t([^\n]*)');if id~=self.pending then return nil end
        self.last=raw;self.pending=nil;self.choices={false};self.labels={'Choose an equipped target'};local selected=1
        self.session=raw:match('\nsession\t([^\n]+)')
        local metadata={file=raw:match('\nfile\t([^\n]+)'),swatches={}}
        metadata.catalog=raw:match('\ncatalog\t([^\n]+)')
        metadata.imported=raw:match('\nimported\t([01])')=='1'
        metadata.rows,metadata.preview=raw:match('\npreview\t(%d+)\t([^\n]+)')
        metadata.applied,metadata.prefix=raw:match('\napplied\t([^\t\n]+)\t([^\n]+)')
        for row,r,g,b in raw:gmatch('\nswatch\t(%d+)\t(%d+)\t(%d+)\t(%d+)')do
            if #metadata.swatches<64 then metadata.swatches[#metadata.swatches+1]={row=tonumber(row),rgb={tonumber(r),tonumber(g),tonumber(b)}}end
        end
        self.metadata=metadata;self.last_message=message
        local exact
        for key,label in raw:gmatch('\ntarget\t([^\t\n]+)\t([^\n]+)')do self.choices[#self.choices+1]=key;self.labels[#self.labels+1]=label end
        exact=raw:match('\nselected\t([^\n]+)')
        for i,key in ipairs(self.choices)do if key==exact then selected=i end end
        if #self.labels==1 then self.labels={'No compatible target — import another file'}end
        return message,selected,metadata
    end
    return self
end
return N
