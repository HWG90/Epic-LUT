import ctypes,os
from tools.runtime_guard import require_physical_runtime,blocked_path
require_physical_runtime()
assert blocked_path('C:/Users/test/AppData/Local/Microsoft/WindowsApps/python.exe')
assert blocked_path('C:/Users/test/AppData/Local/Packages/PythonSoftwareFoundation.Python/LocalCache/Local/LLL/mod.lua')
assert not blocked_path('C:/runtimes/python/python.exe')
from pathlib import Path
ROOT=Path(__file__).resolve().parent;os.chdir(ROOT)
os.environ['EPIC_LUT_TEST_ROOT']=str(ROOT)
(ROOT/'tests/presets').mkdir(exist_ok=True)
(ROOT/'tests/tmp/files').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/tmp/cache').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/tmp/direct-state').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/tmp/presets').mkdir(exist_ok=True)
os.environ.setdefault('MCM_SOURCE_DIR',str(ROOT.parent/'DBF-MCM'))
from tools.runtime_paths import lua_library
dll=ctypes.CDLL(str(lua_library()))
dll.luaL_newstate.restype=ctypes.c_void_p
for n in ['luaL_openlibs','lua_close']:getattr(dll,n).argtypes=[ctypes.c_void_p]
dll.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p];dll.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
dll.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];dll.lua_tolstring.restype=ctypes.c_char_p
for file in [*ROOT.glob('src/*.lua'),*ROOT.glob('vendor/*.lua'),ROOT/'dist/armor_lut_editor/mod.lua',ROOT/'tests/contracts.lua',ROOT/'tests/float_lut.lua',ROOT/'tests/provider_menu.lua',ROOT/'tests/full_editor.lua',ROOT/'tests/native_ipc.lua',ROOT/'tests/frontend.lua',ROOT/'tests/startup_bridge.lua',ROOT/'tests/bindings.lua',ROOT/'tests/catalog_split_read.lua',ROOT/'tests/catalog_worker.lua',ROOT/'tests/startup_apply_gate.lua',ROOT/'tests/direct_editor.lua',ROOT/'tests/palette_editor.lua',ROOT/'tests/standalone_frontend.lua',ROOT/'tests/import_view.lua',ROOT/'tests/table_groups.lua',ROOT/'tests/original_luts.lua',ROOT/'tests/basic_view.lua',ROOT/'tests/update_check.lua',ROOT/'dist/Epic-LUT-BSL-startup.lua']:
    L=dll.luaL_newstate();dll.luaL_openlibs(L)
    code=dll.luaL_loadfile(L,str(file).encode())
    if not code and file.name in ('contracts.lua','float_lut.lua','provider_menu.lua','full_editor.lua','native_ipc.lua','frontend.lua','startup_bridge.lua','bindings.lua','catalog_split_read.lua','catalog_worker.lua','startup_apply_gate.lua','direct_editor.lua','palette_editor.lua','standalone_frontend.lua','import_view.lua','table_groups.lua','original_luts.lua','basic_view.lua','update_check.lua'):code=dll.lua_pcall(L,0,0,0)
    if code:raise RuntimeError(f'{file}: '+dll.lua_tolstring(L,-1,None).decode(errors='replace'))
    dll.lua_close(L)
print('PASS: all source and bundled LuaJIT syntax; meaningful session/palette contracts')
