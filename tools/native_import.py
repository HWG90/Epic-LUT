"""User-invoked Windows dialog on a worker thread; bounded file IPC back to MCM."""
from pathlib import Path
import ctypes,json,os,threading,time,uuid
from ctypes import wintypes as W
from lut_files import MAX_BYTES,load,save

def choose_file(owner=0,pid=0):
    if os.name!='nt':raise RuntimeError('Native file picker requires Windows')
    class OPENFILENAME(ctypes.Structure):
        _fields_=[('lStructSize',W.DWORD),('hwndOwner',W.HWND),('hInstance',W.HINSTANCE),('lpstrFilter',W.LPCWSTR),('lpstrCustomFilter',W.LPWSTR),('nMaxCustFilter',W.DWORD),('nFilterIndex',W.DWORD),('lpstrFile',W.LPWSTR),('nMaxFile',W.DWORD),('lpstrFileTitle',W.LPWSTR),('nMaxFileTitle',W.DWORD),('lpstrInitialDir',W.LPCWSTR),('lpstrTitle',W.LPCWSTR),('Flags',W.DWORD),('nFileOffset',W.WORD),('nFileExtension',W.WORD),('lpstrDefExt',W.LPCWSTR),('lCustData',W.LPARAM),('lpfnHook',ctypes.c_void_p),('lpTemplateName',W.LPCWSTR),('pvReserved',ctypes.c_void_p),('dwReserved',W.DWORD),('FlagsEx',W.DWORD)]
    user=ctypes.WinDLL('user32',use_last_error=True);dialog=ctypes.WinDLL('comdlg32',use_last_error=True)
    user.GetWindowThreadProcessId.argtypes=[W.HWND,ctypes.POINTER(W.DWORD)];user.IsWindow.argtypes=[W.HWND]
    actual=W.DWORD()
    if owner:
        user.GetWindowThreadProcessId(owner,ctypes.byref(actual))
        if not user.IsWindow(owner)or actual.value!=pid:raise ValueError('Game window changed; open the picker again')
    buffer=ctypes.create_unicode_buffer(32768);ofn=OPENFILENAME();ofn.lStructSize=ctypes.sizeof(ofn);ofn.hwndOwner=owner or None
    ofn.lpstrFilter='LUT / mod archive (*.zip;*.rar;*.dds;*.exr)\0*.zip;*.rar;*.dds;*.exr\0\0';ofn.nFilterIndex=1
    ofn.lpstrFile=ctypes.cast(buffer,W.LPWSTR);ofn.nMaxFile=len(buffer);ofn.lpstrTitle='Epic LUT — Import LUT / mod archive';ofn.Flags=0x80000|0x1000|0x800|0x8
    dialog.GetOpenFileNameW.argtypes=[ctypes.POINTER(OPENFILENAME)];dialog.GetOpenFileNameW.restype=W.BOOL
    ole=ctypes.WinDLL('ole32');ole.CoInitializeEx.argtypes=[ctypes.c_void_p,W.DWORD];ole.CoInitializeEx.restype=ctypes.c_long
    initialized=ole.CoInitializeEx(None,2);proxy=None
    user.CreateWindowExW.argtypes=[W.DWORD,W.LPCWSTR,W.LPCWSTR,W.DWORD,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,W.HWND,W.HMENU,W.HINSTANCE,ctypes.c_void_p];user.CreateWindowExW.restype=W.HWND
    user.DestroyWindow.argtypes=[W.HWND];user.GetForegroundWindow.restype=W.HWND;user.SetForegroundWindow.argtypes=[W.HWND]
    diagnostics={'struct_size':ctypes.sizeof(ofn),'owner':owner,'owner_pid':actual.value,'helper_pid':os.getpid(),'sta_hresult':hex(initialized&0xffffffff)}
    try:
        success=dialog.GetOpenFileNameW(ctypes.byref(ofn));error=0 if success else dialog.CommDlgExtendedError()
        diagnostics.update(initial_error=hex(error),last_error=ctypes.get_last_error())
        if not success and error==0xffff and owner:
            # An elevated game's HWND can reject a lower-integrity helper's modal creation.
            # Retry with a window owned by this helper; no elevation or game-input changes.
            proxy=user.CreateWindowExW(0,'STATIC','Epic LUT import',0x80000000,0,0,1,1,None,None,None,None)
            if not proxy:raise RuntimeError('Native import owner window could not be created')
            ofn.hwndOwner=proxy;success=dialog.GetOpenFileNameW(ctypes.byref(ofn));error=0 if success else dialog.CommDlgExtendedError()
            diagnostics.update(fallback_owner=int(proxy),fallback_error=hex(error),fallback_last_error=ctypes.get_last_error())
        if error:raise RuntimeError('Windows file picker failed: '+hex(error)+'; STA '+diagnostics['sta_hresult'])
        return Path(buffer.value)if success else None
    finally:
        diagnostics['foreground_after']=user.GetForegroundWindow()
        if proxy:
            foreground=user.GetForegroundWindow();foreground_pid=W.DWORD();user.GetWindowThreadProcessId(foreground,ctypes.byref(foreground_pid))
            user.DestroyWindow(proxy)
            if owner and (not foreground or foreground_pid.value==os.getpid()):diagnostics['focus_restore_result']=bool(user.SetForegroundWindow(owner))
        if initialized in (0,1):ole.CoUninitialize()
        choose_file.last_diagnostics=diagnostics

def clean(text):return str(text).replace('<','(').replace('>',')').replace('\t',' ').replace('\r',' ').replace('\n',' ')[:240]

def replace_retry(source,target):
    for attempt in range(100):
        try:return os.replace(source,target)
        except OSError as error:
            if getattr(error,'winerror',None)not in (32,33)or attempt==99:raise
            time.sleep(.01)

class NativeImporter:
    def __init__(self,folder,editor_factory,picker=choose_file):
        self.folder=Path(folder);self.factory=editor_factory;self.picker=picker;self.busy=False;self.sessions={};self.seen={}
        # Never replay a prior session's dialog request when the helper restarts.
        for kind in ('armor','helmet','quick'):
            path=self.file('native-'+kind+'.request')
            if path.exists():self.seen[kind]=path.read_bytes()[:4097]
        cached=self.file('native-quick.session.json')
        if cached.exists():
            try:
                raw=cached.read_bytes()
                if len(raw)>32768:raise ValueError('Stored import too large')
                saved=json.loads(raw);editor=self.factory(self.folder);editor.open(saved['name']);editor.imports=saved['imports'];editor.resource=saved.get('resource');editor.package_name=saved.get('package_name')
                if not isinstance(saved['id'],str)or not saved['id'].isalnum():raise ValueError('Invalid cached session')
                for item in editor.imports:load(editor.file(item['name']))
                self.sessions['quick']=(saved['id'],editor)
            except (OSError,ValueError,KeyError,TypeError):pass
    def file(self,name):
        path=(self.folder/name).resolve()
        if path.parent!=self.folder.resolve():raise ValueError('Native IPC path leaves workspace')
        return path
    def respond(self,kind,request_id,message,session=None,applied=None,imported=False):
        lines=[request_id+'\t'+clean(message)]
        if imported:lines.append('imported\t1')
        if session:
            editor=session;editor.match();live=(editor.live()or {}).get('luts',[])
            lines.append('session\t'+self.sessions[kind][0])
            lines.append('file\t'+clean(editor.package_name or editor.path.name))
            if editor.data.shape[1]in (23,16,3):
                lines.append('preview\t'+str(editor.data.shape[0])+'\t'+clean(('Pattern color'if editor.data.shape[1]==3 else 'Base color')+' RGB — source table '+(editor.resource or editor.path.name)))
                for row,value in enumerate(editor.data[:,0,:3],1):lines.append('swatch\t'+str(row)+'\t'+'\t'.join(str(int(max(0,min(1,float(v)))*255+.5))for v in value))
            if applied:lines.append('applied\t'+applied['kind']+'\t'+applied['prefix'])
            for v in live:
                if v.get('kind')!=kind or (v['width'],v['height'])!=(editor.data.shape[1],editor.data.shape[0]):continue
                key=v.get('key',v['hash']);label='Equipped '+kind+' LUT '+v['hash']+(' (exact match)'if key in editor.matches else ' (manual remap)')
                lines.append('target\t'+key+'\t'+label)
            compatible=[v for v in live if v.get('kind')==kind and v['width']==23 and (v['width'],v['height'])==(editor.data.shape[1],editor.data.shape[0])]
            if compatible:lines.append('target\tall-'+kind+'\tAll compatible '+kind+' material LUTs ('+str(len(compatible))+') — deliberate remap')
            if len(editor.matches)==1 and any(v.get('key',v['hash'])==editor.matches[0]and v.get('kind')==kind for v in live):lines.append('selected\t'+editor.matches[0])
        path=self.file('native-'+kind+'.result');temp=self.file(path.with_suffix('.tmp').name);temp.write_text('\n'.join(lines)+'\n',encoding='utf-8');replace_retry(temp,path)
    def handle(self,kind,raw):
        request=json.loads(raw);request_id=request['id']
        if not isinstance(request_id,str)or not request_id.isalnum()or len(request_id)>80:raise ValueError('Invalid native request')
        if request['action']=='catalog':
            from game_catalog import discover
            target=request['kind']
            if kind!='catalog'+target:raise ValueError('Catalog target mismatch')
            catalog=discover(request['data_folder'],request['kit'],request['body'],target,self.folder,request_id)
            lines=[]
            for lut in catalog['luts']:
                lines.append('lut\t'+ '\t'.join(map(str,[lut['name'],lut['width'],lut['height'],lut['lookup_type'],lut['file'],','.join(map(str,lut['slots']))])))
            lines.extend('piece\t'+piece for piece in catalog['pieces'])
            lines.extend('reference\t'+'\t'.join(map(str,[v['slot'],v['name'],v['material'],v['piece']]))for v in catalog['references'])
            lines.extend('unsupported\t'+v['name']+'\t'+clean(v['reason'])for v in catalog['unsupported'])
            name='catalog-'+request_id+'.tsv';path=self.file(name);temp=self.file(name+'.tmp');temp.write_text('\n'.join(lines)+'\n',encoding='utf-8');replace_retry(temp,path)
            result=self.file('native-'+kind+'.result');temp=self.file(result.name+'.tmp');temp.write_text(request_id+'\tArchive discovery complete\ncatalog\t'+name+'\n',encoding='utf-8');replace_retry(temp,result)
        elif request['action']=='pick':
            selected=self.picker(int(request.get('owner',0)),int(request.get('pid',0)))
            if selected is None:self.respond(kind,request_id,'Import canceled; colors unchanged',self.sessions.get(kind,(None,None))[1]);return
            if selected.suffix.lower()not in ('.zip','.rar','.dds','.exr'):raise ValueError('Choose ZIP, RAR, DDS or EXR')
            if selected.stat().st_size>MAX_BYTES:raise ValueError('Selected file exceeds import limit')
            raw_file=selected.read_bytes()
            if len(raw_file)>MAX_BYTES:raise ValueError('Selected file exceeds import limit')
            editor=self.factory(self.folder)
            if selected.suffix.lower()in('.zip','.rar'):editor.upload_package(selected.name,raw_file)
            else:
                # Load precisely the selected file; no directories or profile scanning.
                data=load(selected);name='native-'+uuid.uuid4().hex+'.dds';save(editor.file(name),data);editor.open(name)
                editor.package_name=selected.name
                stem=selected.stem
                if len(stem)==16 and all(c in '0123456789abcdefABCDEF'for c in stem):editor.resource=stem.lower();editor.match()
            self.sessions[kind]=(request_id,editor)
            if kind=='quick':self.file('native-quick.session.json').write_text(json.dumps({'id':request_id,'name':editor.path.name,'imports':editor.imports,'resource':editor.resource,'package_name':editor.package_name}),encoding='utf-8')
            self.respond(kind,request_id,'Imported '+selected.name+' — choose target and Apply; original colors retained',editor,imported=True)
        elif request['action']=='resume':
            if kind!='quick':raise ValueError('Unsupported resume target')
            self.respond(kind,request_id,'Loaded palette retained; choose Armor or Helmet to apply.',self.sessions.get('quick',(None,None))[1])
        elif request['action']=='apply':
            session_id,editor=self.sessions.get(kind,(None,None))
            if editor is None or request.get('session')!=session_id:raise ValueError('Import session expired; choose the file again')
            target=request['target'];live=(editor.live()or {}).get('luts',[])
            if target=='all-'+kind:result=editor.command('publish_all',{'kind':kind});count=result['applied_batch']['count']
            else:
                if not any(v.get('key',v['hash'])==target and v.get('kind')==kind for v in live):raise ValueError('Equipped target changed; choose the file again')
                editor.command('publish',{'target':target});count=1
            self.respond(kind,request_id,'Applied to '+str(count)+' '+kind+' LUTs; MCM hotload handles rendering. Restore originals is available.',editor)
        elif request['action']=='quick_apply':
            session_id,editor=self.sessions.get('quick',(None,None))
            if kind!='quick'or editor is None or request.get('session')!=session_id:raise ValueError('Choose a file in Quick Load first')
            for flag in ('preserve_material','preserve_emission'):
                if type(request.get(flag))is not bool:raise ValueError('Choose both preservation settings')
            result=editor.command('quick_apply',request)['quick_result']
            message='Quick Load '+result['kind']+': '+str(result['applied'])+' applied / '+str(result['attempted'])+' attempted, '+str(result['skipped'])+' skipped, '+str(result['partial'])+' base-color-only. Nearest row remap; unknown fields retained.'
            self.respond(kind,request_id,message,editor,result)
        else:raise ValueError('Unknown native action')
    def tick(self):
        for name,value in (('native-ready.txt',str(int(time.time()))),('native-pid.txt',str(os.getpid())),('native-version.txt','archive-worker-v4')):
            path=self.file(name);temp=self.file(name+'.tmp');temp.write_text(value,encoding='ascii');replace_retry(temp,path)
        if self.busy:return
        for kind in ('catalogarmor','cataloghelmet','armor','helmet','quick'):
            path=self.file('native-'+kind+'.request')
            if not path.exists():continue
            raw=path.read_bytes()
            if len(raw)>65536 or self.seen.get(kind)==raw:continue
            self.seen[kind]=raw;self.busy=True
            def work(kind=kind,raw=raw):
                try:self.handle(kind,raw)
                except Exception as error:
                    try:request_id=json.loads(raw).get('id','error');self.respond(kind,clean(request_id),str(error),self.sessions.get(kind,(None,None))[1])
                    except Exception:pass
                finally:
                    diagnostic=getattr(self.picker,'last_diagnostics',None)
                    if diagnostic:
                        try:self.file('native-dialog-diagnostics.json').write_text(json.dumps(diagnostic,indent=2),encoding='utf-8')
                        except OSError:pass
                    self.busy=False
            threading.Thread(target=work,daemon=True,name='Epic-LUT-file-worker').start();break
