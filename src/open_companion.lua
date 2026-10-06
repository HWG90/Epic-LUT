-- User-invoked URL opening only. No input capture, process injection or shell command construction.
local O={}
function O.open()
    local ffi=require('ffi')
    if not pcall(ffi.typeof,'epic_lut_url_char')then ffi.cdef([[
        typedef uint16_t epic_lut_url_char;
        void *epic_lut_open_url(void *,const epic_lut_url_char *,const epic_lut_url_char *,const epic_lut_url_char *,const epic_lut_url_char *,int) __asm__("ShellExecuteW");
    ]])end
    local function wide(text)local out=ffi.new('uint16_t[?]',#text+1);for i=1,#text do out[i-1]=text:byte(i)end;return out end
    local result=ffi.load('shell32').epic_lut_open_url(nil,wide('open'),wide('http://127.0.0.1:8765'),nil,nil,1)
    assert(tonumber(ffi.cast('uintptr_t',result))>32,'Companion URL could not be opened')
    return 'Local DDS/EXR/ZIP/RAR picker opened. Start the companion first if it is not running.'
end
return O
