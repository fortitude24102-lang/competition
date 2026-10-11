/* Diagnostic only. Include the actual main + V3 loop; do not copy gameplay.
 * No normal firmware changes. MENU is forbidden in this direct-LIVE probe.
 * Wrappers change code placement: absolute CPU times are NOT native baseline
 * times. Corroborate with original telemetry / terminal V3_DETAIL_PROBE.
 * Timings are exclusive; hardware busy and submit timings OVERLAP scene time.
 * Split Copy is a separate perturbing experiment, never the normal baseline. */
#define V3_INTERACTIVE 1
#define V3_PROBE_FRAMES LP_SAMPLES
#include "live_phase_stats.h"
#define main reference_main
#include "../src/main.c"
#undef main
#include "v3_runtime.h"
#include "game_menu.h"
#include "render_phase_health.h"
#include <string.h>
int main(void) {
 bsp_init();gpu_device gpu;int e=gpu_init(&gpu,GPU_APB_BASE);if(e) return e;
 uint32_t session=(uint32_t)gpu_platform_cycles();
 int network=bullet_prepare_assets(GPU_APB_BASE,session?session:1);
 if(network) {bsp_printf("LIVE_PHASE_FAIL,assets=%d\r\n",network);return network;}
 gpu_platform_sync();e=bullet_prepare_texture_cache(&gpu,network,10000000u);if(e) return e;
 framebuffer_pair buffers;framebuffer_init(&buffers);
 hud_init_glyph_atlas();gpu_platform_sync();
 /* Fail rather than enter AUTO/CPU fallback. Unused legacy BSS is garbage
  * collected; actual V3 game/render/HUD loop below is unchanged. */
 return v3_demo_run(&gpu,&buffers,1,&scene,&overlay,&hud_cache);
}
#ifndef LIVE_PHASE_TIMING
#define LIVE_PHASE_TIMING 1
#endif
#ifndef LIVE_PHASE_SPLIT
#define LIVE_PHASE_SPLIT 0
#endif
static live_phase_stats lp;
static uint32_t lp_frame[LP_COUNT];
static uint64_t lp_previous,lp_background,lp_sprites,lp_busy,lp_read,lp_write,lp_cache;
static gpu_perf_snapshot lp_before,lp_after;
static unsigned lp_frames,lp_steps,lp_step_total,lp_worst_tick,lp_worst_steps;
static const gpu_command *lp_scene;
static uint64_t lp_begin(void) {return LIVE_PHASE_TIMING?gpu_platform_cycles():0;}
static void lp_end(unsigned phase,uint64_t begin) {
 if(LIVE_PHASE_TIMING) lp_frame[phase]+=(uint32_t)(gpu_platform_cycles()-begin);
}
#define LP_CALL(phase,call) ({ uint64_t _lp_t=lp_begin(); int _lp_e=(call); lp_end(phase,_lp_t); _lp_e; })
#define LP_VOID(phase,call) do {uint64_t _lp_t=lp_begin(); call; lp_end(phase,_lp_t);} while(0)
static int lp_build(const bullet_state *s,uint32_t dst,int net,int glow,unsigned cap,bullet_stream *out) {
 int e=LP_CALL(LP_BUILD,game_build(s,dst,net,glow,cap,out));lp_scene=out->commands;return e;
}
static int lp_advance(v3_runtime *r,const game_input *input,uint32_t elapsed) {
 int e=LP_CALL(LP_LOGIC,v3_runtime_advance(r,input,elapsed));if(e>=0) lp_steps+=(unsigned)e;return e;
}
static int lp_snapshot(gpu_device *d,gpu_perf_snapshot *s,const char *name) {
 int e=LP_CALL(LP_SNAPSHOT,gpu_read_perf_snapshot(d,s));
 if(!e && !strcmp(name,"&before")) lp_before=*s;
 if(!e && !strcmp(name,"&after")) lp_after=*s;
 return e;
}
static int lp_render(gpu_device *d,const gpu_command *c,unsigned n,uint32_t polls) {
 int is_scene=c==lp_scene;
 uint64_t t=lp_begin();int e;
 if(LIVE_PHASE_SPLIT && is_scene) {
  if(!n || c->op!=GPU_OP_COPY) return GPU_DRIVER_ARGUMENT;
  uint64_t bg=gpu_platform_cycles();e=perf_render_gpu(d,c,1,polls);
  uint64_t end=gpu_platform_cycles();if(lp_frames>=30) lp_background+=end-bg;
  if(!e) e=perf_render_gpu(d,c+1,n-1,polls);
  if(lp_frames>=30) lp_sprites+=gpu_platform_cycles()-end;
 } else e=perf_render_gpu(d,c,n,polls);
 lp_end(is_scene?LP_SCENE:LP_HUD_COPY,t);return e;
}
static int lp_present(gpu_device *d,framebuffer_pair *pair,uint32_t polls) {
 uint64_t start=gpu_platform_cycles();
 int e=framebuffer_present(d,pair,polls);uint64_t end=gpu_platform_cycles();
 /* First PRESENT is the unchanged blank-front startup, not a game frame. */
 if(lp_previous && !e) {
  ++lp_frames;
  if(lp_frames>30) {
   uint32_t work=(uint32_t)(start-lp_previous);
   if(work>lp.max_work) {
    const v3_runtime *r=(const v3_runtime *)(uintptr_t)0x02d00000u;
    lp_worst_tick=r->game.tick;lp_worst_steps=lp_steps;
   }
   if(live_phase_record(&lp,lp_frame,work,(uint32_t)(end-lp_previous),BSP_CLINT_HZ/60u))
    return GPU_DRIVER_ARGUMENT;
   lp_busy+=lp_after.cycles-lp_before.cycles;
   lp_read+=lp_after.read_bytes-lp_before.read_bytes;
   lp_write+=lp_after.write_bytes-lp_before.write_bytes;
   lp_cache+=lp_after.cache_bytes-lp_before.cache_bytes;
   lp_step_total+=lp_steps;
  }
 }
 memset(lp_frame,0,sizeof lp_frame);lp_steps=0;lp_previous=end;return e;
}
static unsigned lp_us(uint64_t t,unsigned n) {return (unsigned)(t/((uint64_t)n*(BSP_CLINT_HZ/1000000u)));}
static void lp_report(void) {
 static const char *names[]={"CONTROL","LOGIC","BUILD","SYNC","SCENE","HUD_UPDATE","HUD_COPY","SNAPSHOT","OTHER"};
 for(unsigned i=1;i<lp.frames;i++) {
  uint32_t value=lp.samples[i];unsigned j=i;
  while(j && lp.samples[j-1]>value) {lp.samples[j]=lp.samples[j-1];--j;}
  lp.samples[j]=value;
 }
 bsp_printf("LIVE_PHASE,target=%d,timing=%d,split=%d,frames=%d,fps_x10=%d,work_us=%d,p95_us=%d,max_us=%d,miss=%d,late=%d,logic_steps=%d,worst_tick=%d,worst_steps=%d\r\n",
  V3_START_COUNT,LIVE_PHASE_TIMING,LIVE_PHASE_SPLIT,lp.frames,
  (uint32_t)((uint64_t)lp.frames*BSP_CLINT_HZ*10u/lp.wall),lp_us(lp.work,lp.frames),
  lp_us(lp.samples[(lp.frames*95u+99u)/100u-1u],1),lp_us(lp.max_work,1),lp.misses,lp.late,
  lp_step_total,lp_worst_tick,lp_worst_steps);
 for(unsigned i=0;i<LP_COUNT;i++) bsp_printf("LIVE_STAGE,name=%s,mean_us=%d,max_us=%d,worst_us=%d\r\n",
  names[i],lp_us(lp.total[i],lp.frames),lp_us(lp.max[i],1),lp_us(lp.worst[i],1));
 bsp_printf("LIVE_HW,busy_us=%d,rd=%d,wr=%d,cache=%d,background_us=%d,sprites_us=%d\r\n",
  lp_us(lp_busy,lp.frames),(uint32_t)(lp_read/lp.frames),(uint32_t)(lp_write/lp.frames),
  (uint32_t)(lp_cache/lp.frames),lp_us(lp_background,lp.frames),lp_us(lp_sprites,lp.frames));
}
static void lp_log(const char *format,...) {
 /* Suppress window UART prints in BOTH control and timed cohorts. Saves RAM
  * without changing builders, telemetry, scoring or HUD updates. */
 if(!strncmp(format,"V3_PROBE_STOP",13)) {
  if(lp.frames==LP_SAMPLES) {lp_report();bsp_printf("LIVE_PHASE_STOP,result=0\r\n");}
  else bsp_printf("LIVE_PHASE_FAIL,incomplete=%d\r\n",lp.frames);
 } else if(!strncmp(format,"V3_FAIL",7) || !strncmp(format,"V3_PROBE_HEALTH_FAIL",20))
  bsp_printf("LIVE_PHASE_FAIL,firmware=1\r\n");
}
/* Avoid linking 4-card painting into the RAM-limited terminal probe. */
static int lp_no_menu(gpu_device *d,game_menu_cache *c,unsigned b,uint32_t dst,uint32_t gen,int net,hud_command_stream *scratch,uint32_t polls) {
 (void)d;(void)c;(void)b;(void)dst;(void)gen;(void)net;(void)scratch;(void)polls;return GPU_DRIVER_ARGUMENT;
}
#define game_build lp_build
#define v3_runtime_advance lp_advance
#define gpu_read_perf_snapshot(d,s) lp_snapshot(d,s,#s)
#define perf_render_gpu lp_render
#define framebuffer_present lp_present
#define gpu_platform_sync() LP_VOID(LP_SYNC,gpu_platform_sync())
#define hud_update_gpu_cache(...) LP_CALL(LP_HUD_UPDATE,hud_update_gpu_cache(__VA_ARGS__))
#define nc_poll(...) LP_CALL(LP_CONTROL,nc_poll(__VA_ARGS__))
#define nc_try_publish(...) LP_CALL(LP_CONTROL,nc_try_publish(__VA_ARGS__))
#define game_menu_draw lp_no_menu
#define bsp_printf lp_log
#include "../src/v3_demo.c"
