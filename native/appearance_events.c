#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <string.h>
/* Build 6AB3B43F, same bounded actor chain as vendor/avatar.lua.
   Supported PluginApi Unit events only: no hooks or idle update callback. */
static void *api[256];
static uintptr_t game;
static DWORD thread;
static int running;
static void (*notify)(void);
static uint32_t prior[37];
static uint64_t events, checks, changes, faults;
static uintptr_t ptr(uintptr_t a){return *(uintptr_t*)a;}
static uint32_t u32(uintptr_t a){return *(uint32_t*)a;}
static int map(uintptr_t a,uint32_t key,uint32_t limit,uint32_t *out){
 uint32_t cap=u32(a+8),empty=u32(a+12),mult=u32(a+16);
 if(!cap||cap>limit||(cap&(cap-1))||key==empty||key==0xffffffff)return 0;
 uintptr_t data=ptr(a);if(data<65536)return 0;
 for(uint32_t n=0;n<cap&&n<128;n++){
  uintptr_t row=data+(((key*mult+n)&(cap-1))*8ull);
  uint32_t found=u32(row);if(found==key){*out=u32(row+4);return *out!=0xffffffff;}if(found==empty)return 0;
 }return 0;
}
static int sample(uint32_t out[37]){
 uintptr_t players=ptr(game+0x3326468),owner=ptr(game+0x346bf98);
 if(players<65536||owner<65536)return 0;
 uint32_t count=u32(players+0x84),player=0,ix;
 if(!count||count>8)return 0;
 for(uint32_t i=0;i<count;i++){
  uintptr_t record=ptr(players+0xe8+i*8ull);
  if(record<65536)return 0;
  if(*(unsigned char*)(record+20)&1){if(player)return 0;player=u32(record+8);}
 }
 if(!player||!map(players+0xd0,player,64,&ix)||ix>=count)return 0;
 uint32_t ref=u32(players+0x3a8+ix*32ull),entity;
 if(!ref||ref==0x7fff||ref==0xffffffff||!map(owner+0xf22ec8,ref,1048576,&entity)||entity>=1048576)return 0;
 uintptr_t record=owner+0xf32f18+entity*24ull;
 if(*(uint64_t*)record!=0x4d1c334d294dfa97ull||!(*(unsigned char*)(record+20)&1))return 0;
 uint32_t avatar=u32(record+8);
 uintptr_t avatars=ptr(game+0x3326d20),custom=ptr(game+0x33264f8);
 if(avatars<65536||custom<65536||!map(avatars+248,avatar,65536,&ix)||ix>=u32(avatars+0x6c)||ix>=4096)return 0;
 out[0]=player;out[1]=ref;out[2]=avatar;
 memcpy(out+3,(void*)(avatars+5532272+ix*440ull+220),120);
 if(!map(custom+2352,player,65536,&ix)||ix>=4096)return 0;
 memcpy(out+33,(void*)(custom+2412+ix*68ull),16);
 return 1;
}
static void snapshot(uint32_t out[37]){
 memset(out,0,148);
 __try{if(!sample(out))memset(out,0,148);}
 __except(EXCEPTION_EXECUTE_HANDLER){memset(out,0,148);faults++;}
}
static void deferred(float dt){
 (void)dt;api[12]=0;if(!running||GetCurrentThreadId()!=thread)return;
 uint32_t now[37];checks++;snapshot(now);
 if(memcmp(now,prior,148)){memcpy(prior,now,148);changes++;if(notify)notify();}
}
static void units(void *world,void **list,unsigned count){
 (void)world;(void)list;if(!count||!running||GetCurrentThreadId()!=thread)return;
 events++;api[12]=(void*)deferred;
}
static const char *name(void){return "Epic LUT Appearance Events V1";}
__declspec(dllexport) void *get_plugin_api(unsigned id){
 if(id)return 0;api[0]=(void*)name;api[23]=(void*)units;api[24]=(void*)units;return api;
}
__declspec(dllexport) int epic_appearance_start(uintptr_t g){
 api[12]=0;game=g;thread=GetCurrentThreadId();snapshot(prior);running=1;return 1;
}
__declspec(dllexport) void epic_appearance_subscribe(void (*fn)(void)){notify=fn;}
__declspec(dllexport) void epic_appearance_stop(void){running=0;api[12]=0;notify=0;}
__declspec(dllexport) uint64_t epic_appearance_stat(unsigned f){return f==0?events:f==1?checks:f==2?changes:f==3?faults:f==4?running:f==5?(api[12]!=0):0;}
