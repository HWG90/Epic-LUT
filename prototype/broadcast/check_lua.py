from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.lua_runner import LuaRunner
runner=LuaRunner()
for path in (ROOT/'prototype/broadcast').glob('*.lua'):
    runner.check(path,execute=path.name.startswith('test_'))
runner.check(ROOT/'dist/broadcast-poc/mod.lua')
print('LuaJIT syntax and remote roster fixture passed')
