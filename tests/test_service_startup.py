"""Windows integration test: own temporary service, no game or picker interaction."""
import ctypes,json,os,sys,tempfile,socket,time,hashlib,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT));os.chdir(ROOT)
from tools.runtime_paths import lua_library
sys.path.insert(0,str(ROOT/'tests'));from test_game_catalog import fixture
def lua(value):
 if isinstance(value,str):return json.dumps(value)
 if isinstance(value,int):return str(value)
 if isinstance(value,list):return "{"+",".join(lua(v)for v in value)+"}"
 return "{"+",".join("["+lua(k)+"]="+lua(v)for k,v in value.items())+"}"
FILES=['tools/install_flat_runtime.ps1','tools/owner_watch.py','tools/game_catalog.py','tools/start_bundled.ps1','start_editor.ps1','tools/runtime_paths.ps1','tools/deploy_guard.ps1','tools/companion.py','tools/native_import.py','tools/remap.py','tools/lut_files.py','tools/extract_luts.py','tools/runtime_guard.py','tools/runtime_paths.py','companion/index.html']
lib=ctypes.CDLL(str(lua_library()));lib.luaL_newstate.restype=ctypes.c_void_p
for name in ('luaL_openlibs','lua_close'):getattr(lib,name).argtypes=[ctypes.c_void_p]
lib.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
runtime=ROOT/'dist/runtime/runtime.zip';runtime_hash=hashlib.sha256(runtime.read_bytes()).hexdigest()
flat_mode=os.getenv('EPIC_TEST_FLAT_RUNTIME')=='1'
system_mode=os.getenv('EPIC_TEST_SYSTEM_PYTHON')=='1'
assert not(flat_mode and system_mode)
if flat_mode:
 from tools.flat_runtime import flatten
 flat_files,flat_hash=flatten(runtime.read_bytes())
for mode in ('loose','bsl'):
 with tempfile.TemporaryDirectory(prefix='epic-lut-service-test-')as tmp:
  root=Path(tmp);cache=root/'cache';cache.mkdir();folder=root/'files';folder.mkdir()
  with socket.socket()as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
  bundle=root/'bundle';bundle.mkdir();game_data=root/'data';game_data.mkdir()
  if mode!='loose':
   # Arsenal renumbers packages. The runtime may lie beyond sixteen older stream files.
   for index in range(24):(game_data/f'9ba626afa44a3aa3.patch_{index}.stream').write_bytes(b'not the runtime')
  prior_localappdata=os.environ.get('LOCALAPPDATA')
  if system_mode:
   localdata=root/'appdata';localdata.mkdir();os.environ['LOCALAPPDATA']=str(localdata)
   cache=localdata/'Epic LUT/cache';cache.mkdir(parents=True)
   pip_env=os.environ.copy();pip_env.pop('PIP_NO_INDEX',None);pip_env['PIP_FIND_LINKS']=str(ROOT/'dist/runtime-cache/wheels')
   installed=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'setup_companion.ps1'),'-Python',sys.executable],env=pip_env,capture_output=True,text=True)
   assert installed.returncode==0,installed.stdout+installed.stderr
   assert (localdata/'Epic LUT/settings/python-runtime.txt').read_text().strip()==sys.executable
  if flat_mode:
   flat_source=bundle/'runtime';flat_source.mkdir()
   for name,data in flat_files.items():
    path=flat_source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
   if mode=='bsl':
    # Same verified copier used by the one-time BSL installation script, within this test's private root.
    subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'tools/install_flat_runtime.ps1'),'-SourceRuntime',str(flat_source),'-DestinationRuntime',str(cache/('file-service/runtime-'+runtime_hash[:16])),'-RuntimeHash',runtime_hash,'-ManifestHash',flat_hash],check=True,capture_output=True)
  elif not system_mode:
   shutil.copyfile(runtime,bundle/'runtime.zip'if mode=='loose'else game_data/'9ba626afa44a3aa3.patch_999.stream')
  kit,original=fixture(game_data)
  owner=subprocess.Popen([sys.executable,'-c','import time;time.sleep(90)'],creationflags=subprocess.CREATE_NO_WINDOW)
  model='{runtime_hash='+repr(runtime_hash)+',service_files={'+','.join('['+repr(name)+']='+repr((ROOT/name).read_bytes().hex())for name in FILES)+'}}'
  if flat_mode:model=model[:-1]+',flat_manifest_hash='+repr(flat_hash)+'}'
  if system_mode:model=model.replace('runtime_hash='+repr(runtime_hash)+',','system_python=true,')
  code="""local ffi=require('ffi');ffi.cdef('void Sleep(uint32_t);');local kernel=ffi.load('kernel32')
 local N=dofile('src/legacy/native_import.lua');N.configure(MODEL,CACHE,{port=PORT,bundle_dir=BUNDLE,game_data=GAMEDATA,owner_pid=OWNERPID})
 local client=N.new(FOLDER,'armor');client.choices={'fixture'};client.labels={'Fixture'};client.session='test-session'
 assert(client.apply(1));assert(client.pending and client.queued,'Startup did not queue the request')
 local message
 for i=1,170 do kernel.Sleep(200);message=client.poll();if message then break end end
 assert(message,'Automatic service startup timed out');assert(message:find('Import session expired',1,true),message);assert(not client.queued and not client.pending,'Request never reached worker')
 print('PASS automatic file-service startup, queued request publication, worker response and no browser launch')
N.model.files={game_data_folder=function()
 local text=GAMEDATA;local bound=N.verify_interface();local _,bound_kernel=N.verify_interface()
 local n=bound_kernel.epic_native_wide(65001,8,text,-1,nil,0);local wide=ffi.new('uint16_t[?]',n)
 assert(bound_kernel.epic_native_wide(65001,8,text,-1,wide,n)==n);return wide,n-1
end}
local kit=FIXTUREKIT
local memory={time=os.clock,read_into=function(a,n,b)
 assert(n<=ffi.sizeof(b));ffi.fill(b,n);a=tonumber(ffi.cast('uintptr_t',a))
 if a==0x10000+0x33264f8 then ffi.cast('uint64_t *',b)[0]=0x20000
 elseif a==0x20000 then ffi.cast('uint64_t *',b)[0]=0x30000;ffi.cast('uint32_t *',b)[2]=1
 elseif a==0x30000 then ffi.cast('uint64_t *',b)[0]=0x40000
 elseif a==0x40000 then ffi.cast('uint32_t *',b)[0]=123
 else error('Unexpected native snapshot address')end;return true
end}
local m={paths={files=FOLDER},native_import=N,dds=dofile('src/core/dds.lua'),kits={ARMOR='Armor',HELMET='Helmet',read_kit=function()return kit end}}
local catalog=dofile('src/legacy/catalog.lua').new(m,memory,0x10000,'Armor');local result
local job=coroutine.create(function()result=catalog.load({target_id=123,body=0},coroutine.yield)end)
for i=1,170 do local ok,why=coroutine.resume(job);assert(ok,why);if coroutine.status(job)=='dead'then break end;kernel.Sleep(100)end
assert(result and #result.luts==1 and #result.references==1 and result.pieces['0:2'],'Catalog request did not complete')
local expected=(EXPECTED):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
assert(ffi.string(result.luts[1].values,23*2*16)==expected,'Worker changed original floats')
print('PASS full Lua kit request, archive worker, asynchronous manifest response and byte-identical original float decode')

 """.replace('MODEL',model).replace('CACHE',json.dumps(cache.as_posix())).replace('FOLDER',json.dumps(folder.as_posix())).replace('PORT',str(port)).replace('BUNDLE',json.dumps(bundle.as_posix())).replace('GAMEDATA',json.dumps(game_data.as_posix())).replace('FIXTUREKIT',lua(kit)).replace('EXPECTED',repr(original.tobytes().hex())).replace('OWNERPID',str(owner.pid))
  path=root/'check.lua';path.write_text(code);previous=os.environ.get('EPIC_LUT_PYTHON')
  if system_mode:os.environ.pop('EPIC_LUT_PYTHON',None)
  else:os.environ['EPIC_LUT_PYTHON']='C:/unavailable/python.exe'
  L=lib.luaL_newstate();lib.luaL_openlibs(L)
  try:
   status=lib.luaL_loadfile(L,str(path).encode())
   if not status:status=lib.lua_pcall(L,0,0,0)
   if not status:
    ready_info=json.loads((cache/'file-service/dist/companion/ready.json').read_text());service_pid=int(ready_info['pid']);owner.terminate();owner.wait(timeout=5)
    sys.path.insert(0,str(ROOT/'tools'));from owner_watch import process_alive
    for _ in range(40):
     if not process_alive(service_pid):break
     time.sleep(.1)
    assert not process_alive(service_pid),'Game-owned helper survived owner exit'
    assert not (folder/'native-ready.txt').exists(),'Exited helper left a fresh readiness marker'
    print('PASS game-owned helper exits automatically after its owner, without stopping unrelated processes')
   if status:raise RuntimeError(lib.lua_tolstring(L,-1,None).decode()+'\n'+((cache/'file-service/dist/companion/startup-error.log').read_text(errors='replace') if (cache/'file-service/dist/companion/startup-error.log').exists() else ''))
  finally:
   lib.lua_close(L)
   if owner.poll()is None:owner.terminate();owner.wait(timeout=5)
   if previous is None:os.environ.pop('EPIC_LUT_PYTHON',None)
   else:os.environ['EPIC_LUT_PYTHON']=previous
   ready=cache/'file-service/dist/companion/ready.json'
   if ready.exists():
    pid=int(json.loads(ready.read_text())['pid']);kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32];kernel.OpenProcess.restype=ctypes.c_void_p
    kernel.QueryFullProcessImageNameW.argtypes=[ctypes.c_void_p,ctypes.c_uint32,ctypes.c_wchar_p,ctypes.POINTER(ctypes.c_uint32)]
    kernel.TerminateProcess.argtypes=[ctypes.c_void_p,ctypes.c_uint32];kernel.CloseHandle.argtypes=[ctypes.c_void_p]
    handle=kernel.OpenProcess(0x1001,False,pid)
    if handle:
     try:
      image=ctypes.create_unicode_buffer(32768);size=ctypes.c_uint32(len(image))
      assert kernel.QueryFullProcessImageNameW(handle,0,image,ctypes.byref(size)) and Path(image.value).samefile(Path(sys.executable)if system_mode else cache/('file-service/runtime-'+runtime_hash[:16]+'/python.exe')),'Refused to stop an unexpected process'
      assert kernel.TerminateProcess(handle,0)
     finally:kernel.CloseHandle(handle)
   time.sleep(.6) # Allow the launcher and terminated child's redirected handles to close.

  if system_mode:
   if prior_localappdata is None:os.environ.pop('LOCALAPPDATA',None)
   else:os.environ['LOCALAPPDATA']=prior_localappdata
