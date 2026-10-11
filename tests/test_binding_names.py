"""Ensure SDK display aliases are never passed to game named-slot APIs."""
from pathlib import Path
import hashlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.generate_binding_names import hash32, rows, INPUT, INPUT_SHA, SUPPLEMENTAL_NAMES

text = (ROOT / 'src/gear/binding_names.lua').read_text()
generated = dict((int(key, 16), name) for key, name in
                 re.findall(r"\[0x([0-9a-f]{8})\] = '([^']+)'", text))
assert INPUT_SHA in text and len(generated) == 4992
if INPUT.is_file():
    data = INPUT.read_bytes()
    assert hashlib.sha256(data).hexdigest() == INPUT_SHA
    names = rows(data)
    expected = {key: name for key, name in names.items() if name.startswith(('m_', 'g_'))}
    expected.update(SUPPLEMENTAL_NAMES)
    assert generated == expected, 'Generated binding names differ from pinned verified values'
for key, name in generated.items():
    assert hash32(name) == key, 'Display alias used instead of an engine literal'
assert generated[0xe02f71fe] == 'm_helmet' and hash32('MHelmet') != 0xe02f71fe
assert generated[0xa838f8a6] == 'm_jacket' and hash32('MJacket') != 0xa838f8a6
assert generated[0x7682a507] == 'g_helmet_LOD1'
assert generated[0x2cf8d519] == 'm_hips_undergarment'
assert generated[0xdfe66f6c] == 'm_hips_armor'
# Real SDK rows use unpadded hex for these named slots/meshes. Losing an
# unrelated slot name previously rejected every binding in its whole Unit.
short_rows = (b'MShirt 0x967f8b5\nMGibs 0xbf81d82\n'
              b'GArmRLod2 0xd903a17\nGLegUndergarmentL 0x4e9376\n'
              b'GShoulderLMaleLod2 0xfed40c9\n')
expected_short = {
    0x0967f8b5: 'm_shirt', 0x0bf81d82: 'm_gibs',
    0x0d903a17: 'g_arm_r_LOD2', 0x004e9376: 'g_leg_undergarment_l',
    0x0fed40c9: 'g_shoulder_l_male_LOD2',
}
assert rows(short_rows) == expected_short
assert all(generated[key] == name for key, name in expected_short.items())
assert rows(b'MHelmet 0x967f8b5\n') == {}, 'Unpadded hex bypassed literal hash verification'
assert rows(b'MShirt 0x00967f8b5\n') == {}, 'Overwide hash accepted as uint32'
assert len(text.encode()) <= 512 * 1024
print('PASS binding names: %d pinned, exact uint32 hashes; aliases excluded and LOD case preserved' % len(generated))
