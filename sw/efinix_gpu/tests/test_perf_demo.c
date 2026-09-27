#define _GNU_SOURCE
#include "perf_demo.h"
#include "hud.h"
#include "asset_catalog.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <limits.h>

static unsigned submitted,waited;
static gpu_command captured[PERF_MAX_SPRITES+1];
int gpu_submit(gpu_device *d,const gpu_command *c,uint32_t polls,uint16_t *tag) {
 assert(d && polls && submitted<PERF_MAX_SPRITES+1);
 captured[submitted++]=*c; *tag=(uint16_t)submitted; return 0;
}
int gpu_wait_tag(gpu_device *d,uint16_t tag,uint32_t polls) {
 assert(d && polls && tag==submitted); ++waited; return 0;
}
int gpu_fill_async(gpu_device *d,uint32_t dst,uint32_t stride,uint16_t w,uint16_t h,uint16_t color,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_FILL,.dst_addr=dst,.dst_stride=stride,.width_pixels=w,.height_pixels=h,.color=color};
 return gpu_submit(d,&c,1,tag);
}
/* Independent pixel loop, intentionally not using golden_renderer or rgb565. */
static void reference(const perf_stream *s,uint16_t *out) {
 for(unsigned n=0;n<s->count;n++) {
  const gpu_command *c=&s->commands[n];
  unsigned offset=(c->dst_addr-GPU_FRAMEBUFFER_A)/2;
  const uint16_t *src=(const uint16_t *)(uintptr_t)c->src_addr;
  for(unsigned y=0;y<c->height_pixels;y++) for(unsigned x=0;x<c->width_pixels;x++) {
   uint16_t *dst=&out[offset+y*GPU_FRAME_WIDTH+x];
   if(c->op==GPU_OP_FILL) { *dst=c->color; continue; }
   uint16_t fg=src[y*(c->src_stride/2)+x];
   if(c->op==GPU_OP_ALPHA) {
    unsigned a=c->alpha,b=255-a;
    unsigned r=(((fg>>11)&31)*a+((*dst>>11)&31)*b+127)/255;
    unsigned g=(((fg>>5)&63)*a+((*dst>>5)&63)*b+127)/255;
    unsigned bl=((fg&31)*a+(*dst&31)*b+127)/255;
    *dst=(uint16_t)((r<<11)|(g<<5)|bl);
   } else if(c->op==GPU_OP_COPY || fg!=c->color_key) *dst=fg;
  }
 }
}
int main(void) {
 size_t bytes=0x00900000u;
 void *mapping=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,bytes,PROT_READ|PROT_WRITE,
  MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
 assert(mapping==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 perf_init_local_assets();
 static perf_stream scene,again;
 assert(perf_build_frame(GPU_FRAMEBUFFER_A,3,0,0,&scene)==GPU_DRIVER_ARGUMENT);
 assert(perf_build_frame(GPU_FRAMEBUFFER_A,257,0,0,&scene)==GPU_DRIVER_ARGUMENT);
 assert(perf_build_frame(GPU_FRAMEBUFFER_A+2,16,0,0,&scene)==GPU_DRIVER_ARGUMENT);
 unsigned tiers[]={16,32,64,96,128,192,256};
 for(unsigned t=0;t<sizeof tiers/sizeof tiers[0];t++) for(unsigned f=0;f<30;f++) {
  assert(!perf_build_frame(GPU_FRAMEBUFFER_A,tiers[t],f,0,&scene));
  assert(scene.count==tiers[t]+1);
  unsigned key=0,alpha=0;
  for(unsigned i=1;i<scene.count;i++) {
   gpu_command *c=&scene.commands[i];
   unsigned offset=c->dst_addr-GPU_FRAMEBUFFER_A;
   assert(offset%GPU_FRAME_STRIDE+c->width_pixels*2u<=GPU_FRAME_STRIDE);
   assert((uint64_t)offset+(c->height_pixels-1)*GPU_FRAME_STRIDE+c->width_pixels*2u<=GPU_FRAME_BYTES);
   assert(c->width_pixels==64 && c->height_pixels==80);
   key+=c->op==GPU_OP_COLOR_KEY; alpha+=c->op==GPU_OP_ALPHA;
  }
  assert(key && alpha);
 }
 assert(!perf_build_frame(GPU_FRAMEBUFFER_A,32,7,0,&scene));
 assert(!perf_build_frame(GPU_FRAMEBUFFER_A,32,7,0,&again));
 for(unsigned i=0;i<scene.count;i++) {
  assert(scene.commands[i].dst_addr==again.commands[i].dst_addr);
  assert(scene.commands[i].src_addr==again.commands[i].src_addr);
 }
 assert(!perf_render_cpu(scene.commands,scene.count));
 reference(&scene,(uint16_t *)(uintptr_t)GPU_FRAMEBUFFER_B);
 assert(!memcmp((void *)(uintptr_t)GPU_FRAMEBUFFER_A,(void *)(uintptr_t)GPU_FRAMEBUFFER_B,GPU_FRAME_BYTES));
 uint32_t crc=golden_crc32((void *)(uintptr_t)GPU_FRAMEBUFFER_A,GPU_FRAME_BYTES);
 assert(crc==UINT32_C(0x8e341090));
 assert(crc==golden_crc32((void *)(uintptr_t)GPU_FRAMEBUFFER_B,GPU_FRAME_BYTES));
 printf("local scene CRC=%08x\n",crc);
 assert(!perf_build_frame(GPU_FRAMEBUFFER_A,32,8,0,&again));
 assert(scene.commands[1].dst_addr!=again.commands[1].dst_addr);
 gpu_device device={0};
 assert(!perf_render_gpu(&device,scene.commands,scene.count,100));
 assert(submitted==scene.count && waited==1);
 for(unsigned i=0;i<scene.count;i++) {
  assert(captured[i].op==scene.commands[i].op);
  assert(captured[i].dst_addr==scene.commands[i].dst_addr);
 }
 /* Network path reads the validated scene/sprite addresses; fallback upload cannot touch them. */
 memset((void *)(uintptr_t)ASSET_SCENE_ADDR,0x35,ASSET_SCENE_BYTES);
 memset((void *)(uintptr_t)ASSET_FLOWER_ADDR,0x73,ASSET_FLOWER_BYTES);
 memset((void *)(uintptr_t)ASSET_ZOMBIE_WALK1_ADDR,0x92,ASSET_ZOMBIE_WALK1_BYTES);
 memset((void *)(uintptr_t)ASSET_ZOMBIE_WALK2_ADDR,0xA4,ASSET_ZOMBIE_WALK2_BYTES);
 perf_init_local_assets();
 assert(*(uint16_t *)(uintptr_t)ASSET_SCENE_ADDR==0x3535);
 assert(!perf_build_frame(GPU_FRAMEBUFFER_A,16,8,1,&scene));
 assert(scene.commands[0].op==GPU_OP_COPY && scene.commands[0].src_addr==ASSET_SCENE_ADDR);
 assert(scene.commands[2].src_addr==ASSET_ZOMBIE_WALK2_ADDR);
 assert(!perf_render_cpu(scene.commands,scene.count));
 reference(&scene,(uint16_t *)(uintptr_t)GPU_FRAMEBUFFER_B);
 assert(!memcmp((void *)(uintptr_t)GPU_FRAMEBUFFER_A,(void *)(uintptr_t)GPU_FRAMEBUFFER_B,GPU_FRAME_BYTES));
 gpu_command bad=scene.commands[1]; bad.dst_addr=GPU_FRAMEBUFFER_A+GPU_FRAME_BYTES;
 assert(perf_render_cpu(&bad,1)==GPU_DRIVER_ARGUMENT);
 bad=scene.commands[1]; bad.src_addr=GPU_DDR_END_EXCLUSIVE-2;
 assert(perf_render_cpu(&bad,1)==GPU_DRIVER_ARGUMENT);
 perf_window w={0};
 assert(perf_fps_x10(&w,100000000)==0 && perf_render_us(&w,100000000)==0);
 assert(perf_window_add(&w,0,0)==GPU_DRIVER_ARGUMENT);
 assert(perf_window_add(&w,1,2)==GPU_DRIVER_ARGUMENT);
 for(unsigned i=0;i<30;i++) assert(!perf_window_add(&w,2000000,500000));
 assert(perf_fps_x10(&w,100000000)==500 && perf_render_us(&w,100000000)==5000);
 assert(perf_fps_x10(&w,0)==0 && perf_render_us(&w,0)==0);
 w=(perf_window){.wall_ticks=UINT64_MAX,.render_ticks=UINT64_MAX,.frames=1};
 assert(perf_window_add(&w,1,1)==GPU_DRIVER_ARGUMENT);
 w=(perf_window){.wall_ticks=1,.frames=UINT_MAX};
 assert(perf_fps_x10(&w,UINT32_MAX)==0);
 assert(perf_window_add(&w,1,0)==GPU_DRIVER_ARGUMENT);
 w=(perf_window){.wall_ticks=1,.frames=PERF_WINDOW_FRAMES};
 assert(perf_fps_x10(&w,UINT32_MAX)==UINT32_MAX);
 assert(perf_window_add(&w,1,0)==GPU_DRIVER_ARGUMENT);
 w=(perf_window){.render_ticks=UINT64_MAX,.frames=1};
 assert(perf_render_us(&w,1)==UINT32_MAX);
 hud_comparison m={.sprites=256};
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 assert(!hud_comparison_text(&m,lines));
 assert(strstr(lines[0],"CPU FPS --") && strstr(lines[1],"GPU FPS --"));
 assert(strstr(lines[2],"MODE CPU") && strstr(lines[2],"NET FAIL FALLBACK"));
 assert(strstr(lines[3],"30 FRAME FPS WITH PRESENT"));
 static struct { hud_command_stream hud; uint32_t guard; } h;
 h.guard=0x12345678;
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&h.hud));
 assert(!perf_render_cpu(h.hud.commands,h.hud.count));
 m=(hud_comparison){.sprites=65535,.cpu_valid=1,.gpu_valid=1,.gpu_active=1,.network_ready=1,
  .cpu_fps_x10=UINT32_MAX,.gpu_fps_x10=UINT32_MAX,.cpu_render_us=UINT32_MAX,.gpu_render_us=UINT32_MAX};
 assert(!hud_comparison_text(&m,lines));
 assert(strstr(lines[0],"CPU FPS 9999.9") && strstr(lines[1],"GPU FPS 9999.9"));
 assert(strstr(lines[2],"MODE GPU") && strstr(lines[2],"NET READY"));
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&h.hud));
 assert(h.hud.count<HUD_MAX_COMMANDS && h.guard==0x12345678);
 for(unsigned i=0;i<h.hud.count;i++) {
  const gpu_command *c=&h.hud.commands[i];
  assert(c->dst_addr-GPU_FRAMEBUFFER_A+(c->height_pixels-1)*GPU_FRAME_STRIDE+c->width_pixels*2u<=72u*GPU_FRAME_STRIDE);
 }
 printf("HUD maximum test uses %u/%u commands\n",h.hud.count,HUD_MAX_COMMANDS);
 for(unsigned digit=0;digit<10;digit++) for(unsigned ready=0;ready<2;ready++) {
  m.cpu_fps_x10=m.gpu_fps_x10=digit*11111u;
  m.cpu_render_us=m.gpu_render_us=digit*111111111u;
  m.network_ready=(uint8_t)ready;
  assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&h.hud));
  assert(h.hud.count<=HUD_MAX_COMMANDS && h.guard==0x12345678);
 }
 assert(!munmap(mapping,bytes));
 puts("PASS: V2 scene, CPU pixels/CRC, GPU submission, timing and HUD (host only)");
 return 0;
}
