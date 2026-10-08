#include "v3_demo.h"
#include "v3_runtime.h"
#include "perf_demo.h"
#include "hud.h"
#include "benchmark.h"
#include "game_menu.h"
#include "v3_frame_stats.h"
#include "render_phase_health.h"
#include "bsp.h"
#include "network_assets.h"
#include "../assets/hud/hud_logo_catalog.h"
#define V3_BUILD_ID 0x20261008u
#define V3_RESOURCE_EPOCH 0x00030002u
#define V3_STATE_ADDRESS 0x02d00000u
#define V3_POLLS 10000000u
#ifndef V3_START_COUNT
#define V3_START_COUNT 64u
#endif
#ifndef V3_PROBE_FRAMES
#define V3_PROBE_FRAMES 0u
#endif
_Static_assert(V3_START_COUNT>=32 && V3_START_COUNT<=BULLET_MAX_OBJECTS,"start count capacity");
/* Runtime + record are private CPU data in disjoint DDR. They are never GPU
 * input and need no per-tick cache flush. This is not CPU rendering tuning. */
_Static_assert(V3_STATE_ADDRESS>=HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES,"state/assets overlap");
_Static_assert(V3_STATE_ADDRESS+sizeof(v3_runtime)<=GPU_DDR_END_EXCLUSIVE,"state DDR bound");
static uint32_t work_samples[PERF_WINDOW_FRAMES];
static uint32_t us(uint64_t ticks) {return (uint32_t)(ticks/(BSP_CLINT_HZ/1000000u));}
static uint32_t now_ms(void) {return (uint32_t)(gpu_platform_cycles()/(BSP_CLINT_HZ/1000u));}
static uint32_t p95(unsigned n) {
 uint32_t sorted[PERF_WINDOW_FRAMES];
 for(unsigned i=0;i<n;i++) {
  unsigned j=i;while(j && sorted[j-1]>work_samples[i]) {sorted[j]=sorted[j-1];--j;}
  sorted[j]=work_samples[i];
 }
 return n?sorted[(n*95u+99u)/100u-1u]:0;
}
int v3_apply_game_command(v3_runtime *r,nc_device *d,const nc_game_command *cmd) {
 nc_game_command pending;
 if(!r || !cmd || nc_take_game(d,&pending)!=1 || !d->input.connected ||
    cmd->session!=d->input.session || cmd->session!=pending.session ||
    cmd->request_id!=pending.request_id || cmd->opcode!=pending.opcode || cmd->level!=pending.level)
  return GPU_DRIVER_ARGUMENT;
 int e=v3_runtime_game_command(r,cmd->opcode,cmd->level,cmd->session,cmd->sequence);
 int ack=nc_complete_game(d,cmd,e<0?2u:e?1u:0u);
 return ack<0?ack:e<0?e:0;
}
int v3_demo_run(gpu_device *gpu,framebuffer_pair *buffers,int network,
 bullet_stream *scene,hud_command_stream *overlay,hud_raster_cache *hud_cache) {
 v3_runtime *runtime=(v3_runtime *)(uintptr_t)V3_STATE_ADDRESS;
 nc_device control;nc_input raw={0};game_input input={0};
 int e=nc_init(&control,GPU_APB_BASE);
 if(e) {bsp_printf("V3_CONTROL,unavailable=%d; use frozen R7 firmware\r\n",e);return 1;}
#if V3_PROBE_FRAMES
 e=v3_runtime_init(runtime,V3_START_COUNT,7,V3_RESOURCE_EPOCH);
#else
 e=v3_runtime_menu_init(runtime,7,V3_RESOURCE_EPOCH);
#endif
 if(e) return 1;
 e=gpu_set_qos(gpu,256,1536,1);if(e) return 1;
 /* Optional decoration: a failed/missing mark must not break the game or
  * validate partial DDR. Fetch before sampling; no per-frame resource I/O. */
 hud_set_logo_enabled(0);
 network_asset_report logo_report={0};
 uint32_t logo_session=(uint32_t)gpu_platform_cycles();
 int logo_result=network?network_asset_fetch(GPU_APB_BASE,BSP_CLINT_HZ,logo_session?logo_session:1,
  HUD_LOGO_ASSET_ID,HUD_LOGO_ADDR,HUD_LOGO_BYTES,HUD_LOGO_CRC32,&logo_report):NETWORK_UNAVAILABLE;
 hud_set_logo_enabled(logo_result==NETWORK_OK);
 hud_cache->valid=0;
 bsp_printf("HUD_LOGO,id=%d,bytes=%d,retries=%d,result=%d,enabled=%d\r\n",
  HUD_LOGO_ASSET_ID,logo_report.committed_bytes,logo_report.retries,logo_result,logo_result==NETWORK_OK);
 hud_comparison metrics={.bullet_demo=1,.gameplay=1,.network_ready=(uint8_t)network};
 nc_telemetry telemetry={.firmware_build_id=V3_BUILD_ID,.resource_epoch=V3_RESOURCE_EPOCH};
 perf_window window={0};v3_scene_metrics results={0};game_menu_cache menu_cache={0};
 uint32_t last_report=0,under_delta=0,miss_delta=0,last_drops=0,last_rejected=0;
 uint64_t previous_present=gpu_platform_cycles(),previous_logic=previous_present;
 uint64_t sampled_underflows=0;
 uint8_t previous_mode=V3_MODE_LIVE;unsigned frame=0;
#if V3_PROBE_FRAMES
 v3_frame_stats stats={0};unsigned probe_frame=0;uint32_t previous_log=0;
 uint64_t probe_underflows=0;
 gpu_perf_snapshot probe_initial;
 e=gpu_read_perf_snapshot(gpu,&probe_initial);if(e)return 1;
 probe_underflows=probe_initial.underflows;
 bsp_printf("V3_PROBE_START,warm=30,samples=%d,log_windows=1\r\n",V3_PROBE_FRAMES);
#endif
 bsp_printf("V3_READY,build=%x,epoch=%x,network=%d,state=%x,mode=%s,count=%d\r\n",V3_BUILD_ID,V3_RESOURCE_EPOCH,network,V3_STATE_ADDRESS,runtime->menu_enabled?"MENU":"LIVE",runtime->menu_enabled?0:V3_START_COUNT);
 for(;;) {
  uint64_t start=previous_present;
  gpu_perf_snapshot before,after;
  e=gpu_read_perf_snapshot(gpu,&before);if(e) break;
  e=nc_poll(&control,now_ms(),&raw);if(e<0) break;
  input_update(&input,&raw);
  nc_game_command command;
  e=nc_take_game(&control,&command);if(e<0)break;
  if(e) {e=v3_apply_game_command(runtime,&control,&command);if(e<0) {(void)nc_try_publish(&control,0,now_ms());break;}}
  (void)nc_try_publish(&control,0,now_ms()); /* ACK before render, never wait. */
  uint64_t logic=gpu_platform_cycles();
  uint8_t old_mode=runtime->mode;
  e=v3_runtime_advance(runtime,&input,us(logic-previous_logic));previous_logic=logic;
  if(e<0) break;
  if(old_mode==V3_MODE_LIVE && runtime->mode==V3_MODE_CPU) {
   e=v3_runtime_advance(runtime,&input,0);if(e<0) break;
  }
  unsigned mode=runtime->mode;
  int menu=runtime->menu_enabled && runtime->phase==V3_PHASE_MENU;
  if(results.generation!=runtime->scene_generation) {
   v3_scene_metrics_transition(&results,runtime->scene_generation,menu);
   window=(perf_window){0};frame=0;hud_cache->valid=0;game_menu_invalidate(&menu_cache);
   nc_discard_pending_telemetry(&control);last_report=now_ms()-V3_TELEMETRY_DEFAULT_MS;
   previous_logic=logic;start=gpu_platform_cycles();
   bsp_printf("V3_SCENE,phase=%s,level=%d,count=%d,generation=%d,reason=%d\r\n",menu?"MENU":"PLAY",runtime->level,menu?0:runtime->game.count,runtime->scene_generation,runtime->menu_reason);
  }
  if(mode!=previous_mode) {window=(perf_window){0};frame=0;previous_mode=(uint8_t)mode;hud_cache->valid=0;if(mode==V3_MODE_CPU) {results.cpu_fresh=0;results.pending_cpu_fps=results.pending_cpu_us=0;}}
  uint64_t build=gpu_platform_cycles();
  if(menu) {scene->count=scene->visible=scene->alpha_commands=scene->alpha_pixels=0;}
  else {
   e=game_build(&runtime->game,buffers->back,network,1,BULLET_MAX_COMMANDS,scene);if(e) break;
   if(mode!=V3_MODE_CPU) {e=bullet_clip_background_for_hud(scene,HUD_CACHE_HEIGHT);if(e) break;}
  }
  uint32_t build_us=us(gpu_platform_cycles()-build);
  gpu_platform_sync();uint64_t render_start=gpu_platform_cycles();
  e=menu?game_menu_draw(gpu,&menu_cache,buffers->back==GPU_FRAMEBUFFER_A?0u:1u,
   buffers->back,runtime->scene_generation,raw.connected,overlay,V3_POLLS):
   mode==V3_MODE_CPU?perf_render_cpu(scene->commands,scene->count):perf_render_gpu(gpu,scene->commands,scene->count,V3_POLLS);
  gpu_platform_sync();uint32_t render_us=us(gpu_platform_cycles()-render_start);if(e) break;
  metrics=(hud_comparison){.cpu_fps_x10=results.cpu_fps,.gpu_fps_x10=results.gpu_fps,.cpu_render_us=results.cpu_us,.gpu_render_us=results.gpu_us,
   .cpu_valid=(uint8_t)(results.cpu_fps!=0),.gpu_valid=(uint8_t)(!menu && results.gpu_fps!=0),.gpu_active=(uint8_t)(mode!=V3_MODE_CPU),
   .network_ready=(uint8_t)network,.bullet_demo=1,.gameplay=(uint8_t)!menu,.sprites=(uint16_t)scene->visible,
   .alpha_commands=(uint16_t)scene->alpha_commands,.hp=runtime->game.hp,.score=runtime->game.score,
   .grazes=runtime->game.grazes,.invulnerable=(uint8_t)(runtime->game.invulnerable!=0),.game_over=(uint8_t)(runtime->game.hp==0),
   .underflows=(uint32_t)before.underflows,.v3_mode=(uint8_t)(menu?4:mode==V3_MODE_LIVE?1:mode==V3_MODE_CPU?2:3),
   .cpu_stale=(uint8_t)((v3_runtime_status(runtime,network,raw.connected,results.gpu_fps!=0,results.cpu_fps!=0,results.cpu_fresh)&V3_STATUS_CPU_STALE)!=0),.logic_slow=runtime->clock.slow};
  e=mode==V3_MODE_CPU?hud_update_cache(&metrics,hud_cache,overlay):hud_update_gpu_cache(gpu,&metrics,hud_cache,overlay,V3_POLLS);
  if(e) break;
  gpu_platform_sync();e=hud_cached_command(buffers->back,hud_cache,&overlay->commands[0]);if(e) break;
  e=mode==V3_MODE_CPU?perf_render_cpu(overlay->commands,1):perf_render_gpu(gpu,overlay->commands,1,V3_POLLS);if(e) break;
  gpu_platform_sync();uint64_t present_start=gpu_platform_cycles();
  e=gpu_read_perf_snapshot(gpu,&after);if(e) break;
  uint64_t work_ticks=gpu_platform_cycles()-start;
  uint32_t work_us=us(work_ticks);
  e=framebuffer_present(gpu,buffers,V3_POLLS);if(e) break;
  previous_present=gpu_platform_cycles();uint64_t wall=previous_present-start;
  if(!menu) {
   e=perf_window_add(&window,wall,(uint64_t)render_us*(BSP_CLINT_HZ/1000000u));if(e) break;
   work_samples[frame++]=work_us;
   if(mode!=V3_MODE_CPU && us(wall)>20000u) ++miss_delta;
  }
  under_delta+=(uint32_t)(after.underflows-sampled_underflows);
  sampled_underflows=after.underflows; /* Include inter-frame/PRESENT events. */
#if V3_PROBE_FRAMES
  if(mode!=V3_MODE_LIVE) {e=GPU_DRIVER_ARGUMENT;break;} /* No mixed CPU/GPU sample. */
  gpu_perf_snapshot probe_after;
  e=gpu_read_perf_snapshot(gpu,&probe_after);if(e) break;
  if(!render_phase_health_ok(probe_underflows,probe_after.underflows,gpu->hardware_error)) {
   bsp_printf("V3_PROBE_HEALTH_FAIL,frame=%d,warmup=%d,under_before=%d,under_after=%d,hardware=%d\r\n",
    probe_frame,probe_frame<30u,(uint32_t)probe_underflows,(uint32_t)probe_after.underflows,gpu->hardware_error);
   e=GPU_DRIVER_HARDWARE;break;
  }
  if(probe_frame++>=30u)
   v3_frame_stats_add(&stats,BSP_CLINT_HZ,(uint32_t)work_ticks,(uint32_t)wall,
    previous_log,(uint32_t)(probe_after.underflows-probe_underflows),gpu->hardware_error!=0,
    scene->visible,scene->alpha_commands);
  probe_underflows=probe_after.underflows; /* Includes PRESENT/inter-frame events. */
  previous_log=0;
#endif
  uint32_t p95_us=p95(frame);
  if(frame==PERF_WINDOW_FRAMES) {
   uint32_t fps=perf_fps_x10(&window,BSP_CLINT_HZ),avg=perf_render_us(&window,BSP_CLINT_HZ);
   if(mode==V3_MODE_CPU) {results.pending_cpu_fps=fps;results.pending_cpu_us=avg;} else {results.gpu_fps=fps;results.gpu_us=avg;}
#if V3_PROBE_FRAMES
    uint64_t log_start=gpu_platform_cycles();
#endif
    bsp_printf("V3_PERF,mode=%d,tick=%d,seq=%d,x=%d,y=%d,visible=%d,fps_x10=%d,scene_us=%d,p95_work_us=%d,under=%d,miss=%d,keys=%x,age=%d\r\n",
    mode,runtime->game.tick,raw.sequence,runtime->game.player_x,runtime->game.player_y,scene->visible,fps,avg,p95_us,under_delta,miss_delta,input.held,raw.age_ms);
#if V3_PROBE_FRAMES
    previous_log=(uint32_t)(gpu_platform_cycles()-log_start);
#endif
   window=(perf_window){0};frame=0;
  }
  uint32_t now=now_ms();
  if(now-last_report>=V3_TELEMETRY_DEFAULT_MS) {
   uint32_t drops=*(volatile uint32_t *)(uintptr_t)(GPU_APB_BASE+NC_REG_RX_DROP_COUNT);
   unsigned key_commands=0;for(unsigned i=0;i<scene->count;i++) if(scene->commands[i].op==GPU_OP_COLOR_KEY) ++key_commands;
   telemetry.simulation_tick=runtime->game.tick;telemetry.requested_sprites=menu?0:runtime->game.count;
   telemetry.visible_sprites=scene->visible;telemetry.gpu_full_frame_fps_x100=results.gpu_fps*10u;telemetry.cpu_full_frame_fps_x100=results.cpu_fps*10u;
   telemetry.pre_present_us=menu?0:work_us;telemetry.gpu_busy_us=menu?0:(uint32_t)((after.cycles-before.cycles)/100u);
   telemetry.command_build_us=menu?0:build_us;telemetry.p95_work_us=menu?0:p95_us;telemetry.present_wait_us=menu?0:us(previous_present-present_start);
   telemetry.scanout_underflow_delta=under_delta;telemetry.gpu_error_delta=gpu->hardware_error;telemetry.missed_vblank_delta=miss_delta;
   telemetry.control_drop_delta=drops-last_drops+control.rejected_packets-last_rejected;telemetry.input_age_ms=raw.age_ms;
   telemetry.alpha_commands=scene->alpha_commands;telemetry.alpha_pixels=scene->alpha_pixels;telemetry.key_commands=key_commands;
   /* Probe and traffic groups are invalid: no fabricated zero counters and
    * no intrusive per-command probes in the normal real-time firmware. */
   telemetry.status_flags=v3_runtime_status(runtime,network,raw.connected,results.gpu_fps!=0,results.cpu_fps!=0,results.cpu_fresh);
   e=nc_try_publish(&control,&telemetry,now);if(e<0) break;
   last_report=now;last_drops=drops;last_rejected=control.rejected_packets;under_delta=miss_delta=0;
  }
  e=v3_runtime_frame_done(runtime);if(e) break;
#if V3_PROBE_FRAMES
  if(stats.frames==V3_PROBE_FRAMES) {
   bsp_printf("V3_PROBE,target=%d,frames=%d,fps_x10=%d,work_mean_us=%d,work_max_us=%d,wall_max_us=%d,work_miss=%d,late_present=%d,under=%d,errors=%d,visible_min=%d,visible_max=%d,alpha_min=%d,alpha_max=%d,log_mean_us=%d,log_max_us=%d\r\n",
    V3_START_COUNT,stats.frames,(uint32_t)((uint64_t)stats.frames*BSP_CLINT_HZ*10u/stats.wall_ticks),
    us(stats.work_ticks/stats.frames),us(stats.max_work_ticks),us(stats.max_wall_ticks),
    stats.work_misses,stats.cadence_misses,stats.underflows,stats.errors,
    stats.min_visible,stats.max_visible,stats.min_alpha,stats.max_alpha,
    us(stats.log_ticks/stats.frames),us(stats.max_log_ticks));
   bsp_printf("V3_PROBE_STOP,result=0\r\n");return 0;
  }
#endif
  if(mode==V3_MODE_CPU && runtime->mode==V3_MODE_GPU) {
   v3_scene_metrics_cpu_done(&results);
   bsp_printf("V3_REPLAY,CPU_DONE,crc=%x,frames=600\r\n",runtime->recording.crc32);
  }
  if(mode==V3_MODE_GPU && runtime->mode==V3_MODE_LIVE) {
   // Polling already consumed action_sequence throughout replay. Preserve it
   // so a held R/C cannot turn into a new press on returning to LIVE.
   previous_logic=previous_present;
   bsp_printf("V3_REPLAY,GPU_DONE,frames=600,LIVE_RESTORED\r\n");
  }
 }
 bsp_printf("V3_FAIL,result=%d,hardware=%d\r\n",e,gpu->hardware_error);
 return 1;
}
