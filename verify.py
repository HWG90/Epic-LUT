import ctypes,os
from tools.runtime_guard import require_physical_runtime,blocked_path
require_physical_runtime()
assert blocked_path('C:/Users/test/AppData/Local/Microsoft/WindowsApps/python.exe')
assert blocked_path('C:/Users/test/AppData/Local/Packages/PythonSoftwareFoundation.Python/LocalCache/Local/LLL/mod.lua')
assert not blocked_path('C:/runtimes/python/python.exe')
from pathlib import Path
ROOT=Path(__file__).resolve().parent;os.chdir(ROOT)
(ROOT/'tests/presets').mkdir(exist_ok=True)
os.environ.setdefault('MCM_SOURCE_DIR',str(ROOT.parent/'DBF-MCM'))
dll=ctypes.CDLL(os.environ.get('LUA51_DLL',r'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2\bin\lua51.dll'))
dll.luaL_newstate.restype=ctypes.c_void_p
for n in ['luaL_openlibs','lua_close']:getattr(dll,n).argtypes=[ctypes.c_void_p]
dll.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p];dll.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
dll.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];dll.lua_tolstring.restype=ctypes.c_char_p
for file in [*ROOT.glob('src/*.lua'),*ROOT.glob('vendor/*.lua'),ROOT/'dist/armor_lut_editor/mod.lua',ROOT/'tests/contracts.lua']:
    L=dll.luaL_newstate();dll.luaL_openlibs(L)
    code=dll.luaL_loadfile(L,str(file).encode())
    if not code and file.name=='contracts.lua':code=dll.lua_pcall(L,0,0,0)
    if code:raise RuntimeError(f'{file}: '+dll.lua_tolstring(L,-1,None).decode(errors='replace'))
    dll.lua_close(L)
print('PASS: all source and bundled LuaJIT syntax; meaningful session/palette contracts')
