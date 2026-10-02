/* Owner diagnostic: unchanged R7 stream/HUD and retained legacy hardware.
 * Pixel oracle runs BEFORE first PRESENT; timed runs include planner + copies.
 * Full-copy control then six policies, identical seed=7 and frame sequence. */
#define main reference_main
#include "../src/main.c"
#undef main
#include <limits.h>
#include "damage_acceptance.h"
static gpu_damage_state damage;
static gpu_damage_result damage_plan;
static gpu_command reference_commands[BULLET_MAX_COMMANDS];
static uint32_t work_samples[300];
static const gpu_damage_config policies[]={
 {16,0,128,{517,64,164}},{16,2,128,{517,64,164}},{16,4,128,{517,64,164}},
 {32,0,128,{517,64,164}},{32,2,128,{517,64,164}},{32,4,128,{517,64,164}}};
static unsigned us(uint64_t ticks) { return (unsigned)(ticks/(BSP_CLINT_HZ/1000000u)); }
static int oracle(gpu_device *gpu) {
 for(unsigned policy=0;policy<6;policy++) {
  int e=gpu_damage_init(&damage,policies+policy); if(e) return e;
  e=bullet_reset(&bullets,512,7); if(e) return e;
  for(unsigned frame=0;frame<6;frame++) {
   uint32_t base=frame&1?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
   e=bullet_build_frame(&bullets,base,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
   e=bullet_clip_background_for_hud(&scene,72); if(e) return e;
   for(unsigned i=0;i<scene.count;i++) {
    reference_commands[i]=scene.commands[i];
    reference_commands[i].dst_addr+=0x02d00000u-base;
   }
   e=perf_render_gpu(gpu,reference_commands,scene.count,10000000u); if(e) return e;
   e=perf_render_gpu_damage(gpu,&damage,scene.commands,scene.count,1,&damage_plan,10000000u); if(e) return e;
   gpu_platform_sync();
   volatile uint16_t *a=(volatile uint16_t *)(uintptr_t)(base+72*1920);
   volatile uint16_t *b=(volatile uint16_t *)(uintptr_t)(0x02d00000u+72*1920);
   unsigned mismatches=0;
   for(unsigned i=0;i<960*468;i++) mismatches+=a[i]!=b[i];
   bsp_printf("DAMAGE_BOARD_ORACLE,policy=%d,frame=%d,words=449280,mismatch=%d,copies=%d,reason=%d\r\n",
    policy,frame,mismatches,damage_plan.count,damage_plan.reason);
   if(mismatches) return GPU_DRIVER_HARDWARE;
   e=bullet_step(&bullets); if(e) return e;
  }
 }
 return 0;
}
static int run(gpu_device *gpu,framebuffer_pair *buffers,int policy,unsigned target) {
 int e=bullet_reset(&bullets,target,7); if(e) return e;
 if(policy>=0) { e=gpu_damage_init(&damage,policies+policy); if(e) return e; }
 hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.network_ready=1};
 perf_window window={0};
 uint64_t total_wall=0,total_scene=0,total_work=0,total_hud=0,total_cache=0;
 uint64_t total_bytes=0,total_read=0,total_write=0,total_busy=0;
 unsigned copies=0,full=0,missed=0,cadence_missed=0,min_visible=UINT_MAX,max_visible=0;
 gpu_perf_snapshot snapshot; e=gpu_read_perf_snapshot(gpu,&snapshot); if(e) return e;
 uint64_t previous_under=snapshot.underflows,previous=gpu_platform_cycles();
 for(unsigned frame=0;frame<330;frame++) {
  uint64_t start=previous;
  e=bullet_build_frame(&bullets,buffers->back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
  e=bullet_clip_background_for_hud(&scene,72); if(e) return e;
  gpu_perf_snapshot before,after,done;
  e=gpu_read_perf_snapshot(gpu,&before); if(e) return e;
  gpu_platform_sync(); uint64_t t=gpu_platform_cycles();
  e=policy<0?perf_render_gpu(gpu,scene.commands,scene.count,10000000u):
   perf_render_gpu_damage(gpu,&damage,scene.commands,scene.count,1,&damage_plan,10000000u);
  if(e) return e;
  gpu_platform_sync(); uint64_t scene_time=gpu_platform_cycles()-t;
  e=gpu_read_perf_snapshot(gpu,&after); if(e) return e;
  m.sprites=(uint16_t)scene.visible; m.error_code=gpu->hardware_error;
  m.hp=bullets.hp; m.score=bullets.score; m.grazes=bullets.grazes;
  m.invulnerable=bullets.invulnerable!=0; m.game_over=bullets.hp==0;
  m.alpha_commands=(uint16_t)scene.alpha_commands;
  t=gpu_platform_cycles();
  e=hud_update_gpu_cache(gpu,&m,&hud_cache,&overlay,10000000u); if(e) return e;
  gpu_platform_sync(); uint64_t cache_time=gpu_platform_cycles()-t;
  t=gpu_platform_cycles();
  e=hud_cached_command(buffers->back,&hud_cache,&overlay.commands[0]); if(e) return e;
  e=perf_render_gpu(gpu,overlay.commands,1,10000000u); if(e) return e;
  gpu_platform_sync(); uint64_t hud_time=gpu_platform_cycles()-t;
  uint64_t work=gpu_platform_cycles()-start;
  e=framebuffer_present(gpu,buffers,10000000u); if(e) return e;
  previous=gpu_platform_cycles(); uint64_t wall=previous-start;
  e=gpu_read_perf_snapshot(gpu,&done); if(e) return e;
  if(frame>=30) {
   unsigned n=frame-30; uint64_t delta=done.underflows-previous_under;
   perf_window one={.wall_ticks=wall,.render_ticks=scene_time,.frames=1};
   gpu_samples[n]=(benchmark_frame_sample){.fps=(uint16_t)(perf_fps_x10(&one,BSP_CLINT_HZ)/10u),
    .sprite_count=m.sprites,.underflow_count=(uint16_t)(delta>65535?65535:delta),.error_count=!!gpu->hardware_error};
   work_samples[n]=us(work); missed+=work>BSP_CLINT_HZ/60u;
   cadence_missed+=wall>BSP_CLINT_HZ/60u;
   total_wall+=wall; total_scene+=scene_time; total_work+=work;
   total_cache+=cache_time; total_hud+=hud_time;
   total_read+=after.read_bytes-before.read_bytes; total_write+=after.write_bytes-before.write_bytes;
   total_busy+=after.cycles-before.cycles;
   copies+=policy<0?1:damage_plan.count;
   full+=policy<0?1:damage_plan.reason!=GPU_DAMAGE_PARTIAL;
   total_bytes+=policy<0?898560:damage_plan.bytes;
   if(scene.visible<min_visible) min_visible=scene.visible;
   if(scene.visible>max_visible) max_visible=scene.visible;
  }
  previous_under=done.underflows; m.underflows=(uint32_t)done.underflows;
  e=perf_window_add(&window,wall,scene_time); if(e) return e;
  if(window.frames==30) {
   m.gpu_fps_x10=perf_fps_x10(&window,BSP_CLINT_HZ);
   m.gpu_render_us=perf_render_us(&window,BSP_CLINT_HZ); m.gpu_valid=1;
   window=(perf_window){0};
  }
  e=bullet_step(&bullets); if(e) return e;
 }
 benchmark_run_summary summary; e=benchmark_summarize_run(gpu_samples,300,&summary); if(e) return e;
 for(unsigned i=1;i<300;i++) {
  uint32_t v=work_samples[i]; unsigned j=i;
  while(j && work_samples[j-1]>v) { work_samples[j]=work_samples[j-1]; --j; }
  work_samples[j]=v;
 }
 bsp_printf("DAMAGE_SWEEP,policy=%d,target=%d,frames=300,fps_x10=%d,p5_fps=%d,scene_us=%d,work_us=%d,p95_us=%d,max_us=%d,missed=%d,under=%d,errors=%d,qualified=%d\r\n",
  policy,target,(unsigned)((uint64_t)BSP_CLINT_HZ*3000u/total_wall),summary.p5_fps,
  us(total_scene/300),us(total_work/300),work_samples[284],work_samples[299],missed,
  summary.total_underflows,summary.total_errors,damage_run_qualified(&summary,300,missed,cadence_missed));
 bsp_printf("DAMAGE_CADENCE,policy=%d,target=%d,frames=300,late_present=%d,legacy_p5_qualified=%d\r\n",
  policy,target,cadence_missed,summary.stable_sprite_count!=0);
 bsp_printf("DAMAGE_TRAFFIC,policy=%d,target=%d,copies_x10=%d,full=%d,bg_bytes=%d,rd=%d,wr=%d,busy_us=%d,hud_us=%d,cache_us=%d,visible_min=%d,visible_max=%d\r\n",
  policy,target,copies*10/300,full,(unsigned)(total_bytes/300),(unsigned)(total_read/300),
  (unsigned)(total_write/300),us(total_busy/300),us(total_hud/300),us(total_cache/300),min_visible,max_visible);
 return summary.total_underflows || summary.total_errors?GPU_DRIVER_HARDWARE:0;
}
int main(void) {
 bsp_init(); gpu_device gpu; int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 e=bullet_prepare_assets(GPU_APB_BASE,1);
 bsp_printf("DAMAGE_SWEEP_START,network_result=%d,seed=7,clock=%d,warmup=30,samples=300\r\n",e,BSP_CLINT_HZ);
 if(e) goto stop;
 hud_init_glyph_atlas(); gpu_platform_sync();
 e=bullet_prepare_texture_cache(&gpu,0,10000000u); if(e) goto stop;
 e=gpu_set_qos(&gpu,256,1536,1); if(e) goto stop;
 /* Exact same planner/renderer already passed36 oracle frames in the primary
  * sweep. Lower-tier timing cohort does not repeat that unchanged oracle. */
#ifndef DAMAGE_LOWER_SWEEP
 e=oracle(&gpu); if(e) goto stop;
#else
 (void)oracle;
#endif
 framebuffer_pair buffers; framebuffer_init(&buffers);
#ifdef DAMAGE_LOWER_SWEEP
 static const unsigned lower_targets[]={64,256};
 for(unsigned k=0;k<2;k++) {
  e=run(&gpu,&buffers,-1,lower_targets[k]); if(e) goto stop;
  e=run(&gpu,&buffers,2,lower_targets[k]); if(e) goto stop;
 }
#else
 for(int policy=-1;policy<6;policy++) { e=run(&gpu,&buffers,policy,512); if(e) goto stop; }
#endif
stop:
 bsp_printf("DAMAGE_SWEEP_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error); return e;
}
