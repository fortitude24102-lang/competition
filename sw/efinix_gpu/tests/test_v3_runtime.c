#include <assert.h>
#include <stdio.h>
#include "v3_runtime.h"
static v3_runtime runtime;
static bullet_state expected;
int main(void) {
 assert(v3_runtime_init(&runtime,64,7,0x30001)==0);
 game_input input={.held=V3_KEY_RIGHT|V3_KEY_FIRE};
 /* Four catch-up steps are four real records, never just the last frame. */
 assert(v3_runtime_advance(&runtime,&input,66667)==4);
 assert(runtime.recording.count==4 && runtime.game.tick==4);
 assert(runtime.game.player_x==496);
 input=(game_input){.pressed=V3_KEY_COMPARE};
 assert(v3_runtime_advance(&runtime,&input,16667)==1);
 assert(runtime.mode==V3_MODE_LIVE && runtime.compare_pending);
 input=(game_input){.held=V3_KEY_FIRE};
 for(unsigned i=5;i<600;i++) assert(v3_runtime_advance(&runtime,&input,16667)==1);
 assert(runtime.recording.sealed && runtime.mode==V3_MODE_CPU);
 expected=runtime.recording.initial;
 replay_cursor cursor; bullet_state reference;
 assert(replay_begin(&runtime.recording,0x30001,&reference,&cursor)==0);
 for(unsigned i=0;i<600;i++) {
  game_input tick;
  assert(replay_next(&runtime.recording,&cursor,&tick)==1);
  assert(game_update(&reference,&tick)>=0);
  /* Live keys must not affect either comparison backend. */
  assert(v3_runtime_advance(&runtime,&input,999999)==1);
  assert(runtime.game.tick==reference.tick);
  assert(runtime.game.player_x==reference.player_x);
  assert(v3_runtime_frame_done(&runtime)==0);
 }
 expected=reference;
 assert(runtime.mode==V3_MODE_GPU);
 for(unsigned i=0;i<600;i++) {
  assert(v3_runtime_advance(&runtime,&input,999999)==1);
  if(i==599) { assert(runtime.game.tick==expected.tick);assert(runtime.game.score==expected.score); }
  assert(v3_runtime_frame_done(&runtime)==0);
 }
 assert(runtime.mode==V3_MODE_LIVE && runtime.recording.count==0);
 assert(runtime.game.tick==600);
 assert(v3_runtime_set_epoch(&runtime,0x30002)==0);
 assert(runtime.epoch==0x30002 && runtime.recording.resource_epoch==0x30002);
 assert(v3_runtime_advance(&runtime,&input,500000)==4);
 assert(runtime.clock.slow && runtime.recording.count==4);
 uint32_t flags=v3_runtime_status(&runtime,1,1,1,1,0);
 assert(!(flags&V3_STATUS_PAUSED)); /* Catch-up still advances the game. */
 assert(flags&V3_VALID_GPU_TIMING);
 assert(flags&V3_STATUS_CPU_STALE);
 runtime.mode=V3_MODE_CPU;
 flags=v3_runtime_status(&runtime,1,1,1,1,0);
 assert(!(flags&V3_VALID_GPU_TIMING)); /* Current CPU durations are not GPU. */
 assert(flags&V3_STATUS_CPU_STALE); /* Previous comparison until new window. */
 flags=v3_runtime_status(&runtime,1,1,1,1,1);
 assert(!(flags&V3_STATUS_CPU_STALE));
 runtime.mode=V3_MODE_GPU;
 assert(v3_runtime_status(&runtime,1,1,1,1,1)&V3_STATUS_CPU_STALE);
 /* Input polling continues through replay. Do not discard its consumed
    action counter when frame_done restores LIVE. */
 game_input held={0};
 nc_input packet={.session=3,.sequence=1,.action_sequence=1,
  .keys=V3_KEY_RESTART|V3_KEY_COMPARE,.connected=1};
 input_update(&held,&packet);
 runtime.replay_frames=599;
 assert(!v3_runtime_frame_done(&runtime));
 ++packet.sequence;input_update(&held,&packet);
 assert(held.pressed==0);
 uint32_t tick=runtime.game.tick;
 assert(v3_runtime_advance(&runtime,&held,16667)==1);
 assert(runtime.game.tick==tick+1 && !runtime.compare_pending);
 puts("PASS V3 runtime per-tick recording, 600-tick two-backend replay, live restore, epoch, bounded catch-up");
 return 0;
}
