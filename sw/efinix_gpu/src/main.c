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
 return clint_getTime(BSP_CLINT);
}
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 /*
  * The official Ti60 Sapphire image exposes the standard VexRiscv cache
  * controls, but it does not implement the optional Efinix write-buffer CSR
  * (0x810) used by soc_write_buffer_flush().  Executing that CSR traps to
  * mtvec=0 and makes the application appear to reset.  The fence plus cache
  * invalidate is sufficient for the uncached GPU/DDR sharing path used here.
  */
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
/* The official Sapphire linker reserves a 4 KiB stack. Keep bounded command
 * lists in BSS so the demo cannot overwrite its own image at runtime. */
static game_command_stream frame_commands;
static game_command_stream dense_compare_commands, sparse_compare_commands;
static hud_command_stream hud_commands;
static benchmark_frame_sample frame_samples[BENCHMARK_FRAME_COUNT];
static size_t sparse_player_words, sparse_enemy_words, sparse_demo_words;
static int submit_hud(gpu_device *d,const hud_command_stream *s,int batch) {
 uint16_t tag=0;
 for(unsigned i=0;i<s->count;i++) {
  int e=gpu_submit(d,&s->commands[i],10000000u,&tag); if(e) return e;
  if(!batch && (e=gpu_wait_tag(d,tag,10000000u))) return e;
 }
 return batch && s->count ? gpu_wait_tag(d,tag,10000000u) : 0;
}
static int run_controlled_qos(gpu_device *d,int adaptive,gpu_qos_sample *sample,
 uint32_t *command_hash) {
 if(!d || !sample || !command_hash) return GPU_DRIVER_ARGUMENT;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 game_state game; game_init(&game);
 int e=gpu_set_qos(d,256,1536,adaptive); if(e) return e;
 e=gpu_clear_perf(d); if(e) return e;
 uint64_t start=gpu_platform_cycles();
 uint32_t hash=UINT32_C(2166136261);
 for(unsigned frame=0;frame<BENCHMARK_FRAME_COUNT;frame++) {
  unsigned input=(frame&64u)?GAME_INPUT_RIGHT:GAME_INPUT_LEFT;
  if(frame%17u==0) input|=GAME_INPUT_FIRE;
  game_step(&game,input,16);
  e=game_build_commands_mode(&game,buffers.back,(frame/75u)&1u,&frame_commands); if(e) return e;
  hash=gpu_command_stream_hash(frame_commands.commands,frame_commands.count,hash);
  e=game_submit_commands(d,&frame_commands,1,10000000u); if(e) return e;
  e=framebuffer_present(d,&buffers,10000000u); if(e) return e;
 }
 gpu_platform_sync();
 gpu_perf_snapshot perf;
 e=gpu_read_perf_snapshot(d,&perf); if(e) return e;
 gpu_platform_sync();
 *sample=(gpu_qos_sample){.cpu_cycles=gpu_platform_cycles()-start,
  .render_stalls=perf.stalls,.underflows=perf.underflows,
  .render_grants=perf.render_grants,.scanout_grants=perf.scanout_grants,
  .frame_crc=golden_crc32((const void *)(uintptr_t)buffers.front,GPU_FRAME_BYTES)};
 *command_hash=hash;
 return 0;
}
int main(void) {
 bsp_init(); gpu_device d; int e=gpu_init(&d,GPU_APB_BASE);
 if(e) { bsp_printf("GPU unavailable: probe=%d; integration/board test pending\r\n",e); return 1; }
 if(gpu_assets_upload_dense((volatile uint16_t *)(uintptr_t)GPU_DENSE_ASSETS,GPU_ASSET_WORDS)!=GPU_ASSET_WORDS) return 1;
 if(gpu_assets_upload_sparse((volatile uint32_t *)(uintptr_t)GPU_SPARSE_ASSETS,
    GPU_SPARSE_SLOT_WORDS*3u,&sparse_player_words,&sparse_enemy_words,&sparse_demo_words)!=SPARSE_PACK_OK) return 1;
 gpu_platform_sync(); framebuffer_pair buffers; framebuffer_init(&buffers); game_state game; game_init(&game);
 gpu_sparse_benchmark_result sparse_runtime={0};
 e=game_build_commands_mode(&game,GPU_FRAMEBUFFER_A,0,&dense_compare_commands);
 if(!e) e=game_build_commands_mode(&game,GPU_FRAMEBUFFER_B,1,&sparse_compare_commands);
 if(e || dense_compare_commands.count!=sparse_compare_commands.count ||
    gpu_benchmark_sparse_compare(&d,dense_compare_commands.commands,sparse_compare_commands.commands,
      dense_compare_commands.count,10000000u,(const void *)(uintptr_t)GPU_FRAMEBUFFER_A,
      (const void *)(uintptr_t)GPU_FRAMEBUFFER_B,GPU_FRAME_BYTES,GPU_DEMO_ASSET_WORDS*2u,
      (uint32_t)(sparse_demo_words*4u),&sparse_runtime)) return 1;
 framebuffer_pair warmup; framebuffer_init(&warmup);
 if(framebuffer_present(&d,&warmup,10000000u) || framebuffer_present(&d,&warmup,10000000u)) return 1;
 gpu_qos_benchmark_result exact_qos={.dense_bytes=GPU_DEMO_ASSET_WORDS*2u,
  .sparse_bytes=(uint32_t)(sparse_demo_words*4u)};
 uint32_t fixed_hash=0,adaptive_hash=0;
 if(run_controlled_qos(&d,0,&exact_qos.fixed,&fixed_hash) ||
    run_controlled_qos(&d,1,&exact_qos.adaptive,&adaptive_hash) ||
    fixed_hash!=adaptive_hash || gpu_qos_benchmark_validate(&exact_qos)) return 1;
 if(gpu_set_qos(&d,256,1536,0) || gpu_clear_perf(&d)) return 1;
 uint64_t previous=gpu_platform_cycles(); unsigned fps=60,busy_permille=0;
 gpu_perf_snapshot perf={0};
 uint64_t previous_underflows=0;
 for(unsigned frame=0;frame<300;frame++) {
  if(frame==150) {
   if(gpu_set_qos(&d,256,1536,1) || gpu_clear_perf(&d)) { e=1; break; }
   perf=(gpu_perf_snapshot){0};
   previous_underflows=0;
  }
  uint32_t keys=~gpio_getInput(SYSTEM_GPIO_0_IO_CTRL);
  unsigned input=(keys&1?GAME_INPUT_LEFT:0)|(keys&2?GAME_INPUT_RIGHT:0)|(keys&4?GAME_INPUT_FIRE:0);
  game_step(&game,input,16);
  int batch=frame>=150;
  uint64_t render_start=gpu_platform_cycles();
  int sparse=(frame/75u)&1u;
  e=game_build_commands_mode(&game,buffers.back,sparse,&frame_commands); if(e) break;
  e=game_submit_commands(&d,&frame_commands,batch,10000000u); if(e) break;
  hud_metrics metrics={.fps=(uint16_t)(fps>999?999:fps),.sprite_count=frame_commands.sprite_count,
   .cpu_busy_permille=(uint16_t)(busy_permille>999?999:busy_permille),
   .queue_high_watermark=d.queue_high_watermark,
   .underflow_count=(uint16_t)(perf.underflows>999?999:perf.underflows),
   .error_code=d.hardware_error,.render_stalls=(uint16_t)(perf.stalls>999?999:perf.stalls),
   .batch_mode=(uint8_t)batch,.qos_adaptive=(uint8_t)(frame>=150)};
  e=hud_build_metrics(buffers.back,1280,8,8,&metrics,&hud_commands); if(e) break;
  e=submit_hud(&d,&hud_commands,batch); if(e) break;
  uint64_t render_cycles=gpu_platform_cycles()-render_start;
  e=framebuffer_present(&d,&buffers,10000000u); if(e) break;
  e=gpu_read_perf_snapshot(&d,&perf); if(e) break;
  uint64_t now=gpu_platform_cycles(),elapsed=now-previous; previous=now;
  if(elapsed) { fps=(unsigned)(100000000u/elapsed); busy_permille=(unsigned)(render_cycles*1000u/elapsed); }
  frame_samples[frame]=(benchmark_frame_sample){.fps=(uint16_t)(fps>65535?65535:fps),
   .sprite_count=frame_commands.sprite_count,
   .underflow_count=benchmark_counter_delta(perf.underflows,&previous_underflows),
   .error_count=d.hardware_error?1:0};
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
 bsp_printf("QOS,fixed_underflow=%d,fixed_stall=%d,adaptive_underflow=%d,adaptive_stall=%d\r\n",
  (uint32_t)exact_qos.fixed.underflows,(uint32_t)exact_qos.fixed.render_stalls,
  (uint32_t)exact_qos.adaptive.underflows,(uint32_t)exact_qos.adaptive.render_stalls);
 int32_t underflow_benefit=exact_qos.fixed.underflows>=exact_qos.adaptive.underflows ?
  (int32_t)(exact_qos.fixed.underflows-exact_qos.adaptive.underflows) :
  -(int32_t)(exact_qos.adaptive.underflows-exact_qos.fixed.underflows);
 int32_t stall_cost=exact_qos.adaptive.render_stalls>=exact_qos.fixed.render_stalls ?
  (int32_t)(exact_qos.adaptive.render_stalls-exact_qos.fixed.render_stalls) :
  -(int32_t)(exact_qos.fixed.render_stalls-exact_qos.adaptive.render_stalls);
 bsp_printf("QOS_DELTA,underflows_avoided=%d,render_stall_cost=%d\r\n",
  underflow_benefit,stall_cost);
 bsp_printf("QOS_EXACT,frames=300,fixed_underflow=%d,adaptive_underflow=%d,fixed_crc=%x,adaptive_crc=%x,command_hash=%x\r\n",
  (uint32_t)exact_qos.fixed.underflows,(uint32_t)exact_qos.adaptive.underflows,
  exact_qos.fixed.frame_crc,exact_qos.adaptive.frame_crc,fixed_hash);
 bsp_printf("SPARSE,demo_bytes=%d,demo_dense=%d,player_bytes=%d,enemy_bytes=%d\r\n",
  (uint32_t)(sparse_demo_words*4u),GPU_DEMO_ASSET_WORDS*2u,
  (uint32_t)(sparse_player_words*4u),(uint32_t)(sparse_enemy_words*4u));
 bsp_printf("SPARSE_RUNTIME,dense_read=%d,sparse_read=%d,dense_cycles=%d,sparse_cycles=%d,crc=%x\r\n",
  (uint32_t)sparse_runtime.dense.read_bytes,(uint32_t)sparse_runtime.sparse.read_bytes,
  (uint32_t)sparse_runtime.dense.cycles,(uint32_t)sparse_runtime.sparse.cycles,
  sparse_runtime.dense_crc);
 return 0;
}
