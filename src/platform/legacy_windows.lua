-- Shared Windows declarations for menu, paths and import launch.
local W={}
function W.verify_interface()
    local ffi=require('ffi')
    if not pcall(ffi.typeof,'epic_native_hwnd')then ffi.cdef('typedef void *epic_native_hwnd;')end
    local user=ffi.load('user32');local kernel=ffi.load('kernel32')
    for _,entry in ipairs({
        {user,'epic_native_foreground','epic_native_hwnd epic_native_foreground(void) __asm__("GetForegroundWindow");'},
        {kernel,'epic_native_pid','uint32_t epic_native_pid(void) __asm__("GetCurrentProcessId");'},
        {user,'epic_native_window_pid','uint32_t epic_native_window_pid(epic_native_hwnd,uint32_t *) __asm__("GetWindowThreadProcessId");'},
        {user,'epic_native_allow_foreground','int epic_native_allow_foreground(uint32_t) __asm__("AllowSetForegroundWindow");'}
        ,{kernel,'epic_native_attributes','uint32_t epic_native_attributes(const uint16_t *) __asm__("GetFileAttributesW");'}
        ,{kernel,'epic_native_wide','int epic_native_wide(uint32_t,uint32_t,const char *,int,uint16_t *,int) __asm__("MultiByteToWideChar");'}
        ,{kernel,'epic_native_move','int epic_native_move(const uint16_t *,const uint16_t *,uint32_t) __asm__("MoveFileExW");'}
        ,{kernel,'epic_native_mkdir','int epic_native_mkdir(const uint16_t *,void *) __asm__("CreateDirectoryW");'}
        ,{kernel,'epic_native_utf8','int epic_native_utf8(uint32_t,uint32_t,const uint16_t *,int,char *,int,const char *,int *) __asm__("WideCharToMultiByte");'}
    })do
        if not pcall(function()return entry[1][entry[2]]end)then ffi.cdef(entry[3])end
        assert(entry[1][entry[2]],'Native import Windows API unavailable: '..entry[2])
    end
    return user,kernel
end
function W.launch_worker(args,folder)
    local ffi=require('ffi');local _,kernel=W.verify_interface()
    if not pcall(ffi.typeof,'epic_process_startup2')then ffi.cdef([[
        typedef struct {
            uint32_t size;uint16_t *reserved,*desktop,*title;
            uint32_t x,y,width,height,columns,rows,fill,flags;
            uint16_t show,reserved_size;uint8_t *reserved_bytes;
            void *input,*output,*error;
        } epic_process_startup2;
        typedef struct {void *process,*thread;uint32_t pid,tid;} epic_process_info2;
        int epic_process_create2(const uint16_t *,uint16_t *,void *,void *,int,uint32_t,void *,const uint16_t *,epic_process_startup2 *,epic_process_info2 *) __asm__("CreateProcessW");
        uint32_t epic_process_system2(uint16_t *,uint32_t) __asm__("GetSystemDirectoryW");
        uint32_t epic_process_error2(void) __asm__("GetLastError");
        uint32_t epic_process_wait2(void *,uint32_t) __asm__("WaitForSingleObject");
        int epic_process_stop2(void *,uint32_t) __asm__("TerminateProcess");
        int epic_process_close2(void *) __asm__("CloseHandle");
    ]])end
    local function wide(text)
        assert(type(text)=='string' and not text:find('\0',1,true),'Invalid worker command')
        local n=kernel.epic_native_wide(65001,8,text,-1,nil,0);assert(n>0 and n<=32767,'Worker command exceeds Windows limit')
        local out=ffi.new('uint16_t[?]',n);assert(kernel.epic_native_wide(65001,8,text,-1,out,n)==n);return out,n
    end
    -- ShellExecuteEx enters shell/COM handlers on the game thread. The hung
    -- Load Current Gear dump stops inside that call. Launch this known executable
    -- directly; no shell extensions, file associations or shell message pump.
    local system=ffi.new('uint16_t[32768]');local count=tonumber(kernel.epic_process_system2(system,32768))
    assert(count>0 and count<32768,'Windows system directory unavailable')
    local suffix=wide('\\WindowsPowerShell\\v1.0\\powershell.exe')
    local suffix_count=0;while suffix[suffix_count]~=0 do suffix_count=suffix_count+1 end
    local file=ffi.new('uint16_t[?]',count+suffix_count+1)
    ffi.copy(file,system,count*2);ffi.copy(file+count,suffix,(suffix_count+1)*2)
    local command=ffi.new('uint16_t[?]',count+suffix_count+3)
    command[0]=34;ffi.copy(command+1,file,(count+suffix_count)*2);command[count+suffix_count+1]=34
    local parameters,param_count=wide(' '..args)
    local length=count+suffix_count+2
    assert(length+param_count<=32767,'Worker command exceeds Windows limit')
    local line=ffi.new('uint16_t[?]',length+param_count)
    ffi.copy(line,command,length*2);ffi.copy(line+length,parameters,param_count*2)
    local directory=wide(folder)
    local startup,info=ffi.new('epic_process_startup2'),ffi.new('epic_process_info2')
    startup.size=ffi.sizeof(startup);startup.flags=1;startup.show=0
    -- Mutable UTF-16 command line, hidden console, no inherited handles.
    local started=kernel.epic_process_create2(file,line,nil,nil,0,0x08000000,nil,directory,startup,info)
    assert(started~=0,'Windows could not start worker: '..tonumber(kernel.epic_process_error2()))
    kernel.epic_process_close2(info.thread)
    local self={handle=info.process,pid=tonumber(info.pid)}
    function self.running()return self.handle~=nil and kernel.epic_process_wait2(self.handle,0)==258 end
    function self.stop()if self.running()and kernel.epic_process_stop2(self.handle,1)==0 and self.running()then return false,'Could not stop owned import worker'end;return true end
    function self.close()if self.handle~=nil then kernel.epic_process_close2(self.handle);self.handle=nil end end
    return self
end
function W.game_data()
    local ffi=require('ffi');local _,kernel=W.verify_interface()
    if not pcall(function()return kernel.epic_worker_module_file end)then ffi.cdef('uint32_t epic_worker_module_file(void *,uint16_t *,uint32_t) __asm__("GetModuleFileNameW");')end
    local path=ffi.new('uint16_t[32768]');local count=tonumber(kernel.epic_worker_module_file(nil,path,32768));assert(count>0 and count<32768,'Game executable path unavailable')
    local length=kernel.epic_native_utf8(65001,0,path,count,nil,0,nil,nil);local bytes=ffi.new('char[?]',length+1);assert(kernel.epic_native_utf8(65001,0,path,count,bytes,length,nil,nil)==length)
    local exe=ffi.string(bytes,length):gsub('\\','/');local parent=assert(exe:match('^(.*)/[^/]+$'))
    if parent:lower():match('/bin$')then parent=parent:sub(1,-5)end
    return parent..'/data'
end
function W.files(folder,filter)
    local ffi=require('ffi');local _,kernel=W.verify_interface()
    if not pcall(ffi.typeof,'epic_find_data')then ffi.cdef([[
        typedef struct {uint32_t header[11];uint16_t name[260],alternate[14];} epic_find_data;
        void *epic_find_first(const uint16_t *,epic_find_data *) __asm__("FindFirstFileW");
        int epic_find_next(void *,epic_find_data *) __asm__("FindNextFileW");
        int epic_find_close(void *) __asm__("FindClose");
    ]])end
    local pattern=folder..'/'..filter;local n=kernel.epic_native_wide(65001,8,pattern,-1,nil,0);local wide=ffi.new('uint16_t[?]',n);assert(kernel.epic_native_wide(65001,8,pattern,-1,wide,n)==n)
    local data=ffi.new('epic_find_data');local handle=kernel.epic_find_first(wide,data)
    if ffi.cast('intptr_t',handle)==-1 then return {}end
    local names={};local ok,why=pcall(function()
        repeat
            local length=kernel.epic_native_utf8(65001,0,data.name,-1,nil,0,nil,nil)
            if length>0 then local bytes=ffi.new('char[?]',length);kernel.epic_native_utf8(65001,0,data.name,-1,bytes,length,nil,nil)
                local name=ffi.string(bytes);names[#names+1]=name
            end
        until kernel.epic_find_next(handle,data)==0
    end)
    kernel.epic_find_close(handle);assert(ok,why);table.sort(names);return names
end
function W.replace(source,destination,verify)
    local ffi=require('ffi')
    local _,kernel=(verify or W.verify_interface)()
    local function wide(text)
        local n=kernel.epic_native_wide(65001,8,text,-1,nil,0);assert(n>0)
        local out=ffi.new('uint16_t[?]',n)
        assert(kernel.epic_native_wide(65001,8,text,-1,out,n)==n)
        return out
    end
    return kernel.epic_native_move(wide(source),wide(destination),1)~=0
end
function W.row_presets(folder)
    local names={};for _,file in ipairs(W.files(folder,'row-*.dds'))do local name=file:match('^row%-([%w _-]+)%.dds$');if name then names[#names+1]=name end end;return names
end
return W
