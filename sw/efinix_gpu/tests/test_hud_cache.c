#define _GNU_SOURCE
#include "hud.h"
#include "perf_demo.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <sys/mman.h>
static hud_command_stream scratch;
int gpu_submit(gpu_device *d,const gpu_command *c,uint32_t p,uint16_t *t) {(void)d;(void)c;(void)p;(void)t;return 0;}
int gpu_wait_tag(gpu_device *d,uint16_t t,uint32_t p) {(void)d;(void)t;(void)p;return 0;}
int gpu_fill_async(gpu_device *d,uint32_t a,uint32_t s,uint16_t w,uint16_t h,uint16_t c,uint16_t *t) {
 (void)d;(void)a;(void)s;(void)w;(void)h;(void)c;(void)t;return 0;
}
int main(void) {
 const unsigned bytes=0xd00000u;
 void *mem=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,bytes,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
 assert(mem==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 hud_raster_cache cache={0}; gpu_command copy;
 hud_comparison m={.bullet_demo=1};
 assert(hud_cached_command(GPU_FRAMEBUFFER_A,&cache,&copy)==GPU_DRIVER_ARGUMENT);
 assert(hud_update_cache(NULL,&cache,&scratch)==GPU_DRIVER_ARGUMENT);
 unsigned char *guard=(unsigned char *)(uintptr_t)(HUD_CACHE_ADDR+HUD_CACHE_BYTES);
 memset(guard,0xa5,16);
 for(unsigned i=0;i<12;i++) {
  m.sprites=(uint16_t)(32+i*43); m.gpu_active=i%2; m.network_ready=(i/2)%2;
  m.cpu_valid=i>=4; m.gpu_valid=i>=8; m.underflows=i*123456789u; m.error_code=(uint8_t)i;
  m.cpu_fps_x10=UINT32_MAX; m.gpu_fps_x10=600; m.cpu_render_us=UINT32_MAX; m.gpu_render_us=12345;
  assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&scratch));
  assert(!perf_render_cpu(scratch.commands,scratch.count));
  assert(!hud_update_cache(&m,&cache,&scratch));
  assert(cache.rebuilds==i+1);
  assert(!hud_cached_command(GPU_FRAMEBUFFER_B,&cache,&copy));
  assert(copy.op==GPU_OP_COPY && copy.width_pixels==960 && copy.height_pixels==72);
  assert(!perf_render_cpu(&copy,1));
  assert(!memcmp((void *)(uintptr_t)GPU_FRAMEBUFFER_A,(void *)(uintptr_t)GPU_FRAMEBUFFER_B,HUD_CACHE_BYTES));
  assert(!hud_update_cache(&m,&cache,&scratch) && cache.rebuilds==i+1);
  for(unsigned n=0;n<16;n++) assert(guard[n]==0xa5);
 }
 /* Raw values can change without changing the displayed (quantized) text. */
 ++m.gpu_render_us;
 assert(!hud_update_cache(&m,&cache,&scratch) && cache.rebuilds==12);
 assert(hud_cached_command(GPU_FRAMEBUFFER_A+2,&cache,&copy)==GPU_DRIVER_ARGUMENT);
 assert(!munmap(mem,bytes));
 puts("PASS HUD cache: exact pixels, text invalidation, A/B copy, DDR canary");
 return 0;
}
