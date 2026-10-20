/* Stock Lua5.1 platform bridge. Standard zero-result Lua C callback only;
 * lua_State is opaque and never read. No game API, process memory, hooks,
 * input capture, executable patches or background polling. Explicit import
 * workers launch only the system PowerShell executable with hidden windows.
 * Protocol: per-PID unidirectional named pipes; ELP1/ELR1 + nonce u32
 * + operation/status u32 + payload length u32. No IPC files are created.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <bcrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define MAX_PAYLOAD (1024u * 1024u)
#define MAX_ENTRIES 16384u
#define MAX_PATH_CHARS 32767u
#define MAX_FILE_BYTES (64u * 1024u * 1024u)
#define MAX_STREAM_POSITION UINT64_C(9007199254740991)
static HANDLE request_pipe=INVALID_HANDLE_VALUE,response_pipe=INVALID_HANDLE_VALUE;
static volatile LONG active;
typedef struct { HANDLE process,job; uint32_t token; DWORD pid; } Worker;
static Worker workers[8];
static uint32_t next_worker;
typedef struct { HANDLE handle; uint32_t token; unsigned mode; } OwnedFile;
static OwnedFile files[8];
static uint32_t next_file;
typedef struct {
    BCRYPT_ALG_HANDLE algorithm;BCRYPT_HASH_HANDLE handle;unsigned char *object;
    ULONG object_length;uint32_t token;uint64_t total,limit;unsigned exact;
} OwnedHash;
static OwnedHash hashes[8];
static uint32_t next_hash;
typedef struct { char *data; uint32_t length, capacity; } Buffer;
static uint32_t word(const unsigned char *p) {
    return p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static uint64_t qword(const unsigned char *p) {
    return word(p) | (uint64_t)word(p+4)<<32;
}
static void put_word(unsigned char *p,uint32_t n) {
    p[0]=(unsigned char)n;p[1]=(unsigned char)(n>>8);p[2]=(unsigned char)(n>>16);p[3]=(unsigned char)(n>>24);
}
static void put_qword(unsigned char *p,uint64_t n) {
    put_word(p,(uint32_t)n);put_word(p+4,(uint32_t)(n>>32));
}
static DWORD last_error(void) { DWORD e=GetLastError();return e ? e : ERROR_INVALID_DATA; }
static DWORD append(Buffer *b,const void *bytes,uint32_t count) {
    uint32_t capacity;char *replacement;
    if(count>MAX_PAYLOAD-b->length)return ERROR_MORE_DATA;
    if(b->length+count>b->capacity) {
        capacity=b->capacity ? b->capacity : 256;
        while(capacity<b->length+count)capacity=capacity>MAX_PAYLOAD/2 ? MAX_PAYLOAD : capacity*2;
        replacement=(char*)realloc(b->data,capacity);
        if(!replacement)return ERROR_NOT_ENOUGH_MEMORY;
        b->data=replacement;b->capacity=capacity;
    }
    if(count)memcpy(b->data+b->length,bytes,count);
    b->length+=count;return ERROR_SUCCESS;
}
static DWORD utf16(const char *s,uint32_t length,uint32_t maximum,wchar_t **out) {
    int count;wchar_t *value;
    if(!length || length>MAX_PAYLOAD || memchr(s,0,length))return ERROR_INVALID_DATA;
    count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,(int)length,NULL,0);
    if(count<=0)return ERROR_NO_UNICODE_TRANSLATION;
    if((uint32_t)count>maximum)return ERROR_FILENAME_EXCED_RANGE;
    value=(wchar_t*)malloc(((size_t)count+1)*sizeof(wchar_t));
    if(!value)return ERROR_NOT_ENOUGH_MEMORY;
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,(int)length,value,count)!=count) {
        free(value);return ERROR_NO_UNICODE_TRANSLATION;
    }
    value[count]=0;*out=value;return ERROR_SUCCESS;
}
static DWORD utf8(Buffer *b,const wchar_t *value,size_t length) {
    int needed;char *bytes;DWORD result;
    if(length>MAX_PAYLOAD)return ERROR_MORE_DATA;
    if(!length)return ERROR_SUCCESS;
    needed=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,(int)length,NULL,0,NULL,NULL);
    if(needed<=0)return ERROR_NO_UNICODE_TRANSLATION;
    if((uint32_t)needed>MAX_PAYLOAD-b->length)return ERROR_MORE_DATA;
    bytes=(char*)malloc((size_t)needed);
    if(!bytes)return ERROR_NOT_ENOUGH_MEMORY;
    if(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,(int)length,bytes,needed,NULL,NULL)!=needed) {
        free(bytes);return ERROR_NO_UNICODE_TRANSLATION;
    }
    result=append(b,bytes,(uint32_t)needed);free(bytes);return result;
}
static void close_workers(void) {
    unsigned i;
    for(i=0;i<8;i++) {
        if(workers[i].process)CloseHandle(workers[i].process);
        if(workers[i].job)CloseHandle(workers[i].job);
        memset(&workers[i],0,sizeof(workers[i]));
    }
}
static void close_file(OwnedFile *file) {
    if(file->handle)CloseHandle(file->handle);
    memset(file,0,sizeof(*file));
}
static void close_files(void) {
    unsigned i;for(i=0;i<8;i++)close_file(&files[i]);
}
static DWORD open_file(const char *payload,uint32_t length,Buffer *output) {
    wchar_t *name=NULL;unsigned slot,mode;DWORD result,access,share,creation;
    HANDLE handle=INVALID_HANDLE_VALUE;LARGE_INTEGER size,zero;unsigned char receipt[4];
    if(length<2)return ERROR_INVALID_DATA;
    mode=(unsigned char)payload[0];if(mode>2)return ERROR_INVALID_DATA;
    for(slot=0;slot<8 && files[slot].handle;slot++);
    if(slot==8 || next_file==UINT32_MAX)return ERROR_TOO_MANY_OPEN_FILES;
    result=utf16(payload+1,length-1,MAX_PATH_CHARS,&name);if(result)return result;
    access=mode ? GENERIC_WRITE : GENERIC_READ;share=mode ? 0 : FILE_SHARE_READ;
    creation=mode==1 ? CREATE_ALWAYS : mode==2 ? OPEN_ALWAYS : OPEN_EXISTING;
    handle=CreateFileW(name,access,share,NULL,creation,FILE_ATTRIBUTE_NORMAL,NULL);free(name);
    if(handle==INVALID_HANDLE_VALUE)return last_error();
    if(GetFileType(handle)!=FILE_TYPE_DISK) {result=ERROR_INVALID_HANDLE;goto failed;}
    if(!GetFileSizeEx(handle,&size)) {result=last_error();goto failed;}
    if(size.QuadPart<0 || (uint64_t)size.QuadPart>(mode ? MAX_FILE_BYTES : MAX_STREAM_POSITION)) {
        result=ERROR_FILE_TOO_LARGE;goto failed;
    }
    zero.QuadPart=0;
    if(mode==2 && !SetFilePointerEx(handle,zero,NULL,FILE_END)) {result=last_error();goto failed;}
    files[slot].handle=handle;files[slot].token=++next_file;files[slot].mode=mode;
    put_word(receipt,files[slot].token);result=append(output,receipt,sizeof(receipt));
    if(result)close_file(&files[slot]);
    return result;
failed:
    CloseHandle(handle);return result;
}
static DWORD file_operation(uint32_t operation,const char *payload,uint32_t length,Buffer *output) {
    OwnedFile *file=NULL;unsigned i;uint32_t token,count;DWORD result=ERROR_SUCCESS,done=0;
    LARGE_INTEGER zero,position,size;unsigned char receipt[8];
    if(length<4)return ERROR_INVALID_DATA;
    token=word((const unsigned char*)payload);
    for(i=0;i<8;i++)if(files[i].handle && files[i].token==token) {file=&files[i];break;}
    if(!file)return ERROR_INVALID_HANDLE;
    zero.QuadPart=0;
    if(operation==21) {
        if(length!=4) {result=ERROR_INVALID_DATA;goto failed;}
        if(!CloseHandle(file->handle))result=last_error();
        memset(file,0,sizeof(*file));return result;
    }
    if(operation==20) {
        if(length!=4) {result=ERROR_INVALID_DATA;goto failed;}
        if(file->mode && !FlushFileBuffers(file->handle)) {result=last_error();goto failed;}
        return ERROR_SUCCESS;
    }
    if(operation==19 || operation==28) {
        uint32_t origin;int64_t offset;uint64_t raw,magnitude,limit;
        unsigned wide=operation==28;
        if(length!=(wide ? 16u : 12u)) {result=ERROR_INVALID_DATA;goto failed;}
        origin=word((const unsigned char*)payload+4);
        if(wide) {
            raw=qword((const unsigned char*)payload+8);
            if(raw & (UINT64_C(1)<<63)) {
                magnitude=(~raw)+1;
                if(magnitude>MAX_STREAM_POSITION) {result=ERROR_INVALID_DATA;goto failed;}
                offset=-(int64_t)magnitude;
            } else {
                if(raw>MAX_STREAM_POSITION) {result=ERROR_INVALID_DATA;goto failed;}
                offset=(int64_t)raw;
            }
        } else offset=(int32_t)word((const unsigned char*)payload+8);
        if(origin>2 || (!wide && (offset<-(int64_t)MAX_FILE_BYTES || offset>(int64_t)MAX_FILE_BYTES))) {
            result=ERROR_INVALID_DATA;goto failed;
        }
        limit=wide && !file->mode ? MAX_STREAM_POSITION : MAX_FILE_BYTES;
        if(origin==0)position.QuadPart=0;
        else if(origin==1) {
            if(!SetFilePointerEx(file->handle,zero,&position,FILE_CURRENT)) {result=last_error();goto failed;}
        } else if(!GetFileSizeEx(file->handle,&position)) {result=last_error();goto failed;}
        if(position.QuadPart<0 || (uint64_t)position.QuadPart>limit) {result=ERROR_FILE_TOO_LARGE;goto failed;}
        position.QuadPart+=offset;
        /* Both operands are bounded to 2^53-1 before addition, far below the
           signed 64-bit limit. The final Lua number must remain exact. */
        if(position.QuadPart<0 || (uint64_t)position.QuadPart>limit) {result=ERROR_FILE_TOO_LARGE;goto failed;}
        if(!SetFilePointerEx(file->handle,position,&position,FILE_BEGIN)) {result=last_error();goto failed;}
        if(wide)put_qword(receipt,(uint64_t)position.QuadPart);
        else put_word(receipt,(uint32_t)position.QuadPart);
        result=append(output,receipt,wide ? 8u : 4u);
        if(result)goto failed;return ERROR_SUCCESS;
    }
    if(operation==17) {
        if(length!=8 || file->mode) {result=length!=8 ? ERROR_INVALID_DATA : ERROR_ACCESS_DENIED;goto failed;}
        count=word((const unsigned char*)payload+4);
        if(count>MAX_PAYLOAD) {result=ERROR_MORE_DATA;goto failed;}
        if(!SetFilePointerEx(file->handle,zero,&position,FILE_CURRENT) || !GetFileSizeEx(file->handle,&size)) {
            result=last_error();goto failed;
        }
        if(size.QuadPart<0 || (uint64_t)size.QuadPart>MAX_STREAM_POSITION
            || position.QuadPart<0 || (uint64_t)position.QuadPart>MAX_STREAM_POSITION) {
            result=ERROR_FILE_TOO_LARGE;goto failed;
        }
        if(position.QuadPart>=size.QuadPart)return ERROR_HANDLE_EOF;
        if((LONGLONG)count>size.QuadPart-position.QuadPart)count=(uint32_t)(size.QuadPart-position.QuadPart);
        if(!count)return ERROR_SUCCESS;
        output->data=(char*)malloc(count);
        if(!output->data) {result=ERROR_NOT_ENOUGH_MEMORY;goto failed;}
        output->capacity=count;
        if(!ReadFile(file->handle,output->data,count,&done,NULL)) {result=last_error();goto failed;}
        output->length=done;return done ? ERROR_SUCCESS : ERROR_HANDLE_EOF;
    }
    if(operation!=18 || !file->mode) {result=ERROR_ACCESS_DENIED;goto failed;}
    count=length-4;
    if(file->mode==2) {
        if(!SetFilePointerEx(file->handle,zero,&position,FILE_END)) {result=last_error();goto failed;}
    } else if(!SetFilePointerEx(file->handle,zero,&position,FILE_CURRENT)) {result=last_error();goto failed;}
    if(position.QuadPart<0 || position.QuadPart>MAX_FILE_BYTES || count>MAX_FILE_BYTES-position.QuadPart) {
        result=ERROR_FILE_TOO_LARGE;goto failed;
    }
    if(count && (!WriteFile(file->handle,payload+4,count,&done,NULL) || done!=count)) {
        result=last_error();goto failed;
    }
    put_word(receipt,done);result=append(output,receipt,4);
    if(result)goto failed;return ERROR_SUCCESS;
failed:
    close_file(file);return result;
}
static void close_hash(OwnedHash *hash) {
    if(hash->handle)BCryptDestroyHash(hash->handle);
    if(hash->algorithm)BCryptCloseAlgorithmProvider(hash->algorithm,0);
    if(hash->object) {SecureZeroMemory(hash->object,hash->object_length);free(hash->object);}
    memset(hash,0,sizeof(*hash));
}
static void close_hashes(void) {unsigned i;for(i=0;i<8;i++)close_hash(&hashes[i]);}
static DWORD begin_hash(const char *payload,uint32_t length,Buffer *output) {
    OwnedHash *hash;unsigned slot,exact;uint64_t limit;ULONG count,digest_length;unsigned char receipt[4];
    DWORD result=ERROR_GEN_FAILURE;
    if(length!=9 || (unsigned char)payload[0]>1)return ERROR_INVALID_DATA;
    exact=(unsigned char)payload[0];
    limit=word((const unsigned char*)payload+1) | (uint64_t)word((const unsigned char*)payload+5)<<32;
    if(limit>UINT64_C(9007199254740991) || (!exact && limit))return ERROR_INVALID_DATA;
    if(!exact)limit=UINT64_C(512)*1024*1024;
    for(slot=0;slot<8 && hashes[slot].handle;slot++);
    if(slot==8 || next_hash==UINT32_MAX)return ERROR_TOO_MANY_OPEN_FILES;
    hash=&hashes[slot];
    if(BCryptOpenAlgorithmProvider(&hash->algorithm,BCRYPT_SHA256_ALGORITHM,NULL,0)<0)goto failed;
    if(BCryptGetProperty(hash->algorithm,BCRYPT_OBJECT_LENGTH,(PUCHAR)&hash->object_length,
        sizeof(hash->object_length),&count,0)<0 || count!=sizeof(hash->object_length))goto failed;
    if(!hash->object_length || hash->object_length>MAX_PAYLOAD) {result=ERROR_MORE_DATA;goto failed;}
    if(BCryptGetProperty(hash->algorithm,BCRYPT_HASH_LENGTH,(PUCHAR)&digest_length,
        sizeof(digest_length),&count,0)<0 || count!=sizeof(digest_length) || digest_length!=32)goto failed;
    hash->object=(unsigned char*)malloc(hash->object_length);
    if(!hash->object) {result=ERROR_NOT_ENOUGH_MEMORY;goto failed;}
    if(BCryptCreateHash(hash->algorithm,&hash->handle,hash->object,hash->object_length,NULL,0,0)<0)goto failed;
    hash->token=++next_hash;hash->limit=limit;hash->exact=exact;
    put_word(receipt,hash->token);result=append(output,receipt,sizeof(receipt));
    if(result)close_hash(hash);
    return result;
failed:
    close_hash(hash);return result;
}
static DWORD hash_operation(uint32_t operation,const char *payload,uint32_t length,Buffer *output) {
    OwnedHash *hash=NULL;unsigned i;uint32_t token,count;DWORD result=ERROR_SUCCESS;
    unsigned char digest[32];char hex[64];const char digits[]="0123456789abcdef";
    if(length<4)return ERROR_INVALID_DATA;
    token=word((const unsigned char*)payload);
    for(i=0;i<8;i++)if(hashes[i].handle && hashes[i].token==token) {hash=&hashes[i];break;}
    if(!hash)return ERROR_INVALID_HANDLE;
    if(operation==23) {
        count=length-4;
        if(!count || count>65536) {result=ERROR_INVALID_DATA;goto finished;}
        if(count>hash->limit-hash->total) {result=ERROR_FILE_TOO_LARGE;goto finished;}
        if(BCryptHashData(hash->handle,(PUCHAR)payload+4,count,0)<0) {result=ERROR_GEN_FAILURE;goto finished;}
        hash->total+=count;return ERROR_SUCCESS;
    }
    if(length!=4) {result=ERROR_INVALID_DATA;goto finished;}
    if(operation==25)goto finished;
    if(operation!=24 || (hash->exact && hash->total!=hash->limit)) {result=ERROR_INVALID_DATA;goto finished;}
    if(BCryptFinishHash(hash->handle,digest,sizeof(digest),0)<0) {result=ERROR_GEN_FAILURE;goto finished;}
    for(i=0;i<32;i++) {hex[i*2]=digits[digest[i]>>4];hex[i*2+1]=digits[digest[i]&15];}
    SecureZeroMemory(digest,sizeof(digest));result=append(output,hex,sizeof(hex));
finished:
    close_hash(hash);return result;
}
static DWORD executable_path(Buffer *output) {
    wchar_t *path=(wchar_t*)malloc(MAX_PATH_CHARS*sizeof(wchar_t));DWORD length,result;
    if(!path)return ERROR_NOT_ENOUGH_MEMORY;
    length=GetModuleFileNameW(NULL,path,MAX_PATH_CHARS);
    result=length && length<MAX_PATH_CHARS ? utf8(output,path,length) : ERROR_FILENAME_EXCED_RANGE;
    free(path);return result;
}
static DWORD launch_worker(const char *payload,uint32_t length,Buffer *output) {
    wchar_t *args=NULL,*folder=NULL,*file=NULL,*line=NULL;
    DWORD first,result=ERROR_SUCCESS,system_length,attributes;unsigned slot;
    size_t file_length,args_length;STARTUPINFOW startup={0};PROCESS_INFORMATION info={0};
    HANDLE job=NULL;unsigned char receipt[8];
    const wchar_t suffix[]=L"\\WindowsPowerShell\\v1.0\\powershell.exe";
    if(length<6)return ERROR_INVALID_DATA;
    first=word((const unsigned char*)payload);
    if(!first || first>length-5)return ERROR_INVALID_DATA;
    for(slot=0;slot<8 && workers[slot].process;slot++);
    if(slot==8)return ERROR_TOO_MANY_OPEN_FILES;
    if(next_worker==UINT32_MAX)return ERROR_TOO_MANY_OPEN_FILES;
    result=utf16(payload+4,first,MAX_PATH_CHARS,&args);
    if(!result)result=utf16(payload+4+first,length-4-first,MAX_PATH_CHARS,&folder);
    if(result)goto done;
    attributes=GetFileAttributesW(folder);
    if(attributes==INVALID_FILE_ATTRIBUTES) {result=last_error();goto done;}
    if(!(attributes&FILE_ATTRIBUTE_DIRECTORY)) {result=ERROR_DIRECTORY;goto done;}
    file=(wchar_t*)malloc(MAX_PATH_CHARS*sizeof(wchar_t));
    if(!file) {result=ERROR_NOT_ENOUGH_MEMORY;goto done;}
    system_length=GetSystemDirectoryW(file,MAX_PATH_CHARS);
    if(!system_length || system_length>=MAX_PATH_CHARS
        || system_length+wcslen(suffix)>=MAX_PATH_CHARS) {result=ERROR_FILENAME_EXCED_RANGE;goto done;}
    memcpy(file+system_length,suffix,sizeof(suffix));
    file_length=wcslen(file);args_length=wcslen(args);
    if(file_length+args_length+4>MAX_PATH_CHARS) {result=ERROR_FILENAME_EXCED_RANGE;goto done;}
    line=(wchar_t*)malloc((file_length+args_length+4)*sizeof(wchar_t));
    if(!line) {result=ERROR_NOT_ENOUGH_MEMORY;goto done;}
    line[0]=L'"';memcpy(line+1,file,file_length*sizeof(wchar_t));
    line[file_length+1]=L'"';line[file_length+2]=L' ';
    memcpy(line+file_length+3,args,(args_length+1)*sizeof(wchar_t));
    job=CreateJobObjectW(NULL,NULL);
    if(!job) {result=last_error();goto done;}
    startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESHOWWINDOW;startup.wShowWindow=SW_HIDE;
    if(!CreateProcessW(file,line,NULL,NULL,FALSE,CREATE_NO_WINDOW|CREATE_SUSPENDED,NULL,folder,&startup,&info)) {
        result=last_error();goto done;
    }
    if(!AssignProcessToJobObject(job,info.hProcess) || ResumeThread(info.hThread)==(DWORD)-1) {
        result=last_error();TerminateProcess(info.hProcess,1);goto done;
    }
    workers[slot].process=info.hProcess;workers[slot].job=job;
    workers[slot].token=++next_worker;workers[slot].pid=info.dwProcessId;
    put_word(receipt,workers[slot].token);put_word(receipt+4,info.dwProcessId);
    result=append(output,receipt,sizeof(receipt));
    if(result) {TerminateJobObject(job,1);memset(&workers[slot],0,sizeof(workers[slot]));}
    else {info.hProcess=NULL;job=NULL;}
done:
    if(info.hThread)CloseHandle(info.hThread);
    if(info.hProcess)CloseHandle(info.hProcess);
    if(job)CloseHandle(job);
    free(args);free(folder);free(file);free(line);return result;
}
static DWORD worker_operation(uint32_t operation,const char *payload,uint32_t length,Buffer *output) {
    Worker *worker=NULL;unsigned i;DWORD state;unsigned char value[4];uint32_t token;
    if(length!=4)return ERROR_INVALID_DATA;
    token=word((const unsigned char*)payload);
    for(i=0;i<8;i++)if(workers[i].process && workers[i].token==token) {worker=&workers[i];break;}
    if(!worker)return ERROR_INVALID_HANDLE;
    if(operation==15) {
        CloseHandle(worker->process);CloseHandle(worker->job);memset(worker,0,sizeof(*worker));return ERROR_SUCCESS;
    }
    state=WaitForSingleObject(worker->process,0);
    if(state==WAIT_FAILED)return last_error();
    if(state!=WAIT_OBJECT_0 && state!=WAIT_TIMEOUT)return ERROR_INVALID_DATA;
    if(operation==13) {put_word(value,state==WAIT_TIMEOUT);return append(output,value,sizeof(value));}
    if(state==WAIT_TIMEOUT && !TerminateJobObject(worker->job,1))return last_error();
    return ERROR_SUCCESS;
}
static DWORD own_foreground(HWND *window) {
    DWORD pid=0;HWND value=GetForegroundWindow();
    if(value)GetWindowThreadProcessId(value,&pid);
    if(!value || pid!=GetCurrentProcessId())return ERROR_ACCESS_DENIED;
    *window=value;return ERROR_SUCCESS;
}
static DWORD clipboard_get(Buffer *output) {
    HWND window;HANDLE memory;const wchar_t *text,*end;SIZE_T size;DWORD result=own_foreground(&window);
    if(result)return result;
    if(!OpenClipboard(window))return last_error();
    memory=GetClipboardData(CF_UNICODETEXT);
    if(!memory) {result=last_error();goto closed;}
    size=GlobalSize(memory);
    if(size<sizeof(wchar_t) || size>((SIZE_T)MAX_PAYLOAD+1)*sizeof(wchar_t)) {result=ERROR_MORE_DATA;goto closed;}
    text=(const wchar_t*)GlobalLock(memory);
    if(!text) {result=last_error();goto closed;}
    end=(const wchar_t*)wmemchr(text,0,size/sizeof(wchar_t));
    result=end ? utf8(output,text,(size_t)(end-text)) : ERROR_INVALID_DATA;
    GlobalUnlock(memory);
closed:
    if(!CloseClipboard() && !result)result=last_error();
    return result;
}
static DWORD clipboard_set(const char *payload,uint32_t length) {
    HWND window;wchar_t *text=NULL;HGLOBAL memory=NULL;void *target;SIZE_T size;DWORD result=own_foreground(&window);
    if(result)return result;
    /* Empty text is a valid clipboard value; path/identity inputs remain nonempty. */
    if(length) {result=utf16(payload,length,MAX_PAYLOAD,&text);if(result)return result;}
    size=((SIZE_T)(text ? wcslen(text) : 0)+1)*sizeof(wchar_t);
    memory=GlobalAlloc(GMEM_MOVEABLE,size);
    if(!memory) {free(text);return ERROR_NOT_ENOUGH_MEMORY;}
    target=GlobalLock(memory);
    if(!target) {result=last_error();goto finished;}
    if(text)memcpy(target,text,size);else memset(target,0,size);
    GlobalUnlock(memory);
    if(!OpenClipboard(window)) {result=last_error();goto finished;}
    if(!EmptyClipboard())result=last_error();
    else if(!SetClipboardData(CF_UNICODETEXT,memory))result=last_error();
    else {memory=NULL;result=ERROR_SUCCESS;} /* Clipboard now owns the allocation. */
    if(!CloseClipboard() && !result)result=last_error();
finished:
    if(memory)GlobalFree(memory);
    free(text);return result;
}
static DWORD list(const wchar_t *directory,Buffer *output) {
    WIN32_FIND_DATAW item;HANDLE search;wchar_t *pattern;size_t size=wcslen(directory);DWORD result=ERROR_SUCCESS,count=0;
    if(size>MAX_PATH_CHARS-3)return ERROR_FILENAME_EXCED_RANGE;
    pattern=(wchar_t*)malloc((size+3)*sizeof(wchar_t));
    if(!pattern)return ERROR_NOT_ENOUGH_MEMORY;
    memcpy(pattern,directory,size*sizeof(wchar_t));
    if(size && directory[size-1]!=L'\\' && directory[size-1]!=L'/')pattern[size++]=L'\\';
    pattern[size++]=L'*';pattern[size]=0;
    search=FindFirstFileW(pattern,&item);free(pattern);
    if(search==INVALID_HANDLE_VALUE) {
        result=last_error();
        return result==ERROR_FILE_NOT_FOUND ? ERROR_SUCCESS : result;
    }
    do {
        size_t length;
        if(!wcscmp(item.cFileName,L".") || !wcscmp(item.cFileName,L".."))continue;
        if(++count>MAX_ENTRIES) {result=ERROR_MORE_DATA;break;}
        length=wcslen(item.cFileName);
        if(wcschr(item.cFileName,L'\t') || wcschr(item.cFileName,L'\r') || wcschr(item.cFileName,L'\n')) {
            result=ERROR_INVALID_DATA;break;
        }
        result=append(output,item.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY ? "D\t" : "F\t",2);
        if(!result)result=utf8(output,item.cFileName,length);
        if(!result)result=append(output,"\n",1);
        if(result)break;
    }while(FindNextFileW(search,&item));
    if(!result && GetLastError()!=ERROR_NO_MORE_FILES)result=last_error();
    FindClose(search);return result;
}
static DWORD dispatch(uint32_t operation,const char *payload,uint32_t length,Buffer *output) {
    wchar_t *path=NULL;DWORD result=ERROR_SUCCESS;
    if(operation==0)return length ? ERROR_INVALID_DATA : append(output,"1",1);
    if(operation==1) {
        if(!length)return ERROR_SUCCESS;
        result=utf16(payload,length,MAX_PAYLOAD,&path);
        if(!result)result=utf8(output,path,wcslen(path));
        free(path);return result;
    }
    if(operation==2)return length ? ERROR_INVALID_DATA : clipboard_get(output);
    if(operation==3)return clipboard_set(payload,length);
    if(operation==11)return length ? ERROR_INVALID_DATA : executable_path(output);
    if(operation==12)return launch_worker(payload,length,output);
    if(operation>=13 && operation<=15)return worker_operation(operation,payload,length,output);
    if(operation==16)return open_file(payload,length,output);
    if((operation>=17 && operation<=21) || operation==28)return file_operation(operation,payload,length,output);
    if(operation==22)return begin_hash(payload,length,output);
    if(operation>=23 && operation<=25)return hash_operation(operation,payload,length,output);
    if(operation==9 || operation==27) {
        wchar_t *destination=NULL;uint32_t first;
        if(length<6)return ERROR_INVALID_DATA;
        first=word((const unsigned char*)payload);
        if(!first || first>length-5)return ERROR_INVALID_DATA;
        result=utf16(payload+4,first,MAX_PATH_CHARS,&path);
        if(!result)result=utf16(payload+4+first,length-4-first,MAX_PATH_CHARS,&destination);
        if(!result && !MoveFileExW(path,destination,MOVEFILE_WRITE_THROUGH
            | (operation==9 ? MOVEFILE_REPLACE_EXISTING : 0)))result=last_error();
        free(path);free(destination);return result;
    }
    if((operation<4 || operation>10) && operation!=26)return ERROR_NOT_SUPPORTED;
    result=utf16(payload,length,MAX_PATH_CHARS,&path);
    if(result)return result;
    switch(operation) {
    case 4:
        if(!CreateDirectoryW(path,NULL)) {
            result=last_error();
            if(result==ERROR_ALREADY_EXISTS) {
                DWORD attributes=GetFileAttributesW(path);
                result=(attributes!=INVALID_FILE_ATTRIBUTES && attributes&FILE_ATTRIBUTE_DIRECTORY) ? ERROR_SUCCESS : ERROR_ALREADY_EXISTS;
            }
        }
        break;
    case 5: {
        WIN32_FILE_ATTRIBUTE_DATA info;char row[64];int written;
        if(!GetFileAttributesExW(path,GetFileExInfoStandard,&info)) {result=last_error();break;}
        written=sprintf_s(row,sizeof(row),"%c\t%08x%08x\t%08x%08x",info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY ? 'D' : 'F',
            (unsigned)info.nFileSizeHigh,(unsigned)info.nFileSizeLow,
            (unsigned)info.ftLastWriteTime.dwHighDateTime,(unsigned)info.ftLastWriteTime.dwLowDateTime);
        result=written>0 ? append(output,row,(uint32_t)written) : ERROR_INVALID_DATA;
        break;
    }
    case 6:result=list(path,output);break;
    case 7:if(!CreateDirectoryW(path,NULL))result=last_error();break;
    case 8:if(!RemoveDirectoryW(path))result=last_error();break;
    case 26:if(!DeleteFileW(path))result=last_error();break;
    case 10: {
        DWORD attributes=GetFileAttributesW(path);INT_PTR launched;
        if(attributes==INVALID_FILE_ATTRIBUTES) {result=last_error();break;}
        if(!(attributes&FILE_ATTRIBUTE_DIRECTORY)) {result=ERROR_DIRECTORY;break;}
        launched=(INT_PTR)ShellExecuteW(NULL,L"open",path,NULL,NULL,SW_SHOWNORMAL);
        if(launched<=32)result=launched>0 ? (DWORD)launched : ERROR_GEN_FAILURE;
        break;
    }
    default:result=ERROR_NOT_SUPPORTED;break;
    }
    free(path);return result;
}
static void close_channels(void) {
    if(request_pipe!=INVALID_HANDLE_VALUE) {CloseHandle(request_pipe);request_pipe=INVALID_HANDLE_VALUE;}
    if(response_pipe!=INVALID_HANDLE_VALUE) {CloseHandle(response_pipe);response_pipe=INVALID_HANDLE_VALUE;}
    close_files();
    close_hashes();
}
static int connected(HANDLE pipe) {
    DWORD peer=0,error;
    if(pipe==INVALID_HANDLE_VALUE)return 0;
    if(!ConnectNamedPipe(pipe,NULL)) {
        error=GetLastError();
        if(error!=ERROR_PIPE_CONNECTED)return 0;
    }
    return GetNamedPipeClientProcessId(pipe,&peer) && peer==GetCurrentProcessId();
}
static int respond(uint32_t nonce,DWORD status,Buffer *output) {
    unsigned char *reply;uint32_t size;DWORD written;BOOL ok;
    if(status)output->length=0;
    size=16+output->length;reply=(unsigned char*)malloc(size);
    if(!reply) {close_channels();return 0;}
    memcpy(reply,"ELR1",4);put_word(reply+4,nonce);put_word(reply+8,status);put_word(reply+12,output->length);
    if(output->length)memcpy(reply+16,output->data,output->length);
    /* A whole bounded response fits the preallocated pipe quota. Never wait
       for a future Lua read on this same thread. A failed/partial write closes
       the server handle, so the reader reaches EOF rather than deadlocking. */
    ok=WriteFile(response_pipe,reply,size,&written,NULL) && written==size;
    free(reply);
    if(!ok)close_channels();
    return ok!=FALSE;
}
__declspec(dllexport) int epic_lut_platform_open(void *unused) {
    wchar_t request[160],response[160];DWORD quota=MAX_PAYLOAD+16;
    (void)unused;
    if(InterlockedCompareExchange(&active,1,0))return 0;
    close_channels();close_workers();
    if(swprintf_s(request,160,L"\\\\.\\pipe\\EpicLutPlatform-%lu-request",GetCurrentProcessId())<0
        || swprintf_s(response,160,L"\\\\.\\pipe\\EpicLutPlatform-%lu-response",GetCurrentProcessId())<0)goto done;
    request_pipe=CreateNamedPipeW(request,PIPE_ACCESS_INBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_NOWAIT|PIPE_REJECT_REMOTE_CLIENTS,1,quota,quota,0,NULL);
    if(request_pipe==INVALID_HANDLE_VALUE)goto done;
    response_pipe=CreateNamedPipeW(response,PIPE_ACCESS_OUTBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_NOWAIT|PIPE_REJECT_REMOTE_CLIENTS,1,quota,quota,0,NULL);
    if(response_pipe==INVALID_HANDLE_VALUE)close_channels();
done:
    InterlockedExchange(&active,0);return 0;
}
__declspec(dllexport) int epic_lut_platform_close(void *unused) {
    (void)unused;
    if(InterlockedCompareExchange(&active,1,0))return 0;
    close_channels();close_workers();InterlockedExchange(&active,0);return 0;
}
__declspec(dllexport) int epic_lut_platform(void *unused) {
    unsigned char header[16];DWORD status=ERROR_INVALID_DATA,got,available=0;
    uint32_t nonce=0,length=0;char *payload=NULL;Buffer output={0};int broken=0;
    (void)unused;
    if(InterlockedCompareExchange(&active,1,0))return 0;
    if(!connected(request_pipe) || !connected(response_pipe)) {close_channels();goto finished;}
    if(!ReadFile(request_pipe,header,sizeof(header),&got,NULL) || got!=sizeof(header)) {broken=1;goto replied;}
    if(memcmp(header,"ELP1",4)) {broken=1;goto replied;}
    nonce=word(header+4);length=word(header+12);
    if(!nonce || length>MAX_PAYLOAD) {broken=1;goto replied;}
    if(length) {
        payload=(char*)malloc(length);
        if(!payload) {status=ERROR_NOT_ENOUGH_MEMORY;broken=1;goto replied;}
        if(!ReadFile(request_pipe,payload,length,&got,NULL) || got!=length) {broken=1;goto replied;}
    }
    if(!PeekNamedPipe(request_pipe,NULL,0,NULL,&available,NULL) || available) {broken=1;goto replied;}
    status=dispatch(word(header+8),payload,length,&output);
replied:
    if(respond(nonce,status,&output) && broken)close_channels();
finished:
    free(payload);free(output.data);InterlockedExchange(&active,0);return 0;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID reserved) {
    (void)instance;(void)reserved;if(reason==DLL_PROCESS_DETACH) {close_channels();close_workers();}return TRUE;
}
