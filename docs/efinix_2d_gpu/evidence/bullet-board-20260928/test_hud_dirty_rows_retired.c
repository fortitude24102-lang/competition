#define _GNU_SOURCE
#include "hud.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
static hud_command_stream scratch;
static unsigned filled;
enum gpu_error __real_golden_fill(const golden_surface *,uint16_t,uint16_t,uint16_t,uint16_t,uint16_t);
/* Link --wrap=golden_fill: observe work, still execute the real rasterizer. */
enum gpu_error __wrap_golden_fill(const golden_surface *s,uint16_t x,uint16_t y,uint16_t w,uint16_t h,uint16_t color) {
 filled+=(unsigned)w*h;
 return __real_golden_fill(s,x,y,w,h,color);
}
int gpu_fill_async(gpu_device *d,uint32_t a,uint32_t s,uint16_t w,uint16_t h,uint16_t c,uint16_t *t) {
 (void)d;(void)a;(void)s;(void)w;(void)h;(void)c;(void)t;return 0;
}
int gpu_wait_tag(gpu_device *d,uint16_t t,uint32_t p) {(void)d;(void)t;(void)p;return 0;}
int main(void) {
 const unsigned bytes=0xd00000;
 void *mem=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,bytes,PROT_READ|PROT_WRITE,
  MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
 assert(mem==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 hud_raster_cache cache={0};
 hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.hp=3,.score=9};
 assert(!hud_update_cache(&m,&cache,&scratch));
 /* Changing only score must not clear/repaint the other three HUD rows. */
 m.score=10; filled=0;
 assert(!hud_update_cache(&m,&cache,&scratch));
 printf("HUD score update filled_pixels=%u\n",filled); fflush(stdout);
 assert(filled<25000); /* 960x18 row clear plus glyphs, not 960x72 clear. */
 golden_surface oracle={(uint8_t *)(uintptr_t)GPU_FRAMEBUFFER_A,HUD_CACHE_BYTES,960,72,1920};
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&scratch));
 for(unsigned i=0;i<scratch.count;i++) {
  const gpu_command *c=&scratch.commands[i];
  unsigned offset=c->dst_addr-GPU_FRAMEBUFFER_A;
  assert(!golden_fill(&oracle,(offset%1920)/2,offset/1920,c->width_pixels,c->height_pixels,c->color));
 }
 assert(!memcmp(oracle.pixels,(void *)(uintptr_t)HUD_CACHE_ADDR,HUD_CACHE_BYTES));
 filled=0;
 assert(!hud_update_cache(&m,&cache,&scratch) && filled==0);
 assert(!munmap(mem,bytes));
 puts("PASS HUD dirty rows: bounded score-update work, exact full-raster pixels, zero-work cache hit");
 return 0;
}
