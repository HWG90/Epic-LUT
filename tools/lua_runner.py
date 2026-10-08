"""Isolated LuaJIT validation shared by editor and preview checks."""
import ctypes
from pathlib import Path

from tools.runtime_paths import lua_library

class LuaRunner:
    def __init__(self):
        self.dll = ctypes.CDLL(str(lua_library()))
        self.dll.luaL_newstate.restype = ctypes.c_void_p
        for name in ('luaL_openlibs', 'lua_close'):
            getattr(self.dll, name).argtypes = [ctypes.c_void_p]
        self.dll.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.dll.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        self.dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        self.dll.lua_tolstring.restype = ctypes.c_char_p

    def check(self, path: Path, *, execute: bool = False):
        state = self.dll.luaL_newstate()
        if not state:
            raise RuntimeError('Could not create LuaJIT validation state')
        try:
            self.dll.luaL_openlibs(state)
            code = self.dll.luaL_loadfile(state, str(path).encode())
            if not code and execute:
                code = self.dll.lua_pcall(state, 0, 0, 0)
            if code:
                error = self.dll.lua_tolstring(state, -1, None)
                raise RuntimeError(f'{path}: {error.decode(errors="replace")}')
        finally:
            self.dll.lua_close(state)
