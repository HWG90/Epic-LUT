"""Build a separate, undeployed LLL module and peer companion."""
from pathlib import Path
import hashlib
import json
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = ROOT/'dist/broadcast-poc'
OUT.mkdir(parents=True, exist_ok=True)
sources = {
    'bingus_runtime':'vendor/bingus_runtime.lua',
    'bingus_memory':'vendor/bingus_memory.lua',
    'engine':'vendor/engine.lua', 'avatar':'vendor/avatar.lua',
    'dds':'src/core/dds.lua', 'binding_session':'src/gear/binding_session.lua',
    'remote':'prototype/broadcast/remote.lua',
}
parts = ['-- Epic LUT Broadcast POC. Native adapters: CowboyBingus.\nlocal m={}\n']
for name, path in sources.items():
    parts.append(f'm.{name}=(function()\n{(ROOT/path).read_text(encoding="utf-8")}\nend)()\n')
parts.append((HERE/'runtime.lua').read_text(encoding='utf-8'))
module = ''.join(parts)
(OUT/'mod.lua').write_text(module, encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps({'name':'Epic LUT Broadcast POC','version':'0.1.0','author':'Goose'}))
(OUT/'BUILD-RECEIPT.json').write_text(json.dumps({
    'status':'undeployed experimental candidate',
    'mod_sha256':hashlib.sha256(module.encode()).hexdigest(),
    'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
        for p in [*sources.values(),'prototype/broadcast/runtime.lua']},
}, indent=2))
archive = ROOT/'dist/Epic-LUT-Broadcast-POC-0.1.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for name in ('mod.lua','manifest.json','BUILD-RECEIPT.json'):
        z.write(OUT/name,'epic_lut_broadcast_poc/'+name)
    for name in ('peer.py','README.md'):
        z.write(HERE/name,name)
    z.write(ROOT/'vendor/LICENSE','LICENSE-CowboyBingus.txt')
print(archive)
