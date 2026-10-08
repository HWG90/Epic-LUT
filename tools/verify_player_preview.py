"""Focused offline checks for the optional player-preview candidate."""
from pathlib import Path
import sys
import os

from runtime_guard import require_physical_runtime
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

require_physical_runtime()
ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
from tools.lua_runner import LuaRunner
runner = LuaRunner()

files = [*ROOT.glob('src/player_*.lua'), *ROOT.glob('tests/player_*.lua')]
candidate = ROOT/'dist/releases/player-preview-candidate/mod.lua'
if candidate.exists():
    files.append(candidate)
for path in files:
    runner.check(path, execute=path.parent.name == 'tests')
print('PASS optional player-preview source/candidate syntax and ownership/pose/material contracts')
