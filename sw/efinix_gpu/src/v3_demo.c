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
#ifndef V3_STRIPE_RENDER
#define V3_STRIPE_RENDER 0
#endif
#if V3_STRIPE_RENDER
#include "gpu_stripes.h"
#if !V3_FRAME_LIST
#error "Stripe render requires FrameList"
#endif
#endif
#include "../assets/hud/hud_logo_catalog.h"
#ifndef V3_HUD_DIRECT
#define V3_HUD_DIRECT 0
#endif
#if V3_HUD_DIRECT && V3_HUD_LIST
#error "Choose one HUD candidate"
#endif
#if V3_HUD_DIRECT
static hud_framebuffer_cache physical_hud;
#define V3_HUD_DIRECT_WORD 0x02d10014u
static void invalidate_physical_hud(void) {
 physical_hud.buffers[0].valid=physical_hud.buffers[1].valid=0;
}
#endif
#ifndef V3_HUD_LIST
#define V3_HUD_LIST 0
#endif
#if V3_HUD_LIST
#include "hud_gpu_list.h"
#if !V3_FRAME_LIST
#error "HUD list requires FrameList"
#endif
#define V3_HUD_LIST_WORD 0x02d10010u
#endif
#ifndef V3_PERFORMANCE_CHALLENGE
#define V3_PERFORMANCE_CHALLENGE 0
#endif
#if V3_PERFORMANCE_CHALLENGE
#include "performance_challenge.h"
#if !V3_FRAME_LIST
/* V3_FRAME_LIST is supplied by the candidate build, never enabled implicitly. */
#error "Performance challenge requires FrameList"
#endif
#endif
#if V3_STRIPE_RENDER
#define V3_BUILD_ID 0x20261016u
#elif V3_HUD_LIST || V3_HUD_DIRECT
#define V3_BUILD_ID 0x20261015u
#elif V3_PERFORMANCE_CHALLENGE
#define V3_BUILD_ID 0x20261015u
#else
#define V3_BUILD_ID 0x20261008u
#endif
#define V3_RESOURCE_EPOCH 0x00030002u
#define V3_STATE_ADDRESS 0x02d00000u
#define V3_POLLS 10000000u
#ifndef V3_START_COUNT
#define V3_START_COUNT 64u
#endif
#ifndef V3_PROBE_FRAMES
#define V3_PROBE_FRAMES 0u
#endif
#ifndef V3_DETAIL_PROBE
#define V3_DETAIL_PROBE 0
#endif
#ifndef V3_COPY_AHEAD
#define V3_COPY_AHEAD 0
#endif
#ifndef V3_FRAME_LIST
#define V3_FRAME_LIST 0
#endif
#ifndef V3_LOGIC_COPY
#define V3_LOGIC_COPY 0
#endif
#if V3_LOGIC_COPY && !V3_COPY_AHEAD
#error "Logic Copy requires CopyAhead"
#endif
#define V3_LOGIC_COPY_WORD 0x02d10008u /* Terminal same-BIN scheduling selection. */
#ifndef V3_REPLAY_SEAL_BUDGET
#define V3_REPLAY_SEAL_BUDGET 0
#endif
#define V3_SEAL_BUDGET_WORD 0x02d1000cu
#if V3_FRAME_LIST
#include "gpu_frame_list.h"
#define V3_FRAME_LIST_WORD 0x02d10004u
#endif
#define V3_COPY_AHEAD_WORD 0x02d10000u /* Terminal probe only; JTAG selects 0/1. */
#if V3_DETAIL_PROBE && !V3_PROBE_FRAMES
#error "Detail timings are terminal diagnostic only"
#endif
_Static_assert(V3_START_COUNT>=32 && V3_START_COUNT<=BULLET_MAX_OBJECTS,"start count capacity");
/* Runtime + record are private CPU data in disjoint DDR. They are never GPU
 * input and need no per-tick cache flush. This is not CPU rendering tuning. */
_Static_assert(V3_STATE_ADDRESS>=HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES,"state/assets overlap");
_Static_assert(V3_STATE_ADDRESS+sizeof(v3_runtime)<=GPU_DDR_END_EXCLUSIVE,"state DDR bound");
_Static_assert(V3_STATE_ADDRESS+sizeof(v3_runtime)<=V3_COPY_AHEAD_WORD,"probe control/state overlap");
static uint32_t work_samples[PERF_WINDOW_FRAMES];
static uint32_t us(uint64_t ticks) {return (uint32_t)(ticks/(BSP_CLINT_HZ/1000000u));}
static uint32_t now_ms(void) {return (uint32_t)(gpu_platform_cycles()/(BSP_CLINT_HZ/1000u));}
#if V3_DETAIL_PROBE
/* Dump latched endpoints outside the measured window; counters describe GPU
 * interface traffic, not DDR PHY transfers after upsizing or controller padding. */
static void detail_counters(const char *phase,const gpu_perf_snapshot *s) {
 bsp_printf("V3_COUNTERS,phase=%s,cycles_lo=%x,cycles_hi=%x,pixels_lo=%x,pixels_hi=%x,read_lo=%x,read_hi=%x,write_lo=%x,write_hi=%x,stalls_lo=%x,stalls_hi=%x,cache_lo=%x,cache_hi=%x,render_grants_lo=%x,render_grants_hi=%x,scanout_grants_lo=%x,scanout_grants_hi=%x\r\n",
  phase,(uint32_t)s->cycles,(uint32_t)(s->cycles>>32),(uint32_t)s->pixels,(uint32_t)(s->pixels>>32),
  (uint32_t)s->read_bytes,(uint32_t)(s->read_bytes>>32),(uint32_t)s->write_bytes,(uint32_t)(s->write_bytes>>32),
  (uint32_t)s->stalls,(uint32_t)(s->stalls>>32),(uint32_t)s->cache_bytes,(uint32_t)(s->cache_bytes>>32),
  (uint32_t)s->render_grants,(uint32_t)(s->render_grants>>32),(uint32_t)s->scanout_grants,(uint32_t)(s->scanout_grants>>32));
}
#endif
int v3_build_gpu_scene(const bullet_state *state,uint32_t dst,int network,int list_available,
 gpu_instance *items,bullet_stream *scene,int *using_list) {
 if(!state || !scene || !using_list || (list_available!=0 && list_available!=1))return GPU_DRIVER_ARGUMENT;
 *using_list=0;
 if(list_available && !state->won) {
  gpu_instance_stats s;
  int e=gpu_instances_build_into(state,dst,network,1,1,HUD_CACHE_HEIGHT,BULLET_MAX_COMMANDS,items,&s);
  scene->count=s.count;scene->visible=s.visible;scene->scene_pixels=s.scene_pixels;
  scene->alpha_commands=s.alpha_commands;scene->alpha_pixels=s.alpha_pixels;
  if(!e)*using_list=1;
  return e;
 }
 /* ponytail: WIN is 33 commands, so reuse legacy hardware Fill instead of
  * enlarging the list ABI/RTL for this infrequent, low-load screen. */
 int e=game_build(state,dst,network,1,BULLET_MAX_COMMANDS,scene);
 if(!e)e=bullet_clip_background_for_hud(scene,HUD_CACHE_HEIGHT);
 return e;
}
#if V3_COPY_AHEAD
static int copy_ahead_begin(gpu_device *gpu,uint32_t dst,int network,
 gpu_command *background,uint16_t *tag,uint32_t polls) {
 if(!background || (network!=0 && network!=1) ||
    (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B)) return GPU_DRIVER_ARGUMENT;
 *background=(gpu_command){.op=GPU_OP_COPY,
  .src_addr=(network?BULLET_BACKGROUND_ADDR:BULLET_LOCAL_BACKGROUND)+HUD_CACHE_HEIGHT*GPU_FRAME_STRIDE,
  .dst_addr=dst+HUD_CACHE_HEIGHT*GPU_FRAME_STRIDE,.src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT-HUD_CACHE_HEIGHT};
 /* Assets were fully synced before LIVE. No CPU modifies this source; do not
  * flush the private game state before its builder merely to queue a Copy. */
 return gpu_submit(gpu,background,polls,tag);
}
static int copy_ahead_finish(gpu_device *gpu,const gpu_command *background,
 uint16_t tag,const bullet_stream *scene,uint32_t polls) {
 if(!scene || !background || !scene->count || scene->count>BULLET_MAX_COMMANDS)
  return GPU_DRIVER_ARGUMENT;
 const gpu_command *c=scene->commands;
 /* Compare semantic Copy fields, never compiler padding or ignored tag. A
  * changed resource/layout must fail closed, not present or replay a partial frame. */
 if(c->op!=GPU_OP_COPY || c->flags || c->src_addr!=background->src_addr ||
    c->dst_addr!=background->dst_addr || c->src_stride!=background->src_stride ||
    c->dst_stride!=background->dst_stride || c->width_pixels!=background->width_pixels ||
    c->height_pixels!=background->height_pixels) return GPU_DRIVER_ARGUMENT;
 return scene->count>1?perf_render_gpu(gpu,c+1,scene->count-1,polls):gpu_wait_tag(gpu,tag,polls);
}
#if V3_LOGIC_COPY
static int copy_ahead_advance(gpu_device *gpu,v3_runtime *runtime,const game_input *input,
 uint32_t elapsed,uint32_t dst,int network,gpu_command *background,uint16_t *tag,
 int *issued,uint32_t polls) {
 if(!runtime || !input || !issued)return GPU_DRIVER_ARGUMENT;
 *issued=0;
 if(runtime->mode!=V3_MODE_CPU && !(runtime->menu_enabled && runtime->phase==V3_PHASE_MENU)) {
  int e=copy_ahead_begin(gpu,dst,network,background,tag,polls);if(e)return e;
  *issued=1;
 }
 uint8_t old_mode=runtime->mode;
 int e=v3_runtime_advance(runtime,input,elapsed);if(e<0)return e;
 if(old_mode==V3_MODE_LIVE && runtime->mode==V3_MODE_CPU) {
  e=v3_runtime_advance(runtime,input,0);if(e<0)return e;
 }
 /* Immutable Copy may have started while LIVE, but advance can enter a
  * death menu or CPU comparison. Drain before either alternative writer;
  * failed advance/tag exits cannot render, PRESENT or replay partial work. */
 if(*issued && (runtime->mode==V3_MODE_CPU ||
    (runtime->menu_enabled && runtime->phase==V3_PHASE_MENU))) {
  int wait=gpu_wait_tag(gpu,*tag,polls);if(wait)return wait;
  *issued=0;
 }
 return e;
}
#endif
#endif
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
#if V3_HUD_DIRECT
 invalidate_physical_hud();
 int hud_direct_enabled=1;
 #if V3_PROBE_FRAMES
 uint32_t direct_choice=*(volatile uint32_t *)(uintptr_t)V3_HUD_DIRECT_WORD;
 if(direct_choice>1u)return 1;
 hud_direct_enabled=direct_choice==1u;
 #endif
 bsp_printf("V3_HUD_DIRECT,enabled=%d\r\n",hud_direct_enabled);
#endif
#if V3_FRAME_LIST
 gpu_frame_list list_device;
 e=gpu_frame_list_init(&list_device,gpu,network);if(e)return 1;
 #if V3_PROBE_FRAMES
 int list_enabled=list_device.present && *(volatile uint32_t *)(uintptr_t)V3_FRAME_LIST_WORD==1u;
 #else
 int list_enabled=list_device.present;
 #endif
 bsp_printf("V3_FRAME_LIST,present=%d,enabled=%d\r\n",list_device.present,list_enabled);
 #if V3_STRIPE_RENDER
 if(!list_enabled || !gpu_stripes_supported(gpu)) {
  bsp_printf("V3_STRIPES,unsupported; candidate requires stripe BIT\r\n");return 1;
 }
 bsp_printf("V3_STRIPES,enabled=1,height=8\r\n");
 #endif
 #if V3_HUD_LIST
 int hud_list_enabled=list_enabled;
  #if V3_PROBE_FRAMES
 uint32_t hud_choice=*(volatile uint32_t *)(uintptr_t)V3_HUD_LIST_WORD;
 if(hud_choice>1u)return 1;
 hud_list_enabled=hud_list_enabled && hud_choice==1u;
  #endif
 if(hud_list_enabled) {e=hud_gpu_list_init(&list_device,network);if(e)return 1;}
 bsp_printf("V3_HUD_LIST,enabled=%d\r\n",hud_list_enabled);
 #endif
#endif
#if V3_PROBE_FRAMES
 e=v3_runtime_init(runtime,V3_START_COUNT,7,V3_RESOURCE_EPOCH);
#else
 e=v3_runtime_menu_init(runtime,7,V3_RESOURCE_EPOCH);
#endif
 if(e) return 1;
#if V3_PERFORMANCE_CHALLENGE
 pc_state *challenge=(pc_state *)(uintptr_t)PC_STATE_ADDRESS;
 uint32_t challenge_scene=UINT32_MAX,challenge_generation=0;
 runtime->perf_enabled=(uint8_t)(list_enabled && control.perf_capable);
#endif
#if V3_REPLAY_SEAL_BUDGET
 #if V3_PROBE_FRAMES
 uint32_t seal_words=*(volatile uint32_t *)(uintptr_t)V3_SEAL_BUDGET_WORD;
 if(seal_words!=0 && seal_words!=256)return 1;
 runtime->seal_words=(uint16_t)seal_words;
 #else
 runtime->seal_words=256;
 #endif
 bsp_printf("V3_SEAL_BUDGET,words=%d\r\n",runtime->seal_words);
#endif
#if V3_COPY_AHEAD
 #if V3_PROBE_FRAMES
 int copy_ahead=*(volatile uint32_t *)(uintptr_t)V3_COPY_AHEAD_WORD==1u;
 #else
 int copy_ahead=1;
 #endif
 #if V3_STRIPE_RENDER
 copy_ahead=0; /* Strip load replaces the full-frame Copy, never issue both. */
 #endif
 bsp_printf("V3_COPY_AHEAD,enabled=%d\r\n",copy_ahead);
 #if V3_LOGIC_COPY
  #if V3_PROBE_FRAMES
 int logic_copy=copy_ahead && *(volatile uint32_t *)(uintptr_t)V3_LOGIC_COPY_WORD==1u;
  #else
 int logic_copy=copy_ahead;
  #endif
 bsp_printf("V3_LOGIC_COPY,enabled=%d\r\n",logic_copy);
 #endif
#endif
 e=gpu_set_qos(gpu,256,1536,1);if(e) return 1;
 /* Scanout starts only after PRESENT. Establish a complete blank front
  * during initialization, before the logo fetch and render health baseline.
  * Keep the pair in sync; no warmup/game frame or counter is discarded. */
 overlay->commands[0]=(gpu_command){.op=GPU_OP_FILL,.dst_addr=buffers->back,
  .dst_stride=GPU_FRAME_STRIDE,.width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT};
 e=perf_render_gpu(gpu,overlay->commands,1,V3_POLLS);if(e)return 1;
 e=framebuffer_present(gpu,buffers,V3_POLLS);if(e)return 1;
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
 menu_cache.performance=runtime->perf_enabled;
 menu_cache.levels=BULLET_MAX_OBJECTS>=1024?6:4;
 uint32_t last_report=0,under_delta=0,miss_delta=0,last_drops=0,last_rejected=0;
 uint64_t previous_present=gpu_platform_cycles(),previous_logic=previous_present;
 gpu_perf_snapshot initial;
 e=gpu_read_perf_snapshot(gpu,&initial);if(e)return 1;
 uint64_t sampled_underflows=initial.underflows;
 bsp_printf("V3_COUNTER_BASELINE,under_lo=%d,under_hi=%d\r\n",
  (uint32_t)initial.underflows,(uint32_t)(initial.underflows>>32));
 uint8_t previous_mode=V3_MODE_LIVE;unsigned frame=0;
#if V3_PROBE_FRAMES
 v3_frame_stats stats={0};unsigned probe_frame=0;uint32_t previous_log=0;
 #if V3_DETAIL_PROBE
 v3_worst_frame detail_worst={0};
 #endif
 uint64_t probe_underflows=0;
 gpu_perf_snapshot probe_initial;
 e=gpu_read_perf_snapshot(gpu,&probe_initial);if(e)return 1;
 probe_underflows=probe_initial.underflows;
 #if V3_DETAIL_PROBE
 detail_counters("begin",&probe_initial);
 #endif
 bsp_printf("V3_PROBE_START,warm=30,samples=%d,log_windows=1\r\n",V3_PROBE_FRAMES);
#endif
 bsp_printf("V3_READY,build=%x,epoch=%x,network=%d,state=%x,mode=%s,count=%d\r\n",V3_BUILD_ID,V3_RESOURCE_EPOCH,network,V3_STATE_ADDRESS,runtime->menu_enabled?"MENU":"LIVE",runtime->menu_enabled?0:V3_START_COUNT);
 for(;;) {
  uint64_t start=previous_present;
  gpu_perf_snapshot before,after;
  e=gpu_read_perf_snapshot(gpu,&before);if(e) break;
  e=nc_poll(&control,now_ms(),&raw);if(e<0) break;
  input_update(&input,&raw);
  #if V3_PERFORMANCE_CHALLENGE
  e=v3_runtime_control(runtime,&raw);if(e<0)break;
  #endif
  nc_game_command command;
  e=nc_take_game(&control,&command);if(e<0)break;
  if(e) {e=v3_apply_game_command(runtime,&control,&command);if(e<0) {(void)nc_try_publish(&control,0,now_ms());break;}}
  (void)nc_try_publish(&control,0,now_ms()); /* ACK before render, never wait. */
  uint64_t logic=gpu_platform_cycles();
#if V3_COPY_AHEAD
  gpu_command background;uint16_t background_tag=0;int background_issued=0;
#endif
#if V3_DETAIL_PROBE
  uint8_t detail_sealed=runtime->recording.sealed;
  uint32_t detail_hp_before=runtime->game.hp,detail_death_wait=runtime->game.game_over_ticks;
#endif
#if V3_LOGIC_COPY
  if(logic_copy) {
   e=copy_ahead_advance(gpu,runtime,&input,us(logic-previous_logic),buffers->back,network,
    &background,&background_tag,&background_issued,V3_POLLS);
  } else
#endif
  {
   uint8_t old_mode=runtime->mode;
   e=v3_runtime_advance(runtime,&input,us(logic-previous_logic));
   if(e>=0 && old_mode==V3_MODE_LIVE && runtime->mode==V3_MODE_CPU)
    e=v3_runtime_advance(runtime,&input,0);
  }
  previous_logic=logic;if(e<0)break;
#if V3_PERFORMANCE_CHALLENGE
  int performance=runtime->phase==V3_PHASE_PERFORMANCE;
  if(!performance && challenge_scene!=UINT32_MAX) {
   /* Console output can block for multiple video periods. Export the full
    * final counters only after leaving the workload, never inside sampling
    * or after qualifying while the challenge is still rendering. Network
    * status remains bounded/nonblocking and is included in every frame. */
   const v3_frame_stats *s=&challenge->stats;
   bsp_printf("PERF_RESULT,target=%d,stage=%d,best=%d,frames=%d,fps_x100=%d,work_max_us=%d,wall_max_us=%d,work_miss=%d,late=%d,under=%d,error=%d,visible_min=%d,visible_max=%d,alpha_min=%d,alpha_max=%d\r\n",
    challenge->target,challenge->stage,challenge->best,s->frames,
    s->wall_ticks?(uint32_t)((uint64_t)s->frames*BSP_CLINT_HZ*100u/s->wall_ticks):0,
    us(s->max_work_ticks),us(s->max_wall_ticks),s->work_misses,s->cadence_misses,
    s->underflows,s->errors,s->min_visible,s->max_visible,s->min_alpha,s->max_alpha);
   challenge_scene=UINT32_MAX;
  }
  if(performance) {
   if(challenge_scene!=runtime->scene_generation) {
    e=pc_init(challenge,(list_device.arena_items-1u)*8u/9u,7);if(e)break;
    challenge_scene=runtime->scene_generation;challenge_generation=0;
   }
   e=pc_advance(challenge,&input);if(e)break;
   if(challenge_generation!=challenge->generation) {
    challenge_generation=challenge->generation;window=(perf_window){0};frame=0;
    results.gpu_fps=results.gpu_us=0;nc_discard_pending_telemetry(&control);
   }
  }
#endif
#if V3_DETAIL_PROBE
  unsigned detail_steps=(unsigned)e;
#endif
#if V3_DETAIL_PROBE
  uint32_t detail_logic_us=us(gpu_platform_cycles()-logic);
#endif
  unsigned mode=runtime->mode;
  int menu=runtime->menu_enabled && runtime->phase==V3_PHASE_MENU;
  if(results.generation!=runtime->scene_generation) {
   v3_scene_metrics_transition(&results,runtime->scene_generation,menu);
   window=(perf_window){0};frame=0;hud_cache->valid=0;game_menu_invalidate(&menu_cache);
   #if V3_HUD_DIRECT
   invalidate_physical_hud();
   #endif
   nc_discard_pending_telemetry(&control);last_report=now_ms()-V3_TELEMETRY_DEFAULT_MS;
   previous_logic=logic;start=gpu_platform_cycles();
   bsp_printf("V3_SCENE,phase=%s,level=%d,count=%d,generation=%d,reason=%d\r\n",menu?"MENU":"PLAY",runtime->level,menu?0:runtime->game.count,runtime->scene_generation,runtime->menu_reason);
  }
  if(mode!=previous_mode) {window=(perf_window){0};frame=0;previous_mode=(uint8_t)mode;hud_cache->valid=0;
   #if V3_HUD_DIRECT
   invalidate_physical_hud(); /* CPU scene writes the full framebuffer. */
   #endif
   if(mode==V3_MODE_CPU) {results.cpu_fresh=0;results.pending_cpu_fps=results.pending_cpu_us=0;}}
#if V3_COPY_AHEAD
  int ahead=copy_ahead && !menu && mode!=V3_MODE_CPU;
  if(ahead && !background_issued) {e=copy_ahead_begin(gpu,buffers->back,network,&background,&background_tag,V3_POLLS);if(e)break;}
#endif
  uint64_t build=gpu_platform_cycles();
#if V3_FRAME_LIST
  int list_frame=0;
  uint32_t list_address=buffers->back==GPU_FRAMEBUFFER_A?GPU_FRAME_LIST_BANK_A:GPU_FRAME_LIST_BANK_B;
  #if BULLET_OBJECT_CAPACITY >= 1024 && !V3_STRIPE_RENDER
  list_address=GPU_FRAME_LIST_BANK_A; /* One scene may span banks; framebuffer A/B still alternate. */
  #endif
  #if V3_STRIPE_RENDER
  list_address=GPU_STRIPE_SCENE_ADDR;
  #endif
#endif
  if(menu) {scene->count=scene->visible=scene->alpha_commands=scene->alpha_pixels=0;}
#if V3_FRAME_LIST
  #if V3_PERFORMANCE_CHALLENGE
  else if(performance) {
   gpu_instance_stats s;
   /* Own the actual arena until all scene batches retire. Always start at A;
    * challenge state is disjoint from all four possible list banks. */
   #if !V3_STRIPE_RENDER
   list_address=GPU_FRAME_LIST_BANK_A;
   #endif
   e=pc_build(challenge,buffers->back,network,(gpu_instance *)(uintptr_t)list_address,
    GPU_FRAME_LIST_ARENA_ITEMS,&s);if(e)break;
   scene->count=s.count;scene->visible=s.visible;scene->scene_pixels=s.scene_pixels;
   scene->alpha_commands=s.alpha_commands;scene->alpha_pixels=s.alpha_pixels;list_frame=1;
  }
  #endif
  else if(list_enabled && mode!=V3_MODE_CPU) {
   e=v3_build_gpu_scene(&runtime->game,buffers->back,network,1,
    (gpu_instance *)(uintptr_t)list_address,scene,&list_frame);if(e)break;
  }
#endif
  else {
   e=game_build(&runtime->game,buffers->back,network,1,BULLET_MAX_COMMANDS,scene);if(e) break;
   if(mode!=V3_MODE_CPU) {e=bullet_clip_background_for_hud(scene,HUD_CACHE_HEIGHT);if(e) break;}
  }
  uint32_t build_us=us(gpu_platform_cycles()-build);
  gpu_platform_sync();uint64_t render_start=gpu_platform_cycles();
#if V3_FRAME_LIST
  if(list_frame) {
   #if V3_STRIPE_RENDER
   e=gpu_stripes_render(&list_device,network,buffers->back,
    (const gpu_instance *)(uintptr_t)list_address,scene->count,
    (gpu_instance *)(uintptr_t)GPU_STRIPE_BINS_ADDR,GPU_STRIPE_BIN_ITEMS,
    runtime->scene_generation,V3_POLLS);
   #else
   unsigned skip=0;
   #if V3_COPY_AHEAD
   if(ahead) {e=gpu_wait_tag(gpu,background_tag,V3_POLLS);if(e)break;skip=1;}
   #endif
   e=gpu_frame_list_render_span(&list_device,list_address+16u*skip,scene->count-skip,runtime->scene_generation,V3_POLLS);
   #endif
  } else
#endif
  e=menu?game_menu_draw(gpu,&menu_cache,buffers->back==GPU_FRAMEBUFFER_A?0u:1u,
   buffers->back,runtime->scene_generation,raw.connected,overlay,V3_POLLS):
   mode==V3_MODE_CPU?perf_render_cpu(scene->commands,scene->count):
#if V3_COPY_AHEAD
   ahead?copy_ahead_finish(gpu,&background,background_tag,scene,V3_POLLS):
#endif
   perf_render_gpu(gpu,scene->commands,scene->count,V3_POLLS);
  gpu_platform_sync();uint32_t render_us=us(gpu_platform_cycles()-render_start);if(e) break;
  #if V3_STRIPE_RENDER
  /* MENU/WIN do not enter list_frame. Restore the HUD bank on EVERY scene path. */
  list_address=buffers->back==GPU_FRAMEBUFFER_A?GPU_FRAME_LIST_BANK_A:GPU_FRAME_LIST_BANK_B;
  #endif
  metrics=(hud_comparison){.cpu_fps_x10=results.cpu_fps,.gpu_fps_x10=results.gpu_fps,.cpu_render_us=results.cpu_us,.gpu_render_us=results.gpu_us,
   .cpu_valid=(uint8_t)(results.cpu_fps!=0),.gpu_valid=(uint8_t)(!menu && results.gpu_fps!=0),.gpu_active=(uint8_t)(mode!=V3_MODE_CPU),
   .network_ready=(uint8_t)network,.bullet_demo=1,.gameplay=(uint8_t)!menu,.sprites=(uint16_t)scene->visible,
   .alpha_commands=(uint16_t)scene->alpha_commands,.hp=runtime->game.hp,.score=runtime->game.score,
   .grazes=runtime->game.grazes,.invulnerable=(uint8_t)(runtime->game.invulnerable!=0),.game_over=(uint8_t)(runtime->game.hp==0),
   .underflows=(uint32_t)before.underflows,.v3_mode=(uint8_t)(menu?4:mode==V3_MODE_LIVE?1:mode==V3_MODE_CPU?2:3),
   .cpu_stale=(uint8_t)((v3_runtime_status(runtime,network,raw.connected,results.gpu_fps!=0,results.cpu_fps!=0,results.cpu_fresh)&V3_STATUS_CPU_STALE)!=0),.logic_slow=runtime->clock.slow};
#if V3_PERFORMANCE_CHALLENGE
  if(performance) {
   metrics.v3_mode=5;metrics.perf_stage=(uint8_t)challenge->stage;
   metrics.perf_best=(uint16_t)challenge->best;metrics.perf_frames=(uint16_t)challenge->stats.frames;
  }
#endif
#if V3_DETAIL_PROBE
  uint64_t detail_hud_start=gpu_platform_cycles();
#endif
  #if V3_HUD_LIST
  if(hud_list_enabled && mode!=V3_MODE_CPU) {
   /* Scene batch above has retired. This exact bank can now be reused for
    * glyph updates followed by one complete HUD Copy, before PRESENT. */
   e=hud_render_gpu_list(&list_device,&metrics,hud_cache,overlay,buffers->back,
    list_address,runtime->scene_generation,V3_POLLS);
   if(e)break;
  } else {
  #endif
  #if V3_HUD_DIRECT
  if(hud_direct_enabled && mode!=V3_MODE_CPU) {
   /* All GPU scene/menu/WIN writers above are clipped to y>=72 and retired.
    * Keep independent physical A/B histories; never skip based on front/back. */
   e=hud_render_gpu_direct(gpu,&metrics,&physical_hud,overlay,buffers->back,V3_POLLS);
   if(e)break;
  } else {
  #endif
  e=mode==V3_MODE_CPU?hud_update_cache(&metrics,hud_cache,overlay):hud_update_gpu_cache(gpu,&metrics,hud_cache,overlay,V3_POLLS);
  if(e) break;
  gpu_platform_sync();e=hud_cached_command(buffers->back,hud_cache,&overlay->commands[0]);if(e) break;
  e=mode==V3_MODE_CPU?perf_render_cpu(overlay->commands,1):perf_render_gpu(gpu,overlay->commands,1,V3_POLLS);if(e) break;
  #if V3_HUD_DIRECT
  }
  #endif
  #if V3_HUD_LIST
  }
  #endif
  gpu_platform_sync();uint64_t present_start=gpu_platform_cycles();
#if V3_DETAIL_PROBE
  uint32_t detail_hud_us=us(present_start-detail_hud_start);
#endif
  e=gpu_read_perf_snapshot(gpu,&after);if(e) break;
  uint64_t work_ticks=gpu_platform_cycles()-start;
  uint32_t work_us=us(work_ticks);
  e=framebuffer_present(gpu,buffers,V3_POLLS);if(e) break;
  previous_present=gpu_platform_cycles();uint64_t wall=previous_present-start;
#if V3_PERFORMANCE_CHALLENGE
  if(performance) {
   gpu_perf_snapshot health;e=gpu_read_perf_snapshot(gpu,&health);if(e)break;
   uint32_t under=(uint32_t)(health.underflows-sampled_underflows);
   e=pc_record(challenge,BSP_CLINT_HZ,(uint32_t)work_ticks,(uint32_t)wall,under,
    gpu->hardware_error!=0,scene->visible,scene->alpha_commands);if(e<0)break;
   e=nc_queue_performance(&control,challenge->target,challenge->best,
    challenge->stage|(challenge->stats.frames<<8));if(e)break;
   after.underflows=health.underflows;
  }
#endif
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
  if(probe_frame++>=30u) {
   v3_frame_stats_add(&stats,BSP_CLINT_HZ,(uint32_t)work_ticks,(uint32_t)wall,
    previous_log,(uint32_t)(probe_after.underflows-probe_underflows),gpu->hardware_error!=0,
    scene->visible,scene->alpha_commands);
   #if V3_DETAIL_PROBE
   v3_worst_frame detail_frame={.tick=runtime->game.tick,.steps=detail_steps,
    .logic_us=detail_logic_us,.build_us=build_us,.scene_us=render_us,.hud_us=detail_hud_us,
    .busy_us=(uint32_t)((after.cycles-before.cycles)/100u),.work_us=work_us,.wall_us=us(wall),
    .hp=runtime->game.hp,.seal_event=!detail_sealed && runtime->recording.sealed,
    .hp_before=detail_hp_before,.death_wait_before=detail_death_wait,.round_tick=runtime->game.round_tick};
   if(v3_worst_frame_record(&detail_worst,&detail_frame)) {e=GPU_DRIVER_ARGUMENT;break;}
   #endif
  }
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
#if V3_DETAIL_PROBE
    bsp_printf("V3_DETAIL,tick=%d,build_us=%d,logic_us=%d,scene_us=%d,hud_us=%d,work_us=%d,busy_us=%d,visible=%d,alpha=%d\r\n",
     runtime->game.tick,build_us,detail_logic_us,render_us,detail_hud_us,work_us,
     (uint32_t)((after.cycles-before.cycles)/100u),scene->visible,scene->alpha_commands);
#else
    #if V3_PERFORMANCE_CHALLENGE
    if(!performance) /* Ordinary game/CPU diagnostics unchanged. */
    #endif
    bsp_printf("V3_PERF,mode=%d,tick=%d,seq=%d,x=%d,y=%d,visible=%d,fps_x10=%d,scene_us=%d,p95_work_us=%d,under=%d,miss=%d,keys=%x,age=%d\r\n",
    mode,runtime->game.tick,raw.sequence,runtime->game.player_x,runtime->game.player_y,scene->visible,fps,avg,p95_us,under_delta,miss_delta,input.held,raw.age_ms);
#endif
#if V3_PROBE_FRAMES
    previous_log=(uint32_t)(gpu_platform_cycles()-log_start);
#endif
   window=(perf_window){0};frame=0;
  }
  uint32_t now=now_ms();
  if(now-last_report>=V3_TELEMETRY_DEFAULT_MS) {
   uint32_t drops=*(volatile uint32_t *)(uintptr_t)(GPU_APB_BASE+NC_REG_RX_DROP_COUNT);
   unsigned key_commands=0;
   #if V3_FRAME_LIST
   if(list_frame) key_commands=scene->count-scene->alpha_commands-1u; // Only one background Copy; remaining non-Alpha are Key.
   else
   #endif
   for(unsigned i=0;i<scene->count;i++) if(scene->commands[i].op==GPU_OP_COLOR_KEY) ++key_commands;
   telemetry.simulation_tick=runtime->game.tick;telemetry.requested_sprites=menu?0:runtime->game.count;
   #if V3_PERFORMANCE_CHALLENGE
   if(performance) {telemetry.simulation_tick=challenge->tick;telemetry.requested_sprites=scene->visible;}
   #endif
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
   #if V3_REPLAY_SEAL_BUDGET
   if(!runtime->recording.sealed || runtime->recording.count!=REPLAY_INPUT_TICKS) {
    e=GPU_DRIVER_ARGUMENT;break;
   }
   bsp_printf("V3_SEAL_STATE,count=%d,sealed=%d,words=%d,offset=%d,crc=%x\r\n",
    runtime->recording.count,runtime->recording.sealed,runtime->seal_words,
    runtime->seal_cursor.offset,runtime->recording.crc32);
   #endif
   #if V3_DETAIL_PROBE
   detail_counters("end",&probe_after);
   bsp_printf("V3_WORST,tick=%d,steps=%d,logic_us=%d,build_us=%d,scene_us=%d,hud_us=%d,other_us=%d,busy_us=%d,work_us=%d,wall_us=%d,hp=%d,seal_event=%d,hp_before=%d,death_wait_before=%d,round_tick=%d\r\n",
    detail_worst.tick,detail_worst.steps,detail_worst.logic_us,detail_worst.build_us,
    detail_worst.scene_us,detail_worst.hud_us,detail_worst.other_us,detail_worst.busy_us,
    detail_worst.work_us,detail_worst.wall_us,detail_worst.hp,detail_worst.seal_event,
    detail_worst.hp_before,detail_worst.death_wait_before,detail_worst.round_tick);
   #endif
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
