"""Local-only semantic/grid editor and EXR-to-DDS hotload bridge. No game-memory access."""
from pathlib import Path
import argparse,hashlib,json,os,re,secrets,struct,sys,tempfile,threading,time,uuid
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from runtime_guard import require_physical_runtime
require_physical_runtime()
from lut_files import load,save,validate,encode_dds,convert_directory,MAX_BYTES
from extract_luts import import_package
from urllib.parse import unquote
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
MATERIAL=['Base color / mode','Detail texture / masks','Detail color A','Detail mask A','Detail mask B','Detail inner color','Detail outer color / metal','Metal mask','Unknown 9','Gloss mask','Roughness / rim','Unknown 12','Curvature color','Emission','Tint override','Unknown 16','Camo color 1','Camo color 2','Camo color 3','Camo color 4','Camo fade','Camo selector / scale','Detail profile']
CAPE=['Base color','Overlay color A','Overlay color B','Detail gradient','Icon position 1','Icon focus/detail 1','Icon effects 1','Icon position 2','Icon focus/detail 2','Icon effects 2','Icon position 3','Icon focus/detail 3','Icon effects 3','Icon position 4','Icon focus/detail 4','Icon effects 4']
PATTERN=['Pattern color','Pattern material/opacity','Unconfirmed pattern effects']
COLOR_COLUMNS={23:{0,2,5,6,12,14,16,17,18,19},16:{0,1,2,3},3:{0}}

def columns(width):return {23:MATERIAL,16:CAPE,3:PATTERN}.get(width,[f'Raw column {i+1}' for i in range(width)])
def safe_name(name):
    if not isinstance(name,str) or not name or len(name)>120 or name in('.', '..')or re.search(r'[<>:"/\\|?*\x00-\x1f]',name)or name[-1]in(' ','.'):raise ValueError('Use a simple local filename')
    if re.fullmatch(r'CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]',Path(name).stem,re.I):raise ValueError('Reserved filename')
    return name

class Editor:
    def __init__(self,folder):
        self.folder=Path(folder).resolve();self.folder.mkdir(parents=True,exist_ok=True);self.data=None;self.path=None;self.undo=[];self.redo=[];self.clipboard=None;self.revision=0
        self.lock=threading.RLock();self.imports=[];self.resource=None;self.matches=[]
    def file(self,name):
        path=(self.folder/safe_name(name)).resolve()
        if path.parent!=self.folder:raise ValueError('Path leaves editor folder')
        return path
    def remember(self):
        self.undo.append(self.data.copy());self.undo=self.undo[-64:];self.redo=[]
    def state(self):
        if self.data is None:return {'loaded':False,'files':self.files(),'live':self.live()}
        return {'loaded':True,'name':self.path.name if self.path else None,'width':self.data.shape[1],'height':self.data.shape[0],'values':self.data.tolist(),'columns':columns(self.data.shape[1]),'color_columns':sorted(COLOR_COLUMNS.get(self.data.shape[1],set())),'revision':self.revision,'undo':len(self.undo),'redo':len(self.redo),'files':self.files(),'live':self.live(),'imports':self.imports,'matches':self.matches,'resource':self.resource}
    def files(self):return sorted(p.name for p in self.folder.iterdir() if p.is_file() and p.suffix.lower() in ('.dds','.exr','.json') and p.name!='current.json')
    def live(self):
        try:
            text=self.file('current.json').read_text()
            if len(text)>65536:return None
            return json.loads(text)
        except (OSError,ValueError):return None
    def open(self,name):
        path=self.file(name);data=load(path);self.path=path;self.data=data;self.undo=[];self.redo=[];self.revision+=1
        self.resource=path.stem if re.fullmatch('[0-9a-fA-F]{16}',path.stem)else None;self.match()
    def match(self):
        self.matches=[v.get('key',v['hash'])for v in (self.live()or {}).get('luts',[])if self.resource and v['hash'].lower()==self.resource.lower()and (v['width'],v['height'])==(self.data.shape[1],self.data.shape[0])]
    def upload_package(self,name,raw):
        cache=self.folder/'archive-cache'/uuid.uuid4().hex;cache.mkdir(parents=True);path=cache/safe_name(name);path.write_bytes(raw)
        report=import_package(path,cache/'extracted');self.imports=[]
        for item in report:
            source=Path(item['output']);filename='import-'+uuid.uuid4().hex[:8]+'-'+source.name;destination=self.file(filename);destination.write_bytes(source.read_bytes());self.imports.append({'name':filename,'resource':item.get('resource'),'width':item['width'],'height':item['height']})
        self.open_import(self.imports[0]['name'])
    def open_import(self,name):
        item=next((v for v in self.imports if v['name']==name),None);self.open(name)
        if item:self.resource=item['resource'];self.match()
        # Apply only an exact unambiguous resource/dimension match. Other palettes remain preview-only.
        if len(self.matches)==1:self.command('publish',{'target':self.matches[0]})
    def cells(self,rect):
        if self.data is None:raise ValueError('Open a LUT first')
        r0,r1,c0,c1=[int(v) for v in rect]
        if not 0<=r0<=r1<self.data.shape[0] or not 0<=c0<=c1<self.data.shape[1]:raise ValueError('Selection outside LUT')
        return r0,r1,c0,c1
    def edit(self,rect,rgba,channels):
        r0,r1,c0,c1=self.cells(rect)
        if not channels or any(type(c)!=int or c not in range(4) for c in channels):raise ValueError('Invalid channels')
        if len(rgba)!=4 or not all(isinstance(v,(int,float)) and np.isfinite(v) for v in rgba):raise ValueError('Four finite floats required')
        candidate=self.data.copy()
        for c in channels:candidate[r0:r1+1,c0:c1+1,c]=rgba[c]
        validate(candidate);self.remember();self.data=candidate;self.revision+=1
    def command(self,action,args):
        if action=='open':self.open_import(args['name'])
        elif action=='edit':self.edit(args['rect'],args['rgba'],args['channels'])
        elif action in ('undo','redo'):
            source,dest=(self.undo,self.redo) if action=='undo' else (self.redo,self.undo)
            if source:dest.append(self.data.copy());self.data=source.pop();self.revision+=1
        elif action=='copy':
            r0,r1,c0,c1=self.cells(args['rect']);self.clipboard=self.data[r0:r1+1,c0:c1+1].copy()
        elif action=='paste':
            r0,r1,c0,c1=self.cells(args['rect']);clip=self.clipboard
            if clip is None:raise ValueError('Copy cells first')
            h,w,_=clip.shape
            if r0+h>self.data.shape[0] or c0+w>self.data.shape[1]:raise ValueError('Clipboard exceeds destination')
            self.remember();self.data[r0:r0+h,c0:c0+w]=clip;self.revision+=1
        elif action=='save':
            path=self.file(args['name']) if args.get('name') else self.path
            if path is None:raise ValueError('Choose a filename')
            if path.stem.endswith('-original'):raise ValueError('Original snapshot is protected; Save As another file')
            save(path,self.data);self.path=path
        elif action=='row_save':
            row=int(args['row']);self.cells([row,row,0,self.data.shape[1]-1]);name=safe_name(args['name'])
            if not name.endswith('.row.json'):raise ValueError('Row presets use .row.json')
            payload={'format':'EpicLUT-row','version':1,'width':self.data.shape[1],'rgba':self.data[row].tolist()}
            path=self.file(name)
            if path.exists():raise ValueError('Row preset filename already exists')
            path.write_text(json.dumps(payload,allow_nan=False))
        elif action=='row_load':
            path=self.file(args['name']);raw=path.read_text()
            if len(raw)>65536:raise ValueError('Row preset too large')
            p=json.loads(raw);row=int(args['row']);self.cells([row,row,0,self.data.shape[1]-1])
            if p.get('format')!='EpicLUT-row' or p.get('version')!=1 or p.get('width')!=self.data.shape[1]:raise ValueError('Incompatible row preset')
            data=validate(np.asarray([p['rgba']],dtype=np.float32))
            if data.shape!=(1,self.data.shape[1],4):raise ValueError('Invalid row values')
            self.remember();self.data[row]=data[0];self.revision+=1
        elif action=='debug':
            if self.data.shape[1]!=23:raise ValueError('Row debug colors require a material LUT')
            self.remember()
            import colorsys
            for row in range(self.data.shape[0]):self.data[row,0,:3]=colorsys.hsv_to_rgb(row/self.data.shape[0],1,1)
            self.revision+=1
        elif action=='camo':
            row=int(args['row']);pattern=int(args['pattern']);self.cells([row,row,0,self.data.shape[1]-1])
            if self.data.shape[1]!=23 or pattern not in range(-1,6):raise ValueError('Material LUT and pattern -1 through 5 required')
            self.remember();self.data[row,21]=[20,1,1,pattern] if pattern>=0 else [0,0,0,-1];self.revision+=1
        elif action=='publish':
            live=self.live();target=next((v for v in (live or {}).get('luts',[]) if v.get('key',v['hash'])==args['target']),None)
            if target is None or target['width']!=self.data.shape[1] or target['height']!=self.data.shape[0]:raise ValueError('No compatible equipped LUT target')
            save(self.file(target['working']),self.data)
        elif action=='bulk':return {'results':convert_directory(self.folder,args['format'])}
        else:raise ValueError('Unknown action')
        return self.state()

class Bridge(threading.Thread):
    def __init__(self,editor):super().__init__(daemon=True);self.editor=editor;self.stopped=threading.Event();self.seen={}
    def run(self):
        while not self.stopped.wait(.5):
            for file in self.editor.folder.glob('*.exr'):
                try:
                    if file.resolve().parent!=self.editor.folder:continue
                    raw=file.read_bytes()
                    if len(raw)>MAX_BYTES:continue
                    signature=hashlib.sha256(raw).hexdigest()
                    if self.seen.get(file.name)==signature:continue
                    self.seen[file.name]=signature
                    data=load(file)
                    if hashlib.sha256(file.read_bytes()).hexdigest()!=signature:self.seen.pop(file.name,None);continue
                    save(file.with_name(file.name+'.converted.dds'),data)
                    file.with_name(file.name+'.status.json').write_text(json.dumps({'ok':True,'input_sha256':signature,'output':file.name+'.converted.dds'}))
                except Exception as e:
                    file.with_name(file.name+'.status.json').write_text(json.dumps({'ok':False,'error':str(e)}))

def serve(folder,port=8765,ready=None):
    editor=Editor(folder);token=secrets.token_urlsafe(32)
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def json(self,value,status=200):
            data=json.dumps(value,allow_nan=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
        def allowed(self):
            host=self.headers.get('Host');origin=self.headers.get('Origin')
            if host!=f'127.0.0.1:{self.server.server_port}' or origin not in (None,f'http://{host}'):raise ValueError('Local origin required')
            if self.headers.get('X-Epic-LUT-Token')!=token:raise ValueError('Invalid editor session token')
        def do_GET(self):
            if self.path=='/':
                if self.headers.get('Host')!=f'127.0.0.1:{self.server.server_port}':self.send_error(403,'Local host required');return
                page=(ROOT/'companion/index.html').read_text(encoding='utf-8').replace('__TOKEN__',token);data=page.encode();self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'");self.end_headers();self.wfile.write(data);return
            try:
                self.allowed()
                if self.path!='/api/state':raise ValueError('Unknown path')
                with editor.lock:self.json(editor.state())
            except Exception as e:self.json({'error':str(e)},400)
        def do_POST(self):
            try:
                self.allowed();size=int(self.headers.get('Content-Length','0'))
                if size<0 or size>MAX_BYTES:raise ValueError('Request too large')
                raw=self.rfile.read(size)
                with editor.lock:
                    if self.path.startswith('/api/upload/'):
                        name=safe_name(unquote(self.path.removeprefix('/api/upload/')))
                        if Path(name).suffix.lower()in('.zip','.rar'):
                            editor.upload_package(name,raw);self.json(editor.state());return
                        if Path(name).suffix.lower() not in ('.dds','.exr'):raise ValueError('Upload DDS/EXR/ZIP/RAR only')
                        path=editor.file(name)
                        if path.exists():raise ValueError('Filename exists; rename the incoming file')
                        path.write_bytes(raw)
                        try:editor.open_import(name)
                        except Exception:path.unlink();raise
                        self.json(editor.state())
                    elif self.path=='/api/action':
                        args=json.loads(raw);self.json(editor.command(args.pop('action'),args))
                    else:raise ValueError('Unknown action path')
            except Exception as e:self.json({'error':str(e)},400)
    server=ThreadingHTTPServer(('127.0.0.1',port),Handler);bridge=Bridge(editor);bridge.start()
    if ready:Path(ready).write_text(json.dumps({'url':f'http://127.0.0.1:{server.server_port}','workspace':str(editor.folder),'pid':os.getpid()}))
    print(f'Epic LUT local editor: http://127.0.0.1:{server.server_port}',flush=True)
    try:server.serve_forever()
    finally:bridge.stopped.set();server.server_close()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--workspace',type=Path,required=True);p.add_argument('--port',type=int,default=8765);p.add_argument('--ready',type=Path);a=p.parse_args();serve(a.workspace,a.port,a.ready)
