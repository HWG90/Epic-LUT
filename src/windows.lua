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
    local ffi=require('ffi');local _,kernel=W.verify_interface();local shell=ffi.load('shell32')
    if not pcall(ffi.typeof,'epic_worker_execute')then ffi.cdef([[
        typedef struct {uint32_t size,mask;void *window;const uint16_t *verb,*file,*args,*directory;int show;void *instance,*list;const uint16_t *class_name;void *class_key;uint32_t hotkey;void *icon,*process;} epic_worker_execute;
        int epic_worker_shell(epic_worker_execute *) __asm__("ShellExecuteExW");
        uint32_t epic_worker_pid(void *) __asm__("GetProcessId");
        uint32_t epic_worker_wait(void *,uint32_t) __asm__("WaitForSingleObject");
        int epic_worker_stop(void *,uint32_t) __asm__("TerminateProcess");
        int epic_worker_close(void *) __asm__("CloseHandle");
    ]])end
    local function wide(text)local n=kernel.epic_native_wide(65001,8,text,-1,nil,0);assert(n>0);local out=ffi.new('uint16_t[?]',n);assert(kernel.epic_native_wide(65001,8,text,-1,out,n)==n);return out end
    local file,parameters,directory,verb=wide('powershell.exe'),wide(args),wide(folder),wide('open')
    local info=ffi.new('epic_worker_execute');info.size=ffi.sizeof(info);info.mask=0x40;info.file=file;info.args=parameters;info.directory=directory;info.verb=verb;info.show=0
    assert(shell.epic_worker_shell(info)~=0 and info.process~=nil,'Windows could not start file import')
    local self={handle=info.process,pid=tonumber(kernel.epic_worker_pid(info.process))}
    function self.running()return self.handle~=nil and kernel.epic_worker_wait(self.handle,0)==258 end
    function self.stop()if self.running()then assert(kernel.epic_worker_stop(self.handle,1)~=0,'Could not stop owned import worker')end end
    function self.close()if self.handle~=nil then kernel.epic_worker_close(self.handle);self.handle=nil end end
    return self
end
function W.row_presets(folder)
    local ffi=require('ffi');local _,kernel=W.verify_interface()
    if not pcall(ffi.typeof,'epic_find_data')then ffi.cdef([[
        typedef struct {uint32_t header[11];uint16_t name[260],alternate[14];} epic_find_data;
        void *epic_find_first(const uint16_t *,epic_find_data *) __asm__("FindFirstFileW");
        int epic_find_next(void *,epic_find_data *) __asm__("FindNextFileW");
        int epic_find_close(void *) __asm__("FindClose");
    ]])end
    local pattern=folder..'/row-*.dds';local n=kernel.epic_native_wide(65001,8,pattern,-1,nil,0);local wide=ffi.new('uint16_t[?]',n);assert(kernel.epic_native_wide(65001,8,pattern,-1,wide,n)==n)
    local data=ffi.new('epic_find_data');local handle=kernel.epic_find_first(wide,data)
    if ffi.cast('intptr_t',handle)==-1 then return {}end
    local names={};local ok,why=pcall(function()
        repeat
            local length=kernel.epic_native_utf8(65001,0,data.name,-1,nil,0,nil,nil)
            if length>0 then local bytes=ffi.new('char[?]',length);kernel.epic_native_utf8(65001,0,data.name,-1,bytes,length,nil,nil)
                local name=ffi.string(bytes):match('^row%-([%w _-]+)%.dds$');if name then names[#names+1]=name end
            end
        until kernel.epic_find_next(handle,data)==0
    end)
    kernel.epic_find_close(handle);assert(ok,why);table.sort(names);return names
end
return W
