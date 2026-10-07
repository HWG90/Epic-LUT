from pathlib import Path
import json,sys,tempfile,time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import numpy as np
from companion import Editor
from lut_files import save,load
from native_import import NativeImporter

with tempfile.TemporaryDirectory()as tmp:
    root=Path(tmp);folder=root/'working';folder.mkdir();data=np.zeros((8,23,4),dtype=np.float32);data[0,0]=[2.5,-.25,.75,1]
    chosen=root/'0000000000001234.dds';save(chosen,data)
    target={'key':'armor-kit-0000000000001234','kind':'armor','hash':'0000000000001234','width':23,'height':8,'working':'armor.dds'}
    (folder/'current.json').write_text(json.dumps({'luts':[target]}));save(folder/'armor.dds',np.zeros_like(data))
    service=NativeImporter(folder,Editor,picker=lambda owner,pid:chosen)
    service.handle('armor',json.dumps({'id':'pick1','action':'pick','owner':0,'pid':0}))
    result=(folder/'native-armor.result').read_text(encoding='utf-8');assert 'selected\tarmor-kit' in result and 'all-armor' in result
    assert '\nimported\t1\n'in result,'Successful import lacks provider-Off signal'
    assert not load(folder/'armor.dds').any(),'Choosing a file applied colors'
    service.handle('armor',json.dumps({'id':'apply1','action':'apply','session':'pick1','target':target['key']}))
    assert load(folder/'armor.dds').tobytes()==data.tobytes()
    try:service.handle('helmet',json.dumps({'id':'bad','action':'apply','session':'pick1','target':target['key']}))
    except ValueError:pass
    else:raise AssertionError('Armor session crossed helmet boundary')
    service.picker=lambda owner,pid:None;service.handle('armor',json.dumps({'id':'cancel1','action':'pick'}))
    assert 'canceled' in (folder/'native-armor.result').read_text()and '\nimported\t1\n'not in (folder/'native-armor.result').read_text()and load(folder/'armor.dds').tobytes()==data.tobytes()
    malformed=root/'bad.dds';malformed.write_bytes(b'bad');service.picker=lambda owner,pid:malformed
    (folder/'native-armor.request').write_text(json.dumps({'id':'broken','action':'pick'}));service.tick()
    for _ in range(100):
        if not service.busy:break
        time.sleep(.01)
    assert (folder/'native-armor.result').read_text().startswith('broken\t')and load(folder/'armor.dds').tobytes()==data.tobytes()
    restarted=NativeImporter(folder,Editor,picker=lambda *_:(_ for _ in ()).throw(AssertionError('Replayed request')));restarted.tick();assert not restarted.busy
print('PASS: native IPC success/cancel/error, exact selection without application, float import/apply, target isolation and no stale-dialog replay; OS dialog/focus need live verification')
