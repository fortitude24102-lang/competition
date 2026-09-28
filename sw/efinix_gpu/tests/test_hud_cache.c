#define _GNU_SOURCE
#include "hud.h"
#include "perf_demo.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <sys/mman.h>
static hud_command_stream scratch;
/* Real raster checks catch compressed glyphs and missing inter-letter gutters,
 * not just agreement between two renderers using the same font builder. */
static void check_legibility(const hud_comparison *m) {
 const uint8_t cpu[3][7]={{14,17,16,16,16,17,14},
  {30,17,17,30,16,16,16},{17,17,17,17,17,17,14}};
 const uint8_t em[7]={17,27,21,21,17,17,17};
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 assert(!hud_comparison_text(m,lines));
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,m,&scratch));
 assert(!perf_render_cpu(scratch.commands,scratch.count));
 const uint16_t *pixels=(const uint16_t *)(uintptr_t)GPU_FRAMEBUFFER_A;
 for(unsigned glyph=0;glyph<4;glyph++) for(unsigned row=0;row<7;row++)
  for(unsigned col=0;col<5;col++) for(unsigned dy=0;dy<2;dy++) for(unsigned dx=0;dx<2;dx++) {
   unsigned line=glyph==3?2:0,slot=glyph==3?0:glyph;
   unsigned bits=glyph==3?em[row]:cpu[glyph][row];
   uint16_t want=bits&(16u>>col)?(line==2?0x07e0:0xffff):0;
   assert(pixels[(3+line*18+row*2+dy)*960+8+slot*14+col*2+dx]==want);
  }
 for(unsigned line=0;line<4;line++) {
  unsigned length=(unsigned)strlen(lines[line]);
  assert(8+length*14<=960);
  for(unsigned slot=0;slot<length;slot++) for(unsigned y=3+line*18;y<17+line*18;y++)
   for(unsigned x=8+slot*14+10;x<8+(slot+1)*14;x++) assert(!pixels[y*960+x]);
  /* Four blank rows separate lines; the last line still fits in 72 rows. */
  for(unsigned y=17+line*18;y<21+line*18 && y<72;y++)
   for(unsigned x=0;x<960;x++) assert(!pixels[y*960+x]);
 }
}
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
 check_legibility(&m);
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
 m.gameplay=1; m.hp=2; m.score=123; m.grazes=4; m.alpha_commands=68; m.invulnerable=1;
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 assert(!hud_comparison_text(&m,lines));
 assert(strstr(lines[2],"ALPHA 68"));
 assert(strstr(lines[3],"HP 2 SCORE 123 GRAZE 4"));
 assert(strstr(lines[3],"SHIELD"));
 assert(!hud_update_cache(&m,&cache,&scratch));
 assert(cache.rebuilds==13);
 m.score=UINT32_MAX; m.grazes=UINT32_MAX; m.underflows=UINT32_MAX;
 m.hp=0; m.game_over=1;
 assert(!hud_comparison_text(&m,lines) && strlen(lines[3])<64);
 assert(strstr(lines[3],"SCORE 999999 GRAZE 9999"));
 assert(strstr(lines[3],"OVER"));
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,&m,&scratch));
 assert(!perf_render_cpu(scratch.commands,scratch.count));
 assert(!hud_update_cache(&m,&cache,&scratch));
 assert(!hud_cached_command(GPU_FRAMEBUFFER_B,&cache,&copy));
 assert(!perf_render_cpu(&copy,1));
 assert(!memcmp((void *)(uintptr_t)GPU_FRAMEBUFFER_A,(void *)(uintptr_t)GPU_FRAMEBUFFER_B,HUD_CACHE_BYTES));
 /* Longest gameplay fields, including shield and network fallback, must not
  * truncate the command stream or paint beyond the reserved HUD. */
 m.hp=255; m.error_code=255; m.alpha_commands=65535; m.sprites=65535;
 m.network_ready=0; m.game_over=0; m.invulnerable=1;
 check_legibility(&m);
 for(unsigned i=1;i<scratch.count;i++) {
  const gpu_command *c=&scratch.commands[i];
  unsigned offset=c->dst_addr-GPU_FRAMEBUFFER_A;
  assert((offset%GPU_FRAME_STRIDE)/2+c->width_pixels<=960);
  assert(offset/GPU_FRAME_STRIDE+c->height_pixels<=72);
 }
 assert(!munmap(mem,bytes));
 puts("PASS HUD cache: legible 5x7 glyphs, 4px gutters, bounded layout, exact pixels, text invalidation, A/B copy, DDR canary");
 return 0;
}
