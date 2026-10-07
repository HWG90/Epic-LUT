-- HD2-Addon: mods/goose/epic_lut/startup
-- Same editor model and automatic frontend as the loose entrypoint.
if package.loaded['dbf.armor_lut_editor.owner.v1']or package.loaded['dbf.epic_lut.frontend.v1']then return {duplicate=true}end
local ffi=require('ffi')
pcall(ffi.cdef,[[
 int epic_boot3_wide(uint32_t,uint32_t,const char *,int,uint16_t *,int) __asm__("MultiByteToWideChar");
 int epic_boot3_mkdir(const uint16_t *,void *) __asm__("CreateDirectoryW");
 uint32_t epic_boot3_attr(const uint16_t *) __asm__("GetFileAttributesW");
]])
local kernel=ffi.load('kernel32')
local function wide(text)local n=kernel.epic_boot3_wide(65001,8,text,-1,nil,0);assert(n>0);local out=ffi.new('uint16_t[?]',n);assert(kernel.epic_boot3_wide(65001,8,text,-1,out,n)==n);return out end
local base=assert(os.getenv('LOCALAPPDATA'))
for _,part in ipairs({'Epic LUT','cache'})do base=base..'/'..part;kernel.epic_boot3_mkdir(wide(base),nil);assert(kernel.epic_boot3_attr(wide(base))~=0xffffffff,'Epic LUT runtime folder unavailable')end
-- Durable data folders are created by the shared paths service.
local native_name='__NATIVE_NAME__';local hex='__NATIVE_HEX__'
local payload=hex:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end)
local path=base..'/'..native_name;local existing=io.open(path,'rb')
if existing then local bytes=existing:read('*a');existing:close();assert(bytes==payload,'A different input runtime is already present; refusing replacement')
else local file=assert(io.open(path,'wb'));assert(file:write(payload));assert(file:close())end
local make_descriptor=function()
-- __MODULE__
end
local ctx={api=2,dir=base,cleanups={},globals={}}
function ctx.log(message)local file=io.open(base..'/Epic-LUT-startup.log','a');if file then file:write(tostring(message),'\n');file:close()end end
function ctx.on_cleanup(fn)ctx.cleanups[#ctx.cleanups+1]=fn end
function ctx.global(name,value)ctx.globals[name]={previous=rawget(_G,name),owned=value};rawset(_G,name,value);return value end
local bridge=(function()
-- __BRIDGE__
end)()
return bridge.after_startup(make_descriptor,ctx)
