"""Build-only download and packaging of the official isolated Windows runtime."""
from pathlib import Path
import hashlib,json,subprocess,sys,urllib.request,zipfile
ROOT=Path(__file__).resolve().parents[1]
VERSION='3.13.16'
URL=f'https://www.python.org/ftp/python/{VERSION}/python-{VERSION}-embed-amd64.zip'
EXPECTED='97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297'
cache=ROOT/'dist/runtime-cache';cache.mkdir(parents=True,exist_ok=True)
archive=cache/f'python-{VERSION}-embed-amd64.zip'
if not archive.exists():
 with urllib.request.urlopen(URL,timeout=60)as response:archive.write_bytes(response.read())
assert hashlib.sha256(archive.read_bytes()).hexdigest()==EXPECTED,'Official Python checksum mismatch'
wheels=cache/'wheels';wheels.mkdir(exist_ok=True)
lock_path=ROOT/'tools/runtime-lock.json'
if lock_path.exists():
 lock=json.loads(lock_path.read_text())
 for wheel in lock['wheels']:
  path=wheels/wheel['name']
  if not path.exists():
   with urllib.request.urlopen(wheel['url'],timeout=60)as response:path.write_bytes(response.read())
  assert hashlib.sha256(path.read_bytes()).hexdigest()==wheel['sha256'],'Codec wheel checksum mismatch'
 selected=[wheels/wheel['name']for wheel in lock['wheels']]
else:
 subprocess.run([sys.executable,'-m','pip','download','--only-binary=:all:','--platform','win_amd64','--implementation','cp','--python-version','313','--abi','cp313','--dest',str(wheels),'-r',str(ROOT/'requirements-companion.txt')],check=True)
 selected=list(wheels.glob('*.whl'));records=[]
 for path in selected:
  package,version=path.name.split('-')[:2]
  with urllib.request.urlopen(f'https://pypi.org/pypi/{package}/{version}/json',timeout=30)as response:metadata=json.load(response)
  upstream=next(item for item in metadata['urls']if item['filename']==path.name)
  digest=hashlib.sha256(path.read_bytes()).hexdigest();assert digest==upstream['digests']['sha256']
  records.append({'name':path.name,'url':upstream['url'],'sha256':digest})
 lock={'python':{'version':VERSION,'url':URL,'sha256':EXPECTED},'wheels':records}
 lock_path.write_text(json.dumps(lock,indent=2)+'\n')
files={}
with zipfile.ZipFile(archive)as z:
 for name in z.namelist():
  if not name.endswith('/'):files[name]=z.read(name)
files['python313._pth']=b'python313.zip\n.\nLib/site-packages\n../tools\nimport site\n'
for path in selected:
 with zipfile.ZipFile(path)as z:
  for name in z.namelist():
   if name.endswith('/'):continue
   assert not name.startswith('/')and '..'not in Path(name).parts,'Invalid wheel path'
   target='Lib/site-packages/'+name
   if '.data/'in name:
    prefix,tail=name.split('.data/',1);kind,tail=tail.split('/',1)
    assert kind in ('purelib','platlib'),'Unsupported wheel layout'
    target='Lib/site-packages/'+tail
   assert target not in files,'Wheel file collision';files[target]=z.read(name)
files['BUNDLE-MANIFEST.json']=json.dumps(lock,indent=2).encode()
out=ROOT/'dist/runtime';out.mkdir(exist_ok=True)
with zipfile.ZipFile(out/'runtime.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6)as z:
 for name,data in sorted(files.items()):
  info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,data)
print(f'Bundled runtime: {len(files)} files, {(out/"runtime.zip").stat().st_size/1024/1024:.1f} MiB')
