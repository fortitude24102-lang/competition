/* Real HUD renderer/driver; only MMIO and DDR are modeled. Fail if either
 * physical buffer shares history, a full HUD Copy returns, metadata commits
 * on failed retirement, or any write escapes the top 72 rows. */
#define _GNU_SOURCE
#include "hud.h"
#include "perf_demo.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#ifdef HUD_DIRECT_REFERENCE
static int candidate(gpu_device *g,const hud_comparison *m,hud_framebuffer_cache *c,
 hud_command_stream *s,uint32_t dst,uint32_t polls) {
 int e=hud_update_gpu_cache(g,m,&c->buffers[dst==GPU_FRAMEBUFFER_B],s,polls);
 if(e)return e;
 gpu_command copy;e=hud_cached_command(dst,&c->buffers[dst==GPU_FRAMEBUFFER_B],&copy);
 return e?e:perf_render_gpu(g,&copy,1,polls);
}
#else
#define candidate hud_render_gpu_direct
#endif
static uint32_t regs[256];
static int fail_submit=-1,fail_wait;
static uint32_t frozen_done;
static unsigned commands,full_copies,fills;
static uint32_t bytes_written;
static hud_command_stream scratch,oracle;
static uint8_t pixels[HUD_CACHE_BYTES];
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);
 if(r==GPU_REG_STATUS)return GPU_STATUS_EMPTY|(3u<<14)|(fail_submit==0?GPU_STATUS_FULL:0);
 if(r==GPU_REG_LAST_DONE && fail_wait)return frozen_done;
 return regs[r/4];
}
void gpu_io_write(uintptr_t a,uint32_t v) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);assert(r<sizeof regs);regs[r/4]=v;
 if(r!=GPU_REG_CONTROL || v!=GPU_CONTROL_SUBMIT)return;
 if(fail_submit>0)--fail_submit;
 unsigned w=regs[GPU_REG_SIZE/4]&65535u,h=regs[GPU_REG_SIZE/4]>>16;
 uint32_t dst=regs[GPU_REG_DST_ADDR/4],stride=regs[GPU_REG_DST_STRIDE/4];
 uint32_t base=dst>=GPU_FRAMEBUFFER_B && dst<GPU_FRAMEBUFFER_B+HUD_CACHE_BYTES?GPU_FRAMEBUFFER_B:
  dst>=GPU_FRAMEBUFFER_A && dst<GPU_FRAMEBUFFER_A+HUD_CACHE_BYTES?GPU_FRAMEBUFFER_A:HUD_CACHE_ADDR;
 assert((uint64_t)dst+(h-1u)*stride+w*2u<=base+HUD_CACHE_BYTES);
 for(unsigned y=0;y<h;y++) {
  uint16_t *d=(uint16_t *)(uintptr_t)(dst+y*stride);
  if(regs[GPU_REG_OP/4]==GPU_OP_FILL) {for(unsigned x=0;x<w;x++)d[x]=(uint16_t)regs[GPU_REG_COLOR_KEY/4];}
  else {
   assert(regs[GPU_REG_OP/4]==GPU_OP_COPY);
   memcpy(d,(void *)(uintptr_t)(regs[GPU_REG_SRC_ADDR/4]+y*regs[GPU_REG_SRC_STRIDE/4]),w*2u);
  }
 }
 ++commands;bytes_written+=w*h*2u;
 fills+=regs[GPU_REG_OP/4]==GPU_OP_FILL;
 full_copies+=regs[GPU_REG_OP/4]==GPU_OP_COPY && w==960 && h==72;
 regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];
}
void gpu_io_fence(void) {}
void gpu_platform_sync(void) {}
static void reset(gpu_device *g) {
 memset(regs,0,sizeof regs);fail_submit=-1;fail_wait=0;
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 assert(!gpu_init(g,GPU_APB_BASE));
}
static void exact(uint32_t dst,const hud_comparison *m) {
 memcpy(pixels,(void *)(uintptr_t)dst,HUD_CACHE_BYTES);
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,m,&oracle));
 assert(!perf_render_cpu(oracle.commands,oracle.count));
 assert(!memcmp(pixels,(void *)(uintptr_t)GPU_FRAMEBUFFER_A,HUD_CACHE_BYTES));
 /* Oracle is a destructive writer: put A back to its physical history. */
 if(dst==GPU_FRAMEBUFFER_A)memcpy((void *)(uintptr_t)dst,pixels,HUD_CACHE_BYTES);
}
int main(void) {
 const unsigned size=0xd00000;
 void *p=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,size,PROT_READ|PROT_WRITE,
  MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);assert(p==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 memset(p,0xa5,size);hud_init_glyph_atlas();
 uint16_t *logo=(uint16_t *)(uintptr_t)HUD_LOGO_ADDR;
 for(unsigned i=0;i<HUD_LOGO_BYTES/2;i++)logo[i]=i%17?0xffff:0x193f;
 hud_set_logo_enabled(1);
 gpu_device g;reset(&g);hud_framebuffer_cache cache={0};
 hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.network_ready=1,.hp=3,
  .gpu_valid=1,.gpu_fps_x10=601,.gpu_render_us=8100,.sprites=512,.alpha_commands=67,.v3_mode=1};
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_A,100));
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,100));
 unsigned before=commands;
 m.score=1;
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_A,100));
 /* Old shared-cache path needs glyph + complete HUD Copy. */
 assert(commands==before+1 && full_copies==0);
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,100));
 assert(commands==before+2);
 before=commands;
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_A,100) && commands==before);
 exact(GPU_FRAMEBUFFER_A,&m);exact(GPU_FRAMEBUFFER_B,&m);
 for(unsigned i=0;i<100;i++) {
  m.score=i%2?9:999999;m.grazes=i%3?0:9999;m.underflows=i%3?0:UINT32_MAX;
  m.error_code=i%3?0:255;m.hp=i%2?3:255;m.v3_mode=(uint8_t)(i%6);
  m.cpu_valid=(uint8_t)(i%2);m.cpu_render_us=i*10000;m.cpu_fps_x10=28;
  m.perf_stage=(uint8_t)(i%7);m.perf_best=872;m.perf_frames=i*30;
  uint32_t dst=i%2?GPU_FRAMEBUFFER_A:GPU_FRAMEBUFFER_B;
  /* Preserve the other physical buffer while the CPU oracle uses A. */
  static uint8_t saved_a[HUD_CACHE_BYTES];
  memcpy(saved_a,(void *)(uintptr_t)GPU_FRAMEBUFFER_A,HUD_CACHE_BYTES);
  assert(!candidate(&g,&m,&cache,&scratch,dst,100));exact(dst,&m);
  if(dst==GPU_FRAMEBUFFER_B)memcpy((void *)(uintptr_t)GPU_FRAMEBUFFER_A,saved_a,HUD_CACHE_BYTES);
 }
 m.v3_mode=1;m.score=12;
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,100));
 char saved[4][64];memcpy(saved,cache.buffers[1].text,sizeof saved);
 m.score=345;fail_submit=1;
 assert(candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,2)==GPU_DRIVER_TIMEOUT);
 assert(!cache.buffers[1].valid && !memcmp(saved,cache.buffers[1].text,sizeof saved));
 reset(&g);fills=0;
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,100) && fills==1);exact(GPU_FRAMEBUFFER_B,&m);
 /* External/CPU overwrite requires explicit invalidation, never reuse stale history. */
 memset((void *)(uintptr_t)GPU_FRAMEBUFFER_B,0x55,HUD_CACHE_BYTES);
 cache.buffers[1].valid=0;fills=0;
 assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,100) && fills==1);exact(GPU_FRAMEBUFFER_B,&m);
 frozen_done=regs[GPU_REG_LAST_DONE/4];fail_wait=1;m.score=346;
 assert(candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,2)==GPU_DRIVER_TIMEOUT && !cache.buffers[1].valid);
 reset(&g);assert(!candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,100));exact(GPU_FRAMEBUFFER_B,&m);
 before=commands;
 assert(candidate(&g,&m,&cache,&scratch,GPU_FRAMEBUFFER_B+2,100)==GPU_DRIVER_ARGUMENT);
 assert(candidate(&g,&m,NULL,&scratch,GPU_FRAMEBUFFER_B,100)==GPU_DRIVER_ARGUMENT);
 assert(commands==before);
 for(unsigned i=0;i<32;i++) {
  assert(((uint8_t *)(uintptr_t)(GPU_FRAMEBUFFER_A+HUD_CACHE_BYTES))[i]==0xa5);
  assert(((uint8_t *)(uintptr_t)(GPU_FRAMEBUFFER_B+HUD_CACHE_BYTES))[i]==0xa5);
  assert(((uint8_t *)(uintptr_t)HUD_CACHE_ADDR)[i]==0xa5);
 }
 assert(!full_copies);assert(!munmap(p,size));
 printf("HUD_DIRECT,PASS,physical_AB,100_transitions,logo,shorten,errors,invalidation,canaries,full_copies=%u,bytes_written=%u\n",full_copies,bytes_written);
}
