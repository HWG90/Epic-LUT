from pathlib import Path
import importlib.util,json,hashlib,re,argparse
ROOT=Path(__file__).resolve().parents[1]

parser=argparse.ArgumentParser(description='Build the scoped LLL R30 Epic LUT package')
parser.add_argument('--preview-animation',action='store_true',help='Enable authored salute playback in a separately named development package')
parser.add_argument('--dev-stamp',help='Shared identity for paired local development builds')
parser.add_argument('--output',help='ZIP filename within dist/releases/modular-20261010')
args=parser.parse_args()
if args.output and (Path(args.output).name!=args.output or not args.output.endswith('.zip')):
    parser.error('--output must be a ZIP filename')
if args.preview_animation and not args.output:
    parser.error('--preview-animation requires an explicit development filename')
if args.dev_stamp is not None and (not args.output or not args.output.startswith('Epic-LUT-Dev-') or not re.fullmatch(r'[A-Za-z0-9._-]{1,64}',args.dev_stamp)):
    parser.error('--dev-stamp requires a valid token and an explicit Epic-LUT-Dev- filename')

def package(root,mod_id,title,version,main,modules,extra=None,restart_only=False):
    import hashlib,json,zipfile
    output=root/'dist/releases/modular-20261010';output.mkdir(parents=True,exist_ok=True)
    folder=output/mod_id if args.output is None else output/Path(args.output).stem/mod_id
    folder.mkdir(parents=True,exist_ok=True)
    files={'main.lua':main.encode('utf-8'),'config/defaults.cfg':b'{}\n'}
    files.update({name:body.encode('utf-8') if isinstance(body,str) else body for name,body in modules.items()})
    files.update(extra or {})
    manifest={'id':mod_id,'name':title,'version':version,'author':'Goose','lll':{'entry':'main.lua','defaults':'config/defaults.cfg','modules':sorted(modules),'restart_only':restart_only,'retain_until_exit':True}}
    files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    files['INSTALL.txt']=('Requires LLL R30 or later. Copy '+mod_id+' into LLL/Helldivers2/Mods. Remove the old loose/bundled provider of the same mod before starting. This is a source-layout migration; native DLLs need a normal restart. Existing mod settings are retained. Do not activate alongside the archive provider. '+('This mod remains restart-only; startup hook ownership is unchanged.' if restart_only else 'Lifecycle callbacks and cleanup are preserved.')+'\n').encode()
    files['FILES-SHA256.txt']=''.join(hashlib.sha256(body).hexdigest()+'  '+name+'\n' for name,body in sorted(files.items())).encode()
    for name,body in files.items():
        path=folder/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)
    target=output/(args.output or mod_id+'-'+version+'-LLL-Modular.zip')
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
        for name,body in sorted(files.items()):z.writestr(mod_id+'/'+name,body)
    print(target)
    return target

spec=importlib.util.spec_from_file_location('epic_inventory',ROOT/'tools/module_inventory.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv)
version=(ROOT/'VERSION').read_text().strip()
mode='authored_salute' if args.preview_animation else 'disabled'
label=Path(args.output).stem.removesuffix('-LLL') if args.output else 'Epic-LUT-'+version+'-LLL-Modular'
title='Epic LUT '+version+(' Preview Animation Test' if args.preview_animation else '')
main=['local m={direct_menu_keys=true,direct_lut=true}','mod.scope.m=m','m.version='+json.dumps(version),'m.preview_animation='+json.dumps(mode),'m.dev_build_id='+json.dumps(args.dev_stamp or 'release'),'m.description='+json.dumps(title+' modular LLL package'),'m.build_label='+json.dumps(label)]
extra={};modules={}
for field,path in [('debug_lut_dds_hex','assets/debug-lut.dds'),('original_snapshot_script','tools/original_snapshots.ps1'),('original_snapshot_reader','tools/original_snapshots.cs'),('authored_preview_script','tools/authored_preview.ps1'),('authored_preview_reader','tools/authored_preview_reader.cs'),('zip_import_script','tools/import_zip.ps1')]:
    extra[path]=(ROOT/path).read_bytes();main.append('m.'+field+'=mod.read("'+path+'"):gsub(".",function(c)return string.format("%02x",string.byte(c))end)')
native='mcm_input_9bc2033ffbb3.dll';data=(ROOT.parent/'DBF-MCM/native/build'/native).read_bytes();assert hashlib.sha256(data).hexdigest()=='7e9a41484881fa851184b64a7b09f568b2f42637646bc85426a89fb5fb182350'
extra[native]=data;extra['library.txt']=native.encode();extra['LICENSE-CowboyBingus.txt']=(ROOT/'vendor/LICENSE').read_bytes();main.append('m.frontend_native_name='+json.dumps(native))
for name in inv.MENU:
    path='vendor/menu/'+name+'.lua';modules[path]=(ROOT/path).read_bytes();main.append('m.ui_'+name+'=mod.require("'+path+'")')
for name in inv.VENDOR:
    path='vendor/'+name+'.lua';modules[path]=(ROOT/path).read_bytes();main.append('m.'+name+'=mod.require("'+path+'")')
for name in inv.OWN+inv.PREVIEW:
    path=inv.source_path(name);modules[path]=(ROOT/path).read_bytes();main.append('m.'+name+'=mod.require("'+path+'")')
preferences_path=inv.source_path('preferences')
source=(ROOT/preferences_path).read_text();defaults={};edits=[]
for match in re.finditer(r'\bdefault\s*=\s*(true|false|-?\d+(?:\.\d+)?)',source):
    keys=re.findall(r"\bid\s*=\s*['\"]([\w_-]+)['\"]",source[:match.start()])
    if not keys:continue
    key=keys[-1];defaults[key]=json.loads(match[1]);edits.append((match.start(),match.end(),'default = mod.config.preferences['+json.dumps(key)+']'))
for start,end,replacement in reversed(edits):source=source[:start]+replacement+source[end:]
modules[preferences_path]=source
extra['config/defaults.cfg']=(json.dumps({'preferences':defaults},indent=2)+'\n').encode()
main.append('m.native_import=m.windows')
for name in ['direct_editor','player_preview_candidate']:
    path=inv.source_path(name);modules[path]=(ROOT/path).read_bytes()
editor_path=inv.source_path('direct_editor')
source=(ROOT/editor_path).read_text().replace('frontend.preferences = preferences','frontend.preferences = preferences\n        preferences.mount(frontend.api)\n        local console_fields={}\n        for key,control in pairs(frontend.api.mods.epic_lut_preferences.controls)do\n            local field=key\n            if control.type=="button" then console_fields[field]={call=function()return preferences.handle.activate(field)end}\n            else console_fields[field]={type=control.type=="toggle" and "boolean" or "number",get=function()return preferences.handle.get(field)end,set=function(v)return preferences.handle.set(field,v)end}end\n        end\n        mod.expose("epiclut",{preferences=console_fields})')
modules[editor_path]=source
main+=['mod.scope.editor=mod.require("'+inv.source_path('direct_editor')+'")','mod.scope.PREVIEW_INSPECT_ONLY=false','mod.scope.PREVIEW_ANIMATION_ENABLED='+str(args.preview_animation).lower(),'return mod.require("'+inv.source_path('player_preview_candidate')+'")']
package(ROOT,'armor_lut_editor',title,version,'\n'.join(main)+'\n',modules,extra)
