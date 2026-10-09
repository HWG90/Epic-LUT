"""Independent, lossless float LUT codecs. No image normalization or gamma conversion."""
from pathlib import Path
import math,os,struct,sys,tempfile
if not sys.flags.isolated:sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.deps'))
if not sys.flags.isolated and os.environ.get('LOCALAPPDATA'):
    sys.path.insert(0,str(Path(os.environ['LOCALAPPDATA'])/'Epic LUT/cache/file-service/.deps'))
import numpy as np
MAX_BYTES=8*1024*1024

def validate(data):
    result=np.asarray(data,dtype=np.float32)
    if result.ndim!=3 or result.shape[2]!=4 or not 1<=result.shape[0]<=64 or not 1<=result.shape[1]<=64:
        raise ValueError('Expected a LUT of at most 64 columns, 64 rows and four channels')
    if not np.isfinite(result).all():raise ValueError('Nonfinite LUT values are not supported')
    return np.ascontiguousarray(result)

def decode_dds(raw,*,base_level_only=False):
    if len(raw)>MAX_BYTES or len(raw)<128 or raw[:4]!=b'DDS ':raise ValueError('Invalid DDS file')
    words=struct.unpack_from('<31I',raw,4)
    if words[0]!=124 or words[18]!=32:raise ValueError('Invalid DDS header sizes')
    if words[5]>1 or words[1]&0x800000 or words[27]!=0:raise ValueError('Only 2D LUTs are supported; cube and volume textures are unsupported')
    height,width=words[2:4];format=words[20];offset=128
    if format==0x30315844:
        if len(raw)<148:raise ValueError('Truncated DX10 header')
        format,dimension,misc,array_size,_=struct.unpack_from('<5I',raw,128);offset=148
        if (dimension,misc,array_size)!=(3,0,1):raise ValueError('Unsupported DDS texture kind')
    elif format in (113,116):format={113:10,116:2}[format]
    else:raise ValueError('DDS must contain RGBA16F or RGBA32F')
    if format not in (2,10) or not 1<=width<=64 or not 1<=height<=64:raise ValueError('Unsupported DDS LUT format or dimensions')
    size=width*height*4*(4 if format==2 else 2)
    levels=max(1,words[6])
    if levels>max(width,height).bit_length():raise ValueError('DDS mip count exceeds texture dimensions')
    expected=size if base_level_only else sum(max(1,width>>level)*max(1,height>>level)*4*(4 if format==2 else 2)for level in range(levels))
    if len(raw)!=offset+expected:raise ValueError('DDS payload size mismatch')
    return validate(np.frombuffer(raw, dtype='<f4' if format==2 else '<f2',offset=offset,count=width*height*4).reshape(height,width,4).astype(np.float32))

def encode_dds(data):
    data=validate(data);height,width,_=data.shape
    words=[124,0x100f,height,width,width*16,0,1]+[0]*11+[32,4,0x30315844,0,0,0,0,0,0x1000,0,0,0,0]
    return b'DDS '+struct.pack('<31I',*words)+struct.pack('<5I',2,3,0,1,0)+data.astype('<f4',copy=False).tobytes()

def _exr():
    try:import OpenEXR
    except ImportError as e:raise RuntimeError('OpenEXR dependency missing; run setup_companion.ps1') from e
    return OpenEXR

def load(path):
    path=Path(path)
    if path.stat().st_size>MAX_BYTES:raise ValueError('LUT file exceeds size limit')
    if path.suffix.lower()=='.dds':return decode_dds(path.read_bytes())
    if path.suffix.lower()!='.exr':raise ValueError('Use a DDS or EXR file')
    exr=_exr()
    with exr.File(str(path),header_only=True) as header_file:
        if len(header_file.parts)!=1:raise ValueError('Multipart EXR is unsupported')
        header=header_file.header();lo,hi=header['dataWindow'];w,h=int(hi[0]-lo[0]+1),int(hi[1]-lo[1]+1)
        if not 1<=w<=64 or not 1<=h<=64:raise ValueError('EXR is not a bounded LUT')
        if header['type'] not in (exr.scanlineimage,exr.tiledimage):raise ValueError('Deep EXR is unsupported')
    with exr.File(str(path),separate_channels=True) as f:
        channels=f.channels()
        if set(channels)!={'R','G','B','A'}:raise ValueError('LUT EXR must have exactly R, G, B and A channels')
        return validate(np.stack([channels[c].pixels for c in 'RGBA'],axis=2))

def save(path,data):
    path=Path(path);data=validate(data);path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix=path.stem+'-',suffix=path.suffix,dir=path.parent);os.close(fd)
    try:
        if path.suffix.lower()=='.dds':Path(tmp).write_bytes(encode_dds(data))
        elif path.suffix.lower()=='.exr':
            exr=_exr();header={'compression':exr.ZIP_COMPRESSION,'type':exr.scanlineimage}
            with exr.File(header,{c:data[:,:,i].copy() for i,c in enumerate('RGBA')}) as f:f.write(tmp)
        else:raise ValueError('Use a DDS or EXR extension')
        if path.exists():
            backup=path.with_name(path.name+'.previous');backup.write_bytes(path.read_bytes())
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)
    return path

def convert_directory(folder,destination_format):
    folder=Path(folder);destination_format=destination_format.lower()
    if destination_format not in ('dds','exr'):raise ValueError('Unknown destination format')
    results=[]
    for file in sorted(folder.iterdir()):
        if file.suffix.lower() in ('.dds','.exr') and file.suffix.lower()!=('.'+destination_format):
            output=file.with_suffix('.'+destination_format)
            if output.exists():results.append({'file':file.name,'status':'skipped existing destination'});continue
            try:save(output,load(file));results.append({'file':file.name,'status':'converted','output':output.name})
            except Exception as e:results.append({'file':file.name,'status':'error','message':str(e)})
    return results
