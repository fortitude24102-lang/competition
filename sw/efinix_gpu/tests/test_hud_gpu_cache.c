/* Breaks caught: full rebuild on one changed digit, stale shortened text,
 * incorrect font/spacing/color, early metadata commit after failed DMA. */
#define _GNU_SOURCE
#include "hud.h"
#include "perf_demo.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#define ATLAS_ADDR (HUD_CACHE_ADDR+0x30000u)
#define ATLAS_BYTES 39312u
#define LOGO_ADDRESS 0x02c50000u
static hud_command_stream scratch,oracle_commands;
static unsigned submitted,waits,fills;
static uint32_t copied_bytes;
static int fail_after=-1;
int gpu_submit(gpu_device *d,const gpu_command *c,uint32_t polls,uint16_t *tag) {
 assert(d && d->ready && polls && tag);
 if(fail_after==0) return GPU_DRIVER_TIMEOUT;
 if(fail_after>0) --fail_after;
 assert(c->dst_addr>=HUD_CACHE_ADDR && c->dst_addr<HUD_CACHE_ADDR+HUD_CACHE_BYTES);
 unsigned off=c->dst_addr-HUD_CACHE_ADDR;
 golden_surface dst={(uint8_t *)(uintptr_t)HUD_CACHE_ADDR,HUD_CACHE_BYTES,960,72,1920};
 if(c->op==GPU_OP_FILL) {
  assert(!golden_fill(&dst,(uint16_t)((off%1920)/2),(uint16_t)(off/1920),c->width_pixels,c->height_pixels,c->color));
  ++fills;
 } else {
  assert(c->op==GPU_OP_COPY);
  unsigned bytes=(c->height_pixels-1u)*c->src_stride+c->width_pixels*2u;
  assert((c->src_addr>=ATLAS_ADDR && c->src_addr+bytes<=ATLAS_ADDR+ATLAS_BYTES) ||
   (c->src_addr==LOGO_ADDRESS && bytes==28000u && c->width_pixels==200 && c->height_pixels==70));
  golden_surface src={(uint8_t *)(uintptr_t)c->src_addr,bytes,c->width_pixels,c->height_pixels,c->src_stride};
  assert(!golden_copy(&dst,(uint16_t)((off%1920)/2),(uint16_t)(off/1920),&src,0,0,c->width_pixels,c->height_pixels));
  copied_bytes+=c->width_pixels*c->height_pixels*2u;
 }
 *tag=(uint16_t)++submitted; return 0;
}
int gpu_wait_tag(gpu_device *d,uint16_t tag,uint32_t polls) {
 assert(d && tag==submitted && polls); ++waits; return 0;
}
int gpu_fill_async(gpu_device *d,uint32_t a,uint32_t s,uint16_t w,uint16_t h,uint16_t c,uint16_t *t) {
 (void)d;(void)a;(void)s;(void)w;(void)h;(void)c;(void)t; return GPU_DRIVER_ARGUMENT;
}
static void exact(const hud_comparison *m) {
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,m,&oracle_commands));
 assert(!perf_render_cpu(oracle_commands.commands,oracle_commands.count));
 assert(!memcmp((void *)(uintptr_t)GPU_FRAMEBUFFER_A,(void *)(uintptr_t)HUD_CACHE_ADDR,HUD_CACHE_BYTES));
}
int main(void) {
 const unsigned bytes=0xd00000;
 void *mem=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,bytes,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
 assert(mem==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 memset((void *)(uintptr_t)HUD_CACHE_ADDR,0xa5,HUD_CACHE_BYTES+16);
 memset((void *)(uintptr_t)(ATLAS_ADDR-16),0x5a,ATLAS_BYTES+32);
 hud_init_glyph_atlas();
 /* Literal C bitmap and green bank; catches shared-oracle font errors. */
 const uint8_t rows[7]={14,17,16,16,16,17,14};
 for(unsigned bank=0;bank<2;bank++) {
  const uint16_t *cell=(const uint16_t *)(uintptr_t)(ATLAS_ADDR+bank*19656u+2u*504u);
  for(unsigned y=0;y<18;y++) for(unsigned x=0;x<14;x++) {
   uint16_t want=y>=3 && y<17 && x<10 && (rows[(y-3)/2]&(16u>>(x/2)))?(bank?0x07e0:0xffff):0;
   assert(cell[y*14+x]==want);
  }
 }
 uint32_t atlas_crc=golden_crc32((void *)(uintptr_t)ATLAS_ADDR,ATLAS_BYTES);
 hud_raster_cache cache={0}; gpu_device gpu={.ready=1};
 hud_comparison m={.bullet_demo=1,.gameplay=1,.hp=3,.score=6,.gpu_active=1,.network_ready=1,
  .cpu_valid=1,.gpu_valid=1,.cpu_fps_x10=28,.gpu_fps_x10=563,.cpu_render_us=296316,.gpu_render_us=8098,
  .sprites=64,.alpha_commands=12};
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));
 assert(cache.valid && cache.rebuilds==1 && fills==1 && waits==1); exact(&m);
 unsigned before=submitted;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000) && submitted==before && scratch.count==0);
 m.score=7; fills=0; copied_bytes=0;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));
 assert(submitted==before+1 && fills==0 && copied_bytes==504 && scratch.count==1); exact(&m);
 ++m.gpu_render_us; before=submitted;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000) && submitted==before);
 for(unsigned i=0;i<20;i++) {
  m.score=i%2?9:1000; m.grazes=i%2?1:9999; m.network_ready=(uint8_t)(i%2);
  m.gpu_active=(uint8_t)(i%2); m.game_over=(uint8_t)(i%3==0); m.invulnerable=(uint8_t)(i%3==1);
  m.hp=i%2?255:0; m.error_code=i%2?255:0; m.underflows=i%2?UINT32_MAX:0;
  m.sprites=i%2?65535:32; m.alpha_commands=i%2?65535:0;
  m.cpu_render_us=i%2?UINT32_MAX:0; m.gpu_fps_x10=i%2?UINT32_MAX:0;
  assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000)); exact(&m);
 }
 /* CPU rebuilds remain full and share truthful metadata with GPU updates. */
 m.gpu_active=0; m.score=345;
 assert(!hud_update_cache(&m,&cache,&scratch)); exact(&m);
 m.gpu_active=1; m.score=346;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000)); exact(&m);
 char saved[4][64]; memcpy(saved,cache.text,sizeof saved);
 m.score=123456; m.grazes=456; fail_after=1;
 assert(hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000)==GPU_DRIVER_TIMEOUT);
 assert(!cache.valid && !memcmp(saved,cache.text,sizeof saved));
 fail_after=-1; fills=0;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000) && fills==1); exact(&m);
 before=submitted;
 assert(hud_update_gpu_cache(NULL,&m,&cache,&scratch,1000)==GPU_DRIVER_ARGUMENT);
 assert(hud_update_gpu_cache(&gpu,NULL,&cache,&scratch,1000)==GPU_DRIVER_ARGUMENT);
 assert(hud_update_gpu_cache(&gpu,&m,NULL,&scratch,1000)==GPU_DRIVER_ARGUMENT);
 assert(hud_update_gpu_cache(&gpu,&m,&cache,NULL,1000)==GPU_DRIVER_ARGUMENT);
 assert(hud_update_gpu_cache(&gpu,&m,&cache,&scratch,0)==GPU_DRIVER_ARGUMENT);
 assert(before==submitted && cache.valid);
 for(unsigned i=0;i<16;i++) {
  assert(((uint8_t *)(uintptr_t)(HUD_CACHE_ADDR+HUD_CACHE_BYTES))[i]==0xa5);
  assert(((uint8_t *)(uintptr_t)(ATLAS_ADDR-16))[i]==0x5a);
  assert(((uint8_t *)(uintptr_t)(ATLAS_ADDR+ATLAS_BYTES))[i]==0x5a);
 }
 assert(golden_crc32((void *)(uintptr_t)ATLAS_ADDR,ATLAS_BYTES)==atlas_crc);
 /* A white/blue test image, independent of the uploaded artwork encoder. */
 uint16_t *logo=(uint16_t *)(uintptr_t)LOGO_ADDRESS;
 for(unsigned i=0;i<14000;i++) logo[i]=i==2411?0x193f:0xffff;
 m=(hud_comparison){.bullet_demo=1,.gameplay=1,.hp=3,.gpu_active=1,.network_ready=1,
  .gpu_valid=1,.gpu_fps_x10=601,.gpu_render_us=8100,.sprites=64,.alpha_commands=11};
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));
 hud_set_logo_enabled(1);
 before=submitted;copied_bytes=0;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));
 const uint16_t *pixels=(const uint16_t *)(uintptr_t)HUD_CACHE_ADDR;
 assert(pixels[960+752]==0xffff); /* Old cache paints black here: expected RED. */
 assert(submitted==before+1 && copied_bytes==28000); exact(&m);
 assert(pixels[13*960+763]==0x193f);
 before=submitted;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000) && submitted==before);
 m.score=1;copied_bytes=0;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));
 assert(submitted==before+1 && copied_bytes==504); exact(&m);
 /* Long warnings have priority. Hide and restore without stale white pixels
  * or blank glyph tail copies overwriting the newly restored logo. */
 m.score=999999;m.grazes=9999;m.underflows=UINT32_MAX;m.error_code=255;m.hp=255;m.invulnerable=1;
 copied_bytes=0;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));exact(&m);
 assert(copied_bytes<28000 && pixels[70*960+950]==0);
 m.score=1;m.grazes=0;m.underflows=0;m.error_code=0;m.hp=3;m.invulnerable=0;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));exact(&m);
 assert(pixels[960+752]==0xffff);
 m.score=2;
 assert(!hud_update_cache(&m,&cache,&scratch));exact(&m);
 gpu_command hud_copy;
 assert(!hud_cached_command(GPU_FRAMEBUFFER_B,&cache,&hud_copy));
 assert(hud_copy.width_pixels==960 && hud_copy.height_pixels==72);
 assert(!perf_render_cpu(&hud_copy,1));
 assert(((uint16_t *)(uintptr_t)GPU_FRAMEBUFFER_B)[960+752]==0xffff);
 hud_set_logo_enabled(0);
 assert(!hud_update_cache(&m,&cache,&scratch));exact(&m);
 assert(pixels[960+752]==0);
 hud_set_logo_enabled(1);
 fail_after=0;
 assert(hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000)==GPU_DRIVER_TIMEOUT && !cache.valid);
 fail_after=-1;
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));exact(&m);
 assert(pixels[960+752]==0xffff);
 hud_set_logo_enabled(0);
 assert(!hud_update_gpu_cache(&gpu,&m,&cache,&scratch,1000));exact(&m);
 assert(pixels[960+752]==0);
 assert(!munmap(mem,bytes));
 puts("PASS GPU HUD glyphs and logo: exact raster, one changed digit=504B/one Copy, cache hit=zero commands, warning priority, CPU/GPU switch, A/B copy, partial failure recovery, canaries");
 return 0;
}
