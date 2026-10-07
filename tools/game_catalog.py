"""Read-only game archive discovery outside the game. Format research: CowboyBingus, BSD-0."""
from pathlib import Path
from collections import OrderedDict
import bisect,struct,re
import numpy as np
from lut_files import save,validate
U32=lambda data,at:struct.unpack_from('<I',data,at)[0]
U64=lambda data,at:struct.unpack_from('<Q',data,at)[0]
HEX=lambda data,at:f'{U64(data,at):016x}'
UNIT='e0a48d0be9a7453f';MATERIAL='eac0b497876adedf';TEXTURE='cd4238c6a0c69e32'
LUT=0x7e662968;PATTERN=0x81d4c49d;ZERO='0000000000000000'
SHARED=('18235e0c9ec0e636','ee6b1ba7e22d71ed')
def lz4(source,capacity):
 out=bytearray();at=0
 def length(value):
  nonlocal at
  if value==15:
   while True:
    if at>=len(source):raise ValueError('Truncated LZ4 length')
    extra=source[at];at+=1;value+=extra
    if extra!=255:break
  return value
 while at<len(source):
  token=source[at];at+=1;count=length(token>>4)
  if at+count>len(source)or len(out)+count>capacity:raise ValueError('LZ4 literal overrun')
  out.extend(source[at:at+count]);at+=count
  if at==len(source):break
  if at+2>len(source):raise ValueError('Truncated LZ4 offset')
  offset=source[at]|source[at+1]<<8;at+=2
  if not 0<offset<=len(out):raise ValueError('Invalid LZ4 offset')
  count=length(token&15)+4
  if len(out)+count>capacity:raise ValueError('LZ4 match overrun')
  pattern=out[-offset:];out.extend((pattern*((count+offset-1)//offset))[:count])
 if len(out)!=capacity:raise ValueError('Short LZ4 chunk')
 return bytes(out)
class DSAR:
 def __init__(self,path):
  self.file=Path(path).open('rb');self.size=Path(path).stat().st_size
  head=self.raw(0,32)
  if head[:4]!=b'DSAR':raise ValueError('Invalid game bundle header')
  count=U32(head,8)
  if not 0<count<=1000000:raise ValueError('Invalid game chunk count')
  table=self.raw(32,count*32);self.chunks=[struct.unpack_from('<QQIIB7x',table,i*32)for i in range(count)]
  self.starts=[item[0]for item in self.chunks];self.cache=OrderedDict()
  if self.starts!=sorted(set(self.starts)):raise ValueError('Unordered game chunks')
 def raw(self,at,size):
  if at<0 or size<0 or at+size>self.size:raise ValueError('Game file read outside bounds')
  self.file.seek(at);data=self.file.read(size)
  if len(data)!=size:raise ValueError('Short game file read')
  return data
 def read(self,at,size):
  if at<0 or size<0 or size>128*1024*1024:raise ValueError('Invalid game read size')
  out=bytearray()
  while size:
   index=bisect.bisect_right(self.starts,at)-1
   if index<0:raise ValueError('Game chunk absent')
   start,packed_at,length,packed_size,compression=self.chunks[index]
   if length>64*1024*1024 or not start<=at<start+length:raise ValueError('Invalid game chunk range')
   take=min(size,start+length-at);skip=at-start
   if compression==0:out.extend(self.raw(packed_at+skip,take))
   elif compression==3:
    if index not in self.cache:
     self.cache[index]=lz4(self.raw(packed_at,packed_size),length)
     while len(self.cache)>3:self.cache.popitem(last=False)
    self.cache.move_to_end(index);out.extend(self.cache[index][skip:skip+take])
   else:raise ValueError('Unsupported game compression')
   at+=take;size-=take
  return bytes(out)
 def close(self):self.file.close()
class Archives:
 def __init__(self,folder):
  self.folder=Path(folder).resolve();self.index=DSAR(self.folder/'bundles.nxa');self.bundles={};self.tocs={};self.entries=OrderedDict()
  final=self.index.chunks[-1];self.data=self.index.read(0,final[0]+final[2])
  if self.data[:4]!=b'DSAA':raise ValueError('Invalid game archive index')
  bundles,count=U32(self.data,12),U32(self.data,16)
  if not 0<bundles<=256 or not 0<count<=1000000 or 24+count*24+bundles*4>len(self.data):raise ValueError('Invalid game index counts')
  self.records=[struct.unpack_from('<QIIQ',self.data,24+i*24)for i in range(count)]
  self.names=[self.name(item[1])for item in self.records]
  if self.names!=sorted(set(self.names)):raise ValueError('Unordered archive names')
  self.bundle_names=[self.name(U32(self.data,24+count*24+i*4))for i in range(bundles)]
 def name(self,at):
  end=self.data.find(b'\0',at,min(at+256,len(self.data)))
  if at<0 or end<at:raise ValueError('Invalid archive name')
  return self.data[at:end].decode('ascii')
 def bundle(self,number):
  if not 0<=number<len(self.bundle_names):raise ValueError('Invalid bundle number')
  if number not in self.bundles:
   name=self.bundle_names[number]
   if Path(name).name!=name or '/'in name or '\\'in name:raise ValueError('Invalid game bundle filename')
   self.bundles[number]=DSAR(self.folder/name)
  return self.bundles[number]
 def read(self,name,at,size):
  index=bisect.bisect_left(self.names,name)
  if index==len(self.names)or self.names[index]!=name:raise ValueError('Game archive absent')
  total,_,count,entries_at=self.records[index]
  if at<0 or size<0 or at+size>total:raise ValueError('Read outside game archive')
  if index not in self.entries:
   raw=self.index.read(entries_at,count*16);self.entries[index]=[(U32(raw,i*16),U32(raw,i*16+8),raw[i*16+15])for i in range(count)]
   while len(self.entries)>16:self.entries.popitem(last=False)
  self.entries.move_to_end(index);entries=self.entries[index];starts=[item[0]for item in entries];entry=bisect.bisect_right(starts,at)-1;out=bytearray()
  while size:
   if not 0<=entry<count:raise ValueError('Archive entries ended early')
   start,bundle_at,number=entries[entry];stop=entries[entry+1][0]if entry+1<count else total;take=min(size,stop-at)
   if take<=0:raise ValueError('Invalid archive entry span')
   out.extend(self.bundle(number).read(bundle_at+at-start,take));at+=take;size-=take;entry+=1
  return bytes(out)
 def toc(self,archive):
  if archive not in self.tocs:
   if archive not in self.names:self.tocs[archive]={};return {}
   head=self.read(archive,0,72)
   if U32(head,0)!=0xf0000011:raise ValueError('Invalid resource archive header')
   types,count=U32(head,4),U32(head,8);base=72+types*32
   if types>4096 or count>100000:raise ValueError('Invalid resource table count')
   data=self.read(archive,0,base+count*80);records={}
   for i in range(count):
    at=base+i*80;records.setdefault((HEX(data,at),HEX(data,at+8)),{'main':(U64(data,at+16),U32(data,at+56)),'stream':(U64(data,at+24),U32(data,at+60)),'gpu':(U64(data,at+32),U32(data,at+64))})
   self.tocs[archive]=records
  return self.tocs[archive]
 def find(self,archives,name,kind):
  for archive in archives:
   record=self.toc(archive).get((name,kind))
   if record:return archive,record
  return None,None
 def part(self,archive,record,kind,at,size):
  offset,total=record[kind]
  if at<0 or size<0 or at+size>total:raise ValueError('Read outside resource part')
  return self.read(archive+{'main':'','stream':'.stream','gpu':'.gpu_resources'}[kind],offset+at,size)
 def close(self):
  self.index.close()
  for bundle in self.bundles.values():bundle.close()
def discover(folder,kit,body,kind,destination,request_id):
 if kind not in ('armor','helmet')or not isinstance(body,int)or not 0<=body<=3:raise ValueError('Invalid discovery target')
 if not re.fullmatch('[a-f0-9]{16}',kit['archive'])or not isinstance(kit['pieces'],list)or len(kit['pieces'])>256:raise ValueError('Invalid equipped kit')
 reader=Archives(folder);archives=(kit['archive'],*SHARED);references=[];resources={};luts=[];pieces=set();unsupported=[]
 try:
  for piece in kit['pieces']:
   slot=piece['slot']
   if not ((kind=='helmet'and slot==0)or(kind=='armor'and 2<=slot<=9))or piece['tone']!=0 or piece['body']not in (body,3):continue
   archive,record=reader.find(archives,piece['path'],UNIT)
   if not record:continue
   head=reader.part(archive,record,'main',0,116);at=U32(head,112)
   if not at:continue
   count=U32(reader.part(archive,record,'main',at,4),0)
   if count>64:raise ValueError('Too many unit materials')
   table=reader.part(archive,record,'main',at,4+count*12)
   for i in range(count):
    material=HEX(table,4+count*4+i*8);ma,mr=reader.find(archives,material,MATERIAL)
    if not mr:continue
    count_textures=U32(reader.part(ma,mr,'main',0,136),64)
    if count_textures>64:raise ValueError('Too many material textures')
    textures=reader.part(ma,mr,'main',0,136+count_textures*12)
    for j in range(count_textures):
     texture_slot=U32(textures,136+j*4);resource=HEX(textures,136+count_textures*4+j*8)
     if texture_slot==LUT and piece['lut']!=ZERO:resource=piece['lut']
     if texture_slot==PATTERN and piece.get('pattern',ZERO)!=ZERO:resource=piece['pattern']
     ref={'slot':texture_slot,'name':resource,'material':material,'piece':f"{piece['type']}:{slot}"};references.append(ref);resources.setdefault(resource,set()).add(texture_slot)
  for resource,slots in resources.items():
   try:
    archive,record=reader.find(archives,resource,TEXTURE)
    if not record:raise ValueError('Texture absent from owning/shared archives')
    size=record['main'][1]
    if size>1024*1024:raise ValueError('Texture metadata exceeds budget')
    main=reader.part(archive,record,'main',0,size)
    if len(main)<340 or main[192:196]!=b'DDS 'or main[276:280]!=b'DX10':raise ValueError('Texture does not hold DX10 DDS')
    width,height=U32(main,208),U32(main,204);format=U32(main,320);layers=max(1,U32(main,332));mips=max(1,U32(main,220))
    if format not in (2,10)or layers!=1 or not 1<=width<=64 or not 1<=height<=32 or mips>32:raise ValueError('Not a bounded single-layer float lookup')
    per=16 if format==2 else 8;total=sum(max(1,width>>m)*max(1,height>>m)*per for m in range(mips))
    needed=width*height*per;stream,gpu=record['stream'][1],record['gpu'][1]
    if gpu>=total:raw=reader.part(archive,record,'gpu',0,needed)
    elif stream>=total:raw=reader.part(archive,record,'stream',0,needed)
    elif stream+gpu>=total:
     take=min(stream,needed);raw=reader.part(archive,record,'stream',0,take)+reader.part(archive,record,'gpu',0,needed-take)
    else:raise ValueError('Texture data shorter than mip chain')
    values=np.frombuffer(raw,dtype='<f4'if format==2 else '<f2').astype(np.float32).reshape(height,width,4);validate(values)
    filename=f'catalog-{request_id}-{resource}.dds';save(Path(destination)/filename,values)
    lookup='material'if width==23 else 'pattern'if width==3 and height==1 else 'cape'if width==16 else 'unclassified'
    luts.append({'name':resource,'width':width,'height':height,'lookup_type':lookup,'slots':sorted(slots),'file':filename})
    pieces.update(ref['piece']for ref in references if ref['name']==resource)
   except (ValueError,struct.error)as error:unsupported.append({'name':resource,'reason':str(error)})
  if not 0<len(luts)<=32:raise ValueError('No supported equipped LUTs')
  return {'luts':sorted(luts,key=lambda item:item['name']),'pieces':sorted(pieces),'references':references,'unsupported':unsupported}
 finally:reader.close()
