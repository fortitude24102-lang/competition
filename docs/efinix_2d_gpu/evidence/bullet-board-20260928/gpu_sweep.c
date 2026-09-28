/* Terminal GPU-only benchmark; includes real production builders and helpers.
 * No CPU comparison window. First 30 frames of each tier are warm-up. */
#define main reference_main
#include "sw/efinix_gpu/src/main.c"
#undef main
int main(void) {
 bsp_init(); gpu_device gpu; int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 uint32_t session=(uint32_t)gpu_platform_cycles();
 int network_result=bullet_prepare_assets(GPU_APB_BASE,session?session:1);
 bsp_printf("GPU_SWEEP_START,network_result=%d,warmup=30,samples=300\r\n",network_result);
 if(network_result) return network_result;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 e=gpu_set_qos(&gpu,256,1536,1); if(e) return e;
 for(unsigned tier=0;tier<sizeof tiers/sizeof tiers[0];tier++) {
  e=bullet_reset(&bullets,tiers[tier],7); if(e) return e;
  hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.network_ready=1};
  perf_window window={0},total={0};
  uint64_t build_ticks=0,cache_ticks=0,hud_ticks=0,present_ticks=0,step_ticks=0;
  uint64_t previous=gpu_platform_cycles(),previous_under=0;
  for(unsigned frame=0;frame<330;frame++) {
   uint64_t start=previous;
   e=bullet_build_frame(&bullets,buffers.back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
   gpu_platform_sync(); uint64_t t=gpu_platform_cycles();
   if(frame>=30) build_ticks+=t-start;
   e=perf_render_gpu(&gpu,scene.commands,scene.count,10000000u); if(e) return e;
   gpu_platform_sync(); uint64_t render=gpu_platform_cycles()-t;
   m.sprites=(uint16_t)scene.visible; m.error_code=gpu.hardware_error;
   m.hp=bullets.hp; m.score=bullets.score; m.grazes=bullets.grazes;
   m.invulnerable=bullets.invulnerable!=0; m.game_over=bullets.hp==0;
   m.alpha_commands=(uint16_t)scene.alpha_commands;
   t=gpu_platform_cycles();
   e=hud_update_cache(&m,&hud_cache,&overlay); if(e) return e;
   gpu_platform_sync();
   if(frame>=30) cache_ticks+=gpu_platform_cycles()-t;
   t=gpu_platform_cycles();
   e=hud_cached_command(buffers.back,&hud_cache,&overlay.commands[0]); if(e) return e;
   e=perf_render_gpu(&gpu,overlay.commands,1,10000000u); if(e) return e;
   gpu_platform_sync();
   if(frame>=30) hud_ticks+=gpu_platform_cycles()-t;
   t=gpu_platform_cycles();
   e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
   previous=gpu_platform_cycles(); uint64_t wall=previous-start;
   if(frame>=30) present_ticks+=previous-t;
   gpu_perf_snapshot counters; e=gpu_read_perf_snapshot(&gpu,&counters); if(e) return e;
   m.underflows=(uint32_t)counters.underflows;
   if(frame>=30) {
    perf_window one={.wall_ticks=wall,.render_ticks=render,.frames=1};
    uint64_t delta=counters.underflows-previous_under;
    gpu_samples[frame-30]=(benchmark_frame_sample){
     .fps=(uint16_t)(perf_fps_x10(&one,BSP_CLINT_HZ)/10u),.sprite_count=m.sprites,
     .underflow_count=(uint16_t)(delta>65535?65535:delta),.error_count=gpu.hardware_error?1:0};
    /* perf_window_add intentionally limits windows to 30; sum raw totals here. */
    total.wall_ticks+=wall; total.render_ticks+=render; ++total.frames;
   }
   previous_under=counters.underflows;
   e=perf_window_add(&window,wall,render); if(e) return e;
   if(window.frames==30) {
    m.gpu_fps_x10=perf_fps_x10(&window,BSP_CLINT_HZ);
    m.gpu_render_us=perf_render_us(&window,BSP_CLINT_HZ); m.gpu_valid=1;
    window=(perf_window){0};
   }
   t=gpu_platform_cycles();
   e=bullet_step(&bullets); if(e) return e;
   if(frame>=30) step_ticks+=gpu_platform_cycles()-t;
  }
  benchmark_run_summary summary;
  e=benchmark_summarize_run(gpu_samples,300,&summary); if(e) return e;
  /* FPS/mean calculated from 300 samples, not perf_window's bounded API. */
  unsigned fps=(unsigned)((uint64_t)BSP_CLINT_HZ*3000u/total.wall_ticks);
  unsigned us=(unsigned)(total.render_ticks/300u/(BSP_CLINT_HZ/1000000u));
  bsp_printf("GPU_SWEEP,target=%d,frames=300,fps_x10=%d,render_us=%d,p5_fps=%d,underflows=%d,errors=%d,qualified=%d\r\n",
   tiers[tier],fps,us,summary.p5_fps,summary.total_underflows,summary.total_errors,summary.stable_sprite_count!=0);
  unsigned divisor=300u*(BSP_CLINT_HZ/1000000u);
  bsp_printf("GPU_SWEEP_PHASE,target=%d,build_including_previous_step_us=%d,cache_us=%d,hud_dma_us=%d,present_us=%d,step_us=%d\r\n",
   tiers[tier],(unsigned)(build_ticks/divisor),(unsigned)(cache_ticks/divisor),
   (unsigned)(hud_ticks/divisor),(unsigned)(present_ticks/divisor),(unsigned)(step_ticks/divisor));
 }
 bsp_printf("GPU_SWEEP_STOP,result=0,hardware=%d\r\n",gpu.hardware_error);
 return 0;
}
