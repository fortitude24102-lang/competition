/* Board-only integration check: executes real main, driver and DDR transfers.
 * A regression routing GPU-mode HUD to software fails before doing that copy.
 * Link this instead of src/main.c; stop after the first GPU HUD completion. */
#include "perf_demo.h"
#include "hud.h"
#include "bsp.h"
static unsigned scene_gpu,cpu_huds,passed,glyph_updates;
static int checked_cpu_cache(const hud_comparison *m,hud_raster_cache *cache,hud_command_stream *scratch) {
 if(scene_gpu) return GPU_DRIVER_HARDWARE;
 return hud_update_cache(m,cache,scratch);
}
static int checked_gpu_cache(gpu_device *gpu,const hud_comparison *m,hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls) {
 if(!scene_gpu) return GPU_DRIVER_HARDWARE;
 ++glyph_updates;
 return hud_update_gpu_cache(gpu,m,cache,scratch,polls);
}
static int checked_cpu(const gpu_command *commands,unsigned count) {
 if(count==1 && commands[0].src_addr==HUD_CACHE_ADDR) {
  if(scene_gpu) {
   bsp_printf("HUD_DMA_FAIL: GPU mode used CPU HUD\r\n");
   return GPU_DRIVER_HARDWARE;
  }
  ++cpu_huds;
 } else scene_gpu=0;
 return perf_render_cpu(commands,count);
}
static int checked_gpu(gpu_device *gpu,const gpu_command *commands,unsigned count,uint32_t polls) {
 if(count!=1 || commands[0].src_addr!=HUD_CACHE_ADDR) {
  scene_gpu=1;
  return perf_render_gpu(gpu,commands,count,polls);
 }
 gpu_perf_snapshot before,after;
 int e=gpu_read_perf_snapshot(gpu,&before); if(e) return e;
 e=perf_render_gpu(gpu,commands,count,polls); if(e) return e;
 e=gpu_read_perf_snapshot(gpu,&after); if(e) return e;
 /* 960x72 RGB565: 69120 pixels, 138240 bytes in each direction. */
 passed=scene_gpu && cpu_huds && glyph_updates && !gpu->hardware_error &&
  after.pixels-before.pixels==69120 &&
  after.read_bytes-before.read_bytes==138240 &&
  after.write_bytes-before.write_bytes==138240 &&
  after.underflows==before.underflows;
 bsp_printf("HUD_DMA_%s,cpu_huds=%d,pixels=%d,rd=%d,wr=%d,under=%d\r\n",
  passed?"PASS":"FAIL",cpu_huds,(uint32_t)(after.pixels-before.pixels),
  (uint32_t)(after.read_bytes-before.read_bytes),
  (uint32_t)(after.write_bytes-before.write_bytes),
  (uint32_t)(after.underflows-before.underflows));
 return GPU_DRIVER_FULL; /* Deliberately end the production loop after assertion. */
}
#define perf_render_cpu checked_cpu
#define perf_render_gpu checked_gpu
#define hud_update_cache checked_cpu_cache
#define hud_update_gpu_cache checked_gpu_cache
#define main application_main
#include "../src/main.c"
#undef main
int main(void) {
 (void)application_main();
 bsp_printf("HUD_DMA_TEST_STOP,result=%d\r\n",passed?0:1);
 return passed?0:1;
}
