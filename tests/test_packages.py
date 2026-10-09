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
    tall=np.arange(64*23*4,dtype=np.float32).reshape(64,23,4)/13-100;tall[63,13,3]=-0.0
    tallraw=encode_dds(tall);tallpatch=bytearray(patch)
    tallpatch[184+192:184+340]=tallraw[:148];struct.pack_into('<I',tallpatch,104+64,len(tallraw)-148)
    with zipfile.ZipFile(root/'tall.zip','w')as z:z.writestr('9ba626afa44a3aa3.patch_0',tallpatch);z.writestr('9ba626afa44a3aa3.patch_0.gpu_resources',tallraw[148:])
    tallout=import_package(root/'tall.zip',root/'tall-out');assert tallout[0]['height']==64 and load(tallout[0]['output']).tobytes()==tall.tobytes()
    unsafe=root/'unsafe.zip'
    with zipfile.ZipFile(unsafe,'w')as z:z.writestr('../escape.dds',raw)
    reject(lambda:import_package(unsafe,root/'unsafe-out'))
    corrupt=root/'corrupt.zip'
    with zipfile.ZipFile(corrupt,'w')as z:z.writestr('bad.dds',raw[:-1])
    reject(lambda:import_package(corrupt,root/'bad-out'))
    workspace=root/'editor';editor=Editor(workspace)
    (workspace/'current.json').write_text(json.dumps({'luts':[{'key':'armor-test','hash':'0000000000001234','width':23,'height':8,'working':'live.dds'}]}))
    editor.upload_package('packaged.zip',packaged.read_bytes());assert editor.matches==['armor-test']and not(workspace/'live.dds').exists()
    editor.command('publish',{'target':'armor-test'});assert load(workspace/'live.dds').tobytes()==data.tobytes()
    wrong=Editor(root/'wrong');wrong.upload_package('packaged.zip',packaged.read_bytes());assert not wrong.matches and not(wrong.folder/'live.dds').exists(),'Wrong target applied automatically'
    multi=Editor(root/'multi');(multi.folder/'current.json').write_text(json.dumps({'luts':[{'key':kind,'hash':'0000000000001234','width':23,'height':8,'working':kind+'.dds'}for kind in('armor','helmet')]}))
    multi.upload_package('packaged.zip',packaged.read_bytes());assert len(multi.matches)==2 and not(multi.folder/'armor.dds').exists(),'Ambiguous target was applied'
    batch=Editor(root/'batch');batch.resource=None
    batch.data=data.copy()
    entries=[{'key':kind+str(i),'kind':kind,'hash':str(i),'width':w,'height':h,'working':kind+str(i)+'.dds'} for kind,i,w,h in [('armor',1,23,8),('armor',2,23,8),('armor',3,3,1),('helmet',4,23,8)]]
    (batch.folder/'current.json').write_text(json.dumps({'luts':entries}))
    from lut_files import save
    for v in entries:save(batch.folder/v['working'],np.zeros((v['height'],v['width'],4),dtype=np.float32))
    result=batch.command('publish_all',{'kind':'armor'});assert result['applied_batch']['count']==2 and result['applied_batch']['skipped']==1
    assert load(batch.folder/'armor1.dds').tobytes()==data.tobytes()and load(batch.folder/'armor2.dds').tobytes()==data.tobytes()
    assert not load(batch.folder/'helmet4.dds').any()and not load(batch.folder/'armor3.dds').any()
    prior=(batch.folder/'armor1.dds').read_bytes();(batch.folder/'armor2.dds').write_bytes(b'bad')
    batch.data[:]=.125;reject(lambda:batch.command('publish_all',{'kind':'armor'}))
    assert (batch.folder/'armor1.dds').read_bytes()==prior and not(batch.folder/'apply.lock').exists()and not list(batch.folder.glob('*.batch-*'))
    save(batch.folder/'armor2.dds',data)
    from unittest.mock import patch
    import companion
    real_replace=companion.os.replace;calls=[0]
    def fail_second(source,target):
        calls[0]+=1
        if calls[0]==2:raise OSError('simulated commit failure')
        return real_replace(source,target)
    before={v['working']:(batch.folder/v['working']).read_bytes() for v in entries}
    with patch.object(companion.os,'replace',fail_second):
        try:batch.command('publish_all',{'kind':'armor'})
        except OSError:pass
        else:raise AssertionError('Simulated commit failure was ignored')
    assert all((batch.folder/name).read_bytes()==raw for name,raw in before.items())and not(batch.folder/'apply.lock').exists()
    save(batch.folder/'palette1.dds',data);second=data.copy();second[:]=.625;save(batch.folder/'palette2.dds',second)
    batch.imports=[{'name':'palette1.dds','resource':'1'},{'name':'palette2.dds','resource':'2'}]
    batch.command('publish_all',{'kind':'armor'})
    assert load(batch.folder/'armor1.dds').tobytes()==data.tobytes()and load(batch.folder/'armor2.dds').tobytes()==second.tobytes()
print('PASS: raw DDS ZIP, packaged texture ZIP, traversal/malformed rejection, float fidelity, exact auto-match, unmatched/ambiguous target preview-only')
