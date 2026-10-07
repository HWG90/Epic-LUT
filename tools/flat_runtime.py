"""Expose the bundled interpreter as ordinary files, including its standard library."""
import hashlib, io, json, zipfile

def flatten(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        files={name:archive.read(name)for name in archive.namelist()if not name.endswith('/')}
    library=files.pop('python313.zip')
    with zipfile.ZipFile(io.BytesIO(library))as archive:
        for name in archive.namelist():
            if name.endswith('/'):continue
            assert not name.startswith('/')and '..'not in name.split('/')
            target='Lib/'+name;assert target not in files
            files[target]=archive.read(name)
    files['python313._pth']=b'Lib\n.\nLib/site-packages\n../tools\nimport site\n'
    assert not any(name.lower().endswith(('.zip','.whl','.7z','.rar'))for name in files)
    manifest=json.dumps({'runtime_identity':hashlib.sha256(raw).hexdigest(),
        'files':{name:hashlib.sha256(data).hexdigest()for name,data in sorted(files.items())}},sort_keys=True).encode()
    files['FLAT-MANIFEST.json']=manifest
    return files,hashlib.sha256(manifest).hexdigest()
