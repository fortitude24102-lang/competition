#define _GNU_SOURCE
#include "bullet_demo.h"
#include "bullet_asset_catalog.h"
#include "perf_demo.h"
#include "hud.h"
#include "network_assets.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

static bullet_state state;
static bullet_stream scene;
static hud_command_stream hud;
static uint16_t oracle[960*540];
static gpu_command submitted[BULLET_MAX_COMMANDS];
static unsigned submit_count,wait_count,fetch_count;
static int fail_fetch;
int gpu_submit(gpu_device *d,const gpu_command *c,uint32_t polls,uint16_t *tag) {
 assert(d && polls && submit_count<BULLET_MAX_COMMANDS);
 submitted[submit_count++]=*c; *tag=(uint16_t)submit_count; return 0;
}
int gpu_wait_tag(gpu_device *d,uint16_t tag,uint32_t polls) {
 assert(d && polls && tag==submit_count); ++wait_count; return 0;
}
int gpu_fill_async(gpu_device *d,uint32_t dst,uint32_t stride,uint16_t w,uint16_t h,uint16_t color,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_FILL,.dst_addr=dst,.dst_stride=stride,.width_pixels=w,.height_pixels=h,.color=color};
 return gpu_submit(d,&c,1,tag);
}
int network_configure(uintptr_t base,uint32_t local,uint32_t peer,uint16_t lp,uint16_t pp) {
 assert(base==GPU_APB_BASE && local && peer && lp==8080 && pp==8080); return 0;
}
int network_asset_fetch(uintptr_t base,uint32_t hz,uint32_t session,uint32_t id,
 uint32_t dst,uint32_t bytes,uint32_t crc,network_asset_report *r) {
 assert(base==GPU_APB_BASE && hz==100000000 && session==7);
 assert(id==101+fetch_count);
 assert(dst==(id==101?BULLET_BACKGROUND_ADDR:BULLET_ATLAS_ADDR));
 assert(bytes==(id==101?GPU_FRAME_BYTES:BULLET_ATLAS_BYTES));
 assert(crc==(id==101?BULLET_BACKGROUND_CRC:BULLET_ATLAS_CRC));
 ++fetch_count; *r=(network_asset_report){0};
 if(fail_fetch==(int)id) {
  memset((void *)(uintptr_t)BULLET_BACKGROUND_ADDR,0x55,GPU_FRAME_BYTES);
  memset((void *)(uintptr_t)BULLET_ATLAS_ADDR,0x55,BULLET_ATLAS_BYTES);
  return NETWORK_TIMEOUT; /* Model an abort that leaves writes pending. */
 }
 memcpy((void *)(uintptr_t)dst,(void *)(uintptr_t)(id==101?BULLET_LOCAL_BACKGROUND:BULLET_LOCAL_ATLAS),bytes);
 return 0;
}
static void compare_file(const char *path,uint32_t address,unsigned bytes) {
 FILE *f=fopen(path,"rb"); assert(f);
 for(unsigned i=0;i<bytes;i++) assert(fgetc(f)==((const unsigned char *)(uintptr_t)address)[i]);
 assert(fgetc(f)==EOF); assert(!fclose(f));
}
/* Independent scalar oracle, also emits the actual scene's pixel-pipe inputs.
 * Background is read before each operation, so overlaps and skipped key writes
 * affect subsequent alpha inputs. No golden_renderer/rgb565 helpers are used. */
static unsigned reference(const gpu_command *commands,unsigned count,FILE *vectors) {
 unsigned total=0;
 for(unsigned n=0;n<count;n++) {
  const gpu_command *c=&commands[n];
  unsigned off=(c->dst_addr-GPU_FRAMEBUFFER_A)/2;
  const uint16_t *src=(const uint16_t *)(uintptr_t)c->src_addr;
  for(unsigned y=0;y<c->height_pixels;y++) for(unsigned x=0;x<c->width_pixels;x++) {
   uint16_t *p=&oracle[off+y*960+x],bg=*p;
   uint16_t fg=c->op==GPU_OP_FILL?0:src[y*(c->src_stride/2)+x],pixel=fg;
   unsigned write=c->op!=GPU_OP_COLOR_KEY || fg!=c->color_key;
   if(c->op==GPU_OP_FILL) pixel=c->color;
   if(c->op==GPU_OP_ALPHA) {
    unsigned a=c->alpha,b=255-a;
    unsigned r=(((fg>>11)&31)*a+((bg>>11)&31)*b+127)/255;
    unsigned g=(((fg>>5)&63)*a+((bg>>5)&63)*b+127)/255;
    unsigned bl=((fg&31)*a+(bg&31)*b+127)/255;
    pixel=(uint16_t)((r<<11)|(g<<5)|bl);
   }
   if(vectors) assert(fprintf(vectors,"%x %04x %04x %04x %04x %02x %04x %x\n",
    c->op,fg,bg,c->color,c->color_key,c->alpha,pixel,write)>0);
   if(write) *p=pixel;
   ++total;
  }
 }
 return total;
}
int main(void) {
 const size_t bytes=0x00d00000u;
 void *memory=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,bytes,PROT_READ|PROT_WRITE,
  MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
 assert(memory==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 bullet_init_local_assets();
 compare_file("sw/efinix_gpu/assets/bullet/background.rgb565",BULLET_LOCAL_BACKGROUND,GPU_FRAME_BYTES);
 compare_file("sw/efinix_gpu/assets/bullet/atlas.rgb565",BULLET_LOCAL_ATLAS,BULLET_ATLAS_BYTES);
 assert(golden_crc32((void *)(uintptr_t)BULLET_LOCAL_BACKGROUND,GPU_FRAME_BYTES)==BULLET_BACKGROUND_CRC);
 assert(golden_crc32((void *)(uintptr_t)BULLET_LOCAL_ATLAS,BULLET_ATLAS_BYTES)==BULLET_ATLAS_CRC);
 assert(!bullet_prepare_assets(GPU_APB_BASE,7) && fetch_count==2);
 for(int failed=101;failed<=102;failed++) {
  fetch_count=0; fail_fetch=failed;
  memset((void *)(uintptr_t)BULLET_LOCAL_BACKGROUND,0xaa,GPU_FRAME_BYTES);
  memset((void *)(uintptr_t)BULLET_LOCAL_ATLAS,0xaa,BULLET_ATLAS_BYTES);
  assert(bullet_prepare_assets(GPU_APB_BASE,7)==NETWORK_TIMEOUT && fetch_count==(unsigned)(failed-100));
  /* Late DMA writes after return cannot corrupt the disjoint fallback. */
  memset((void *)(uintptr_t)BULLET_BACKGROUND_ADDR,0xee,GPU_FRAME_BYTES);
  memset((void *)(uintptr_t)BULLET_ATLAS_ADDR,0xee,BULLET_ATLAS_BYTES);
  compare_file("sw/efinix_gpu/assets/bullet/background.rgb565",BULLET_LOCAL_BACKGROUND,GPU_FRAME_BYTES);
  compare_file("sw/efinix_gpu/assets/bullet/atlas.rgb565",BULLET_LOCAL_ATLAS,BULLET_ATLAS_BYTES);
 }
 fail_fetch=0; fetch_count=0;
 assert(!bullet_prepare_assets(GPU_APB_BASE,7));
 unsigned tiers[]={32,64,128,256,512};
 for(unsigned t=0;t<5;t++) {
  assert(!bullet_prepare_frame(&state,tiers[t],37,7));
  /* Deliberate overlap and both-axis clipping, not just nicely spaced objects. */
  state.objects[0].x=-3*256; state.objects[0].y=70*256;
  state.objects[1].x=959*256; state.objects[1].y=539*256;
  state.objects[2].x=480*256; state.objects[2].y=480*256;
  assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,t%2u,1,BULLET_MAX_COMMANDS,&scene));
  assert(!perf_render_cpu(scene.commands,scene.count));
  memset(oracle,0,sizeof oracle);
  reference(scene.commands,scene.count,NULL);
  assert(!memcmp(oracle,(void *)(uintptr_t)GPU_FRAMEBUFFER_A,GPU_FRAME_BYTES));
  assert(scene.scene_pixels<=GPU_FRAME_WIDTH*GPU_FRAME_HEIGHT+tiers[t]*64u+736u);
 }
 /* Representative frame for real RTL: all background, 128 bullets, player,
  * three Alpha emitter halos, Fill markers and comparison HUD. */
 assert(!bullet_prepare_frame(&state,128,90,7));
 assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene));
 gpu_device d={0};
 assert(!perf_render_gpu(&d,scene.commands,scene.count,100));
 assert(submit_count==scene.count && wait_count==1);
 for(unsigned i=0;i<scene.count;i++) {
  assert(submitted[i].op==scene.commands[i].op);
  assert(submitted[i].src_addr==scene.commands[i].src_addr);
  assert(submitted[i].dst_addr==scene.commands[i].dst_addr);
 }
 hud_comparison m={.sprites=128,.gpu_active=1,.network_ready=0};
 m.bullet_demo=1; m.underflows=17; m.error_code=3;
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 assert(!hud_comparison_text(&m,lines));
 assert(strstr(lines[2],"BULLETS 128"));
 assert(strstr(lines[3],"UFL 17 ERR 3"));
 m.underflows=0; m.error_code=0; /* Preview is not a fabricated board failure. */
 m.sprites=(uint16_t)scene.visible;
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&hud));
 assert(!perf_render_cpu(scene.commands,scene.count));
 assert(!perf_render_cpu(hud.commands,hud.count));
 FILE *f=fopen("generated/verification/bullet-demo/pixels.txt","w"); assert(f);
 unsigned total=reference(scene.commands,scene.count,f);
 total+=reference(hud.commands,hud.count,f);
 assert(!fclose(f));
 assert(!memcmp(oracle,(void *)(uintptr_t)GPU_FRAMEBUFFER_A,GPU_FRAME_BYTES));
 f=fopen("generated/verification/bullet-demo/frame.rgb565","wb"); assert(f);
 assert(fwrite(oracle,1,GPU_FRAME_BYTES,f)==GPU_FRAME_BYTES); assert(!fclose(f));
 printf("PASS bullet pixels: tiers=32/64/128/256/512; representative visible=%u commands=%u pixels=%u CRC=%08x\n",
  scene.visible,scene.count,total,golden_crc32(oracle,sizeof oracle));
 assert(!munmap(memory,bytes));
 return 0;
}
