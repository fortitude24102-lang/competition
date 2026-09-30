/* Isolated board probe: timings exclude UART, CRC oracle and perf snapshots.
 * Uses production updater/driver; no CPU baseline or production loop changes. */
#include "hud.h"
#include "perf_demo.h"
#include "framebuffer.h"
#include "golden_renderer.h"
#include "bsp.h"
#include "vexriscv.h"
#include <string.h>
uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
static hud_command_stream scratch,oracle;
static hud_raster_cache cache;
static uint32_t micros(uint64_t start) {
 return (uint32_t)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u));
}
int main(void) {
 bsp_init(); gpu_device gpu;
 int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 e=gpu_set_qos(&gpu,256,1536,1); if(e) return e;
 hud_init_glyph_atlas(); gpu_platform_sync();
 framebuffer_pair buffers; framebuffer_init(&buffers);
 gpu_command fill={.op=GPU_OP_FILL,.dst_addr=buffers.back,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT,.color=0x18e3};
 e=perf_render_gpu(&gpu,&fill,1,10000000u); if(e) return e;
 e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
 uint64_t warm=gpu_platform_cycles();
 while(gpu_platform_cycles()-warm<BSP_CLINT_HZ/20u) {}
 hud_comparison m={.bullet_demo=1,.gameplay=1,.hp=3,.score=6,.gpu_active=1,.network_ready=1,
  .cpu_valid=1,.gpu_valid=1,.cpu_fps_x10=28,.gpu_fps_x10=563,
  .cpu_render_us=296316,.gpu_render_us=8099,.sprites=64,.alpha_commands=12};
 uint64_t start=gpu_platform_cycles();
 e=hud_update_cache(&m,&cache,&scratch); gpu_platform_sync();
 uint32_t cpu_us=micros(start); if(e) return e;
 bsp_printf("GLYPH_BASELINE,cpu_rebuild_us=%d\r\n",cpu_us);
 for(unsigned trial=0;trial<20;trial++) {
  if(trial==0) m.score=7; /* Exactly one changed digit. */
  else if(trial==1) cache.valid=0; /* Full recovery/init path. */
  else if(trial!=2) {
   m.score=trial%2?9:123456; m.grazes=trial%2?1:456;
   m.hp=(uint8_t)(trial%4); m.network_ready=(uint8_t)(trial%2);
   m.sprites=(uint16_t)(32+trial*24); m.alpha_commands=(uint16_t)(8+trial*3);
  }
  gpu_perf_snapshot before,after;
  e=gpu_read_perf_snapshot(&gpu,&before); if(e) return e;
  start=gpu_platform_cycles();
  e=hud_update_gpu_cache(&gpu,&m,&cache,&scratch,10000000u); gpu_platform_sync();
  uint32_t update_us=micros(start); if(e) return e;
  unsigned commands=scratch.count;
  e=gpu_read_perf_snapshot(&gpu,&after); if(e) return e;
  e=hud_build_comparison(buffers.back,&m,&oracle); if(e) return e;
  e=perf_render_cpu(oracle.commands,oracle.count); if(e) return e;
  gpu_platform_sync();
  if(memcmp((void *)(uintptr_t)buffers.back,(void *)(uintptr_t)HUD_CACHE_ADDR,HUD_CACHE_BYTES)) {
   bsp_printf("GLYPH_BOARD_FAIL,trial=%d,raster_mismatch=1\r\n",trial); return 1;
  }
  bsp_printf("GLYPH_UPDATE,trial=%d,us=%d,commands=%d,pixels=%d,rd=%d,wr=%d,under=%d\r\n",
   trial,update_us,commands,(uint32_t)(after.pixels-before.pixels),
   (uint32_t)(after.read_bytes-before.read_bytes),(uint32_t)(after.write_bytes-before.write_bytes),
   (uint32_t)(after.underflows-before.underflows));
 }
 bsp_printf("GLYPH_BOARD_STOP,result=0,hardware=%d\r\n",gpu.hardware_error);
 return 0;
}
