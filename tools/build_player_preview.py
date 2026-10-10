"""Create an isolated player-preview test mod; no runtime dependencies bundled."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parent.parent
import sys
sys.path.insert(0,str(ROOT))
from tools.module_inventory import source_path
p = argparse.ArgumentParser()
p.add_argument('--base', type=Path)
p.add_argument('--inspect-only', action='store_true')
p.add_argument('--standalone', action='store_true')
p.add_argument('--editor-zip', type=Path, help='Combine the matching loose editor and preview into one retest archive')
args = p.parse_args()
out = ROOT / 'dist/releases/player-preview-candidate'
out.mkdir(parents=True, exist_ok=True)
if args.standalone:
    base_bytes = b''
    base = "return {name='Epic LUT Player Preview (test)',author='Goose',on_enable=function()end,on_update=function()end,on_disable=function()return true end,on_cleanup_poll=function()return true end}"
else:
    if not args.base:
        p.error('--base is required unless --standalone is selected')
    base_bytes = args.base.read_bytes()
    base = base_bytes.decode('utf-8')
    assert 'Epic LUT' in base and 'on_enable' in base
    assert 'independent player portrait candidate ready' not in base, 'Do not nest preview candidates'
parts = ['local editor=(function()\n', base, '\nend)()\nlocal m={}\n',
         'local PREVIEW_INSPECT_ONLY='+str(args.inspect_only).lower()+'\nlocal PREVIEW_ANIMATION_ENABLED=false\n']
for name, folder in [('bingus_runtime','vendor'),('bingus_memory','vendor'),
                     ('avatar','vendor'),('engine','vendor'),('player_model','src'),
                     ('player_animation','src'),('player_preview','src'),('player_preview_native','src'),('player_preview_submit','src'),('player_preview_controls','src'),('player_preview_input','src')]:
    parts.append(f'm.{name}=(function()\n'+(ROOT/source_path(name) if folder=='src'else ROOT/f'{folder}/{name}.lua').read_text(encoding='utf-8')+'\nend)()\n')
parts.append((ROOT/'src/preview/player_preview_candidate.lua').read_text(encoding='utf-8'))
candidate = ''.join(parts).encode('utf-8')
(out/'mod.lua').write_bytes(candidate)
(out/'base.lua').write_bytes(base_bytes)
(out/'BUILD.json').write_text(json.dumps({
    'base_path': str(args.base.resolve()) if args.base and not args.standalone else None,
    'base_sha256': hashlib.sha256(base_bytes).hexdigest(),
    'candidate_sha256': hashlib.sha256(candidate).hexdigest(),
    'inspect_only': args.inspect_only,
    'standalone': args.standalone,
    'installed': False,
}, indent=2)+'\n', encoding='utf-8')
if args.standalone:
    readme = (
        'Epic LUT Player Preview - LLL test candidate\n\n'
        'Extract epic_player_preview into your LLL Helldivers2 Mods folder.\n'
        'Requires Epic LUT with the optional Player Preview buttons.\n'
        'Open Basic (F9) or Import / Apply (F10), then click Player Preview.\n'
        'Drag the title to move; X closes; bottom buttons adjust zoom.\n'
        'Drag the lower-right grip to scale the pop-out. Left-drag the model to pan; right-drag rotates 360 degrees.\n'
        'Armor and Helmet edits update the copied character live.\n'
        'Wheel zooms over the model. LUT Editor docks the preview beside the grid.\n'
        'Use Pop Out / Dock in its title or F6 to switch modes on that page.\n'
        'F6 toggles the pop-out on other editor pages; rebind it in Configuration.\n'
        'Controls work while the editor is open and focused.\n'
        'Remove the test mod folder to uninstall. No Python installation needed.\n\n'
        'Development candidate: visible geometry and live color changes verified;\n'
        'all screen transitions and interactive controls still need live testing.\n'
        'CowboyBingus native discovery/adapters: see LICENSE-CowboyBingus.txt.\n'
    )
    with zipfile.ZipFile(out/'Epic-LUT-Player-Preview-LLL-test.zip','w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('epic_player_preview/mod.lua',candidate)
        z.writestr('epic_player_preview/README.txt',readme)
        z.writestr('epic_player_preview/LICENSE-CowboyBingus.txt',(ROOT/'vendor/LICENSE').read_bytes())
    if args.editor_zip:
        instructions = (
            'Epic LUT Player Preview - Armory guard RETEST candidate\n\n'
            'The earlier preview crashed entering game Armory. This candidate adds\n'
            'cleanup ordering and stale-context guards. Offline checks pass; the\n'
            'reported game transition has NOT been verified with this candidate.\n\n'
            'Install both armor_lut_editor and epic_player_preview folders together\n'
            'in LLL Helldivers2/Mods. The editor must include the matching cleanup hook.\n'
            'Open Basic/F10, then Player Preview (default F6; use your configured key).\n'
            'Check pan, rotation, wheel zoom, Pop Out/Dock and live color changes.\n'
            'Close the editor: the preview should close before game input returns.\n'
            'Open the GAME Armory terminal, exit it, and reopen the editor/preview.\n'
            'On failure, disable epic_player_preview and preserve LiveLuaLoader.log.\n'
        )
        entries={}
        for archive in (args.editor_zip,out/'Epic-LUT-Player-Preview-LLL-test.zip'):
            with zipfile.ZipFile(archive) as source:
                assert source.testzip() is None, 'Input archive CRC failure'
                for name in source.namelist():
                    if name.endswith('/'):
                        continue
                    assert not name.startswith(('/', '\\')) and '..' not in Path(name).parts, 'Unsafe archive path'
                    assert name not in entries, 'Duplicate bundled path: '+name
                    entries[name]=source.read(name)
        editor_name=next(name for name in entries if name.endswith('armor_lut_editor/mod.lua'))
        assert b'portrait.before_editor_close()' in entries[editor_name], 'Editor lacks the cleanup handshake'
        with zipfile.ZipFile(out/'Epic-LUT-Player-Preview-Armory-Guard-retest.zip','w',zipfile.ZIP_DEFLATED) as z:
            for name,value in entries.items():
                z.writestr(name,value)
            z.writestr('README-LIVE-RETEST.txt',instructions)
elif args.editor_zip:
    p.error('--editor-zip requires --standalone')
print(out/'mod.lua')
