"""Confirm the generated model embeds each declared adapter once."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.module_inventory import VENDOR, MENU, OWN, PREVIEW

model = (ROOT/'dist/armor_lut_editor/mod.lua').read_text(encoding='utf-8')
expected = list(VENDOR) + ['ui_' + name for name in MENU] + list(OWN)
if 'm.player_model=(function()' in model:
    expected += list(PREVIEW)
assert len(expected) == len(set(expected)), 'Duplicate module inventory'
for name in expected:
    assert len(re.findall(r'm\.' + re.escape(name) + r'=\(function\(\)', model)) == 1, f'{name} missing or duplicated in model'
assert 'src/standalone_frontend.lua' in (ROOT/'build.py').read_text(encoding='utf-8')
print(f'PASS bundle inventory: {len(expected)} modules, each embedded once')
