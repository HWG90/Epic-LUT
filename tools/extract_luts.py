"""Bounded, data-only mod-package to float-LUT extraction. Never installs or executes package contents."""
from pathlib import Path,PurePosixPath
import argparse,json,re,struct,subprocess,sys,tempfile,zipfile
from runtime_guard import require_physical_runtime
require_physical_runtime()
from lut_files import decode_dds,save,load
TEXTURE=0xCD4238C6A0C69E32
PATCH=re.compile(r'^[0-9a-fA-F]{16}\.patch_\d+(?:\.(?:gpu_resources|stream))?$')

def archive_members(archive,sevenzip):
    result=subprocess.run([str(sevenzip),'l','-slt','-ba','-sccUTF-8',str(archive)],capture_output=True,text=True,encoding='utf-8',check=True)
    members=[]
    for block in result.stdout.split('\n\n'):
        fields=dict(line.split(' = ',1) for line in block.splitlines() if ' = ' in line)
        if 'Path' not in fields:continue
        name=fields['Path'].replace('\\','/');path=PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or ':' in name or fields.get('Symbolic Link') or fields.get('Hard Link') or fields.get('Alternate Stream') not in (None,'-'):
            raise ValueError('Unsafe archive member path/link')
        size=int(fields.get('Size','0'))
        if size<0 or size>64*1024*1024:raise ValueError('Archive member exceeds resource budget')
        members.append({'name':name,'size':size,'folder':fields.get('Folder')=='+'})
    if len(members)>1024 or sum(m['size'] for m in members)>256*1024*1024:raise ValueError('Archive budget exceeded')
    return members

def patch_luts(path,output):
    path=Path(path);raw=path.read_bytes()
    if len(raw)>64*1024*1024 or len(raw)<104 or struct.unpack_from('<I',raw)[0]!=0xF0000011:raise ValueError('Unsupported direct resource archive')
    count=struct.unpack_from('<I',raw,8)[0]
    if count>100000 or 104+80*count>len(raw):raise ValueError('Invalid resource table')
    gpu_path=path.with_name(path.name+'.gpu_resources');stream_path=path.with_name(path.name+'.stream')
    gpu=gpu_path.read_bytes() if gpu_path.exists() else b'';stream=stream_path.read_bytes() if stream_path.exists() else b''
    if len(gpu)>64*1024*1024 or len(stream)>64*1024*1024:raise ValueError('Resource sidecar budget exceeded')
    report=[]
    for i in range(count):
        fields=struct.unpack_from('<7Q6I',raw,104+80*i);name,kind,main_at,stream_at,gpu_at=fields[:5];main_size,stream_size,gpu_size=fields[7:10]
        if kind!=TEXTURE:continue
        if main_at<104+80*count or main_at+main_size>len(raw) or stream_at+stream_size>len(stream) or gpu_at+gpu_size>len(gpu):raise ValueError('Resource range leaves archive/sidecar')
        main=raw[main_at:main_at+main_size]
        if len(main)<192+148 or main[192:196]!=b'DDS ':continue
        header=main[192:192+148];width,height=struct.unpack_from('<I',header,16)[0],struct.unpack_from('<I',header,12)[0];format=struct.unpack_from('<I',header,128)[0]
        if format not in (2,10) or not 1<=width<=64 or not 1<=height<=32:continue
        needed=width*height*4*(4 if format==2 else 2)
        if gpu_size>=needed:payload=gpu[gpu_at:gpu_at+needed]
        elif stream_size>=needed:payload=stream[stream_at:stream_at+needed]
        elif stream_size+gpu_size>=needed:payload=(stream[stream_at:stream_at+stream_size]+gpu[gpu_at:gpu_at+gpu_size])[:needed]
        elif len(main)>=192+148+needed:payload=main[192+148:192+148+needed]
        else:raise ValueError('Float LUT has no complete pixel payload')
        data=decode_dds(header+payload);name_hex=f'{name:016x}';destination=Path(output)/(name_hex+'.dds')
        if destination.exists():raise ValueError('Extracted LUT output already exists; use another output folder')
        save(destination,data)
        report.append({'resource':name_hex,'type':'texture','width':width,'height':height,'input_format':'RGBA32F' if format==2 else 'RGBA16F','output':str(destination),'original_archive':str(path),'target_identity':'Resource ID only; armor/helmet ownership is not inferred from the package filename'})
    return report

def extract(package,output,sevenzip):
    package=Path(package).resolve();output=Path(output).resolve();output.mkdir(parents=True,exist_ok=True)
    members=archive_members(package,sevenzip);selected=[m['name'] for m in members if not m['folder'] and (PATCH.fullmatch(PurePosixPath(m['name']).name)or Path(m['name']).suffix.lower()in('.dds','.exr'))]
    if not selected:raise ValueError('No LUT files or standard game patch archives found')
    with tempfile.TemporaryDirectory(prefix='epic-lut-package-') as temp:
        staging=Path(temp)
        subprocess.run([str(sevenzip),'x','-y','-aos','-sccUTF-8','-o'+str(staging),str(package),*selected],capture_output=True,check=True)
        report=[]
        for name in selected:
            file=(staging/PurePosixPath(name)).resolve()
            if not file.is_relative_to(staging.resolve()):raise ValueError('Extraction left staging directory')
            if file.suffix.lower()in('.dds','.exr'):
                data=load(file);destination=output/(file.stem+'.dds')
                if destination.exists():raise ValueError('Duplicate output filename')
                save(destination,data);report.append({'resource':file.stem if re.fullmatch('[0-9a-fA-F]{16}',file.stem)else None,'width':data.shape[1],'height':data.shape[0],'output':str(destination)})
            elif '.gpu_resources' not in file.name and '.stream' not in file.name:
                found=patch_luts(file,output)
                for item in found:item['original_archive']=str(package)+'::'+name
                report.extend(found)
    (output/'extraction.json').write_text(json.dumps({'package':str(package),'members':members,'luts':report,'installed_or_applied':False},indent=2))
    return report

def import_package(package,output,sevenzip=Path(r'C:\Program Files\7-Zip\7z.exe')):
    package=Path(package);output=Path(output);output.mkdir(parents=True,exist_ok=True)
    if package.suffix.lower()!='.zip':return extract(package,output,sevenzip)
    with zipfile.ZipFile(package) as archive, tempfile.TemporaryDirectory(prefix='epic-lut-zip-') as temp:
        entries=archive.infolist()
        if len(entries)>1024 or sum(e.file_size for e in entries)>256*1024*1024:raise ValueError('ZIP size/count budget exceeded')
        for entry in entries:
            name=entry.filename.replace('\\','/');parts=PurePosixPath(name)
            if parts.is_absolute()or '..'in parts.parts or ':'in name or (entry.external_attr>>16)&0o170000==0o120000 or entry.flag_bits&1:raise ValueError('Unsafe ZIP path/link/encryption')
            if entry.file_size>64*1024*1024:raise ValueError('ZIP member budget exceeded')
        staging=Path(temp);report=[];selected=[]
        for entry in entries:
            if entry.is_dir():continue
            path=staging/PurePosixPath(entry.filename.replace('\\','/'))
            if not(PATCH.fullmatch(path.name)or path.suffix.lower()in('.dds','.exr')):continue
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(archive.read(entry));selected.append(path)
        for path in selected:
            if path.suffix.lower()in('.dds','.exr'):
                data=load(path);dest=output/(path.stem+'.dds')
                if dest.exists():raise ValueError('Duplicate LUT filename in package')
                save(dest,data);report.append({'resource':path.stem if re.fullmatch('[0-9a-fA-F]{16}',path.stem)else None,'width':data.shape[1],'height':data.shape[0],'output':str(dest)})
            elif '.gpu_resources'not in path.name and '.stream'not in path.name:
                found=patch_luts(path,output)
                for item in found:item['original_archive']=str(package)+'::'+str(path.relative_to(staging))
                report.extend(found)
        if not report:raise ValueError('No supported float LUTs in ZIP')
        (output/'extraction.json').write_text(json.dumps({'package':str(package),'luts':report,'installed_or_applied':False},indent=2))
        return report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('package',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--sevenzip',type=Path,default=Path(r'C:\Program Files\7-Zip\7z.exe'));a=p.parse_args()
    print(json.dumps(extract(a.package,a.output,a.sevenzip),indent=2))
