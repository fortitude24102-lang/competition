#include "v3_runtime.h"
#include <string.h>
uint32_t v3_runtime_status(const v3_runtime *r,int network,int connected,
 int gpu_valid,int cpu_valid,int cpu_fresh) {
 int menu=r->menu_enabled && r->phase==V3_PHASE_MENU;
 return (r->mode==V3_MODE_LIVE?V3_STATUS_GPU_REALTIME:V3_STATUS_COMPARE_REPLAY)
  |(r->menu_enabled?V3_STATUS_GAME_MENU_CAPABLE:0)
  |(menu?V3_STATUS_MENU|V3_STATUS_PAUSED:0)
  |(!network?V3_STATUS_LOCAL_FALLBACK:0)|(connected?V3_STATUS_CONTROL_CONNECTED:0)
  |(r->mode!=V3_MODE_CPU || !cpu_fresh?V3_STATUS_CPU_STALE:0)
  |V3_STATUS_INVALID_COUNTS|V3_VALID_ERRORS|V3_VALID_INPUT_NETWORK|V3_VALID_ALPHA_KEY
  |(gpu_valid && !menu && r->mode!=V3_MODE_CPU?V3_VALID_GPU_TIMING:0)|(cpu_valid?V3_VALID_CPU_FPS:0);
}
int v3_runtime_init(v3_runtime *r,unsigned count,uint32_t seed,uint32_t epoch) {
 if(!r || !epoch) return GPU_DRIVER_ARGUMENT;
 memset(r,0,sizeof *r);r->epoch=epoch;r->phase=V3_PHASE_PLAY;
 int e=game_reset(&r->game,count,seed);if(e) return e;
 return replay_init(&r->recording,&r->game,epoch);
}
unsigned v3_level_count(unsigned level) {
 return level>=1 && level<=4?64u<<(level-1):0;
}
static void enter_menu(v3_runtime *r,unsigned reason) {
 r->phase=V3_PHASE_MENU;r->menu_reason=(uint8_t)reason;r->mode=V3_MODE_LIVE;
 r->compare_pending=0;r->replay_frames=0;r->cursor=(replay_cursor){0};
 r->clock=(game_clock){0};r->await_neutral=1;++r->scene_generation;
}
int v3_runtime_menu_init(v3_runtime *r,uint32_t seed,uint32_t epoch) {
 int e=v3_runtime_init(r,64,seed,epoch);if(e) return e;
 r->menu_enabled=1;enter_menu(r,V3_MENU_BOOT);return 0;
}
static int restart_game(v3_runtime *r,uint32_t session,uint32_t sequence) {
 int e=game_reset(&r->game,v3_level_count(r->level),7);if(e) return e;
 e=replay_init(&r->recording,&r->game,r->epoch);if(e) return e;
 r->clock=(game_clock){0};r->cursor=(replay_cursor){0};r->replay_frames=0;
 r->mode=V3_MODE_LIVE;r->compare_pending=0;r->phase=V3_PHASE_PLAY;
 r->await_neutral=1;r->neutral_session=session;r->neutral_sequence=sequence;
 ++r->scene_generation;return 0;
}
int v3_runtime_game_command(v3_runtime *r,unsigned op,unsigned level,uint32_t session,uint32_t sequence) {
 if(!r || !r->menu_enabled || !session ||
    !((op==V3_GAME_START && v3_level_count(level)) || (op==V3_GAME_MENU && !level))) return GPU_DRIVER_ARGUMENT;
 if(op==V3_GAME_MENU) {enter_menu(r,V3_MENU_REQUEST);return 0;}
 if(r->phase!=V3_PHASE_MENU) return 1;
 r->level=(uint8_t)level;return restart_game(r,session,sequence);
}
int v3_runtime_set_epoch(v3_runtime *r,uint32_t epoch) {
 if(!r || !epoch || r->mode!=V3_MODE_LIVE) return GPU_DRIVER_ARGUMENT;
 r->epoch=epoch;r->compare_pending=0;r->clock=(game_clock){0};
 return replay_init(&r->recording,&r->game,epoch);
}
static int begin_compare(v3_runtime *r) {
 r->live_saved=r->game;
 int e=replay_begin(&r->recording,r->epoch,&r->game,&r->cursor);if(e) return e;
 r->mode=V3_MODE_CPU;r->replay_frames=0;r->clock=(game_clock){0};
 return 0;
}
int v3_runtime_advance(v3_runtime *r,const game_input *in,uint32_t us) {
 if(!r || !in) return GPU_DRIVER_ARGUMENT;
 if(r->menu_enabled && r->phase==V3_PHASE_MENU) return 0;
 if(r->mode!=V3_MODE_LIVE) {
  game_input tick;
  int e=replay_next(&r->recording,&r->cursor,&tick);if(e!=1) return GPU_DRIVER_ARGUMENT;
  e=game_update(&r->game,&tick);return e<0?e:1;
 }
 if(r->menu_enabled && !r->game.hp) {enter_menu(r,V3_MENU_DEATH);return 0;}
 game_input filtered=*in;
 if(r->menu_enabled && r->await_neutral) {
  uint32_t delta=in->sequence-r->neutral_sequence;
  if(in->initialized && in->neutral &&
     (in->session!=r->neutral_session || (delta && delta<UINT32_C(0x80000000)))) r->await_neutral=0;
  filtered.held=filtered.pressed=filtered.released=0;in=&filtered;
 }
 if(r->menu_enabled && (in->pressed&V3_KEY_RESTART)) return restart_game(r,in->session,in->sequence);
 if(in->pressed&V3_KEY_COMPARE) r->compare_pending=1;
 if(r->compare_pending && r->recording.sealed) return begin_compare(r);
 game_clock *c=&r->clock;c->slow=0;
 if(us>250000u) {us=250000u;c->slow=1;}
 c->accumulator_x60+=us*60u;
 c->pending_pressed|=in->pressed;c->pending_released|=in->released;
 game_input tick=*in;tick.pressed=c->pending_pressed;tick.released=c->pending_released;
 unsigned n=0;
 while(c->accumulator_x60>=1000000u && n<GAME_MAX_CATCHUP) {
  int e=0;
  if(!r->recording.sealed) {e=replay_record(&r->recording,&tick);if(e) return e;}
  e=game_update(&r->game,&tick);if(e<0) return e;
  c->accumulator_x60-=1000000u;++c->total_steps;++n;
  c->pending_pressed=c->pending_released=0;tick.pressed=tick.released=0;
  if(r->menu_enabled && !r->game.hp) {enter_menu(r,V3_MENU_DEATH);return (int)n;}
  if(!r->recording.sealed && r->recording.count==REPLAY_INPUT_TICKS) {
   e=replay_seal(&r->recording);if(e) return e;
  }
  if(r->compare_pending && r->recording.sealed) {e=begin_compare(r);if(e) return e;break;}
 }
 if(c->accumulator_x60>=1000000u) c->slow=1;
 if(c->accumulator_x60>4000000u) {
  uint32_t lost=(c->accumulator_x60-4000000u)/60u;
  c->discarded_wall_us=UINT32_MAX-c->discarded_wall_us<lost?UINT32_MAX:c->discarded_wall_us+lost;
  c->accumulator_x60=4000000u;
 }
 return (int)n;
}
int v3_runtime_frame_done(v3_runtime *r) {
 if(!r) return GPU_DRIVER_ARGUMENT;
 if(r->mode==V3_MODE_LIVE) return 0;
 if(++r->replay_frames<REPLAY_INPUT_TICKS) return 0;
 if(r->mode==V3_MODE_CPU) {
  int e=replay_begin(&r->recording,r->epoch,&r->game,&r->cursor);if(e) return e;
  r->mode=V3_MODE_GPU;r->replay_frames=0;return 0;
 }
 r->game=r->live_saved;r->mode=V3_MODE_LIVE;r->compare_pending=0;
 r->clock=(game_clock){0};r->replay_frames=0;
 return replay_init(&r->recording,&r->game,r->epoch);
}
