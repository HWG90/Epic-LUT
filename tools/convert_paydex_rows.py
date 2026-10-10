"""Convert data-only Paydex JSON material rows to Epic LUT float DDS presets."""
import argparse
import json
import math
from pathlib import Path
import re
import struct
import zipfile


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def encode_dds(rows):
    values = [value for row in rows for value in row]
    words = [124, 0x100f, len(rows), 23, 23 * 16, 0, 1] + [0] * 11
    words += [32, 4, 0x30315844, 0, 0, 0, 0, 0, 0x1000, 0, 0, 0, 0, 2, 3, 0, 1, 0]
    return b'DDS ' + struct.pack('<36I', *words) + struct.pack('<' + 'f' * len(values), *values)


def convert(source, output):
    source, output = Path(source), Path(output)
    if source.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('Preset JSON exceeds 8 MiB')
    presets = json.loads(source.read_text(encoding='utf-8-sig'), object_pairs_hook=unique_object)
    if not isinstance(presets, dict) or not 1 <= len(presets) <= 128:
        raise ValueError('Expected 1-128 named Paydex row presets')
    files, records, rows, used = {}, [], [], set()
    for number, (label, preset) in enumerate(presets.items(), 1):
        if not isinstance(label, str) or not label.strip() or not isinstance(preset, dict):
            raise ValueError('Every preset needs a name and a rowData object')
        cells = preset.get('rowData')
        if not isinstance(cells, list) or len(cells) != 23:
            raise ValueError(f'{label}: expected exactly 23 columns')
        row = []
        for column, cell in enumerate(cells, 1):
            if not isinstance(cell, dict) or set(cell) != {'r', 'g', 'b', 'a'}:
                raise ValueError(f'{label}, column {column}: expected r, g, b, a')
            for channel in ('r', 'g', 'b', 'a'):
                value = cell[channel]
                if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                    raise ValueError(f'{label}, column {column}, {channel}: expected a finite number')
                try:
                    packed = struct.pack('<f', value)
                except (OverflowError, struct.error) as error:
                    raise ValueError(f'{label}: value exceeds float32 range') from error
                row.append(struct.unpack('<f', packed)[0])
        stem = re.sub(r'[^A-Za-z0-9 _-]+', '_', label).strip(' _')[:48].rstrip() or f'Preset-{number:03d}'
        base, suffix = stem, 1
        while stem.casefold() in used:
            suffix += 1
            tail = f'-{suffix}'
            stem = base[:48 - len(tail)].rstrip() + tail
        used.add(stem.casefold())
        filename = 'row-' + stem + '.dds'
        files[filename] = encode_dds([row])
        rows.append(row)
        records.append({'name': label, 'epic_name': stem, 'file': filename, 'timestamp': preset.get('timestamp')})
    for first in range(0, len(rows), 64):
        suffix = '' if len(rows) <= 64 else f'-{first // 64 + 1:02d}'
        files['Paydex-Row-Library' + suffix + '.dds'] = encode_dds(rows[first:first + 64])
    mapping = json.dumps({'format': 'RGBA32F DDS', 'columns': 23, 'presets': records}, indent=2, ensure_ascii=False)
    readme = '''Paydex material rows converted for Epic LUT

Each row-*.dds is one complete 23-column material row, in RGBA32F.
All RGB, alpha, shader controls, negative values and values above 1 are retained.
No color-space conversion, clamping, automatic gear matching or application.

Use the named Rows presets (recommended):
1. Extract only the row-*.dds files from Paydex-Row-Presets-Epic-LUT.zip into:
   %LOCALAPPDATA%/Epic LUT/presets
2. Reload Epic LUT to refresh its preset list.
3. Load the current gear LUT, select a destination row, then Tools > Rows.
4. Choose the converted preset and press Apply preset to row.

Use ordinary import instead:
1. Tools > Import > Import DDS / ZIP / RAR: choose the ZIP or a DDS.
2. Select the imported row/table and Send to LUT Editor.
3. Tools > Rows > Copy row for the desired source row.
4. Load the destination gear LUT, select its destination row, and Paste row.
5. Use Apply armor/helmet when ready.

The separate Paydex-Row-Library.dds contains the presets as successive rows
in their original JSON order. Do not apply this mixed library as a whole outfit.
For more than 64 presets, numbered libraries each contain up to 64 rows.

Original names/timestamps and sanitized filenames are in preset-names.json.
These are row presets, not Armory outfits or texture-ID patch manifests.
'''
    output.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        (output / name).write_bytes(data)
    (output / 'preset-names.json').write_text(mapping, encoding='utf-8')
    (output / 'README.txt').write_text(readme, encoding='utf-8')
    package = output / 'Paydex-Row-Presets-Epic-LUT.zip'
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for record in records:
            archive.writestr(record['file'], files[record['file']])
        archive.writestr('README.txt', readme)
        archive.writestr('preset-names.json', mapping)
    return records, package


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True, help='New output folder; existing folders are never overwritten')
    arguments = parser.parse_args()
    records, package = convert(arguments.source, arguments.output)
    print(f'Converted {len(records)} rows: {package}')
