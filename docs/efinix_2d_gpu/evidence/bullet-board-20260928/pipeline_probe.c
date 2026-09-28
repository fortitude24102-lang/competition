/* Temporary board probe; not a release firmware or a new rendering path. */
#define V2_PROFILE 1
#define main reference_main
#include "sw/efinix_gpu/src/main.c"
#undef main

static uint32_t elapsed_us(uint64_t start) {
 return (uint32_t)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u));
}
static int pipeline_probe(gpu_device *gpu,framebuffer_pair *buffers,int network) {
 gpu_perf_snapshot a,b,c,d;
 hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,
  .network_ready=(uint8_t)network,.sprites=(uint16_t)scene.visible,
  .hp=bullets.hp,.score=bullets.score,.grazes=bullets.grazes,
  .invulnerable=bullets.invulnerable!=0,.game_over=bullets.hp==0,
  .alpha_commands=(uint16_t)scene.alpha_commands};
 int e=gpu_clear_perf(gpu); if(e) return e;
 uint64_t t=gpu_platform_cycles();
 e=bullet_build_frame(&bullets,buffers->back,network,1,BULLET_MAX_COMMANDS,&scene);
 gpu_platform_sync(); if(e) return e;
 uint32_t build=elapsed_us(t);
 t=gpu_platform_cycles();
 e=perf_render_gpu(gpu,scene.commands,scene.count,10000000u);
 gpu_platform_sync(); if(e) return e;
 uint32_t render=elapsed_us(t);
 e=gpu_read_perf_snapshot(gpu,&a); if(e) return e;
 unsigned before=hud_cache.rebuilds;
 t=gpu_platform_cycles();
 e=hud_update_cache(&m,&hud_cache,&overlay);
 gpu_platform_sync(); if(e) return e;
 uint32_t cache=elapsed_us(t);
 e=gpu_read_perf_snapshot(gpu,&b); if(e) return e;
 t=gpu_platform_cycles();
 e=hud_cached_command(buffers->back,&hud_cache,&overlay.commands[0]); if(e) return e;
 e=perf_render_cpu(overlay.commands,1);
 gpu_platform_sync(); if(e) return e;
 uint32_t hud=elapsed_us(t);
 e=gpu_read_perf_snapshot(gpu,&c); if(e) return e;
 t=gpu_platform_cycles();
 e=framebuffer_present(gpu,buffers,10000000u); if(e) return e;
 uint32_t present=elapsed_us(t);
 e=gpu_read_perf_snapshot(gpu,&d); if(e) return e;
 bsp_printf("PIPELINE,build_us=%d,gpu_us=%d,cache_us=%d,cpu_hud_us=%d,present_us=%d,rebuild=%d,under_render=%d,under_cache=%d,under_hud=%d,under_present=%d\r\n",
  build,render,cache,hud,present,hud_cache.rebuilds-before,
  (uint32_t)a.underflows,(uint32_t)(b.underflows-a.underflows),
  (uint32_t)(c.underflows-b.underflows),(uint32_t)(d.underflows-c.underflows));
 t=gpu_platform_cycles();
 e=hud_update_cache(&m,&hud_cache,&overlay);
 gpu_platform_sync(); if(e) return e;
 bsp_printf("HUD_HIT,us=%d\r\n",elapsed_us(t));
 e=hud_cached_command(buffers->back,&hud_cache,&overlay.commands[0]); if(e) return e;
 return profile_stage(gpu,"HUD_GPU",overlay.commands,1);
}

int main(void) {
 bsp_init();
 gpu_device gpu; int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 uint32_t session=(uint32_t)gpu_platform_cycles();
 int network_result=bullet_prepare_assets(GPU_APB_BASE,session?session:1);
 bsp_printf("PIPELINE_PROBE,network_result=%d\r\n",network_result);
 if(network_result) return network_result;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 e=gpu_set_qos(&gpu,256,1536,1); if(e) return e;
 e=bullet_prepare_frame(&bullets,32,0,7); if(e) return e;
 e=bullet_build_frame(&bullets,buffers.back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
 e=perf_render_gpu(&gpu,scene.commands,scene.count,10000000u); if(e) return e;
 e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
 uint64_t warm=gpu_platform_cycles();
 while(gpu_platform_cycles()-warm<BSP_CLINT_HZ/20u) {}
 for(unsigned tier=0;tier<sizeof tiers/sizeof tiers[0];tier++) {
  for(unsigned tick=0;tick<=180;tick+=90) {
   e=bullet_prepare_frame(&bullets,tiers[tier],tick,7); if(e) return e;
   e=bullet_build_frame(&bullets,buffers.back,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
   bsp_printf("PROFILE_CASE,target=%d,tick=%d,visible=%d,count=%d,alpha_count=%d\r\n",
    tiers[tier],tick,scene.visible,scene.count,scene.alpha_commands);
   e=profile_stage(&gpu,"BACKGROUND",scene.commands,1); if(e) return e;
   unsigned count=0;
   for(unsigned i=1;i<scene.count;i++) if(scene.commands[i].op==GPU_OP_COLOR_KEY)
    overlay.commands[count++]=scene.commands[i];
   e=profile_stage(&gpu,"KEY",overlay.commands,count); if(e) return e;
   count=0;
   for(unsigned i=1;i<scene.count;i++) if(scene.commands[i].op==GPU_OP_ALPHA)
    overlay.commands[count++]=scene.commands[i];
   e=profile_stage(&gpu,"ALPHA",overlay.commands,count); if(e) return e;
   e=profile_stage(&gpu,"FULL",scene.commands,scene.count); if(e) return e;
   e=pipeline_probe(&gpu,&buffers,1); if(e) return e;
  }
 }
 bsp_printf("PIPELINE_PROBE_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error);
 return e;
}
