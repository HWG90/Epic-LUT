"""Build the Python-free Epic LUT package. Python is a development tool only."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import zipfile

from tools.lua_archive import hash_name, read, write
from tools.runtime_guard import require_physical_runtime

require_physical_runtime()
ROOT = Path(__file__).resolve().parent
VERSION = (ROOT/'VERSION').read_text(encoding='utf-8').strip()
DISPLAY_VERSION = VERSION.replace('-alpha',' Alpha').replace('-rc',' RC')
parser = argparse.ArgumentParser()
parser.add_argument('--loader', choices=('bsl','loose'), default='bsl')
parser.add_argument('--output')
parser.add_argument('--player-preview',action='store_true',default=True,help='Include Player Preview (R5 default)')
parser.add_argument('--no-player-preview',dest='player_preview',action='store_false',help='Build an editor-only diagnostic package')
args = parser.parse_args()
if args.output is None:
    args.output='Epic-LUT-'+VERSION.replace('-alpha','-Alpha').replace('-rc','-RC')+('-LLL' if args.loader=='loose' else '-BSL')+'.zip'
if Path(args.output).name != args.output or not args.output.endswith('.zip'):
    parser.error('--output must be a ZIP filename within dist')

OUT = ROOT / 'dist/armor_lut_editor'
OUT.mkdir(parents=True, exist_ok=True)
from tools.module_inventory import VENDOR, MENU, OWN as EDITOR_MODULES, PREVIEW, source_path
OWN = list(EDITOR_MODULES)
if args.player_preview:
    OWN.extend(PREVIEW)
NATIVE_NAME = 'mcm_input_9bc2033ffbb3.dll'
NATIVE_SHA = '7e9a41484881fa851184b64a7b09f568b2f42637646bc85426a89fb5fb182350'
native_path = Path(os.environ['EPIC_LUT_INPUT_LIBRARY']) if os.environ.get('EPIC_LUT_INPUT_LIBRARY') else ROOT.parent/'DBF-MCM/native/build'/NATIVE_NAME
native = native_path.read_bytes()
assert hashlib.sha256(native).hexdigest() == NATIVE_SHA, 'Input DLL differs from the reviewed build'

def source(relative):
    return (ROOT / relative).read_text(encoding='utf-8')

def module(name, relative):
    return f'm.{name}=(function()\n{source(relative)}\nend)()\n'

parts = [f'-- Epic LUT {DISPLAY_VERSION}: native adapters by CowboyBingus.\nlocal m={{direct_menu_keys=true,direct_lut=true}}\n']
parts.append('m.version='+repr(VERSION)+'\n')
parts.append('m.original_snapshot_script=' + repr((ROOT/'tools/original_snapshots.ps1').read_bytes().hex()) + '\n')
parts.append('m.original_snapshot_reader=' + repr((ROOT/'tools/original_snapshots.cs').read_bytes().hex()) + '\n')
parts.append('m.zip_import_script=' + repr((ROOT/'tools/import_zip.ps1').read_bytes().hex()) + '\n')
parts.append(f'm.frontend_native_name={NATIVE_NAME!r}\n')
for name in MENU:
    parts.append(module('ui_' + name, f'vendor/menu/{name}.lua'))
for name in VENDOR:
    parts.append(module(name, f'vendor/{name}.lua'))
for name in OWN:
    parts.append(module(name, source_path(name)))
parts.append('m.native_import=m.windows\n')
if args.player_preview:
    parts.append('local editor=(function()\n' + source('src/editor/direct_editor.lua') + '\nend)()\n')
    parts.append('local PREVIEW_INSPECT_ONLY=false\n')
    parts.append(source('src/preview/player_preview_candidate.lua'))
else:
    parts.append('return (function()\n' + source('src/editor/direct_editor.lua') + '\nend)()\n')
model = ''.join(parts)

(OUT/'mod.lua').write_text(model, encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps({'name':'Epic LUT '+DISPLAY_VERSION,'version':VERSION,'author':'Goose','credits':'CowboyBingus native adapters'}, indent=2), encoding='utf-8')
(OUT/NATIVE_NAME).write_bytes(native)
(OUT/'library.txt').write_text(NATIVE_NAME, encoding='utf-8')
(OUT/'LICENSE-CowboyBingus.txt').write_bytes((ROOT/'vendor/LICENSE').read_bytes())
for folder, description in {'files':'Choose DDS/ZIP files from anywhere using the in-game picker. Edited DDS exports live in %LOCALAPPDATA%/Epic LUT/files.','presets':'Saved row presets live in %LOCALAPPDATA%/Epic LUT/presets as row-name.dds.'}.items():
    (OUT/folder).mkdir(exist_ok=True)
    (OUT/folder/'README.txt').write_text(description,encoding='utf-8')
for old_runtime in ('runtime.zip', 'runtime-manifest.json'):
    (OUT/old_runtime).unlink(missing_ok=True)

entry = 'mods/goose/epic_lut/startup'
startup = source('src/loaders/startup_bsl.lua').replace('__NATIVE_NAME__', NATIVE_NAME).replace('__NATIVE_HEX__', native.hex()).replace('-- __MODULE__', model).replace('-- __BRIDGE__', source('src/loaders/startup_bridge.lua'))
(ROOT/'dist/Epic-LUT-BSL-startup.lua').write_text(startup, encoding='utf-8')
envelope = struct.pack('<II',len(startup.encode()),2) + startup.encode()
archive = write({hash_name(entry):envelope})
assert read(archive)[hash_name(entry)][1] == envelope
manager = {'Version':1,'Guid':'2ef4f437-4a43-47ed-b1d0-15505f11c761','Author':'Goose','Name':'Epic LUT '+DISPLAY_VERSION,
    'Description':DISPLAY_VERSION+' - alpha release candidate. F10 opens the standalone armor/helmet LUT editor. DDS/ZIP/RAR import, live color editing, presets, floating Quick Scratch and original-game snapshots. Requires Bingus Shared Loader v15+; RAR requires 7-Zip. No Python or MCM setup. Live validation remains pending.',
    'Options':[{'Name':'Bingus Shared Loader startup','Include':['data']}]}
with zipfile.ZipFile(ROOT/'dist'/args.output,'w',zipfile.ZIP_DEFLATED) as package:
    if args.loader=='bsl':
        package.writestr('manifest.json',json.dumps(manager,indent=2))
        package.writestr('data/9ba626afa44a3aa3.patch_0',archive)
        for suffix in ('stream','gpu_resources'):
            package.writestr('data/9ba626afa44a3aa3.patch_0.'+suffix,b'')
    else:
        package.write(ROOT/'docs/MDL-LLL.md','INSTALL-MDL-LLL.md')
    for name in ('mod.lua','manifest.json','library.txt',NATIVE_NAME,'LICENSE-CowboyBingus.txt'):
        package.write(OUT/name,'armor_lut_editor/'+name)
    for name in ('README.md','tools/import_zip.ps1','tools/original_snapshots.ps1','tools/original_snapshots.cs','docs/DIRECT-LUT.md','docs/NEXUS-BBCODE.txt','docs/NEXUS-CHANGELOG.txt','docs/RELEASE-R4.md','docs/RELEASE-R4-RC1.md','docs/RELEASE-R5.md','docs/RELEASE-R5.1.md','docs/RELEASE-R5.2.md','docs/MDL-LLL.md'):
        package.write(ROOT/name,name)
(ROOT/'BUILD-RECEIPT.json').write_text(json.dumps({'name':'Epic LUT '+DISPLAY_VERSION,'version':VERSION,'author':'Goose','input_runtime_sha256':NATIVE_SHA,'mod_sha256':hashlib.sha256(model.encode()).hexdigest(),'python_required':False,'player_preview':args.player_preview,'modules':VENDOR+OWN},indent=2))
print(ROOT/'dist'/args.output)
