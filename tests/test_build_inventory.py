"""Confirm the generated model embeds each declared adapter once."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.module_inventory import VENDOR, MENU, OWN, PREVIEW, source_path

model = (ROOT/'dist/armor_lut_editor/mod.lua').read_text(encoding='utf-8')
expected = list(VENDOR) + ['ui_' + name for name in MENU] + list(OWN)
if 'm.player_model=(function()' in model:
    expected += list(PREVIEW)
if 'm.player_animation=(function()' in model:
    animated = "m.preview_animation='authored_salute'" in model or "m.preview_animation='garment_poses'" in model
    gate = 'true' if animated else 'false'
    assert '\nlocal PREVIEW_ANIMATION_ENABLED='+gate+'\n' in model, 'Animation differs from its declared build mode'
    embedded = re.search(
        r'm\.player_animation=\(function\(\)\n(.*?)\nend\)\(\)\n(?=m\.\w+=\(function\(\)\n)',
        model, re.DOTALL,
    )
    assert embedded, 'Bundled preview animation module boundaries are missing'
    driver = embedded[1]
    for unsafe in ('A.new_world', 'W.spawn_unit', 'W.update_animations', 'W.update_scene', 'U.animation_event'):
        assert not re.search(r'\b'+re.escape(unsafe)+r'\s*\(', driver), 'Bundled preview animation reintroduced the failed avatar/world path: '+unsafe
    source_driver = (ROOT/source_path('player_animation')).read_text(encoding='utf-8')
    assert driver == source_driver, 'Bundled preview animation differs from maintained source'
assert len(expected) == len(set(expected)), 'Duplicate module inventory'
for name in expected:
    assert len(re.findall(r'm\.' + re.escape(name) + r'=\(function\(\)', model)) == 1, f'{name} missing or duplicated in model'
assert source_path('frontend') == 'src/platform/standalone_frontend.lua'
debug_hex = re.search(r"m\.debug_lut_dds_hex='([0-9a-f]+)'", model)
assert debug_hex and bytes.fromhex(debug_hex[1]) == (ROOT/'assets/debug-lut.dds').read_bytes(), 'Bundled Debug LUT differs'
print(f'PASS bundle inventory: {len(expected)} modules, each embedded once')
