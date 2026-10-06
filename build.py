from pathlib import Path
import hashlib,json,zipfile
from tools.runtime_guard import require_physical_runtime
require_physical_runtime()
ROOT=Path(__file__).resolve().parent
VENDOR=['bingus_runtime','bingus_memory','engine','avatar','kits','files','slim','texture']
OWN=['palette','catalog','dds','semantics','document','provider_menu','open_companion','editor_features','session','presets']
parts=['-- Epic LUT R2; LUT discovery and native adapters by CowboyBingus.\nlocal m={}\n']
for name in VENDOR+OWN:
    folder='vendor' if name in VENDOR else 'src'
    parts.append(f'm.{name}=(function()\n'+(ROOT/folder/f'{name}.lua').read_text(encoding='utf-8')+'\nend)()\n')
parts.append('return (function()\n'+(ROOT/'src/editor.lua').read_text()+'\nend)()\n')
out=ROOT/'dist/armor_lut_editor';out.mkdir(parents=True,exist_ok=True)
(out/'mod.lua').write_text(''.join(parts),encoding='utf-8')
(out/'manifest.json').write_text(json.dumps({'name':'Epic LUT R2','author':'David / Nova; CowboyBingus LUT discovery and adapters'},indent=2))
(out/'presets').mkdir(exist_ok=True)
(out/'presets/README.txt').write_text('Place .dbflut presets here. MCM filename field takes the filename without .dbflut. Export selects its new filename for easy re-import.\n')
(out/'files').mkdir(exist_ok=True)
(out/'files/README.txt').write_text('Working float DDS, external DDS/EXR and private original LUT snapshots live here. EXR conversion uses the local Epic LUT companion.\n')
(out/'LICENSE-CowboyBingus.txt').write_bytes((ROOT/'vendor/LICENSE').read_bytes())
receipt={'source_workspace':'Epic LUT standalone source','promotion':'isolated candidate; maintained MCM unchanged',
 'upstream':'https://github.com/CowboyBingus/MatchYourColors','upstream_commit':'21126db5538b84fe5b2366cda3be6803b1c2e05a',
 'mod_sha256':hashlib.sha256((out/'mod.lua').read_bytes()).hexdigest(),
 'vendor_sha256':{n:hashlib.sha256((ROOT/'vendor'/f'{n}.lua').read_bytes()).hexdigest() for n in VENDOR}}
(ROOT/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2))
with zipfile.ZipFile(ROOT/'dist/Epic-LUT-R2.zip','w',zipfile.ZIP_DEFLATED) as z:
    for f in out.rglob('*'):
        if f.is_file():z.write(f,'armor_lut_editor/'+f.relative_to(out).as_posix())
    for f in [ROOT/'README.md',ROOT/'BUILD-RECEIPT.json']:z.write(f,f.name)
print(out/'mod.lua')
