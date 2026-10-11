"""Ensure SDK display aliases are never passed to game named-slot APIs."""
from pathlib import Path
import hashlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.generate_binding_names import hash32, rows, INPUT, INPUT_SHA

text = (ROOT / 'src/gear/binding_names.lua').read_text()
generated = dict((int(key, 16), name) for key, name in
                 re.findall(r"\[0x([0-9a-f]{8})\] = '([^']+)'", text))
assert INPUT_SHA in text and len(generated) == 4678
if INPUT.is_file():
    data = INPUT.read_bytes()
    assert hashlib.sha256(data).hexdigest() == INPUT_SHA
    names = rows(data)
    expected = {key: name for key, name in names.items() if name.startswith(('m_', 'g_'))}
    assert generated == expected, 'Generated binding names differ from pinned verified values'
for key, name in generated.items():
    assert hash32(name) == key, 'Display alias used instead of an engine literal'
assert generated[0xe02f71fe] == 'm_helmet' and hash32('MHelmet') != 0xe02f71fe
assert generated[0xa838f8a6] == 'm_jacket' and hash32('MJacket') != 0xa838f8a6
assert generated[0x7682a507] == 'g_helmet_LOD1'
assert len(text.encode()) <= 512 * 1024
print('PASS binding names: %d pinned, exact uint32 hashes; aliases excluded and LOD case preserved' % len(generated))
