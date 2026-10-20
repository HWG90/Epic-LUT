#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <string.h>
/* Target 6AB3B43F. Engine PluginApi; no process hooks. */
static void *api[256];
static uintptr_t game, owner, inv;
static uintptr_t players;
static uint32_t player_id, player_index;
static uint32_t avatar, avatar_ref, inventory_index;
static DWORD thread;
static int armed;
static uint64_t signature[3][2], events, checks, changes, faults;
static unsigned changed;
static void (*notify)(unsigned);
static uintptr_t ptr(uintptr_t a){return *(uintptr_t*)a;}
static uint32_t u32(uintptr_t a){return *(uint32_t*)a;}
static int map(uintptr_t a,uint32_t key,uint32_t limit,uint32_t *out){
 uint32_t cap=u32(a+8),empty=u32(a+12),mult=u32(a+16);
 if(!cap||cap>limit||(cap&(cap-1))||key==empty||key==0xffffffff)return 0;
 uintptr_t data=ptr(a); if(data<65536)return 0;
 for(uint32_t n=0;n<cap&&n<128;n++){
  uintptr_t row=data+(((key*mult+n)&(cap-1))*8ull);
  uint32_t found=u32(row);if(found==key){*out=u32(row+4);return *out!=0xffffffff;}if(found==empty)return 0;
 }return 0;
}
static int sample(uint64_t out[3][2]){
 if(ptr(game+0x346bf98)!=owner||ptr(game+0x3326738)!=inv)return 0;
 if(players){
  uint32_t pi,pc=u32(players+0x84);
  if(ptr(game+0x3326468)!=players||!pc||pc>8||player_index>=pc||
     !map(players+0xd0,player_id,64,&pi)||pi!=player_index||
     u32(players+0x3a8+player_index*32ull)!=avatar_ref)return 0;
 }
 uint32_t count=u32(inv+0x14),ix;
 if(!count||count>4096||!map(inv+0x28,avatar,65536,&ix)||ix!=inventory_index||ix>=count)return 0;
 uintptr_t a=ptr(ptr(inv+0x40)+ix*8ull);
 if(a<65536||*(uint64_t*)a!=0x4d1c334d294dfa97ull||u32(a+8)!=avatar||u32(a+16)!=avatar_ref||!(*(unsigned char*)(a+20)&1))return 0;
 uintptr_t data=ptr(inv+0x50)+ix*48ull;
 for(unsigned s=0;s<3;s++){
  uint32_t entity=u32(data+s*4);out[s][0]=entity;out[s][1]=0;
  if(!entity||entity==0xffffffff)continue;
  if(!map(owner+0xf1aeb0,entity,1048576,&ix)||ix>=1048576)continue;
  uintptr_t r=owner+0xf32f18+ix*24ull;
  if(u32(r+8)!=entity||!(*(unsigned char*)(r+20)&1))return 0;
  out[s][0]|=(uint64_t)u32(r+12)<<32;out[s][1]=*(uint64_t*)r;
 }return 1;
}
static void deferred(float dt){
 (void)dt;api[12]=0;if(!notify||GetCurrentThreadId()!=thread)return;
 /* A vanished actor invalidates the receipt, not the subscription. A later
    engine unit-event burst asks Lua for a fresh local actor receipt once. */
 if(!armed){changed|=15;changes++;notify(15);return;}
 uint64_t now[3][2];checks++;
 __try{
  if(!sample(now)){armed=0;faults++;changed|=15;changes++;notify(15);return;}
  unsigned mask=0;
  for(unsigned s=0;s<3;s++)if(memcmp(now[s],signature[s],sizeof now[s]))mask|=1u<<s;
  memcpy(signature,now,sizeof signature);
  if(mask){changed|=mask;changes++;if(notify)notify(mask);}
 }__except(EXCEPTION_EXECUTE_HANDLER){armed=0;faults++;changed|=15;changes++;notify(15);}
}
static void units(void *world,void **list,unsigned count){
 (void)world;(void)list;
 if(!count||!notify||GetCurrentThreadId()!=thread)return;
 events++;api[12]=deferred;
}
static const char *name(void){return "Epic LUT Event Watch V4";}
__declspec(dllexport) void *get_plugin_api(unsigned id){
 if(id)return 0;api[0]=name;api[23]=units;api[24]=units;return api;
}
__declspec(dllexport) int epic_watch(uintptr_t g,uintptr_t o,uintptr_t i,uint32_t a,uint32_t ar,uint32_t ix){
 api[12]=0;armed=0;players=0;game=g;owner=o;inv=i;avatar=a;avatar_ref=ar;inventory_index=ix;thread=GetCurrentThreadId();
 __try{armed=sample(signature);}__except(EXCEPTION_EXECUTE_HANDLER){faults++;}
 return armed;
}
__declspec(dllexport) int epic_watch_actor(uintptr_t g,uintptr_t o,uintptr_t i,uint32_t a,uint32_t ar,uint32_t ix,uintptr_t p,uint32_t id,uint32_t pi){
 epic_watch(g,o,i,a,ar,ix);armed=0;players=p;player_id=id;player_index=pi;
 __try{armed=players>=65536&&sample(signature);}__except(EXCEPTION_EXECUTE_HANDLER){faults++;}
 return armed;
}
__declspec(dllexport) unsigned epic_take(void){unsigned value=changed;changed=0;return value;}
__declspec(dllexport) uint64_t epic_stat(unsigned field){
 return field==0?events:field==1?checks:field==2?changes:field==3?faults:field==4?armed:field==5?(api[12]!=0):0;
}
__declspec(dllexport) void epic_subscribe(void (*fn)(unsigned)){notify=fn;}
__declspec(dllexport) void epic_stop(void){armed=0;api[12]=0;changed=0;notify=0;}
