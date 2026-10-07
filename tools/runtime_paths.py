"""Portable runtime lookup for offline build checks and archive tools."""
import os,shutil
from pathlib import Path

def lua_library():
    configured=os.environ.get('LUA51_DLL')
    if configured:return Path(configured)
    roots=[]
    if os.environ.get('HD2_GAME_DIR'):roots.append(Path(os.environ['HD2_GAME_DIR']))
    if os.name=='nt':
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\Valve\Steam')as key:
                steam=Path(winreg.QueryValueEx(key,'SteamPath')[0]);roots.append(steam/'steamapps/common/Helldivers 2')
        except OSError:pass
    for root in roots:
        candidate=root/'bin/lua51.dll'
        if candidate.is_file():return candidate
    raise RuntimeError('Set LUA51_DLL to the matching LuaJIT library or HD2_GAME_DIR to the game installation.')

def seven_zip(configured=None):
    if configured:return Path(configured)
    if os.environ.get('EPIC_LUT_7ZIP'):return Path(os.environ['EPIC_LUT_7ZIP'])
    executable=shutil.which('7z')or shutil.which('7z.exe')
    if executable:return Path(executable)
    for variable in ('ProgramFiles','ProgramFiles(x86)'):
        if os.environ.get(variable):
            candidate=Path(os.environ[variable])/'7-Zip/7z.exe'
            if candidate.is_file():return candidate
    raise RuntimeError('RAR import requires 7-Zip. Set EPIC_LUT_7ZIP or add 7z to PATH.')
