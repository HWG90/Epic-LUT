"""Validate generated modular packages, then execute their scoped bootstrap."""
import json
import os
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.lua_runner import LuaRunner

os.chdir(ROOT)
folder = ROOT / 'tests/tmp/modular-animation-bootstrap'
folder.mkdir(parents=True, exist_ok=True)
os.environ['EPIC_LUT_MODULAR_TEST_DIR'] = str(folder)
runner = LuaRunner()
inventories = []
for mode in ('static', 'animation'):
    path = ROOT / 'dist/releases/modular-20261010' / f'Epic-LUT-Dev-{mode.title()}-LLL.zip'
    with zipfile.ZipFile(path) as z:
        manifest = json.loads(z.read('armor_lut_editor/manifest.json'))
        assert manifest['lll']['entry'] == 'main.lua'
        modules = manifest['lll']['modules']
        assert len(modules) == len(set(modules))
        assert all('armor_lut_editor/' + name in z.namelist() for name in modules)
        inventories.append(modules)
        (folder / f'{mode}-main.lua').write_bytes(z.read('armor_lut_editor/main.lua'))
        for name in ['main.lua'] + modules:
            source = folder / mode / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(z.read('armor_lut_editor/' + name))
            runner.check(source)
        assert not any(name.endswith(('/mod.lua', '.bin', '.animation')) for name in z.namelist())
assert inventories[0] == inventories[1], 'Modular variants have different runtime inventories'
(folder / 'modules.txt').write_text('\n'.join(inventories[0]), encoding='utf-8')
runner.check(ROOT / 'tests/lll_animation_bootstrap.lua', execute=True)
