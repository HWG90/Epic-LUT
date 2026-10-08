"""Preflight the optional preview against the installed editor; dry run by default."""
from pathlib import Path
import argparse
import hashlib
import os
import tempfile

ROOT = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser()
p.add_argument('--install', action='store_true')
args = p.parse_args()
mods = Path(os.environ['LOCALAPPDATA'])/'LLL/Helldivers2/Mods'
editor = mods/'armor_lut_editor/mod.lua'
candidate = ROOT/'dist/releases/player-preview-candidate/mod.lua'
target = mods/'epic_player_preview/mod.lua'
editor_bytes = editor.read_bytes()
candidate_bytes = candidate.read_bytes()
if b'portrait.before_editor_close()' not in editor_bytes or b'preview_cleanup_guard=true' not in editor_bytes:
    p.exit(2, 'Preview remains disabled: installed editor lacks the cleanup-before-input-release hook.\n')
if b'public.before_editor_close=function()' not in candidate_bytes:
    p.exit(2, 'Preview remains disabled: candidate lacks the matching cleanup hook.\n')
if b'UI lease changed; skip stale viewport destruction' not in candidate_bytes:
    p.exit(2, 'Preview remains disabled: candidate lacks stale-context protection.\n')
print('PASS matching installed editor/preview cleanup hooks')
print('Candidate SHA-256:', hashlib.sha256(candidate_bytes).hexdigest())
if args.install:
    if target.exists():
        old = target.read_bytes()
        backups = ROOT/'dist/releases/player-preview-candidate/installed-backups'
        backups.mkdir(exist_ok=True)
        backup = backups/('installed-'+hashlib.sha256(old).hexdigest()+'.lua')
        if backup.exists() and backup.read_bytes() != old:
            p.exit(2, 'Backup identity mismatch; preview remains unchanged.\n')
        backup.write_bytes(old)
    target.parent.mkdir(parents=True, exist_ok=True)
    if editor.read_bytes() != editor_bytes:
        p.exit(2, 'Editor changed during preflight; preview remains unchanged.\n')
    fd, name = tempfile.mkstemp(prefix='preview-', suffix='.tmp', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(candidate_bytes)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, target)
    finally:
        Path(name).unlink(missing_ok=True)
    print('Installed guarded retest candidate; live validation remains required.')
else:
    print('Dry run only; installed preview unchanged.')
