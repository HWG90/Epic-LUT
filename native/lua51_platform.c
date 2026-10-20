/* Stock Lua5.1 platform bridge. Standard zero-result Lua C callback only;
 * lua_State is opaque and never read. No game API, process memory, hooks,
 * workers, child launch, input capture, executable patches or polling.
 * Protocol: per-PID unidirectional named pipes; ELP1/ELR1 + nonce u32
 * + operation/status u32 + payload length u32. No IPC files are created.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define MAX_PAYLOAD (1024u * 1024u)
#define MAX_ENTRIES 16384u
#define MAX_PATH_CHARS 32767u
static HANDLE request_pipe=INVALID_HANDLE_VALUE,response_pipe=INVALID_HANDLE_VALUE;
static volatile LONG active;
typedef struct { char *data; uint32_t length, capacity; } Buffer;
static uint32_t word(const unsigned char *p) {
    return p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static void put_word(unsigned char *p,uint32_t n) {
    p[0]=(unsigned char)n;p[1]=(unsigned char)(n>>8);p[2]=(unsigned char)(n>>16);p[3]=(unsigned char)(n>>24);
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
    if(operation==9) {
        wchar_t *destination=NULL;uint32_t first;
        if(length<6)return ERROR_INVALID_DATA;
        first=word((const unsigned char*)payload);
        if(!first || first>length-5)return ERROR_INVALID_DATA;
        result=utf16(payload+4,first,MAX_PATH_CHARS,&path);
        if(!result)result=utf16(payload+4+first,length-4-first,MAX_PATH_CHARS,&destination);
        if(!result && !MoveFileExW(path,destination,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))result=last_error();
        free(path);free(destination);return result;
    }
    if(operation<4 || operation>10)return ERROR_NOT_SUPPORTED;
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
    close_channels();
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
    close_channels();InterlockedExchange(&active,0);return 0;
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
    (void)instance;(void)reserved;if(reason==DLL_PROCESS_DETACH)close_channels();return TRUE;
}
