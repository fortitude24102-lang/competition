#include "bullet_demo.h"
#include "bullet_asset_catalog.h"
#include "network_assets.h"
#ifndef GPU_TEST_BACKEND
#include "bsp.h"
#endif
#ifndef NETWORK_LOCAL_IP
#define NETWORK_LOCAL_IP 0xc0a80002u
#endif
#ifndef NETWORK_PEER_IP
#define NETWORK_PEER_IP 0xc0a80003u
#endif

void bullet_init_local_assets(void) {
 volatile uint16_t *bg=(volatile uint16_t *)(uintptr_t)BULLET_LOCAL_BACKGROUND;
 volatile uint16_t *atlas=(volatile uint16_t *)(uintptr_t)BULLET_LOCAL_ATLAS;
 for(unsigned y=0;y<540;y++) for(unsigned x=0;x<960;x++) {
  uint16_t color=y<72?0:(uint16_t)((1u<<11)|((3u+y/90u)<<5)|(5u+y/135u));
  if(y>=72 && (!(x%60u) || !((y-72u)%60u))) color=0x1949;
  bg[y*960+x]=color;
 }
 static const uint16_t colors[3]={0x07ff,0xfc80,0xb81f};
 for(unsigned n=0;n<3;n++) for(int y=0;y<8;y++) for(int x=0;x<8;x++) {
  int dx=2*x-7,dy=2*y-7,r=dx*dx+dy*dy;
  atlas[n*64u+(unsigned)y*8u+(unsigned)x]=r>49?BULLET_COLOR_KEY:r<10?0xffff:colors[n];
 }
 for(int y=0;y<16;y++) for(int x=0;x<16;x++) {
  int dx=2*x-15,dy=2*y-15,d=(dx<0?-dx:dx)+(dy<0?-dy:dy);
  atlas[192u+(unsigned)y*16u+(unsigned)x]=d>16?BULLET_COLOR_KEY:d<8?0xffff:0x07e0;
 }
 for(int y=0;y<12;y++) for(int x=0;x<12;x++) {
  int dx=2*x-11,dy=2*y-11,d=(dx<0?-dx:dx)+(dy<0?-dy:dy);
  atlas[448u+(unsigned)y*12u+(unsigned)x]=(uint16_t)((22-d)*2<<5);
 }
}

int bullet_load_network_assets(uintptr_t base,uint32_t session) {
 int e=network_configure(base,NETWORK_LOCAL_IP,NETWORK_PEER_IP,8080,8080);
 if(e) return e;
#ifdef GPU_TEST_BACKEND
 const uint32_t hz=100000000u;
#else
 const uint32_t hz=BSP_CLINT_HZ;
#endif
 static const struct {uint32_t id,addr,bytes,crc;} files[]={
  {101,BULLET_BACKGROUND_ADDR,GPU_FRAME_BYTES,BULLET_BACKGROUND_CRC},
  {102,BULLET_ATLAS_ADDR,BULLET_ATLAS_BYTES,BULLET_ATLAS_CRC}
 };
 for(unsigned i=0;i<2;i++) {
  network_asset_report r;
  e=network_asset_fetch(base,hz,session,files[i].id,files[i].addr,files[i].bytes,files[i].crc,&r);
#ifndef GPU_TEST_BACKEND
  bsp_printf("BULLET_ASSET,id=%d,bytes=%d,retries=%d,result=%d\r\n",files[i].id,r.committed_bytes,r.retries,e);
#endif
  if(e) return e;
 }
 return 0;
}
int bullet_prepare_assets(uintptr_t base,uint32_t session) {
 int e=bullet_load_network_assets(base,session);
 if(e) bullet_init_local_assets();
 return e;
}
