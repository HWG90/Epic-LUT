import importlib.util,json,struct,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lut_files import validate,load,save,encode_dds,decode_dds,convert_directory
from companion import Editor,Bridge
import numpy as np

def rejects(call):
    try:call()
    except (ValueError,RuntimeError,AssertionError):return
    raise AssertionError('Invalid input accepted')

with tempfile.TemporaryDirectory(prefix='epic-lut-test-') as temp:
    root=Path(temp);data=np.arange(8*23*4,dtype=np.float32).reshape(8,23,4)/7-10
    data[0,13]=[8.5,100000000,-12.5,.46];data[0,0,3]=2;data[1,1,1]=-0.0
    raw=encode_dds(data);assert decode_dds(raw).tobytes()==data.tobytes()
    save(root/'source.dds',data);save(root/'source.exr',data)
    assert load(root/'source.dds').tobytes()==data.tobytes()
    assert load(root/'source.exr').tobytes()==data.tobytes(),'EXR changed HDR/signed/negative-zero values'
    rejects(lambda:decode_dds(raw[:-1]));rejects(lambda:decode_dds(raw[:148]+raw[148:]+b'x'))
    bad=data.copy();bad[0,0,0]=np.inf;rejects(lambda:validate(bad))
    editor=Editor(root);editor.open('source.dds');before=editor.data.copy()
    editor.edit([0,0,0,0],[.25,0,0,0],[0]);assert editor.data[0,0,0]==.25
    mask=np.ones(data.shape,dtype=bool);mask[0,0,0]=False;assert np.array_equal(editor.data[mask],before[mask]),'Untouched emission/mode channel changed'
    editor.command('undo',{});assert editor.data.tobytes()==before.tobytes();editor.command('redo',{})
    editor.command('copy',{'rect':[0,1,0,2]});editor.command('paste',{'rect':[3,3,4,4]});assert np.array_equal(editor.data[3:5,4:7],editor.clipboard)
    editor.command('row_save',{'row':0,'name':'saved.row.json'});editor.command('row_load',{'row':2,'name':'saved.row.json'});assert np.array_equal(editor.data[0],editor.data[2])
    editor.command('camo',{'row':1,'pattern':3});assert np.array_equal(editor.data[1,21],[20,1,1,3])
    editor.command('save',{'name':'edited.dds'});assert load(root/'edited.dds').tobytes()==editor.data.tobytes()
    editor.command('debug',{});assert np.array_equal(editor.data[0,13],before[0,13])
    rejects(lambda:editor.file('../escape.dds'));rejects(lambda:editor.file('evil\\file.dds'))
    (root/'current.json').write_text(json.dumps({'luts':[{'key':'armor-test','hash':'0123456789abcdef','width':23,'height':8,'working':'live.dds'}]}))
    editor.command('publish',{'target':'armor-test'});assert load(root/'live.dds').tobytes()==editor.data.tobytes()
    rejects(lambda:editor.command('publish',{'target':'unknown'}))
    bridge=Bridge(editor);bridge.start()
    for _ in range(30):
        if (root/'source.exr.converted.dds').exists():break
        time.sleep(.1)
    bridge.stopped.set();bridge.join(2);assert load(root/'source.exr.converted.dds').tobytes()==data.tobytes()
    for width,height in [(16,5),(3,1)]:
        array=np.zeros((height,width,4),dtype=np.float32);save(root/f'type-{width}.exr',array);assert load(root/f'type-{width}.exr').tobytes()==array.tobytes()
    result=convert_directory(root,'dds');assert any(v['status']=='converted' for v in result)
print('PASS: DDS/EXR HDR/signed bitwise round trips, untouched emissive data, undo/redo, rectangular clipboard, row presets, camo, debug, quick save, protected paths, live publish and EXR bridge')
