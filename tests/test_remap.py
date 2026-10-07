from pathlib import Path
import json,sys,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import numpy as np
from companion import Editor
from lut_files import save,load
from remap import remap

source=np.arange(2*23*4,dtype=np.float32).reshape(2,23,4)-100;original=np.full((5,23,4),.125,dtype=np.float32)
for material in (False,True):
 for emission in (False,True):
    out,_=remap(source,original,material,emission)
    assert out.shape==original.shape and np.array_equal(out[:,[8,11,15]],original[:,[8,11,15]])
    assert np.array_equal(out[:,13,1:],original[:,13,1:])
    assert np.array_equal(out[:,13,0],original[:,13,0])==emission
    assert np.array_equal(out[:,1],original[:,1])==material
    assert out[0,0,0]==source[0,0,0]and out[-1,0,0]==source[-1,0,0]
    assert (out[:,0,3]==original[:,0,3]).all()==material
pattern=np.full((3,3,4),-2,dtype=np.float32);out,detail=remap(source,pattern)
assert 'base color RGB only'in detail and np.array_equal(out[:,1:],pattern[:,1:])and (out[:,0,3]==pattern[:,0,3]).all()
with tempfile.TemporaryDirectory()as tmp:
    editor=Editor(tmp);editor.data=source;editor.path=editor.file('palette.dds');editor.resource='0000000000009999'
    targets=[{'kind':kind,'key':kind+str(i),'hash':str(i),'width':w,'height':h,'working':kind+str(i)+'.dds','original':kind+str(i)+'-original.dds'}for kind,i,w,h in [('armor',1,23,5),('armor',2,3,3),('armor',3,7,2),('helmet',4,23,5)]]
    editor.file('current.json').write_text(json.dumps({'luts':targets}))
    for t in targets:
        data=np.full((t['height'],t['width'],4),.125,dtype=np.float32);save(editor.file(t['working']),data);save(editor.file(t['original']),data)
    result=editor.command('quick_apply',{'kind':'armor','preserve_material':False,'preserve_emission':False})['quick_result']
    assert result=={'kind':'armor','attempted':3,'applied':2,'skipped':1,'remapped':2,'partial':1,'prefix':'armor1'}
    assert (load(editor.file('helmet4.dds'))==.125).all()and(load(editor.file('armor3.dds'))==.125).all()
    before=editor.file('armor1.dds').read_bytes();editor.file('armor2-original.dds').write_bytes(b'bad')
    try:editor.command('quick_apply',{'kind':'armor'})
    except ValueError:pass
    else:raise AssertionError('Invalid original was accepted')
    assert editor.file('armor1.dds').read_bytes()==before and not editor.file('apply.lock').exists()
print('PASS: cross-item row/layout remapping, independent preservation policies, HDR/signed floats, retained unknown fields, target isolation, partial/skipped reporting, and validation before batch writes')
