/* Exercise the real V3 loop through MENU and WIN; GPU/network boundary calls
 * are stopped at HUD submission so this is not a second firmware renderer. */
#define _GNU_SOURCE
#include "v3_demo.h"
#include "gpu_stripes.h"
#include "hud_gpu_list.h"
#include "perf_demo.h"
#include "game_menu.h"
#include "network_assets.h"
#include <assert.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
static jmp_buf end_frame;
static unsigned won,seen,bank_seen,gpu_render_count;
static bullet_stream scene;
static hud_command_stream hud;
static hud_raster_cache cache;
void bsp_printf(const char *format,...) {va_list args;va_start(args,format);vfprintf(stderr,format,args);va_end(args);}
uint64_t gpu_platform_cycles(void) {static uint64_t ticks;return ticks+=1000;}
void gpu_platform_sync(void) {}
int __real_v3_runtime_menu_init(v3_runtime *,uint32_t,uint32_t);
int __wrap_v3_runtime_menu_init(v3_runtime *r,uint32_t seed,uint32_t epoch) {
 int e=__real_v3_runtime_menu_init(r,seed,epoch);
 if(!e && won) {e=v3_runtime_game_command(r,1,1,seed,epoch);r->game.won=1;memset(r->game.enemy_hp,0,sizeof r->game.enemy_hp);}
 return e;
}
int __wrap_nc_init(nc_device *d,uintptr_t base) {memset(d,0,sizeof *d);d->base=base;return 0;}
int __wrap_nc_poll(nc_device *d,uint32_t ms,nc_input *in) {(void)d;(void)ms;memset(in,0,sizeof *in);return 0;}
int __wrap_nc_take_game(nc_device *d,nc_game_command *c) {(void)d;(void)c;return 0;}
int __wrap_nc_complete_game(nc_device *d,const nc_game_command *c,uint32_t result) {(void)d;(void)c;(void)result;return 0;}
int __wrap_nc_try_publish(nc_device *d,const nc_telemetry *t,uint32_t ms) {(void)d;(void)t;(void)ms;return 0;}
void __wrap_nc_discard_pending_telemetry(nc_device *d) {(void)d;}
int __wrap_gpu_frame_list_init(gpu_frame_list *f,gpu_device *d,int n) {(void)n;*f=(gpu_frame_list){.gpu=d,.present=1};return 0;}
int __wrap_gpu_stripes_supported(gpu_device *d) {(void)d;return 1;}
int __wrap_gpu_stripes_render(gpu_frame_list *f,int n,uint32_t b,const gpu_instance *s,unsigned c,
 gpu_instance *o,unsigned cap,uint32_t epoch,uint32_t polls) {
 (void)f;(void)n;(void)b;(void)s;(void)c;(void)o;(void)cap;(void)epoch;(void)polls;assert(!"MENU/WIN must not use stripe scene");return -8;
}
int __wrap_hud_gpu_list_init(gpu_frame_list *f,int n) {(void)n;f->hud_ready=1;return 0;}
int __wrap_hud_render_gpu_list(gpu_frame_list *f,const hud_comparison *m,hud_raster_cache *c,
 hud_command_stream *s,uint32_t dst,uint32_t bank,uint32_t epoch,uint32_t polls) {
 (void)f;(void)m;(void)c;(void)s;(void)dst;(void)epoch;(void)polls;
 assert(gpu_render_count==(won?2u:1u));
 ++seen;bank_seen=bank;longjmp(end_frame,1);return 0;
}
int __wrap_gpu_set_qos(gpu_device *d,uint16_t a,uint16_t b,int c) {(void)d;(void)a;(void)b;(void)c;return 0;}
int __wrap_gpu_read_perf_snapshot(gpu_device *d,gpu_perf_snapshot *s) {(void)d;memset(s,0,sizeof *s);return 0;}
int __wrap_perf_render_gpu(gpu_device *d,const gpu_command *c,unsigned n,uint32_t p) {
 (void)d;(void)p;++gpu_render_count;
 assert(n && c[0].op==(gpu_render_count==1?GPU_OP_FILL:GPU_OP_COPY));return 0;
}
int __wrap_perf_render_cpu(const gpu_command *c,unsigned n) {(void)c;(void)n;assert(!"CPU not selected");return -8;}
int __wrap_framebuffer_present(gpu_device *d,framebuffer_pair *p,uint32_t polls) {
 (void)d;(void)polls;uint32_t b=p->back;p->back=p->front;p->front=b;return 0;
}
int __wrap_game_menu_draw(gpu_device *d,game_menu_cache *c,unsigned i,uint32_t dst,uint32_t g,
 int n,hud_command_stream *s,uint32_t p) {(void)d;(void)c;(void)i;(void)dst;(void)g;(void)n;(void)s;(void)p;return 0;}
int __wrap_network_asset_fetch(uintptr_t a,uint32_t hz,uint32_t session,uint32_t id,uint32_t dst,
 uint32_t bytes,uint32_t crc,network_asset_report *r) {
 (void)a;(void)hz;(void)session;(void)id;(void)dst;(void)bytes;(void)crc;(void)r;return -1;
}
int main(void) {
 void *p=mmap((void *)0x02d00000,0x80000,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
 assert(p==(void *)0x02d00000);
 for(won=0;won<2;won++) {
  seen=bank_seen=gpu_render_count=0;
  if(!setjmp(end_frame)) {
   gpu_device gpu={.ready=1,.base=GPU_APB_BASE};framebuffer_pair fb={GPU_FRAMEBUFFER_A,GPU_FRAMEBUFFER_B};
   (void)v3_demo_run(&gpu,&fb,0,&scene,&hud,&cache);
  }
  fprintf(stderr,"ROUTE,won=%u,seen=%u,bank=%x,gpu_calls=%u\n",won,seen,bank_seen,gpu_render_count);
  assert(seen==1 && (bank_seen==GPU_FRAME_LIST_BANK_A || bank_seen==GPU_FRAME_LIST_BANK_B));
 }
 assert(!munmap(p,0x80000));puts("STRIPE_HUD_ROUTE,PASS,real_V3_MENU_and_WIN,original_bank_only");
}
