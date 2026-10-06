import json,struct,sys,tempfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lut_files import encode_dds,load
from extract_luts import import_package,TEXTURE
from companion import Editor
import numpy as np
def reject(call):
    try:call()
    except (ValueError,RuntimeError):return
    raise AssertionError('Unsafe package accepted')
with tempfile.TemporaryDirectory(prefix='epic-package-tests-') as temp:
    root=Path(temp);data=np.ones((8,23,4),dtype=np.float32);data[0,13]=[8.5,1000000,-12.5,.46];raw=encode_dds(data)
    rawzip=root/'raw.zip'
    with zipfile.ZipFile(rawzip,'w')as z:z.writestr('folder/palette.dds',raw);z.writestr('README.txt','Never execute archive text')
    out=import_package(rawzip,root/'raw-out');assert len(out)==1 and load(out[0]['output']).tobytes()==data.tobytes()
    patch=bytearray(184);struct.pack_into('<I',patch,0,0xf0000011);struct.pack_into('<I',patch,8,1);main=bytes(192)+raw[:148]
    struct.pack_into('<7Q6I',patch,104,0x1234,TEXTURE,184,0,0,0,0,len(main),0,len(raw)-148,16,64,1);patch.extend(main)
    packaged=root/'packaged.zip'
    with zipfile.ZipFile(packaged,'w')as z:z.writestr('9ba626afa44a3aa3.patch_0',patch);z.writestr('9ba626afa44a3aa3.patch_0.gpu_resources',raw[148:]);z.writestr('9ba626afa44a3aa3.patch_0.stream',b'')
    out=import_package(packaged,root/'patch-out');assert len(out)==1 and out[0]['resource']=='0000000000001234'and load(out[0]['output']).tobytes()==data.tobytes()
    unsafe=root/'unsafe.zip'
    with zipfile.ZipFile(unsafe,'w')as z:z.writestr('../escape.dds',raw)
    reject(lambda:import_package(unsafe,root/'unsafe-out'))
    corrupt=root/'corrupt.zip'
    with zipfile.ZipFile(corrupt,'w')as z:z.writestr('bad.dds',raw[:-1])
    reject(lambda:import_package(corrupt,root/'bad-out'))
    workspace=root/'editor';editor=Editor(workspace)
    (workspace/'current.json').write_text(json.dumps({'luts':[{'key':'armor-test','hash':'0000000000001234','width':23,'height':8,'working':'live.dds'}]}))
    editor.upload_package('packaged.zip',packaged.read_bytes());assert editor.matches==['armor-test']and load(workspace/'live.dds').tobytes()==data.tobytes()
    wrong=Editor(root/'wrong');wrong.upload_package('packaged.zip',packaged.read_bytes());assert not wrong.matches and not(wrong.folder/'live.dds').exists(),'Wrong target applied automatically'
    multi=Editor(root/'multi');(multi.folder/'current.json').write_text(json.dumps({'luts':[{'key':kind,'hash':'0000000000001234','width':23,'height':8,'working':kind+'.dds'}for kind in('armor','helmet')]}))
    multi.upload_package('packaged.zip',packaged.read_bytes());assert len(multi.matches)==2 and not(multi.folder/'armor.dds').exists(),'Ambiguous target was applied'
print('PASS: raw DDS ZIP, packaged texture ZIP, traversal/malformed rejection, float fidelity, exact auto-match, unmatched/ambiguous target preview-only')
