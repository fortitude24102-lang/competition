/* Continuous GPU-only diagnostic, not the ordinary CPU/GPU comparison.
 * Reuses main's production state, helpers and frame timing boundary. */
#define main reference_main
#include "../src/main.c"
#undef main
int main(void) {
 bsp_init(); gpu_device gpu; int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 uint32_t session=(uint32_t)gpu_platform_cycles();
 int network_result=bullet_prepare_assets(GPU_APB_BASE,session?session:1);
 bsp_printf("GLYPH_SWEEP_START,network_result=%d,warmup=30,samples=300\r\n",network_result);
 if(network_result) return network_result;
 hud_init_glyph_atlas(); gpu_platform_sync();
 e=bullet_prepare_texture_cache(&gpu,network_result,10000000u); if(e) return e;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 e=gpu_set_qos(&gpu,256,1536,1); if(e) return e;
 for(unsigned tier=0;tier<sizeof tiers/sizeof tiers[0];tier++) {
  e=bullet_reset(&bullets,tiers[tier],7); if(e) return e;
  hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.network_ready=1};
  /* CPU numbers intentionally unmeasured in this terminal diagnostic. */
  perf_window window={0};
  uint64_t wall_ticks=0,render_ticks=0,cache_ticks=0,hud_ticks=0,present_ticks=0;
  uint64_t previous=gpu_platform_cycles(),previous_under=0;
  uint32_t max_cache_us=0,max_render_us=0,max_before_present_us=0;
  for(unsigned frame=0;frame<330;frame++) {
   uint64_t start=previous;
   e=bullet_build_frame(&bullets,buffers.back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
   e=bullet_clip_background_for_hud(&scene,HUD_CACHE_HEIGHT); if(e) return e;
   gpu_platform_sync(); uint64_t t=gpu_platform_cycles();
   e=perf_render_gpu(&gpu,scene.commands,scene.count,10000000u); if(e) return e;
   gpu_platform_sync(); uint64_t render=gpu_platform_cycles()-t;
   m.sprites=(uint16_t)scene.visible; m.error_code=gpu.hardware_error;
   m.hp=bullets.hp; m.score=bullets.score; m.grazes=bullets.grazes;
   m.invulnerable=bullets.invulnerable!=0; m.game_over=bullets.hp==0;
   m.alpha_commands=(uint16_t)scene.alpha_commands;
   t=gpu_platform_cycles();
   e=hud_update_gpu_cache(&gpu,&m,&hud_cache,&overlay,10000000u); if(e) return e;
   gpu_platform_sync(); uint64_t cache_time=gpu_platform_cycles()-t;
   t=gpu_platform_cycles();
   e=hud_cached_command(buffers.back,&hud_cache,&overlay.commands[0]); if(e) return e;
   e=perf_render_gpu(&gpu,overlay.commands,1,10000000u); if(e) return e;
   gpu_platform_sync(); uint64_t hud_time=gpu_platform_cycles()-t;
   uint32_t work_us=(uint32_t)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u));
   t=gpu_platform_cycles();
   e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
   previous=gpu_platform_cycles(); uint64_t wall=previous-start;
   uint64_t present_time=previous-t;
   gpu_perf_snapshot counters; e=gpu_read_perf_snapshot(&gpu,&counters); if(e) return e;
   m.underflows=(uint32_t)counters.underflows;
   if(frame>=30) {
    perf_window one={.wall_ticks=wall,.render_ticks=render,.frames=1};
    uint64_t delta=counters.underflows-previous_under;
    gpu_samples[frame-30]=(benchmark_frame_sample){
     .fps=(uint16_t)(perf_fps_x10(&one,BSP_CLINT_HZ)/10u),.sprite_count=m.sprites,
     .underflow_count=(uint16_t)(delta>65535?65535:delta),.error_count=gpu.hardware_error?1:0};
    wall_ticks+=wall; render_ticks+=render; cache_ticks+=cache_time;
    hud_ticks+=hud_time; present_ticks+=present_time;
    uint32_t cache_us=(uint32_t)(cache_time/(BSP_CLINT_HZ/1000000u));
    uint32_t render_us=(uint32_t)(render/(BSP_CLINT_HZ/1000000u));
    if(cache_us>max_cache_us) max_cache_us=cache_us;
    if(render_us>max_render_us) max_render_us=render_us;
    if(work_us>max_before_present_us) max_before_present_us=work_us;
   }
   previous_under=counters.underflows;
   e=perf_window_add(&window,wall,render); if(e) return e;
   if(window.frames==30) {
    m.gpu_fps_x10=perf_fps_x10(&window,BSP_CLINT_HZ);
    m.gpu_render_us=perf_render_us(&window,BSP_CLINT_HZ); m.gpu_valid=1;
    window=(perf_window){0};
   }
   e=bullet_step(&bullets); if(e) return e;
  }
  benchmark_run_summary summary;
  e=benchmark_summarize_run(gpu_samples,300,&summary); if(e) return e;
  unsigned divisor=300u*(BSP_CLINT_HZ/1000000u);
  bsp_printf("GLYPH_SWEEP,target=%d,frames=300,fps_x10=%d,render_us=%d,p5_fps=%d,underflows=%d,errors=%d,qualified=%d\r\n",
   tiers[tier],(unsigned)((uint64_t)BSP_CLINT_HZ*3000u/wall_ticks),(unsigned)(render_ticks/divisor),
   summary.p5_fps,summary.total_underflows,summary.total_errors,summary.stable_sprite_count!=0);
  bsp_printf("GLYPH_SWEEP_PHASE,target=%d,cache_us=%d,hud_dma_us=%d,present_us=%d,max_cache_us=%d,max_render_us=%d,max_before_present_us=%d\r\n",
   tiers[tier],(unsigned)(cache_ticks/divisor),(unsigned)(hud_ticks/divisor),(unsigned)(present_ticks/divisor),
   max_cache_us,max_render_us,max_before_present_us);
 }
 bsp_printf("GLYPH_SWEEP_STOP,result=0,hardware=%d\r\n",gpu.hardware_error);
 return 0;
}
