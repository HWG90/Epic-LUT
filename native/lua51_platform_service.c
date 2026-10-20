/* External OS-only host for the shared platform operations. No game memory or
 * Lua ABI access. Both client pipes must belong to the retained client process.
 * Idle work is one overlapped ReadFile blocked on data/client-process exit. */
#define EPIC_PLATFORM_EXTERNAL
#include "lua51_platform.c"

#define STARTUP_TIMEOUT 8000u
#define TRANSFER_TIMEOUT 3000u
static wchar_t instance_token[65];
static HANDLE transfer_event;
static HANDLE main_thread,dispatch_finished;
static volatile LONG dispatch_expired;
#ifdef EPIC_PLATFORM_TEST_BLOCK
static int test_stall_close;
#endif
static VOID CALLBACK expire_dispatch(PVOID unused,BOOLEAN fired) {
    (void)unused;(void)fired;
    InterlockedExchange(&dispatch_expired,1);
    CancelSynchronousIo(main_thread);
    /* Most filesystem IO cancels normally. A native operation that cannot be
       canceled gets only this bounded grace period; only this helper exits. */
    if(WaitForSingleObject(dispatch_finished,500)!=WAIT_OBJECT_0)
        TerminateProcess(GetCurrentProcess(),ERROR_TIMEOUT);
}
static DWORD bounded_dispatch(uint32_t operation,const char *payload,uint32_t length,Buffer *output) {
    HANDLE timer=NULL;DWORD result;
    ResetEvent(dispatch_finished);InterlockedExchange(&dispatch_expired,0);
    if(!CreateTimerQueueTimer(&timer,NULL,expire_dispatch,NULL,TRANSFER_TIMEOUT,0,WT_EXECUTEONLYONCE))return last_error();
#ifdef EPIC_PLATFORM_TEST_BLOCK
    if(operation==248) {
        if(length!=1 || (unsigned char)payload[0]>1)result=ERROR_INVALID_DATA;
        else {platform_test_refuse_detach=payload[0];result=ERROR_SUCCESS;}
    }
    else if(operation==252) {test_stall_close=1;result=ERROR_SUCCESS;}
    else if(operation==254) {platform_test_stall_after_create=1;result=dispatch(12,payload,length,output);}
    else if(operation==249 || operation==250 || operation==251) {
        if(operation==250)result=dispatch(12,payload,length,output);
        else if(operation==251)result=dispatch(4,payload,length,output);
        else result=ERROR_SUCCESS;
        if(!result)Sleep(INFINITE);
    } else
#endif
    if(operation==30) {
        result=length ? ERROR_INVALID_DATA : ERROR_SUCCESS;
        if(!result) {
#ifdef EPIC_PLATFORM_TEST_BLOCK
            if(test_stall_close)Sleep(INFINITE);
#endif
            close_files();close_hashes();close_workers();
        }
    } else result=dispatch(operation,payload,length,output);
    SetEvent(dispatch_finished);
    DeleteTimerQueueTimer(NULL,timer,INVALID_HANDLE_VALUE);
    if(InterlockedCompareExchange(&dispatch_expired,0,0))return ERROR_TIMEOUT;
    return result;
}
static DWORD publish_worker(Buffer *output,int delivered) {
    DWORD result=ERROR_INVALID_DATA;
    {
        unsigned i;uint32_t token=output->length==8 ? word((unsigned char*)output->data) : 0;
        /* Receipt delivery acknowledges ownership; it does not detach it.
           Kill-on-close remains until the client's explicit worker.close. */
        for(i=0;i<8;i++)if(workers[i].job && workers[i].token==token) {
            result=delivered ? ERROR_SUCCESS : ERROR_OPERATION_ABORTED;
            if(result) {
                TerminateJobObject(workers[i].job,1);
                CloseHandle(workers[i].process);CloseHandle(workers[i].job);memset(&workers[i],0,sizeof(workers[i]));
            }
            break;
        }
    }
    return result;
}

static DWORD wait_io(HANDLE pipe,OVERLAPPED *overlapped,DWORD timeout,DWORD *done) {
    HANDLE events[2]={overlapped->hEvent,authenticated_client_process};
    DWORD outcome=WaitForMultipleObjects(2,events,FALSE,timeout);
    if(outcome!=WAIT_OBJECT_0) {
        CancelIoEx(pipe,overlapped);
        /* Cancellation completion owns the OVERLAPPED storage until signaled. */
        WaitForSingleObject(overlapped->hEvent,INFINITE);
        return outcome==WAIT_TIMEOUT ? ERROR_TIMEOUT : ERROR_PROCESS_ABORTED;
    }
    return GetOverlappedResult(pipe,overlapped,done,FALSE) ? ERROR_SUCCESS : last_error();
}
static DWORD transfer(HANDLE pipe,void *bytes,DWORD count,int writing,int idle) {
    DWORD total=0,done,result;ULONGLONG deadline=GetTickCount64()+TRANSFER_TIMEOUT;
    while(total<count) {
        OVERLAPPED overlapped={0};BOOL ok;DWORD timeout=TRANSFER_TIMEOUT;
        overlapped.hEvent=transfer_event;ResetEvent(transfer_event);
        if(idle && !total)timeout=INFINITE;
        else {
            ULONGLONG now=GetTickCount64();
            if(now>=deadline)return ERROR_TIMEOUT;
            timeout=(DWORD)(deadline-now);
        }
        ok=writing ? WriteFile(pipe,(char*)bytes+total,count-total,&done,&overlapped)
                   : ReadFile(pipe,(char*)bytes+total,count-total,&done,&overlapped);
        if(!ok) {
            result=last_error();
            if(result!=ERROR_IO_PENDING)return result;
            result=wait_io(pipe,&overlapped,timeout,&done);if(result)return result;
        }
        if(!done)return ERROR_BROKEN_PIPE;
        if(idle && !total)deadline=GetTickCount64()+TRANSFER_TIMEOUT;
        total+=done;
    }
    return ERROR_SUCCESS;
}
static DWORD connect_client(HANDLE pipe) {
    OVERLAPPED overlapped={0};DWORD done=0,peer=0,result=ERROR_SUCCESS;
    overlapped.hEvent=transfer_event;ResetEvent(transfer_event);
    if(!ConnectNamedPipe(pipe,&overlapped)) {
        result=last_error();
        if(result==ERROR_IO_PENDING)result=wait_io(pipe,&overlapped,STARTUP_TIMEOUT,&done);
        else if(result==ERROR_PIPE_CONNECTED)result=ERROR_SUCCESS;
    }
    if(!result && (!GetNamedPipeClientProcessId(pipe,&peer) || peer!=authenticated_client_pid))
        result=ERROR_ACCESS_DENIED;
    return result;
}
static DWORD identify_client(DWORD pid,const wchar_t *expected) {
    DWORD count=MAX_PATH_CHARS;
    authenticated_client_process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid);
    if(!authenticated_client_process)return last_error();
    authenticated_client_pid=pid;
    if(WaitForSingleObject(authenticated_client_process,0)!=WAIT_TIMEOUT)return ERROR_PROCESS_ABORTED;
    if(!QueryFullProcessImageNameW(authenticated_client_process,0,authenticated_client_image,&count))return last_error();
    if(expected && _wcsicmp(expected,authenticated_client_image))return ERROR_ACCESS_DENIED;
    return ERROR_SUCCESS;
}
static int valid_token(const wchar_t *text) {
    unsigned i;if(wcslen(text)!=64)return 0;
    for(i=0;i<64;i++)if(!((text[i]>=L'0' && text[i]<=L'9') || (text[i]>=L'a' && text[i]<=L'f')))return 0;
    return 1;
}
static DWORD decode_hex(const wchar_t *hex,wchar_t **value) {
    size_t count=wcslen(hex),i;char *bytes;DWORD result;
    if(!count || count%2 || count>MAX_PATH_CHARS*8)return ERROR_INVALID_DATA;
    bytes=(char*)malloc(count/2);if(!bytes)return ERROR_NOT_ENOUGH_MEMORY;
    for(i=0;i<count;i+=2) {
        unsigned a,b;
        if(swscanf_s(hex+i,L"%1x%1x",&a,&b)!=2) {free(bytes);return ERROR_INVALID_DATA;}
        bytes[i/2]=(char)(a*16+b);
    }
    result=utf16(bytes,(uint32_t)(count/2),MAX_PATH_CHARS,value);free(bytes);return result;
}
static DWORD send_response(uint32_t nonce,DWORD status,Buffer *output) {
    unsigned char header[16];DWORD result;
    if(status)output->length=0;
    memcpy(header,"ELR1",4);put_word(header+4,nonce);put_word(header+8,status);put_word(header+12,output->length);
    result=transfer(response_pipe,header,sizeof(header),1,0);
    if(!result && output->length)result=transfer(response_pipe,output->data,output->length,1,0);
    return result;
}
static DWORD serve(void) {
    int authenticated=0;uint32_t previous_nonce=0;
    for(;;) {
        unsigned char header[16];char *payload=NULL;Buffer output={0};DWORD result,status;
        uint32_t nonce,length,operation;int closing=0;
        result=transfer(request_pipe,header,sizeof(header),0,1);if(result)return result;
        if(memcmp(header,"ELP1",4))return ERROR_INVALID_DATA;
        nonce=word(header+4);operation=word(header+8);length=word(header+12);
        if(!nonce || nonce==previous_nonce || length>MAX_PAYLOAD)return ERROR_INVALID_DATA;
        previous_nonce=nonce;
        if(length) {
            payload=(char*)malloc(length);if(!payload)return ERROR_NOT_ENOUGH_MEMORY;
            result=transfer(request_pipe,payload,length,0,0);
            if(result) {free(payload);return result;}
        }
        if(!authenticated) {
            char token[65];unsigned i;
            for(i=0;i<65;i++)token[i]=(char)instance_token[i];
            status=operation==29 && length==72 && !memcmp(payload,token,64)
                && word((unsigned char*)payload+64)==authenticated_client_pid
                && word((unsigned char*)payload+68)==GetCurrentProcessId() ? ERROR_SUCCESS : ERROR_ACCESS_DENIED;
            if(!status) {
                unsigned char receipt[8];put_word(receipt,authenticated_client_pid);put_word(receipt+4,GetCurrentProcessId());
                status=append(&output,receipt,8);if(!status)status=executable_path(&output);
                authenticated=!status;
            }
        } else if(operation==29)status=ERROR_ACCESS_DENIED;
#ifdef EPIC_PLATFORM_TEST_BLOCK
        else if(operation==253) {status=bounded_dispatch(12,payload,length,&output);Sleep(1500);}
#endif
        else if(operation==30) {
            status=bounded_dispatch(operation,payload,length,&output);
            if(!status)closing=1;
        } else status=bounded_dispatch(operation,payload,length,&output);
        if(status==ERROR_TIMEOUT) {free(payload);free(output.data);return status;}
        result=send_response(nonce,status,&output);
        if(!status && (operation==12
#ifdef EPIC_PLATFORM_TEST_BLOCK
            || operation==253
#endif
            )) {
            DWORD published=publish_worker(&output,!result);
            if(!result)result=published;
        }
        free(payload);free(output.data);
        if(result)return result;
        if(!authenticated)return ERROR_ACCESS_DENIED;
        if(closing)return ERROR_SUCCESS;
    }
}
int wmain(int argc,wchar_t **argv) {
    DWORD pid,result=ERROR_INVALID_PARAMETER;wchar_t *end,*expected=NULL;
    wchar_t request[200],response[200],ready_name[160];HANDLE ready=NULL;
    if(argc==3 && !wcscmp(argv[1],L"--describe")) {
        Buffer image={0};size_t i;pid=wcstoul(argv[2],&end,10);
        if(*end || !pid)return ERROR_INVALID_PARAMETER;
        result=identify_client(pid,NULL);
        if(!result)result=executable_path(&image);
        if(!result) {for(i=0;i<image.length;i++)printf("%02x",(unsigned char)image.data[i]);printf("\n");fflush(stdout);}
        free(image.data);if(authenticated_client_process)CloseHandle(authenticated_client_process);return (int)result;
    }
    if(argc!=7 || wcscmp(argv[1],L"--client") || wcscmp(argv[3],L"--token") || wcscmp(argv[5],L"--image"))return (int)result;
    pid=wcstoul(argv[2],&end,10);if(*end || !pid || !valid_token(argv[4]))return (int)result;
    result=decode_hex(argv[6],&expected);if(result)return (int)result;
    result=identify_client(pid,expected);free(expected);if(result)goto finished;
    wcscpy_s(instance_token,65,argv[4]);
    if(swprintf_s(request,200,L"\\\\.\\pipe\\EpicLutExternal-%lu-%ls-request",pid,instance_token)<0
        || swprintf_s(response,200,L"\\\\.\\pipe\\EpicLutExternal-%lu-%ls-response",pid,instance_token)<0
        || swprintf_s(ready_name,160,L"Local\\EpicLutExternal-%ls",instance_token)<0) {result=ERROR_INVALID_DATA;goto finished;}
    transfer_event=CreateEventW(NULL,TRUE,FALSE,NULL);if(!transfer_event) {result=last_error();goto finished;}
    dispatch_finished=CreateEventW(NULL,TRUE,FALSE,NULL);
    main_thread=OpenThread(THREAD_TERMINATE|SYNCHRONIZE,FALSE,GetCurrentThreadId());
    if(!dispatch_finished || !main_thread) {result=last_error();goto finished;}
    request_pipe=CreateNamedPipeW(request,PIPE_ACCESS_INBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE|FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,MAX_PAYLOAD+16,MAX_PAYLOAD+16,0,NULL);
    if(request_pipe==INVALID_HANDLE_VALUE) {result=last_error();goto finished;}
    response_pipe=CreateNamedPipeW(response,PIPE_ACCESS_OUTBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE|FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,MAX_PAYLOAD+16,MAX_PAYLOAD+16,0,NULL);
    if(response_pipe==INVALID_HANDLE_VALUE) {result=last_error();goto finished;}
    ready=OpenEventW(EVENT_MODIFY_STATE,FALSE,ready_name);
    if(!ready || !SetEvent(ready)) {result=last_error();goto finished;}
    result=connect_client(request_pipe);if(result)goto finished;
    result=connect_client(response_pipe);if(result)goto finished;
    result=serve();
finished:
    close_channels();close_workers();
    if(ready)CloseHandle(ready);if(transfer_event)CloseHandle(transfer_event);
    if(dispatch_finished)CloseHandle(dispatch_finished);if(main_thread)CloseHandle(main_thread);
    if(authenticated_client_process)CloseHandle(authenticated_client_process);
    return (int)result;
}
