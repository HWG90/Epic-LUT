"""Real stock Lua5.1 and Python named-pipe clients; child timeout bounds deadlocks.
Private temp files only for fs contracts. No clipboard or ShellExecute invocation.
"""
import ctypes,gc,hashlib,json,os,shutil,statistics,struct,subprocess,sys,tempfile,time
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]


def foreign_client(request,response):
    with open(request,'wb',buffering=0) as output,open(response,'rb',buffering=0) as incoming:
        output.write(b'ELP1'+struct.pack('<III',1,0,0))
        print('connected',flush=True)
        assert incoming.read(16)==b'', 'Foreign peer was not closed at native PID check'
    print('foreign peer rejected',flush=True)


def worker(directory,dll):
    receipt=json.loads((ROOT/'dist/native-lua51-platform/build.json').read_text())
    assert hashlib.sha256(Path(dll).read_bytes()).hexdigest()==receipt['sha256']
    assert hashlib.sha256((ROOT/'native/lua51_platform.c').read_bytes()).hexdigest()==receipt['source_sha256']
    assert receipt['exports']==['epic_lut_platform','epic_lut_platform_close','epic_lut_platform_open']
    root=Path(directory);lua=LuaRuntime(encoding=None,unpack_returned_tuples=True)
    lua.execute(b"assert(_VERSION=='Lua 5.1');ffi,bit,jit=nil,nil,nil")
    load=lua.eval(b'package.loadlib')
    call=load(str(dll).encode('ascii'),b'epic_lut_platform')
    start=load(str(dll).encode('ascii'),b'epic_lut_platform_open')
    stop=load(str(dll).encode('ascii'),b'epic_lut_platform_close')
    assert not any(isinstance(value,tuple) for value in [call,start,stop])
    request=rf'\\.\pipe\EpicLutPlatform-{os.getpid()}-request'
    response=rf'\\.\pipe\EpicLutPlatform-{os.getpid()}-response'
    make_client=lua.execute(b"""return function(callback,request_path,response_path)
        local output=assert(io.open(request_path,'wb'));output:setvbuf('no')
        local input=assert(io.open(response_path,'rb'));input:setvbuf('no')
        return {
            exchange=function(bytes)
                assert(output:write(bytes));assert(output:flush());assert(callback()==nil)
                local header=assert(input:read(16),'Response EOF');assert(#header==16,'Short response header')
                local a,b,c,d=header:byte(13,16);local count=a+b*256+c*65536+d*16777216
                assert(count<=1048576,'Response bounds')
                local payload=count>0 and assert(input:read(count),'Response payload EOF') or ''
                assert(#payload==count,'Truncated response payload');return header..payload
            end,
            close=function()output:close();input:close()end,
        }
    end""")
    client=None
    def reopen():
        nonlocal client
        if client:client.close();client=None
        assert stop() is None and start() is None
        client=make_client(call,request.encode(),response.encode())
    reopen();sequence,calls=0,0
    def exchange(operation,payload=b'',expected=0):
        nonlocal sequence,calls
        sequence+=1;calls+=1
        frame=b'ELP1'+struct.pack('<III',sequence,operation,len(payload))+payload
        assert len(frame)<=1048592
        reply=client.exchange(frame);magic,nonce,status,length=struct.unpack('<4sIII',reply[:16])
        assert magic==b'ELR1' and nonce==sequence and len(reply)==16+length and length<=1048576
        assert status==expected,(operation,status,expected)
        if status:assert length==0,'Partial failed reply escaped'
        return reply[16:]
    assert exchange(0)==b'1'
    assert exchange(0)==b'1','Persistent same-process pipe disconnected'
    for text in ['', 'ASCII', '\u65e5\u672c\u8a9e / \u00c4\u00df / \u0394 / \U0001f986', '\U00010437']:
        value=text.encode('utf8');assert exchange(1,value)==value
    for invalid in [b'x\0y',b'\xc0\xaf',b'\xed\xa0\x80',b'\xff']:
        exchange(1,invalid,13 if b'\0' in invalid else 1113)
    exchange(255,b'',50)
    for operation in (13,14,15):
        exchange(operation,b'',13)
        exchange(operation,struct.pack('<I',4294967295),6)
    work=root/'\u8863\u88c5 \U0001f986';exchange(4,str(work).encode());exchange(4,str(work).encode())
    exchange(7,str(work).encode(),183)
    exclusive=root/'exclusive';exchange(7,str(exclusive).encode());exchange(8,str(exclusive).encode())
    marker=work/'helmet \u65e5\u672c\u8a9e.dds';marker.write_bytes(b'palette')
    exchange(4,str(marker).encode(),183);exchange(8,str(work).encode(),145)
    fields=exchange(5,str(marker).encode()).decode().split('\t')
    assert fields[0]=='F' and len(fields[1])==16 and int(fields[1],16)==7 and len(fields[2])==16 and int(fields[2],16)>0
    assert exchange(5,str(work).encode()).decode().startswith('D\t')
    assert exchange(6,str(work).encode())==('F\t'+marker.name+'\n').encode()
    nested=work/'capes';nested.mkdir()
    assert set(exchange(6,str(work).encode()).decode().splitlines())=={'F\t'+marker.name,'D\t'+nested.name}
    src=work/'new \u8272.dds';dst=work/'existing.dds';src.write_bytes(b'new palette');dst.write_bytes(b'old palette')
    encoded=str(src).encode();exchange(9,struct.pack('<I',len(encoded))+encoded+str(dst).encode())
    assert dst.read_bytes()==b'new palette' and not src.exists()
    exchange(9,struct.pack('<I',0)+b'x',13);exchange(9,struct.pack('<I',99)+b'x',13)
    for invalid in [b'a\0b',b'\xff']:exchange(5,invalid,13 if b'\0' in invalid else 1113)
    contract_calls=calls
    assert exchange(1,b'Q'*1048576)==b'Q'*1048576,'Maximum pipe quota deadlocked/truncated'
    # Corrupt headers and lengths return a bounded failure and terminate that session.
    for frame,nonce in [(b'ELP1'+struct.pack('<III',99,0,1),99),
                        (b'ELP1'+struct.pack('<III',99,1,1048577),99),
                        (b'ELP1'+struct.pack('<III',99,0,0)+b'extra',99),
                        (b'ELP1',0)]:
        reply=client.exchange(frame)
        assert struct.unpack('<4sIII',reply)==(b'ELR1',nonce,13,0)
        reopen();assert exchange(0)==b'1'
    timings={}
    for operation,payload in [(1,'Native UTF8 latency \u65e5\u672c\u8a9e'.encode()),(5,str(marker).encode())]:
        samples=[]
        for _ in range(100):
            started=time.perf_counter();exchange(operation,payload);samples.append((time.perf_counter()-started)*1000)
        ordered=sorted(samples)
        timings[operation]={'median_ms':round(statistics.median(samples),3),'p95_ms':round(ordered[94],3),'max_ms':round(max(samples),3)}
    client.close();client=None;stop();start()
    # Real Python pipe handles exercise the same native callback through ctypes.
    native=ctypes.WinDLL(str(dll));callback=native.epic_lut_platform
    callback.argtypes=[ctypes.c_void_p];callback.restype=ctypes.c_int
    with open(request,'wb',buffering=0) as output,open(response,'rb',buffering=0) as incoming:
        output.write(b'ELP1'+struct.pack('<III',7,1,6)+b'python');assert callback(None)==0
        header=incoming.read(16);assert struct.unpack('<4sIII',header)==(b'ELR1',7,0,6)
        assert incoming.read(6)==b'python'
    # Withhold reads until the output quota cannot fit a maximum reply. The
    # nonblocking write must close its server on partial output, exposing EOF.
    stop();start()
    with open(request,'wb',buffering=0) as output,open(response,'rb',buffering=0) as incoming:
        for _ in range(500):
            output.write(b'ELP1'+struct.pack('<III',7,0,0));assert callback(None)==0
        output.write(b'ELP1'+struct.pack('<III',8,1,1048576)+b'Q'*1048576);assert callback(None)==0
        received=0
        while True:
            part=incoming.read(65536)
            if not part:break
            received+=len(part);assert received<=2097184,'Unbounded failed response'
        assert received>0,'Pressure test did not queue any valid response'
    stop();start()
    # A same-user foreign process can connect but cannot dispatch any platform operation.
    child=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'--foreign',request,response],
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    assert child.stdout.readline().strip()=='connected'
    assert callback(None)==0
    stdout,stderr=child.communicate(timeout=5)
    assert child.returncode==0,(stdout,stderr)
    reopen();assert exchange(0)==b'1'
    client.close();client=None;stop();stop()
    assert not list(root.glob('*request.bin')) and not list(root.glob('*response.bin')) and not list(root.glob('*.tmp'))
    del call,start,stop,load,make_client,lua;gc.collect();handle=native._handle;del callback,native
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.FreeLibrary.argtypes=[ctypes.c_void_p];kernel.FreeLibrary.restype=ctypes.c_int
    assert kernel.FreeLibrary(handle)
    print('PASS native Lua5.1 named pipes:',contract_calls,'fs/UTF8 contracts; maximum1MiB, malformed EOF/reopen, output-quota failure EOF, Pythonclient, foreignPID rejection, no IPC files, no clipboard/ShellExecute invocation')
    print('In-process named-pipe latency UTF8op1/statop5:',timings)


def main():
    receipt=json.loads((ROOT/'dist/native-lua51-platform/build.json').read_text())
    with tempfile.TemporaryDirectory(prefix='epic-lua51-platform-') as temporary:
        root=Path(temporary).resolve()
        assert root.parent==Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-lua51-platform-')
        dll=root/Path(receipt['dll']).name;shutil.copyfile(receipt['dll'],dll)
        result=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--worker',str(root),str(dll)],
            capture_output=True,text=True,timeout=30)
        print(result.stdout,end='');print(result.stderr,end='',file=sys.stderr)
        assert result.returncode==0,'Native pipe test process failed or exceeded its deadline'
        assert root.parent==Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-lua51-platform-')

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--worker':worker(sys.argv[2],sys.argv[3])
    elif len(sys.argv)>1 and sys.argv[1]=='--foreign':foreign_client(sys.argv[2],sys.argv[3])
    else:main()
