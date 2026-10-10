"""Exercise runtime Paydex JSON import without a Python dependency in the worker."""
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def command(source, output, result):
    return [
            'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', str(ROOT / 'tools/import_zip.ps1'), '-RowPresets',
            '-Package', str(source), '-Output', str(output), '-Result', str(result),
    ]


def worker(source, output, result):
    return subprocess.run(
        command(source, output, result),
        capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW,
    )


def row():
    return {'timestamp': '2026-10-10T00:00:00Z', 'rowData': [
        {'r': (column - 12) / 9, 'g': 8.125, 'b': 1 / 3, 'a': -0.0 if column == 0 else 2.75}
        for column in range(23)
    ]}


def expected_pixels(preset):
    return b''.join(struct.pack('<f', cell[channel]) for cell in preset['rowData'] for channel in 'rgba')


with tempfile.TemporaryDirectory(prefix='epic-paydex-worker-') as temporary:
    folder = Path(temporary)
    source = folder / 'rows.json'
    presets = {'A/B': row(), 'A:B': row(), 'a_b': row(), '\N{SNOWMAN}': row(), 'CON': row()}
    source.write_text('\ufeff' + json.dumps(presets), encoding='utf-8')
    output, result = folder / 'converted', folder / 'converted.txt'
    completed = worker(source, output, result)
    assert completed.returncode == 0, (completed.stderr, result.read_text())
    assert result.read_text().splitlines() == ['row-presets', 'rows.tsv']
    names = (output / 'rows.tsv').read_text().splitlines()
    assert names == ['row-A_B.dds', 'row-A_B-2.dds', 'row-a_b-3.dds', 'row-Preset-004.dds', 'row-CON.dds']
    assert {path.name for path in output.iterdir()} == {'rows.tsv', *names}
    for name, preset in zip(names, presets.values()):
        raw = (output / name).read_bytes()
        assert len(raw) == 516 and raw[:4] == b'DDS '
        assert struct.unpack_from('<II', raw, 12) == (1, 23)
        assert struct.unpack_from('<5I', raw, 128) == (2, 3, 0, 1, 0)
        assert raw[148:] == expected_pixels(preset), 'Negative, HDR, alpha, signed zero or F32 rounding changed'
    # An existing folder is never treated as a writable preset destination.
    protected = folder / 'existing'
    protected.mkdir()
    (protected / 'row-A_B.dds').write_bytes(b'keep existing bytes')
    completed = worker(source, protected, folder / 'existing.txt')
    assert completed.returncode != 0 and (protected / 'row-A_B.dds').read_bytes() == b'keep existing bytes'
    assert {path.name for path in protected.iterdir()} == {'row-A_B.dds'}

    invalid_cases = []
    short = row()
    short['rowData'].pop()
    invalid_cases.append(('columns', json.dumps({'Valid first': row(), 'Invalid second': short}), '23 columns'))
    missing = row()
    del missing['rowData'][1]['a']
    invalid_cases.append(('channel', json.dumps({'Bad': missing}), 'r, g, b, a'))
    boolean = row()
    boolean['rowData'][2]['g'] = True
    invalid_cases.append(('boolean', json.dumps({'Bad': boolean}), 'finite number'))
    numeric_string = row()
    numeric_string['rowData'][3]['a'] = '2.75'
    invalid_cases.append(('numeric-string', json.dumps({'Bad': numeric_string}), 'finite number'))
    overflow = row()
    overflow['rowData'][4]['r'] = 1e100
    invalid_cases.append(('float-overflow', json.dumps({'Bad': overflow}), 'float32 range'))
    finite = row()
    finite['rowData'][4]['r'] = float('nan')
    invalid_cases.append(('nan', json.dumps({'Bad': finite}), 'Invalid Paydex JSON'))
    encoded = json.dumps(row())
    invalid_cases.append(('duplicate-name', '{"Same":' + encoded + ',"Same":' + encoded + '}', 'Duplicate JSON key'))
    invalid_cases.append(('duplicate-channel', json.dumps({'Bad': row()}).replace('"r":', '"r":0,"r":', 1), 'Duplicate JSON key'))
    invalid_cases.append(('trailing-comma', '{"Bad":' + encoded + ',}', 'Invalid Paydex JSON'))
    invalid_cases.append(('empty', '{}', '1-4096'))
    for label, text, error in invalid_cases:
        source.write_text(text, encoding='utf-8')
        output, result = folder / label, folder / (label + '.txt')
        completed = worker(source, output, result)
        assert completed.returncode != 0 and error in result.read_text(), (label, completed.stderr, result.read_text())
        assert not output.exists(), 'Invalid rows published a partial scratch library'

    # Every supported row is converted; the upper limit is independent of the
    # 256-palette archive import cap and uses a compact result plus manifest.
    source.write_text(json.dumps({f'Row {i}': row() for i in range(4096)}, separators=(',', ':')), encoding='utf-8')
    output, result = folder / 'many', folder / 'many.txt'
    completed = worker(source, output, result)
    assert completed.returncode == 0, (completed.stderr, result.read_text())
    assert len((output / 'rows.tsv').read_text().splitlines()) == 4096
    assert len(result.read_bytes()) < 8192 and len((output / 'rows.tsv').read_bytes()) <= 256 * 1024
    # Cancel while the .NET parser is active, rather than only before startup.
    result = folder / 'mid-cancel.txt'
    process = subprocess.Popen(command(source, folder / 'mid-canceled', result),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
    started = time.monotonic()
    progress = result.with_name(result.name + '.progress')
    try:
        while process.poll() is None and time.monotonic() - started < 8:
            try:
                heartbeat = progress.read_text()
            except (FileNotFoundError, PermissionError):
                # The worker atomically replaces its heartbeat. Like the
                # runtime reader, retry a transient Windows sharing lock.
                heartbeat = ''
            if '\treading\t' in heartbeat:
                result.with_name(result.name + '.cancel').write_text('cancel')
                break
            time.sleep(.02)
        stdout, stderr = process.communicate(timeout=15)
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=5)
    assert process.returncode == 0 and result.read_text() == 'cancel', (stdout, stderr, result.read_text())
    assert not (folder / 'mid-canceled').exists()
    source.write_text(json.dumps({f'Row {i}': row() for i in range(4097)}, separators=(',', ':')), encoding='utf-8')
    completed = worker(source, folder / 'too-many', folder / 'too-many.txt')
    assert completed.returncode != 0 and '1-4096' in (folder / 'too-many.txt').read_text()
    assert not (folder / 'too-many').exists()

    source.write_bytes(b' ' * (8 * 1024 * 1024 + 1))
    completed = worker(source, folder / 'oversize', folder / 'oversize.txt')
    assert completed.returncode != 0 and '8 MiB' in (folder / 'oversize.txt').read_text()
    assert not (folder / 'oversize').exists()
    source.write_bytes(b'\xff\xfeinvalid utf8')
    completed = worker(source, folder / 'utf8', folder / 'utf8.txt')
    assert completed.returncode != 0 and not (folder / 'utf8').exists()
    result = folder / 'cancel.txt'
    result.with_name(result.name + '.cancel').write_text('cancel')
    completed = worker(source, folder / 'canceled', result)
    assert completed.returncode == 0 and result.read_text() == 'cancel'
    assert not (folder / 'canceled').exists()

print('PASS Paydex worker: exact F32 rows, naming collisions, atomic schema rejection, UTF8/bounds/cancel, 4096-row manifest')
