"""Generate only hash-verified engine mesh/slot names from the pinned SDK list."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
REVISION = '5a886256e54db52b5d228335eae20ce796f87fc0'
INPUT_SHA = 'd20d66fcb747ebb0bf597a7c0cd4a8caf07e8667d4ea8424fa7f7c100c447e9a'
INPUT = ROOT / 'dist/sdk-reference' / REVISION / 'hashlists/shadervariables.txt'
OUTPUT = ROOT / 'src/gear/binding_names.lua'


def hash32(value):
    data = value.encode('utf-8')
    mask, multiplier = (1 << 64) - 1, 0xc6a4a7935bd1e995
    result = len(data) * multiplier & mask
    for at in range(0, len(data) // 8 * 8, 8):
        word = int.from_bytes(data[at:at + 8], 'little') * multiplier & mask
        word ^= word >> 47
        word = word * multiplier & mask
        result = (result ^ word) * multiplier & mask
    tail = data[len(data) // 8 * 8:]
    if tail:
        result = (result ^ int.from_bytes(tail, 'little')) * multiplier & mask
    result ^= result >> 47
    result = result * multiplier & mask
    result ^= result >> 47
    return result >> 32


def candidates(alias):
    snake = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2', alias)
    snake = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', snake).lower()
    values = {alias, alias.lower(), snake}
    values.update(re.sub(r'_lod(\d+)$', r'_LOD\1', value) for value in list(values))
    return values


def rows(data):
    found = {}
    for line in data.decode('utf-8-sig').splitlines():
        match = re.fullmatch(r'([^\s]+)\s+0x([0-9a-fA-F]{8})', line.strip())
        if not match:
            continue
        alias, key = match.groups()
        if not re.match(r'^[GM][A-Z0-9_]', alias):
            continue
        number = int(key, 16)
        names = {value for value in candidates(alias) if hash32(value) == number}
        found.setdefault(number, set()).update(names)
    return {key: next(iter(values)) for key, values in found.items() if len(values) == 1}


def generate():
    data = INPUT.read_bytes()
    assert hashlib.sha256(data).hexdigest() == INPUT_SHA, 'Pinned binding-name input changed'
    names = rows(data)
    assert names.get(0xe02f71fe) == 'm_helmet'
    assert names.get(0xa838f8a6) == 'm_jacket'
    assert names.get(0x7682a507) == 'g_helmet_LOD1'
    sections = {key: value for key, value in names.items() if value.startswith('m_')}
    meshes = {key: value for key, value in names.items() if value.startswith('g_')}
    text = [
        '-- Generated factual engine names; every literal hashes to its exact uint32 ID.',
        '-- SDK revision ' + REVISION + '; shadervariables SHA256 ' + INPUT_SHA,
        'local N = {}',
    ]
    for kind, entries in [('sections', sections), ('meshes', meshes)]:
        text.append('local ' + kind + ' = {')
        text.extend('    [0x%08x] = %r,' % (key, value) for key, value in sorted(entries.items()))
        text.append('}')
    text.extend([
        'local function key(value)',
        '    if type(value) ~= "number" or value % 1 ~= 0 then return nil end',
        '    if value < 0 then value = value + 4294967296 end',
        '    if value < 0 or value >= 4294967296 then return nil end',
        '    return value',
        'end',
        'function N.section(value) return sections[key(value)] end',
        'function N.mesh(value) return meshes[key(value)] end',
        'return N',
    ])
    result = '\n'.join(text) + '\n'
    assert len(result.encode()) <= 512 * 1024, 'Binding name catalog exceeds its bound'
    OUTPUT.write_text(result, encoding='utf-8', newline='\n')
    print('Generated %d hash-verified section names and %d mesh names' % (len(sections), len(meshes)))


if __name__ == '__main__':
    generate()
