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

static void aircraft(volatile uint16_t *atlas,uint16_t color) {
 for(int y=0;y<16;y++) for(int x=0;x<16;x++) {
  int yy=y;
  int dx=2*x-15; if(dx<0) dx=-dx;
  int body=dx<=3 && yy>=2 && yy<=12;
  int wing=yy>=5 && yy<=12 && dx<=(yy-4)*2;
  int engine=yy>=13 && yy<=15 && dx<=3;
  atlas[(unsigned)y*16u+(unsigned)x]=body?0xffff:wing?(yy>=11?0x0430:color):engine?0xfc80:BULLET_COLOR_KEY;
 }
}

static void enemy_aircraft(volatile uint16_t *atlas,uint16_t color) {
 for(int y=0;y<16;y++) for(int x=0;x<16;x++) {
  int dx=2*x-15; if(dx<0) dx=-dx;
  int pods=dx>=7 && dx<=9 && y>=1 && y<=11;
  int body=dx<=3 && y>=3 && y<=12;
  int wing=((y==5 || y==9) && dx<=11) || y==6 || y==7 || (y==8 && dx<=13);
  int nose=dx<=1 && (y==13 || y==14);
  atlas[(unsigned)y*16u+(unsigned)x]=nose || (body && y>=10)?0xffff:
   pods && y<=2?0xfc80:pods?0x8410:wing && y==8?0x0430:body || wing?color:BULLET_COLOR_KEY;
 }
}

void bullet_init_local_assets(void) {
 volatile uint16_t *bg=(volatile uint16_t *)(uintptr_t)BULLET_LOCAL_BACKGROUND;
 volatile uint16_t *atlas=(volatile uint16_t *)(uintptr_t)BULLET_LOCAL_ATLAS;
 for(unsigned y=0;y<540;y++) for(unsigned x=0;x<960;x++) {
  uint16_t color=0;
  if(y>=72) {
   unsigned edge=x;
   if(959u-x<edge) edge=959u-x;
   if(y-72u<edge) edge=y-72u;
   if(539u-y<edge) edge=539u-y;
   color=(uint16_t)((1u<<11)|((3u+y/90u)<<5)|(7u+y/135u));
   if(!(x%60u) || !((y-72u)%60u)) color=0x1107;
   if(!(x%120u) && !((y-72u)%120u)) color=0x29ad;
   if(((x*73u+y*151u)^(x*y*3u))%4093u<3u) color=0x4a71;
   if(edge==8u || edge==9u) color=0x1a2c;
   if(edge>=12u && edge<=14u && (x/24u+y/24u)%3u==0) color=0x21af;
  }
  bg[y*960+x]=color;
 }
 static const uint16_t colors[BULLET_SHAPE_COUNT]={0x07ff,0xfc80,0xb81f,0x07e0,0xffe0,0xf800};
 for(unsigned n=0;n<BULLET_SHAPE_COUNT;n++) for(int y=0;y<8;y++) for(int x=0;x<8;x++) {
  int dx=2*x-7,dy=2*y-7,r=dx*dx+dy*dy;
  atlas[n*64u+(unsigned)y*8u+(unsigned)x]=!bullet_shape_opaque(n,(unsigned)x,(unsigned)y)?BULLET_COLOR_KEY:r<10?0xffff:r>=34?0x4208:colors[n];
 }
 aircraft(atlas+BULLET_PLAYER_OFFSET/2u,0x07ff);
 for(int y=0;y<12;y++) for(int x=0;x<12;x++) {
  int dx=2*x-11,dy=2*y-11,d=(dx<0?-dx:dx)+(dy<0?-dy:dy);
  atlas[BULLET_GLOW_OFFSET/2u+(unsigned)y*12u+(unsigned)x]=(uint16_t)((22-d)*2<<5);
 }
 static const uint16_t enemies[3]={0xfc80,0xb81f,0x07e0};
 for(unsigned n=0;n<3;n++) enemy_aircraft(atlas+BULLET_EMITTER_OFFSET/2u+n*256u,enemies[n]);
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
