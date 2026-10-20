"""Real LLL project loading of shared provenance, with actual external SHA256.

Private Temp, stock Lua5.1, declared imports only. No game, DLL loading,
clipboard, dialog, installation, or checkout fallback is used by the project.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from lupa.lua51 import LuaError, LuaRuntime
from test_lua51_external_project import retired

ROOT = Path(__file__).resolve().parents[1]
LLL = Path(os.environ.get('EPIC_LLL_TEST_ROOT', ROOT.parent / 'DBF-Suite/LLL')).resolve()
MODULES = {
    'external_platform': 'src/platform/external_platform.lua',
    'native_platform': 'src/platform/native_platform.lua',
    'runtime_services': 'src/platform/runtime_services.lua',
    'loader_store': 'src/platform/loader_store.lua',
    'file_io': 'src/core/file_io.lua',
    'cooperative': 'src/core/cooperative.lua',
    'float_buffer': 'src/core/float_buffer.lua',
    'binding_provenance': 'src/presets/binding_provenance.lua',
    'export_provenance': 'src/presets/export_provenance.lua',
    'direct_editor': 'src/editor/direct_editor.lua',
}
PAYLOAD = bytes(range(256)) * 257


def entry_source(executable, digest):
    assert executable.startswith('EpicLutLua51Service-') and executable.endswith('.exe')
    assert len(digest) == 64 and all(c in '0123456789abcdef' for c in digest)
    prefix = ('local m={platform_backend="external",native_platform_name="' + executable
        + '",native_platform_sha256="' + digest + '"}\nmod.scope.m=m\n')
    for name, path in MODULES.items():
        prefix += 'm.' + name + '=mod.require("' + path + '")\n'
    return (prefix + r'''
local start=m.external_platform.start
m.external_platform.start=function(...)
    local channel=start(...);m.helper_pid=channel.server_pid;return channel
end
local lease,stream,files,owned
local filename=mod.dir..'/owned-\230\156\141\232\163\133-digest.bin'
local function cleanup()
    if stream then assert(stream:close());stream=nil end
    if owned then assert(files.remove(filename));owned=false end
    if lease then assert(lease.close(true));lease=nil end
    return true
end
return {live_lua_api=1,on_enable=function()
    if mod.config.capture then return true end
    local report={success=false}
    local ok,why=pcall(function()
        local reason;lease,reason=m.runtime_services.start(m,mod)
        assert(lease and lease.ready,reason)
        files=m.file_io.new(lease.platform)
        assert(lease.platform.stat(filename)==nil,'Owned fixture path already exists')
        local bytes={};for value=0,255 do bytes[#bytes+1]=string.char(value)end
        local payload=string.rep(table.concat(bytes),257)
        stream=assert(files.open(filename,'wb'));owned=true
        assert(stream:write(payload));assert(stream:close());stream=nil
        report.string_digest=m.binding_provenance.digest('abc')
        report.empty_digest=m.binding_provenance.digest('')
        stream=assert(files.open(filename,'rb'))
        local slices=0
        local thread=coroutine.create(function()
            return m.binding_provenance.digest(function()
                local chunk=stream:read(32768)
                if chunk then slices=slices+1;coroutine.yield('digest-slice')end
                return chunk
            end,#payload)
        end)
        while true do
            local worked,value=coroutine.resume(thread);assert(worked,value)
            if coroutine.status(thread)=='dead' then report.file_digest=value;break end
            assert(value=='digest-slice')
        end
        report.slices,report.bytes=slices,#payload
        assert(stream:close());stream=nil
        local snapshot=string.char(0,1,2,3,250,251,252,253)
        local exporter=m.export_provenance.new({}, {read_snapshot=function(address,size)
            assert(address==65536 and size==#snapshot);return snapshot
        end})
        assert(exporter.read(65536,#snapshot)==snapshot)
        report.export_snapshot=true
        assert(type(m.direct_editor.on_enable)=='function' and m.direct_editor.on_disable()==true)
        report.direct_descriptor=true
    end)
    local clean,problem=pcall(cleanup)
    report.helper_process_id=m.helper_pid
    report.success=ok and clean
    report.cleanup_complete=clean
    if not ok then report.error=tostring(why)end
    if not clean then report.cleanup_error=tostring(problem)end
    assert(mod.set('capture',report)~=false)
    return true
end,on_disable=cleanup}
''').encode('utf8')


def worker(directory, executable, digest):
    private = Path(directory).resolve()
    assert Path.cwd().resolve() == private and private.parent == Path(tempfile.gettempdir()).resolve()
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.globals()[b'actual_pid'] = os.getpid()
    lua.execute(b"""ffi,bit,jit=nil,nil,nil;package.path='';package.cpath=''
        local popen=io.popen;fixture_launches=0
        io.popen=function(...)fixture_launches=fixture_launches+1;return popen(...)end
        package.loadlib=function()error('Unexpected DLL loading')end
        require=function(name)error('Undeclared checkout import: '..name)end
        stingray={Application={process_id=function()return actual_pid end}}
    """)
    lua.globals()[b'LLL_METADATA'] = lua.execute((LLL/'src/metadata.lua').read_bytes())
    lua.globals()[b'LLL_CONFIG'] = lua.execute((LLL/'src/config.lua').read_bytes())
    project = lua.execute((LLL/'src/project.lua').read_bytes())
    lua.execute(b"dofile=function(name)error('Undeclared dofile: '..tostring(name))end")
    settings, writes = private/'loader-settings', [0]

    def owned(path):
        result = Path(os.fsdecode(path)).resolve()
        assert result.is_relative_to(private), 'Loader fixture escaped private Temp'
        return result

    def read(path, limit):
        try:
            data = owned(path).read_bytes()
        except FileNotFoundError:
            return None
        assert len(data) <= limit
        return data

    def write(path, data):
        target=owned(path);pending=target.with_suffix('.owned-pending')
        pending.write_bytes(data);os.replace(pending,target);writes[0]+=1
        return True

    def mkdir(path):
        owned(path).mkdir(parents=True,exist_ok=True)
        return True

    host=lua.table_from({b'native_ffi':False,b'settings':str(settings).encode('utf8'),
        b'read':read,b'write':write,b'mkdir':mkdir})
    # The old guarded layout is still rejected. Never hide or disable LLL's
    # native check merely because a portable branch would execute first.
    guarded=b"if m and m.platform then return m.platform.digest('abc') end\nlocal ffi=require('ffi')"
    for source in (guarded,(ROOT/'src/platform/legacy_binding_digest.lua').read_bytes()):
        try:
            project[b'check_runtime'](host,source,b'legacy-digest-counterexample.lua')
        except LuaError as error:
            assert 'requires LuaJIT ffi' in str(error)
        else:
            raise AssertionError('Guarded legacy FFI unexpectedly passed stock preflight')
    assert lua.globals()[b'fixture_launches']==0
    for source in ('src/presets/binding_provenance.lua','src/presets/export_provenance.lua'):
        project[b'check_runtime'](host,(ROOT/source).read_bytes(),source.encode())

    identifier='provenance_digest'
    directory=private/'project-\u670d\u88c5';(directory/'config').mkdir(parents=True)
    for source in MODULES.values():
        destination=directory/source;destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/source,destination)
    shutil.copyfile(executable,directory/Path(executable).name)
    (directory/'main.lua').write_bytes(entry_source(Path(executable).name,digest))
    (directory/'manifest.json').write_text(json.dumps({'lll':{'entry':'main.lua','defaults':'config/defaults.cfg',
        'modules':list(MODULES.values())}}),encoding='utf8')
    (directory/'config/defaults.cfg').write_text('{"unrelated":{"enabled":true}}',encoding='ascii')
    entry=lua.table_from({b'id':identifier.encode(),b'dir':str(directory).replace('\\','/').encode('utf8')})
    spec=project[b'descriptor'](host,entry[b'dir'])

    def instantiate():
        snapshot=project[b'snapshot'](host,entry,spec)
        return project[b'instantiate'](host,entry,snapshot,lambda *_:None)

    definition,public=instantiate()
    assert definition[b'on_update'] is None and definition[b'on_enable']() is True
    capture=public[b'config'][b'capture']
    assert capture[b'success'] is True, {os.fsdecode(k):v for k,v in capture.items()}
    assert capture[b'string_digest'].decode()==hashlib.sha256(b'abc').hexdigest()
    assert capture[b'empty_digest'].decode()==hashlib.sha256(b'').hexdigest()
    assert capture[b'file_digest'].decode()==hashlib.sha256(PAYLOAD).hexdigest()
    assert capture[b'bytes']==len(PAYLOAD) and capture[b'slices']==3
    assert capture[b'export_snapshot'] is True and capture[b'direct_descriptor'] is True
    assert capture[b'cleanup_complete'] is True
    assert not (directory/'owned-\u670d\u88c5-digest.bin').exists()
    assert definition[b'on_disable']() is True
    retired(capture[b'helper_process_id'])
    before=(writes[0],lua.globals()[b'fixture_launches'])
    for _ in range(3):assert definition[b'on_enable']() is True
    reloaded,api=instantiate()
    assert api[b'config'][b'capture'][b'file_digest']==capture[b'file_digest']
    assert api[b'config'][b'unrelated'][b'enabled'] is True and reloaded[b'on_enable']() is True
    assert before==(writes[0],lua.globals()[b'fixture_launches']) and before[1]==1
    assert reloaded[b'on_disable']() is True
    print(json.dumps({'status':'PASS','runtime':'Lua 5.1','sha256':digest,'bytes':len(PAYLOAD),
        'yielding_reader_slices':3,'actual_lll_preflight':True,'exact_shared_modules':True,
        'direct_descriptor_cold_cleanup':True,'config_reload_idle':True,'helper_retired':True}))


def main():
    receipt=json.loads((ROOT/'dist/native-lua51-platform-service/build.json').read_text())
    executable=Path(receipt['exe']);digest=receipt['sha256']
    assert hashlib.sha256(executable.read_bytes()).hexdigest()==digest
    with tempfile.TemporaryDirectory(prefix='epic-binding-digest-') as directory:
        result=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--worker',directory,
            str(executable),digest],cwd=directory,capture_output=True,text=True,timeout=45)
        print(result.stdout,end='')
        if result.returncode:print(result.stderr,file=sys.stderr,end='')
        assert result.returncode==0,'Hermetic provenance digest project failed'


if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--worker':worker(*sys.argv[2:])
    else:main()
