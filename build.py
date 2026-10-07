from pathlib import Path
import hashlib,json,zipfile,os,argparse
parser=argparse.ArgumentParser();parser.add_argument('--diagnostic',action='store_true');parser.add_argument('--without-native-bindings',action='store_true');parser.add_argument('--discovery-only',action='store_true');parser.add_argument('--without-editor-menu',action='store_true');parser.add_argument('--registry-only',action='store_true');parser.add_argument('--input-library-only',action='store_true');parser.add_argument('--idle-poll-only',action='store_true');parser.add_argument('--readonly-menu',action='store_true');parser.add_argument('--interactive-menu',action='store_true');parser.add_argument('--without-binding-adapter',action='store_true');parser.add_argument('--with-texture-application',action='store_true');parser.add_argument('--alpha-ui',action='store_true');parser.add_argument('--grouped-colors',action='store_true');args=parser.parse_args()
if args.grouped_colors:args.alpha_ui=True
if args.alpha_ui:args.diagnostic=True;args.without_binding_adapter=True;args.with_texture_application=True
if args.without_binding_adapter:args.interactive_menu=True
if args.idle_poll_only:args.input_library_only=True
if args.input_library_only:args.registry_only=True
if args.without_editor_menu or args.registry_only or args.readonly_menu or args.interactive_menu:args.discovery_only=True
if args.discovery_only and not args.diagnostic:parser.error('--discovery-only requires --diagnostic')
if args.with_texture_application:
    if not args.without_binding_adapter or not args.diagnostic:parser.error('--with-texture-application requires --diagnostic --without-binding-adapter')
    if args.without_editor_menu or args.registry_only or args.readonly_menu:parser.error('Texture application conflicts with non-interactive diagnostics')
    args.discovery_only=False
from tools.runtime_guard import require_physical_runtime
require_physical_runtime()
ROOT=Path(__file__).resolve().parent
runtime_path=ROOT/'dist/runtime/runtime.zip'
if not runtime_path.exists():
    import subprocess,sys
    subprocess.run([sys.executable,str(ROOT/'tools/prepare_runtime.py')],check=True)
runtime_bytes=runtime_path.read_bytes();runtime_hash=hashlib.sha256(runtime_bytes).hexdigest()
VENDOR=['bingus_runtime','bingus_memory','engine','avatar','kits','files','slim','texture']
OWN=['palette','catalog','dds','semantics','document','provider_menu','open_companion','native_import','paths','preferences','bindings','frontend','editor_features','session','presets']
parts=['-- Epic LUT R3; LUT discovery and native adapters by CowboyBingus.\nlocal m={}\n']
if not args.diagnostic:parts.append('m.direct_menu_keys=true\n')
if args.without_native_bindings:parts.append('m.native_bindings_disabled=true\n')
if args.discovery_only:parts.append('m.diagnostic_discovery_only=true\n')
if args.without_editor_menu:parts.append('m.diagnostic_without_menu=true\n')
if args.registry_only:parts.append('m.diagnostic_registry_only=true\n')
if args.input_library_only:parts.append('m.diagnostic_input_library=true\n')
if args.idle_poll_only:parts.append('m.diagnostic_idle_poll=true\n')
if args.readonly_menu:parts.append('m.diagnostic_readonly_menu=true\n')
if args.interactive_menu:parts.append('m.diagnostic_interactive_menu=true\n')
if args.without_binding_adapter:parts.append('m.diagnostic_without_binding_adapter=true\n')
if args.with_texture_application:parts.append('m.diagnostic_texture_application=true\n')
if args.alpha_ui:parts.append('m.alpha_ui=true\n')
if args.grouped_colors:parts.append('m.grouped_colors=true\n')
service_files=['tools/owner_watch.py','start_editor.ps1','tools/start_bundled.ps1','tools/runtime_paths.ps1','tools/deploy_guard.ps1','tools/companion.py','tools/native_import.py','tools/game_catalog.py','tools/remap.py','tools/lut_files.py','tools/extract_luts.py','tools/runtime_guard.py','tools/runtime_paths.py','companion/index.html']
parts.append('m.service_files={'+','.join('['+repr(name)+']='+repr((ROOT/name).read_bytes().hex())for name in service_files)+'}\n')
parts.append(f'm.runtime_hash={runtime_hash!r}\n')
MENU=['core','store','menu','view','capture','grouping','legacy']
for name in MENU:
    parts.append(f'm.ui_{name}=(function()\n'+(ROOT/'vendor/menu'/f'{name}.lua').read_text(encoding='utf-8')+'\nend)()\n')
native_name='mcm_input_9bc2033ffbb3.dll'
native_path=Path(os.environ['EPIC_LUT_INPUT_LIBRARY'])if os.environ.get('EPIC_LUT_INPUT_LIBRARY')else ROOT.parent/'DBF-MCM/native/build'/native_name
native_sha='7e9a41484881fa851184b64a7b09f568b2f42637646bc85426a89fb5fb182350'
if hashlib.sha256(native_path.read_bytes()).hexdigest()!=native_sha:raise RuntimeError('Fallback input runtime differs from the pinned input library; refused')
parts.append(f'm.frontend_native_name={native_name!r}\n')
for name in VENDOR+OWN:
    folder='vendor' if name in VENDOR else 'src'
    parts.append(f'm.{name}=(function()\n'+(ROOT/folder/f'{name}.lua').read_text(encoding='utf-8')+'\nend)()\n')
parts.append('return (function()\n'+(ROOT/'src/editor.lua').read_text()+'\nend)()\n')
out=ROOT/'dist/armor_lut_editor';out.mkdir(parents=True,exist_ok=True)
(out/'mod.lua').write_text(''.join(parts),encoding='utf-8')
(out/'manifest.json').write_text(json.dumps({'name':'Epic LUT R3','author':'Goose','credits':'CowboyBingus LUT discovery and native adapters'},indent=2))
(out/'presets').mkdir(exist_ok=True)
(out/'presets/README.txt').write_text('Place .dbflut presets here. MCM filename field takes the filename without .dbflut. Export selects its new filename for easy re-import.\n')
(out/'files').mkdir(exist_ok=True)
(out/'files/README.txt').write_text('Working float DDS, external DDS/EXR and private original LUT snapshots live here. EXR conversion uses the local file service.\n')
(out/native_name).write_bytes(native_path.read_bytes())
(out/'runtime.zip').write_bytes(runtime_bytes)
(out/'runtime-manifest.json').write_text(json.dumps({'sha256':runtime_hash,'bytes':len(runtime_bytes)},indent=2))
(out/'library.txt').write_text(native_name)
(out/'LICENSE-CowboyBingus.txt').write_bytes((ROOT/'vendor/LICENSE').read_bytes())
receipt={'name':'Epic LUT R3','author':'Goose',
 'upstream':'https://github.com/CowboyBingus/MatchYourColors','upstream_commit':'21126db5538b84fe5b2366cda3be6803b1c2e05a',
 'menu_foundation':'DBF-MCM maintained source snapshot; same generated editor specs and canonical settings folder',
 'input_runtime_sha256':native_sha,
 'menu_sources_sha256':{n:hashlib.sha256((ROOT/'vendor/menu'/f'{n}.lua').read_bytes()).hexdigest()for n in MENU},
 'mod_sha256':hashlib.sha256((out/'mod.lua').read_bytes()).hexdigest(),
 'vendor_sha256':{n:hashlib.sha256((ROOT/'vendor'/f'{n}.lua').read_bytes()).hexdigest() for n in VENDOR}}
(ROOT/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2))
from tools.lua_archive import hash_name,write,read
import struct
entry_name='mods/goose/epic_lut/startup'
startup=(ROOT/'src/startup_bsl.lua').read_text(encoding='utf-8').replace('__NATIVE_NAME__',native_name).replace('__NATIVE_HEX__',native_path.read_bytes().hex()).replace('-- __MODULE__',(out/'mod.lua').read_text(encoding='utf-8')).replace('-- __BRIDGE__',(ROOT/'src/startup_bridge.lua').read_text(encoding='utf-8'))
if args.diagnostic:
    needle='local ctx={api=2,dir=base,cleanups={},globals={}}'
    assert startup.count(needle)==1
    startup=startup.replace(needle,needle+"\nlocal phase_sequence=0\nfunction ctx.phase(message)phase_sequence=phase_sequence+1;local f=io.open(base..'/startup-phase.txt','wb');if f then f:write(tostring(phase_sequence),' ',tostring(os.time()),' ',message,'\\n');f:close()end end\n")
(ROOT/'dist/Epic-LUT-BSL-startup.lua').write_text(startup,encoding='utf-8')
envelope=struct.pack('<II',len(startup.encode()),2)+startup.encode()
archive=write({hash_name(entry_name):envelope})
assert read(archive)[hash_name(entry_name)][1]==envelope
assert startup.startswith('-- HD2-Addon: '+entry_name+'\n')
manager={'Version':1,'Guid':'2ef4f437-4a43-47ed-b1d0-15505f11c761','Author':'Goose','Name':'Epic LUT R3','Description':'Requires Bingus Shared Loader v15+ for this manager entry. Uses MCM when compatible, own in-game menu otherwise. Includes its own Windows x64 Python runtime and codecs; no Python installation or setup is required.','Options':[{'Name':'Bingus Shared Loader startup','Include':['data']}]}
release_name='Epic-LUT-R3-grouped-colors-test.zip'if args.grouped_colors else 'Epic-LUT-R3-alpha-ui-test.zip'if args.alpha_ui else 'Epic-LUT-R3-direct-f10-textures-test.zip'if args.with_texture_application else 'Epic-LUT-R3-direct-f10-test.zip'if args.without_binding_adapter else 'Epic-LUT-R3-interactive-menu-test.zip'if args.interactive_menu else 'Epic-LUT-R3-readonly-menu-test.zip'if args.readonly_menu else 'Epic-LUT-R3-idle-poll-only-test.zip'if args.idle_poll_only else 'Epic-LUT-R3-input-library-only-test.zip'if args.input_library_only else 'Epic-LUT-R3-registry-only-test.zip'if args.registry_only else 'Epic-LUT-R3-discovery-no-menu-test.zip'if args.without_editor_menu else 'Epic-LUT-R3-discovery-only-test.zip'if args.discovery_only else ('Epic-LUT-R3-reader-diagnostic.zip'if args.diagnostic else 'Epic-LUT-R3.zip')
with zipfile.ZipFile(ROOT/'dist'/release_name,'w',zipfile.ZIP_DEFLATED) as z:
    z.writestr('manifest.json',json.dumps(manager,indent=2))
    z.writestr('data/9ba626afa44a3aa3.patch_0',archive)
    z.writestr('data/9ba626afa44a3aa3.patch_0.stream',runtime_bytes)
    z.writestr('data/9ba626afa44a3aa3.patch_0.gpu_resources',b'')
    for name in ['mod.lua','manifest.json','library.txt',native_name,'runtime.zip','runtime-manifest.json','LICENSE-CowboyBingus.txt','files/README.txt','presets/README.txt']:
        z.write(out/name,'armor_lut_editor/'+name)
    helpers=['README.md','requirements-companion.txt','setup_companion.ps1','start_editor.ps1','companion/index.html','tools/companion.py','tools/native_import.py','tools/remap.py','tools/lut_files.py','tools/extract_luts.py','tools/runtime_guard.py','tools/runtime_paths.py','tools/runtime_paths.ps1','tools/deploy_guard.ps1','docs/FILES.md','docs/MAPPING.md','docs/FRONTEND.md','docs/BSL.md','docs/NEXUS.md','docs/NEXUS-BBCODE.txt','docs/RELEASE-R3.md']
    helpers+=['tools/owner_watch.py','tools/start_bundled.ps1','tools/game_catalog.py','tools/runtime-lock.json']
    for name in helpers:z.write(ROOT/name,name)
print(out/'mod.lua')
