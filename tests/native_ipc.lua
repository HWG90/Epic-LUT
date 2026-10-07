local ffi=require('ffi')
-- Simulate an earlier module's declarations surviving a game-side hot reload.
ffi.cdef([[typedef void *epic_native_hwnd;
epic_native_hwnd epic_native_foreground(void) __asm__("GetForegroundWindow");
uint32_t epic_native_pid(void) __asm__("GetCurrentProcessId");
uint32_t epic_native_window_pid(epic_native_hwnd,uint32_t *) __asm__("GetWindowThreadProcessId");]])
local N=dofile('src/native_import.lua');local user,kernel=N.verify_interface()
assert(user.epic_native_allow_foreground and tonumber(kernel.epic_native_pid())>0)
assert(N.verify_interface()) -- repeated module initialization is safe.
local client=N.new('tests/tmp/files','armor')
local empty=assert(io.open('tests/tmp/files/native-ready.txt','wb'));empty:close()
empty=assert(io.open('tests/tmp/files/native-armor.result','wb'));empty:close()
assert(client.poll()==nil,'Empty status/result file halted polling')
local f=assert(io.open('tests/tmp/files/native-armor.result','wb'));f:write('test1\tImported safely\ntarget\tarmor-a\tArmor resource A\ntarget\tall-armor\tAll compatible armor\nselected\tarmor-a\nsession\ttest1\n');f:close()
client.pending='test1';client.session='test1';local message,index=client.poll();assert(message=='Imported safely'and index==2 and client.choices[2]=='armor-a')
assert(not pcall(client.apply,1),'No-target placeholder was applicable')
f=assert(io.open('tests/tmp/files/native-ready.txt','wb'));f:write(tostring(os.time()));f:close()
assert(client.apply(3));f=assert(io.open('tests/tmp/files/native-armor.request'));local request=f:read('*a');f:close();assert(request:find('"target":"all%-armor"')and request:find('"session":"test1"'))
print('PASS: retained FFI declarations upgrade, Windows symbol availability, repeated initialization, MCM exact selection, placeholder rejection and bounded apply IPC')
os.remove('tests/tmp/files/native-ready.txt')
local error_path='tests/tmp/files/startup-error.log'
f=assert(io.open(error_path,'wb'));f:write('Python not found.');f:close()
client.session='retained-session';client.pending='startup-request';client.queued={started=os.time()};client.start_error=error_path
local failure=client.poll()
assert(failure:find('Bundled file runtime',1,true)and not client.pending and not client.queued and client.session=='retained-session','Startup failure lost the retained palette or remained pending')
os.remove(error_path)
print('PASS: startup failure is actionable, clears pending work and preserves the retained import session')
