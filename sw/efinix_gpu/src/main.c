#include "assets.h"
#include "benchmark.h"
#include "framebuffer.h"
#include "game.h"
#include "hud.h"
#include "bsp.h"
#include "gpio.h"
#include "soc.h"
#include "vexriscv.h"
uint64_t gpu_platform_cycles(void) {
 uint32_t hi,lo,again;
 do { __asm__ volatile("rdcycleh %0" : "=r"(hi)); __asm__ volatile("rdcycle %0" : "=r"(lo)); __asm__ volatile("rdcycleh %0" : "=r"(again)); } while(hi!=again);
 return ((uint64_t)hi<<32)|lo;
}
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 soc_write_buffer_flush();
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
/* The official Sapphire linker reserves a 4 KiB stack. Keep bounded command
 * lists in BSS so the demo cannot overwrite its own image at runtime. */
static game_command_stream frame_commands;
static hud_command_stream hud_commands;
static benchmark_frame_sample frame_samples[BENCHMARK_FRAME_COUNT];
static int submit_hud(gpu_device *d,const hud_command_stream *s,int batch) {
 uint16_t tag=0;
 for(unsigned i=0;i<s->count;i++) {
  int e=gpu_submit(d,&s->commands[i],10000000u,&tag); if(e) return e;
  if(!batch && (e=gpu_wait_tag(d,tag,10000000u))) return e;
 }
 return batch && s->count ? gpu_wait_tag(d,tag,10000000u) : 0;
}
int main(void) {
 bsp_init(); gpu_device d; int e=gpu_init(&d,GPU_APB_BASE);
 if(e) { bsp_printf("GPU unavailable: probe=%d; integration/board test pending\r\n",e); return 1; }
 if(gpu_assets_upload_dense((volatile uint16_t *)(uintptr_t)GPU_DENSE_ASSETS,GPU_ASSET_WORDS)!=GPU_ASSET_WORDS) return 1;
 gpu_platform_sync(); framebuffer_pair buffers; framebuffer_init(&buffers); game_state game; game_init(&game);
 uint64_t previous=gpu_platform_cycles(); unsigned fps=60,busy_permille=0;
 for(unsigned frame=0;frame<300;frame++) {
  uint32_t keys=~gpio_getInput(SYSTEM_GPIO_0_IO_CTRL);
  unsigned input=(keys&1?GAME_INPUT_LEFT:0)|(keys&2?GAME_INPUT_RIGHT:0)|(keys&4?GAME_INPUT_FIRE:0);
  game_step(&game,input,16);
  int batch=frame>=150;
  uint64_t render_start=gpu_platform_cycles();
  e=game_build_commands(&game,buffers.back,&frame_commands); if(e) break;
  e=game_submit_commands(&d,&frame_commands,batch,10000000u); if(e) break;
  hud_metrics metrics={.fps=(uint16_t)(fps>999?999:fps),.sprite_count=frame_commands.sprite_count,
   .cpu_busy_permille=(uint16_t)(busy_permille>999?999:busy_permille),
   .queue_high_watermark=d.queue_high_watermark,.underflow_count=0,
   .error_code=d.hardware_error,.batch_mode=(uint8_t)batch};
  e=hud_build_metrics(buffers.back,1280,8,8,&metrics,&hud_commands); if(e) break;
  e=submit_hud(&d,&hud_commands,batch); if(e) break;
  uint64_t render_cycles=gpu_platform_cycles()-render_start;
  e=framebuffer_present(&d,&buffers,10000000u); if(e) break;
  uint64_t now=gpu_platform_cycles(),elapsed=now-previous; previous=now;
  if(elapsed) { fps=(unsigned)(100000000u/elapsed); busy_permille=(unsigned)(render_cycles*1000u/elapsed); }
  frame_samples[frame]=(benchmark_frame_sample){.fps=(uint16_t)(fps>65535?65535:fps),
   .sprite_count=frame_commands.sprite_count,.underflow_count=0,.error_count=d.hardware_error?1:0};
 }
 if(e) { bsp_printf("GPU game stopped: result=%d hardware=%d (PRESENT requires lead Day14)\r\n",e,d.hardware_error); return 1; }
 benchmark_run_summary summary={0};
 e=benchmark_summarize_run(frame_samples,BENCHMARK_FRAME_COUNT,&summary);
 if(e || !summary.stable_sprite_count) {
  bsp_printf("GPU game UNSTABLE: p5=%d sprites=%d underflow=%d errors=%d\r\n",
   summary.p5_fps,summary.stable_sprite_count,summary.total_underflows,summary.total_errors);
  return 1;
 }
 bsp_printf("GPU game PASS: frames=300 p5=%d stable_sprites=%d wait-each=150 batch=150\r\n",
  summary.p5_fps,summary.stable_sprite_count);
 return 0;
}
