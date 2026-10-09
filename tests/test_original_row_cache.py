"""A previous 32-row resource index must be rebuilt by the 64-row reader."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from test_game_catalog import fixture
from lut_files import load

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix='epic-original-row-cache-') as temp:
    folder = Path(temp)
    _, pixels = fixture(folder / 'game', 64)
    stamp = hashlib.sha256((folder / 'game/bundles.nxa').read_bytes()).hexdigest().upper()
    output = folder / 'originals'
    version = output / stamp
    version.mkdir(parents=True)
    # Old schema/index appears complete, but its catalog lacks the custom table.
    (version / 'patch-source-v2.txt').write_text('3x1 and 23xN')
    (version / 'catalog.txt').write_text('ffffffffffffffff\n')
    (output / 'index-complete.txt').write_text(stamp + '\n1')

    command = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
               '-File', str(ROOT / 'tools/original_snapshots.ps1'),
               '-GameData', str(folder / 'game'), '-Output', str(output)]
    indexed = subprocess.run(command + ['-IndexOnly'], capture_output=True, text=True)
    assert indexed.returncode == 0, (indexed.stderr, (output / 'error.txt').read_text() if (output / 'error.txt').exists() else '')
    assert (version / 'patch-source-v3.txt').read_text() == '3x1 and 23x1-64'
    assert (version / 'catalog.txt').read_text().splitlines() == ['3333333333333333'], 'Old row-limit index was reused'

    wanted = folder / 'wanted.txt'
    wanted.write_text('3333333333333333\n')
    captured = subprocess.run(command + ['-Wanted', str(wanted)], capture_output=True, text=True)
    assert captured.returncode == 0, (captured.stderr, (output / 'error.txt').read_text() if (output / 'error.txt').exists() else '')
    assert load(version / 'game-3333333333333333-original.dds').tobytes() == pixels.tobytes(), 'Original capture truncated row 64'
    assert (version / 'game-3333333333333333-original.patch-source').stat().st_size == 357

print('PASS native original reader: rebuild old 32-row index and capture all 64 rows plus exact patch metadata')
