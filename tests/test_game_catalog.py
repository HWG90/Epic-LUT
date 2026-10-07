from pathlib import Path
import sys,struct,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import numpy as np
from game_catalog import discover,lz4,UNIT,MATERIAL,TEXTURE,LUT
from lut_files import encode_dds,load

def fixture(folder):
 folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
 archive='aaaaaaaaaaaaaaaa';unit='1111111111111111';material='2222222222222222';texture='3333333333333333'
 values=np.arange(2*23*4,dtype=np.float32).reshape(2,23,4)/8-10;values[0,13]=[8.5,100000000,-12.5,-0.0]
 unit_bytes=bytearray(132);struct.pack_into('<I',unit_bytes,112,116);struct.pack_into('<I',unit_bytes,116,1);struct.pack_into('<Q',unit_bytes,124,int(material,16))
 material_bytes=bytearray(148);struct.pack_into('<I',material_bytes,64,1);struct.pack_into('<IQ',material_bytes,136,LUT,int(texture,16))
 dds=encode_dds(values);texture_bytes=bytes(192)+dds[:148];parts=[(unit,UNIT,bytes(unit_bytes)),(material,MATERIAL,bytes(material_bytes)),(texture,TEXTURE,texture_bytes)]
 base=72+3*32;main=bytearray(base+3*80);struct.pack_into('<III',main,0,0xf0000011,3,3)
 for index,(name,kind,body)in enumerate(parts):
  at=len(main);main.extend(body);o=base+index*80;struct.pack_into('<QQQ',main,o,int(name,16),int(kind,16),at);struct.pack_into('<I',main,o+56,len(body))
  if kind==TEXTURE:struct.pack_into('<I',main,o+64,len(dds)-148)
 gpu=dds[148:];names=[archive,archive+'.gpu_resources'];bundle_name='bundles.00.nxa';index=bytearray(24+len(names)*24+4);struct.pack_into('<IIIIII',index,0,0x41415344,0,0,1,len(names),0)
 offsets=[]
 for name in [*names,bundle_name]:offsets.append(len(index));index.extend(name.encode()+b'\0')
 for i,total in enumerate((len(main),len(gpu))):
  entries_at=len(index);index.extend(struct.pack('<IIII',0,0,0 if i==0 else len(main),0));struct.pack_into('<QIIQ',index,24+i*24,total,offsets[i],1,entries_at)
 struct.pack_into('<I',index,24+len(names)*24,offsets[-1])
 def dsar(data,width):
  chunks=[data[i:i+width]for i in range(0,len(data),width)];result=bytearray(32+32*len(chunks));result[:4]=b'DSAR';struct.pack_into('<I',result,8,len(chunks));offset=0
  for i,chunk in enumerate(chunks):struct.pack_into('<QQIIB7x',result,32+i*32,offset,len(result),len(chunk),len(chunk),0);result.extend(chunk);offset+=len(chunk)
  return result
 (folder/'bundles.nxa').write_bytes(dsar(bytes(index),17));(folder/bundle_name).write_bytes(dsar(bytes(main)+gpu,128))
 return {'kit_type':'Armor','archive':archive,'pieces':[{'path':unit,'slot':2,'type':0,'body':0,'tone':0,'lut':'0000000000000000','pattern':'0000000000000000'}]},values

if __name__=='__main__':
 assert lz4(b'\x11a\x01\x00',6)==b'aaaaaa'
 for data,capacity in ((b'\x11a\x01\x00',5),(b'\x10a\x01',6),(b'\x10a\0\0',5),(b'\xf0',1)):
  try:lz4(data,capacity)
  except ValueError:pass
  else:raise AssertionError('Invalid LZ4 accepted')
 with tempfile.TemporaryDirectory()as tmp:
  root=Path(tmp);kit,original=fixture(root/'game');out=root/'out';out.mkdir()
  result=discover(root/'game',kit,0,'armor',out,'fixture')
  assert len(result['luts'])==1 and len(result['references'])==1 and result['pieces']==['0:2']
  assert load(out/result['luts'][0]['file']).tobytes()==original.tobytes()
  assert result['luts'][0]['slots']==[LUT]
  try:discover(root/'game',kit,1,'armor',out,'wrongbody')
  except ValueError:pass
  else:raise AssertionError('Wrong body discovered')
 print('PASS archive chunk/entry boundaries, resource/slot discovery, exact HDR/signed floats, body filtering and malformed LZ4 rejection')
