from pathlib import Path
import hashlib,json,struct,sys,zipfile,io
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lua_archive import read,hash_name,LUA_TYPE

root=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1])if len(sys.argv)>1 else root/'dist/Epic-LUT-R3.zip'
with zipfile.ZipFile(candidate)as z:
    assert z.testzip()is None and len(z.namelist())==len(set(z.namelist()))
    assert json.loads(z.read('manifest.json'))['Author']=='Goose'
    assert json.loads(z.read('armor_lut_editor/manifest.json'))['author']=='Goose'
    resources=read(z.read('data/9ba626afa44a3aa3.patch_0'));entry='mods/goose/epic_lut/startup'
    assert list(resources)==[hash_name(entry)]
    kind,body=resources[hash_name(entry)];length,version=struct.unpack_from('<II',body)
    assert kind==LUA_TYPE and version==2 and length==len(body)-8
    assert body[8:].startswith(('-- HD2-Addon: '+entry+'\n').encode())
    library=z.read('armor_lut_editor/mcm_input_9bc2033ffbb3.dll')
    assert hashlib.sha256(library).hexdigest()=='7e9a41484881fa851184b64a7b09f568b2f42637646bc85426a89fb5fb182350'
    assert library.hex().encode()in body and b"author='Goose'"in z.read('armor_lut_editor/mod.lua')
    assert not any(name.endswith(('.dds','.exr','.ini','.rar','.dbflut'))for name in z.namelist())
    assert 'tools/native_import.py'in z.namelist()and 'docs/BSL.md'in z.namelist()
    runtime=z.read('armor_lut_editor/runtime.zip');manifest=json.loads(z.read('armor_lut_editor/runtime-manifest.json'))
    assert z.read('data/9ba626afa44a3aa3.patch_0.stream')==runtime
    assert hashlib.sha256(runtime).hexdigest()==manifest['sha256']and len(runtime)==manifest['bytes']
    with zipfile.ZipFile(io.BytesIO(runtime))as bundled:
        assert bundled.testzip()is None
        assert 'python.exe'in bundled.namelist()and 'python313.dll'in bundled.namelist()
        assert json.loads(bundled.read('BUNDLE-MANIFEST.json'))==json.loads((root/'tools/runtime-lock.json').read_text())
        assert any(name.endswith('LICENSE.txt')for name in bundled.namelist())
        assert any('numpy/'in name for name in bundled.namelist())and any('OpenEXR'in name and name.endswith('.pyd')for name in bundled.namelist())
    assert struct.unpack_from('<I',z.read('data/9ba626afa44a3aa3.patch_0'),104+60)[0]==0,'Runtime sidecar became an engine resource dependency'
    assert b'm.runtime_hash='in body and runtime[:64].hex().encode()not in body,'Binary runtime expanded into startup Lua'
    if candidate.name=='Epic-LUT-R3.zip':assert b'm.direct_menu_keys=true'in body,'Ordinary release re-enabled the unproven binding adapter'
    assert 'tools/game_catalog.py'in z.namelist()
    assert b'waiting for archive worker'in body and b'loading validated original LUTs'in body,'Release contains the obsolete in-game archive reader'
print('PASS: single release ZIP, declared BSL resource/hash/envelope, same loose model, Goose metadata, exact reviewed DLL, helper dependencies, no user textures/settings, ZIP integrity')
