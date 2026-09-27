#include "benchmark.h"
#include "framebuffer.h"
#include "hud.h"
#include "perf_demo.h"
#include "network_assets.h"
#include "bullet_demo.h"
#include "bsp.h"
#include "gpio.h"
#include "vexriscv.h"

uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 /* Official Sapphire lacks optional CSR 0x810. Retain its verified cache path. */
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
/* Command buffers live in BSS: the official linker provides only a 4 KiB stack. */
#ifndef BULLET_DEMO_DEFAULT
#define BULLET_DEMO_DEFAULT 1
#endif
#if BULLET_DEMO_DEFAULT
static bullet_stream scene;
static bullet_state bullets,window_start;
static hud_raster_cache hud_cache;
static const unsigned tiers[]={32,64,128,256,512};
#else
static perf_stream scene;
static const unsigned tiers[]={16,32,64,96,128,192,256};
#endif
static hud_command_stream overlay;
static benchmark_frame_sample gpu_samples[BENCHMARK_FRAME_COUNT];

#ifdef V2_PROFILE
/* Keep main's phase diagnostic, selecting the same scene as normal firmware.
 * Reuse the HUD scratch only in this terminal diagnostic path. */
static int profile_stage(gpu_device *gpu,const char *name,const gpu_command *commands,unsigned count) {
 gpu_perf_snapshot hw;
 int e=gpu_clear_perf(gpu); if(e) return e;
 gpu_platform_sync();
 uint64_t t=gpu_platform_cycles();
 e=perf_render_gpu(gpu,commands,count,10000000u);
 gpu_platform_sync();
 uint32_t us=(uint32_t)((gpu_platform_cycles()-t)/(BSP_CLINT_HZ/1000000u));
 if(e) return e;
 e=gpu_read_perf_snapshot(gpu,&hw); if(e) return e;
 bsp_printf("PROFILE,%s,count=%d,us=%d,pixels=%d,rd=%d,wr=%d,stalls=%d,render_grants=%d,scan_grants=%d,under=%d\r\n",
  name,count,us,(uint32_t)hw.pixels,(uint32_t)hw.read_bytes,(uint32_t)hw.write_bytes,
  (uint32_t)hw.stalls,(uint32_t)hw.render_grants,(uint32_t)hw.scanout_grants,(uint32_t)hw.underflows);
 return 0;
}
static int profile_run(gpu_device *gpu,framebuffer_pair *buffers,int network) {
 for(unsigned trial=0;trial<3;trial++) {
#if BULLET_DEMO_DEFAULT
  int e=bullet_prepare_frame(&bullets,32,trial,7); if(e) return e;
  e=bullet_build_frame(&bullets,buffers->back,network,1,BULLET_MAX_COMMANDS,&scene);
#else
  int e=perf_build_frame(buffers->back,32,trial,network,&scene);
#endif
  if(e) return e;
  e=profile_stage(gpu,"BACKGROUND",scene.commands,1); if(e) return e;
  unsigned count=0;
  for(unsigned i=1;i<scene.count;i++) if(scene.commands[i].op==GPU_OP_COLOR_KEY) {
   if(count>=HUD_MAX_COMMANDS) return GPU_DRIVER_FULL;
   overlay.commands[count++]=scene.commands[i];
  }
  e=profile_stage(gpu,"KEY",overlay.commands,count); if(e) return e;
  count=0;
  for(unsigned i=1;i<scene.count;i++) if(scene.commands[i].op==GPU_OP_ALPHA) {
   if(count>=HUD_MAX_COMMANDS) return GPU_DRIVER_FULL;
   overlay.commands[count++]=scene.commands[i];
  }
  e=profile_stage(gpu,"ALPHA",overlay.commands,count); if(e) return e;
  e=profile_stage(gpu,"FULL",scene.commands,scene.count); if(e) return e;
  gpu_platform_sync();
  uint64_t t=gpu_platform_cycles();
  e=framebuffer_present(gpu,buffers,10000000u); if(e) return e;
  bsp_printf("PROFILE,PRESENT,us=%d\r\n",(uint32_t)((gpu_platform_cycles()-t)/(BSP_CLINT_HZ/1000000u)));
 }
 return 0;
}
#endif

int main(void) {
 bsp_init();
 gpu_device gpu;
 int e=gpu_init(&gpu,GPU_APB_BASE);
 if(e) { bsp_printf("GPU unavailable: %d\r\n",e); return 1; }
 uint32_t session=(uint32_t)gpu_platform_cycles();
#if BULLET_DEMO_DEFAULT
 int network_result=bullet_prepare_assets(GPU_APB_BASE,session?session:1);
#else
 int network_result=network_assets_load(GPU_APB_BASE,session?session:1);
#endif
 int network=network_result==0;
 /* Disjoint from every network destination, including a partially loaded scene. */
#if BULLET_DEMO_DEFAULT
 /* Network preparation regenerates disjoint local assets on every failure. */
 e=bullet_reset(&bullets,tiers[0],7); if(e) return 1;
 window_start=bullets;
#else
 perf_init_local_assets();
#endif
 gpu_platform_sync();
 framebuffer_pair buffers; framebuffer_init(&buffers);
#ifdef V2_PROFILE
 bsp_printf("V2 profile: scene=%s network_result=%d, target=32\r\n",
  BULLET_DEMO_DEFAULT?"BULLET":"LEGACY",network_result);
 int profile_result=profile_run(&gpu,&buffers,network);
 bsp_printf("V2 profile stopped: result=%d hardware=%d\r\n",profile_result,gpu.hardware_error);
 return profile_result!=0;
#endif
 perf_window samples[2]={{0},{0}};
 hud_comparison metrics={.network_ready=(uint8_t)network};
#if BULLET_DEMO_DEFAULT
 metrics.bullet_demo=1;
 metrics.gameplay=1;
 bsp_printf("SCENE BULLET: AUTO survival, HP/graze/shield/restart, deterministic replay; no physical input\r\n");
#endif
 unsigned tier=0,mode=0,frame=0,old_keys=0,gpu_frames=0;
 uint64_t previous_underflows=0;
 if((e=gpu_set_qos(&gpu,256,1536,1))) return 1;
 bsp_printf("V2 comparison: CLINT Hz=%d network_result=%d; KEY1 less KEY2 more\r\n",BSP_CLINT_HZ,network_result);
 uint64_t previous_present=gpu_platform_cycles();
 for(;;) {
  uint64_t start=previous_present;
  unsigned keys=(~gpio_getInput(SYSTEM_GPIO_0_IO_CTRL))&3u;
  unsigned pressed=keys&~old_keys; old_keys=keys;
  unsigned next=tier;
  if((pressed&1u) && next) --next;
  if((pressed&2u) && next+1<sizeof tiers/sizeof tiers[0]) ++next;
  if(next!=tier) {
   tier=next; mode=0; frame=0; gpu_frames=0;
   samples[0]=(perf_window){0}; samples[1]=(perf_window){0};
   metrics.cpu_valid=metrics.gpu_valid=0;
#if BULLET_DEMO_DEFAULT
   e=bullet_reset(&bullets,tiers[tier],7); if(e) break;
   window_start=bullets;
#endif
  }
  if(mode && frame==0) {
   gpu_perf_snapshot baseline;
   e=gpu_read_perf_snapshot(&gpu,&baseline); if(e) break;
   previous_underflows=baseline.underflows;
  }
#if BULLET_DEMO_DEFAULT
  e=bullet_build_frame(&bullets,buffers.back,network,1,BULLET_MAX_COMMANDS,&scene);
#else
  e=perf_build_frame(buffers.back,tiers[tier],frame,network,&scene);
#endif
  if(e) break;
  gpu_platform_sync();
  uint64_t render_start=gpu_platform_cycles();
  e=mode?perf_render_gpu(&gpu,scene.commands,scene.count,10000000u):
   perf_render_cpu(scene.commands,scene.count);
  gpu_platform_sync();
  uint64_t render=gpu_platform_cycles()-render_start;
  if(e) break;
  metrics.sprites=(uint16_t)tiers[tier]; metrics.gpu_active=(uint8_t)mode;
#if BULLET_DEMO_DEFAULT
  metrics.sprites=(uint16_t)scene.visible;
  metrics.error_code=gpu.hardware_error;
  metrics.hp=bullets.hp; metrics.score=bullets.score; metrics.grazes=bullets.grazes;
  metrics.invulnerable=bullets.invulnerable!=0; metrics.game_over=bullets.hp==0;
  metrics.alpha_commands=(uint16_t)scene.alpha_commands;
#endif
#if BULLET_DEMO_DEFAULT
  e=hud_update_cache(&metrics,&hud_cache,&overlay); if(e) break;
  gpu_platform_sync();
  e=hud_cached_command(buffers.back,&hud_cache,&overlay.commands[0]); if(e) break;
  overlay.count=1;
#else
  e=hud_build_comparison(buffers.back,&metrics,&overlay); if(e) break;
#endif
  /* Identical CPU HUD work in both modes, outside the scene render measurement. */
  e=perf_render_cpu(overlay.commands,overlay.count); if(e) break;
  gpu_platform_sync();
  e=framebuffer_present(&gpu,&buffers,10000000u); if(e) break;
  previous_present=gpu_platform_cycles();
  uint64_t wall=previous_present-start;
  e=perf_window_add(&samples[mode],wall,render); if(e) break;
  if(mode) {
   gpu_perf_snapshot counters;
   e=gpu_read_perf_snapshot(&gpu,&counters); if(e) break;
   perf_window one={.wall_ticks=wall,.render_ticks=render,.frames=1};
   uint32_t fps=perf_fps_x10(&one,BSP_CLINT_HZ)/10u;
   uint64_t delta=counters.underflows-previous_underflows;
   previous_underflows=counters.underflows;
#if BULLET_DEMO_DEFAULT
   metrics.underflows=counters.underflows>UINT32_MAX?UINT32_MAX:(uint32_t)counters.underflows;
#endif
   gpu_samples[gpu_frames++]=(benchmark_frame_sample){
    .fps=(uint16_t)(fps>UINT16_MAX?UINT16_MAX:fps),.sprite_count=metrics.sprites,
    .underflow_count=(uint16_t)(delta>UINT16_MAX?UINT16_MAX:delta),.error_count=gpu.hardware_error?1:0};
   if(gpu_frames==BENCHMARK_FRAME_COUNT) {
    benchmark_run_summary summary;
    e=benchmark_summarize_run(gpu_samples,BENCHMARK_FRAME_COUNT,&summary); if(e) break;
#if BULLET_DEMO_DEFAULT
    bsp_printf("BULLET_GPU_300,target=%d,frames=300,p5_fps=%d,underflows=%d,errors=%d,windowed_60fps=%d\r\n",
#else
    bsp_printf("GPU_300,n=%d,frames=300,p5_fps=%d,underflows=%d,errors=%d,qualified_60fps=%d\r\n",
#endif
     tiers[tier],summary.p5_fps,summary.total_underflows,summary.total_errors,summary.stable_sprite_count!=0);
    gpu_frames=0;
   }
  }
#if BULLET_DEMO_DEFAULT
  e=bullet_step(&bullets); if(e) break;
#endif
  ++frame;
  if(frame==PERF_WINDOW_FRAMES) {
   uint32_t fps=perf_fps_x10(&samples[mode],BSP_CLINT_HZ);
   uint32_t us=perf_render_us(&samples[mode],BSP_CLINT_HZ);
   if(mode) { metrics.gpu_fps_x10=fps; metrics.gpu_render_us=us; metrics.gpu_valid=1; }
   else { metrics.cpu_fps_x10=fps; metrics.cpu_render_us=us; metrics.cpu_valid=1; }
#if BULLET_DEMO_DEFAULT
   bsp_printf("BULLET_PERF,mode=%s,target=%d,frames=%d,fps_x10=%d,render_us=%d\r\n",
#else
   bsp_printf("PERF,mode=%s,n=%d,frames=%d,fps_x10=%d,render_us=%d\r\n",
#endif
    mode?"GPU":"CPU",tiers[tier],frame,fps,us);
   /* Replay the exact state sequence, not frame-time-dependent trajectories. */
#if BULLET_DEMO_DEFAULT
   e=bullet_finish_window(&bullets,&window_start,(int)mode); if(e) break;
#endif
   samples[mode]=(perf_window){0}; mode^=1u; frame=0;
  }
 }
 bsp_printf("V2 comparison stopped: result=%d hardware=%d\r\n",e,gpu.hardware_error);
 return 1;
}
