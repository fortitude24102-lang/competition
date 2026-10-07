/* Throwaway diagnostic firmware: no CPU/render algorithm/RTL changes.
 * Five tiers, uninstrumented control + timed submission on identical replay.
 * HW busy overlaps CPU submission and includes queue/DDR waits; never add them.
 * Split-stage runs preserve command order but intentionally break pipelining. */
#define main reference_main
#include "../src/main.c"
#undef main
#include <limits.h>
#include "submit_probe.h"
#include "damage_acceptance.h"
static uint64_t probe_clock(void) { return gpu_platform_cycles(); }
#define PHASE_SAMPLES 300u
#define GPU_CLOCK_HZ 100000000u
enum { BUILD,SYNC,SCENE,SUBMIT,BLOCKED,TAIL,HARDWARE,STALL,CACHE,HUD,PRESENT,STEP,WORK,WALL,PHASE_COUNT };
static uint64_t totals[PHASE_COUNT];
static uint32_t work_samples[PHASE_SAMPLES];
static unsigned phase_us(uint64_t ticks,unsigned samples) {
 return (unsigned)(ticks/((uint64_t)samples*(BSP_CLINT_HZ/1000000u)));
}
static unsigned percentile_work(unsigned percentile) {
 /* Insertion sort only AFTER timed frames: small diagnostic scratch. */
 for(unsigned i=1;i<PHASE_SAMPLES;i++) {
  uint32_t v=work_samples[i]; unsigned j=i;
  while(j && work_samples[j-1]>v) { work_samples[j]=work_samples[j-1]; --j; }
  work_samples[j]=v;
 }
 return work_samples[(PHASE_SAMPLES*percentile+99u)/100u-1u];
}
/* Keep the diagnostic entry out-of-line in every driver variant. Otherwise
 * GCC may inline only one cohort into main, confounding submit comparisons. */
static __attribute__((noinline)) int continuous(gpu_device *gpu,framebuffer_pair *buffers,unsigned target,int enabled) {
 int e=bullet_reset(&bullets,target,7); if(e) return e;
 hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.network_ready=1};
 perf_window window={0};
 for(unsigned i=0;i<PHASE_COUNT;i++) totals[i]=0;
 uint64_t previous=gpu_platform_cycles(),previous_under=0,read_bytes=0,write_bytes=0,cache_bytes=0;
 unsigned commands=0,blocked_calls=0,min_visible=UINT_MAX,max_visible=0,missed=0,cadence_missed=0;
 for(unsigned frame=0;frame<30u+PHASE_SAMPLES;frame++) {
  uint64_t v[PHASE_COUNT]={0},t=gpu_platform_cycles();
  e=bullet_build_frame(&bullets,buffers->back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
  e=bullet_clip_background_for_hud(&scene,HUD_CACHE_HEIGHT); if(e) return e;
  v[BUILD]=gpu_platform_cycles()-t;
  gpu_perf_snapshot before,after,done;
  e=gpu_read_perf_snapshot(gpu,&before); if(e) return e;
  t=gpu_platform_cycles(); gpu_platform_sync(); v[SYNC]=gpu_platform_cycles()-t;
  submit_probe=(submit_probe_stats){0}; submit_probe_enabled=enabled;
  t=gpu_platform_cycles();
  e=perf_render_gpu(gpu,scene.commands,scene.count,10000000u); if(e) return e;
  gpu_platform_sync(); v[SCENE]=gpu_platform_cycles()-t;
  submit_probe_enabled=0;
  v[SUBMIT]=submit_probe.submit_ticks; v[BLOCKED]=submit_probe.blocked_ticks;
  v[TAIL]=submit_probe.wait_ticks;
  e=gpu_read_perf_snapshot(gpu,&after); if(e) return e;
  /* Hardware and CLINT clocks are both nominal 100 MHz in this BIT. */
  v[HARDWARE]=(after.cycles-before.cycles)*BSP_CLINT_HZ/GPU_CLOCK_HZ;
  v[STALL]=(after.stalls-before.stalls)*BSP_CLINT_HZ/GPU_CLOCK_HZ;
  m.sprites=(uint16_t)scene.visible; m.error_code=gpu->hardware_error;
  m.hp=bullets.hp; m.score=bullets.score; m.grazes=bullets.grazes;
  m.invulnerable=bullets.invulnerable!=0; m.game_over=bullets.hp==0;
  m.alpha_commands=(uint16_t)scene.alpha_commands;
  t=gpu_platform_cycles();
  e=hud_update_gpu_cache(gpu,&m,&hud_cache,&overlay,10000000u); if(e) return e;
  gpu_platform_sync(); v[CACHE]=gpu_platform_cycles()-t;
  t=gpu_platform_cycles();
  e=hud_cached_command(buffers->back,&hud_cache,&overlay.commands[0]); if(e) return e;
  e=perf_render_gpu(gpu,overlay.commands,1,10000000u); if(e) return e;
  gpu_platform_sync(); v[HUD]=gpu_platform_cycles()-t;
  t=gpu_platform_cycles(); v[WORK]=t-previous;
  e=framebuffer_present(gpu,buffers,10000000u); if(e) return e;
  uint64_t end=gpu_platform_cycles(); v[PRESENT]=end-t; v[WALL]=end-previous; previous=end;
  e=gpu_read_perf_snapshot(gpu,&done); if(e) return e;
  m.underflows=(uint32_t)done.underflows;
  if(frame>=30) {
   unsigned n=frame-30;
   uint64_t delta=done.underflows-previous_under;
   perf_window one={.wall_ticks=v[WALL],.render_ticks=v[SCENE],.frames=1};
   gpu_samples[n]=(benchmark_frame_sample){
    .fps=(uint16_t)(perf_fps_x10(&one,BSP_CLINT_HZ)/10u),.sprite_count=m.sprites,
    .underflow_count=(uint16_t)(delta>UINT16_MAX?UINT16_MAX:delta),.error_count=gpu->hardware_error?1:0};
   work_samples[n]=phase_us(v[WORK],1);
   missed+=v[WORK]>BSP_CLINT_HZ/60u;
   cadence_missed+=v[WALL]>BSP_CLINT_HZ/60u;
   commands+=scene.count; blocked_calls+=submit_probe.blocked_calls;
   if(scene.visible<min_visible) min_visible=scene.visible;
   if(scene.visible>max_visible) max_visible=scene.visible;
   read_bytes+=after.read_bytes-before.read_bytes; write_bytes+=after.write_bytes-before.write_bytes;
   cache_bytes+=after.cache_bytes-before.cache_bytes;
  }
  previous_under=done.underflows;
  e=perf_window_add(&window,v[WALL],v[SCENE]); if(e) return e;
  if(window.frames==30) {
   m.gpu_fps_x10=perf_fps_x10(&window,BSP_CLINT_HZ);
   m.gpu_render_us=perf_render_us(&window,BSP_CLINT_HZ); m.gpu_valid=1;
   window=(perf_window){0};
  }
  t=gpu_platform_cycles(); e=bullet_step(&bullets); if(e) return e;
  v[STEP]=gpu_platform_cycles()-t;
  if(frame>=30) for(unsigned i=0;i<PHASE_COUNT;i++) totals[i]+=v[i];
 }
 benchmark_run_summary summary;
 e=benchmark_summarize_run(gpu_samples,PHASE_SAMPLES,&summary); if(e) return e;
 unsigned p95=percentile_work(95),max=work_samples[PHASE_SAMPLES-1];
 bsp_printf("RENDER_PHASE,target=%d,probe=%d,frames=300,fps_x10=%d,p5_fps=%d,underflows=%d,errors=%d,commands_x10=%d,visible_min=%d,visible_max=%d\r\n",
  target,enabled,(unsigned)((uint64_t)BSP_CLINT_HZ*PHASE_SAMPLES*10u/totals[WALL]),
  summary.p5_fps,summary.total_underflows,summary.total_errors,commands*10u/PHASE_SAMPLES,min_visible,max_visible);
 bsp_printf("RENDER_CPU,target=%d,probe=%d,build_us=%d,sync_us=%d,submit_us=%d,blocked_us=%d,nonblocked_us=%d,tail_us=%d,step_us=%d,blocked_calls_x10=%d\r\n",
  target,enabled,phase_us(totals[BUILD],PHASE_SAMPLES),phase_us(totals[SYNC],PHASE_SAMPLES),
  phase_us(totals[SUBMIT],PHASE_SAMPLES),phase_us(totals[BLOCKED],PHASE_SAMPLES),
  phase_us(totals[SUBMIT]-totals[BLOCKED],PHASE_SAMPLES),phase_us(totals[TAIL],PHASE_SAMPLES),
  phase_us(totals[STEP],PHASE_SAMPLES),blocked_calls*10u/PHASE_SAMPLES);
 bsp_printf("RENDER_GPU,target=%d,probe=%d,scene_us=%d,busy_us=%d,stall_us=%d,rd_bytes=%d,wr_bytes=%d,cache_bytes=%d\r\n",
  target,enabled,phase_us(totals[SCENE],PHASE_SAMPLES),phase_us(totals[HARDWARE],PHASE_SAMPLES),
  phase_us(totals[STALL],PHASE_SAMPLES),(unsigned)(read_bytes/PHASE_SAMPLES),
  (unsigned)(write_bytes/PHASE_SAMPLES),(unsigned)(cache_bytes/PHASE_SAMPLES));
 bsp_printf("RENDER_FRAME,target=%d,probe=%d,hud_cache_us=%d,hud_copy_us=%d,present_us=%d,work_us=%d,work_p95_us=%d,work_max_us=%d,missed=%d\r\n",
  target,enabled,phase_us(totals[CACHE],PHASE_SAMPLES),phase_us(totals[HUD],PHASE_SAMPLES),
  phase_us(totals[PRESENT],PHASE_SAMPLES),phase_us(totals[WORK],PHASE_SAMPLES),p95,max,missed);
 bsp_printf("RENDER_CADENCE,target=%d,probe=%d,late_present=%d,qualified=%d,stable=%d\r\n",
  target,enabled,cadence_missed,damage_run_qualified(&summary,PHASE_SAMPLES,missed,cadence_missed),
  summary.stable_sprite_count);
 return summary.total_errors || summary.total_underflows ? GPU_DRIVER_HARDWARE : 0;
}
#ifndef RENDER_VALIDATION_COHORT
static int isolated(gpu_device *gpu,const char *name,const gpu_command *commands,unsigned count,unsigned target,unsigned tick) {
 gpu_perf_snapshot before,after;
 int e=gpu_read_perf_snapshot(gpu,&before); if(e) return e;
 gpu_platform_sync(); submit_probe=(submit_probe_stats){0}; submit_probe_enabled=1;
 uint64_t t=gpu_platform_cycles();
 e=perf_render_gpu(gpu,commands,count,10000000u); if(e) return e;
 gpu_platform_sync(); uint64_t wall=gpu_platform_cycles()-t; submit_probe_enabled=0;
 e=gpu_read_perf_snapshot(gpu,&after); if(e) return e;
 bsp_printf("RENDER_ISOLATED,stage=%s,target=%d,tick=%d,count=%d,wall_us=%d,busy_us=%d,submit_us=%d,blocked_us=%d,tail_us=%d,stall_us=%d,rd=%d,wr=%d,cache=%d,under=%d\r\n",
  name,target,tick,count,phase_us(wall,1),phase_us(after.cycles-before.cycles,1),
  phase_us(submit_probe.submit_ticks,1),phase_us(submit_probe.blocked_ticks,1),phase_us(submit_probe.wait_ticks,1),
  phase_us(after.stalls-before.stalls,1),(unsigned)(after.read_bytes-before.read_bytes),
  (unsigned)(after.write_bytes-before.write_bytes),(unsigned)(after.cache_bytes-before.cache_bytes),
  (unsigned)(after.underflows-before.underflows));
 return after.underflows!=before.underflows ? GPU_DRIVER_HARDWARE : 0;
}
#endif
int main(void) {
 bsp_init(); gpu_device gpu; int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 uint32_t session=(uint32_t)gpu_platform_cycles();
 e=bullet_prepare_assets(GPU_APB_BASE,session?session:1);
 bsp_printf("RENDER_PHASE_START,network_result=%d,warmup=30,samples=300,gpu_hz=%d,clint_hz=%d\r\n",e,GPU_CLOCK_HZ,BSP_CLINT_HZ);
 if(e) goto stop;
 hud_init_glyph_atlas(); gpu_platform_sync();
 e=bullet_prepare_texture_cache(&gpu,0,10000000u); if(e) goto stop;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 e=gpu_set_qos(&gpu,256,1536,1); if(e) goto stop;
#ifdef RENDER_VALIDATION_COHORT
 /* Identical automaticR7 ticks, probesOFF, GPU driver only. Not live inputs. */
 static const unsigned targets[]={256,384,512};
#ifdef RENDER_QOS_SWEEP
 /* SAME executable and old ordered backend; adaptive protection never disabled.
  * Repeat original parameters at the end to expose drift/ordering effects. */
 static const uint16_t highs[]={1536,1024,768,512,1536};
 for(unsigned q=0;q<sizeof highs/sizeof highs[0];q++) {
  e=gpu_set_qos(&gpu,256,highs[q],1);if(e) goto stop;
  bsp_printf("QOS_COHORT,index=%d,low=256,high=%d,adaptive=1,probe=0\r\n",q,highs[q]);
  for(unsigned i=0;i<sizeof targets/sizeof targets[0];i++) {
   e=continuous(&gpu,&buffers,targets[i],0);if(e) goto stop;
  }
 }
#else
 for(unsigned i=0;i<sizeof targets/sizeof targets[0];i++) {
  e=continuous(&gpu,&buffers,targets[i],0);if(e) goto stop;
 }
#endif
#else
 static const unsigned targets[]={32,64,128,256,512},ticks[]={0,90,180};
 for(unsigned i=0;i<sizeof targets/sizeof targets[0];i++) for(int enabled=0;enabled<2;enabled++) {
  e=continuous(&gpu,&buffers,targets[i],enabled); if(e) goto stop;
 }
 for(unsigned i=0;i<sizeof targets/sizeof targets[0];i++) for(unsigned j=0;j<sizeof ticks/sizeof ticks[0];j++) {
  e=bullet_prepare_frame(&bullets,targets[i],ticks[j],7); if(e) goto stop;
  e=bullet_build_frame(&bullets,buffers.back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) goto stop;
  e=bullet_clip_background_for_hud(&scene,HUD_CACHE_HEIGHT); if(e) goto stop;
  e=isolated(&gpu,"BACKGROUND",scene.commands,1,targets[i],ticks[j]); if(e) goto stop;
  e=isolated(&gpu,"SPRITES_ORDERED",scene.commands+1,scene.count-1,targets[i],ticks[j]); if(e) goto stop;
  e=framebuffer_present(&gpu,&buffers,10000000u); if(e) goto stop;
 }
#endif
stop:
#ifdef RENDER_QOS_SWEEP
 /* Restore safe old admission settings even when a candidate failed. */
 {int restore=gpu_set_qos(&gpu,256,1536,1);if(!e) e=restore;}
 bsp_printf("QOS_SWEEP_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error);
#endif
 bsp_printf("RENDER_PHASE_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error);
 return e;
}
