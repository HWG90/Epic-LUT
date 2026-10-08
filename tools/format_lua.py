"""Format/check maintained Lua using pinned StyLua. Does not modify upstream adapters."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools.module_inventory import OWN, PREVIEW, FORMAT_EXCEPTIONS, source_path

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
parser.add_argument('--stylua', type=Path, default=ROOT/'dist/tools/stylua/stylua.exe')
args = parser.parse_args()
version = subprocess.run([str(args.stylua), '--version'], capture_output=True, text=True, check=True).stdout.strip()
if version != 'stylua 2.5.2':
    parser.error('Use the pinned StyLua 2.5.2 release')
files = [source_path(name) for name in OWN + PREVIEW]
files += ['src/editor/direct_editor.lua', 'src/preview/player_preview_candidate.lua', 'vendor/menu/menu.lua']
files += [str(path.relative_to(ROOT)).replace('\\', '/') for path in (ROOT/'tests').glob('*.lua')]
files = sorted(set(files) - FORMAT_EXCEPTIONS)
command = [str(args.stylua), '--verify']
if args.check:
    command.append('--check')
subprocess.run(command + files, cwd=ROOT, check=True)
print(f'PASS formatting: {len(files)} maintained Lua files; {len(FORMAT_EXCEPTIONS)} documented FFI exceptions')
