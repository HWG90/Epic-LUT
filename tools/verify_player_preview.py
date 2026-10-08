"""Focused offline checks for the optional player-preview candidate."""
from pathlib import Path
import ctypes
import os

from runtime_guard import require_physical_runtime
from runtime_paths import lua_library

require_physical_runtime()
ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
dll = ctypes.CDLL(str(lua_library()))
dll.luaL_newstate.restype = ctypes.c_void_p
for name in ('luaL_openlibs', 'lua_close'):
    getattr(dll, name).argtypes = [ctypes.c_void_p]
dll.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
dll.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
dll.lua_tolstring.restype = ctypes.c_char_p

files = [*ROOT.glob('src/player_*.lua'), *ROOT.glob('tests/player_*.lua')]
candidate = ROOT/'dist/releases/player-preview-candidate/mod.lua'
if candidate.exists():
    files.append(candidate)
for path in files:
    state = dll.luaL_newstate()
    dll.luaL_openlibs(state)
    try:
        code = dll.luaL_loadfile(state, str(path).encode())
        if not code and path.parent.name == 'tests':
            code = dll.lua_pcall(state, 0, 0, 0)
        if code:
            raise RuntimeError(str(path)+': '+dll.lua_tolstring(state, -1, None).decode())
    finally:
        dll.lua_close(state)
print('PASS optional player-preview source/candidate syntax and ownership/pose/material contracts')
