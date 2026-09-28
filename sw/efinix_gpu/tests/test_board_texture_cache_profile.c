#include "bullet_demo.h"
#include "framebuffer.h"
#include "perf_demo.h"
#include "bsp.h"
#include "vexriscv.h"

uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}

static bullet_state state;
static bullet_stream scene;
static gpu_command filtered[BULLET_MAX_COMMANDS];

static int stage(gpu_device *gpu,const char *name,const gpu_command *commands,
                 unsigned count,unsigned tier,unsigned tick) {
 int e=gpu_clear_perf(gpu); if(e) return e;
 gpu_platform_sync();
 uint64_t start=gpu_platform_cycles();
 e=perf_render_gpu(gpu,commands,count,10000000u);
 gpu_platform_sync();
 uint32_t us=(uint32_t)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u));
 if(e) return e;
 gpu_perf_snapshot perf;
 e=gpu_read_perf_snapshot(gpu,&perf); if(e) return e;
 uint32_t status=*(volatile uint32_t *)(uintptr_t)(GPU_APB_BASE+GPU_REG_TEXTURE_CACHE_STATUS);
 bsp_printf("TEXTURE_PROFILE,%s,tier=%d,tick=%d,count=%d,us=%d,pixels=%d,rd=%d,wr=%d,stalls=%d,render_grants=%d,scan_grants=%d,under=%d,cache=%d,cache_status=%d\r\n",
  name,tier,tick,count,us,(uint32_t)perf.pixels,(uint32_t)perf.read_bytes,
  (uint32_t)perf.write_bytes,(uint32_t)perf.stalls,(uint32_t)perf.render_grants,
  (uint32_t)perf.scanout_grants,(uint32_t)perf.underflows,
  (uint32_t)perf.cache_bytes,status);
 return 0;
}

int main(void) {
 bsp_init();
 gpu_device gpu;
 int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 bullet_init_local_assets();
 gpu_platform_sync();
 e=bullet_prepare_texture_cache(&gpu,1,10000000u); if(e) return e;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 e=bullet_prepare_frame(&state,32,0,7); if(e) return e;
 e=bullet_build_frame(&state,buffers.back,0,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
 e=perf_render_gpu(&gpu,scene.commands,scene.count,10000000u); if(e) return e;
 e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
 uint64_t warm=gpu_platform_cycles();
 while(gpu_platform_cycles()-warm<BSP_CLINT_HZ/20u) {}
 static const unsigned tiers[]={32,64,128,256,512};
 static const unsigned ticks[]={0,90,180};
 for(unsigned ti=0;ti<5;ti++) for(unsigned ki=0;ki<3;ki++) {
  unsigned tier=tiers[ti],tick=ticks[ki];
  e=bullet_prepare_frame(&state,tier,tick,7); if(e) return e;
  e=bullet_build_frame(&state,buffers.back,0,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
  e=stage(&gpu,"BACKGROUND",scene.commands,1,tier,tick); if(e) return e;
  unsigned count=0;
  for(unsigned i=1;i<scene.count;i++) if(scene.commands[i].op==GPU_OP_COLOR_KEY)
   filtered[count++]=scene.commands[i];
  e=stage(&gpu,"KEY",filtered,count,tier,tick); if(e) return e;
  count=0;
  for(unsigned i=1;i<scene.count;i++) if(scene.commands[i].op==GPU_OP_ALPHA)
   filtered[count++]=scene.commands[i];
  e=stage(&gpu,"ALPHA",filtered,count,tier,tick); if(e) return e;
  e=stage(&gpu,"FULL",scene.commands,scene.count,tier,tick); if(e) return e;
  gpu_platform_sync();
  uint64_t start=gpu_platform_cycles();
  e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
  bsp_printf("TEXTURE_PROFILE,PRESENT,tier=%d,tick=%d,us=%d\r\n",tier,tick,
   (uint32_t)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u)));
 }
 bsp_printf("TEXTURE_CACHE_PROFILE_STOP,result=0,hardware=%d\r\n",gpu.hardware_error);
 return 0;
}
