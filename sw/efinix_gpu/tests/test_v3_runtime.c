#include <assert.h>
#include <stdio.h>
#include "v3_runtime.h"
static v3_runtime runtime;
static bullet_state expected;
static void test_menu_levels(void) {
 const unsigned counts[]={64,128,256,512};game_input in={.pressed=V3_KEY_RESTART|V3_KEY_COMPARE};
 for(unsigned level=1;level<=4;level++) {
  assert(v3_level_count(level)==counts[level-1]);
  assert(!v3_runtime_menu_init(&runtime,7,3));
  assert(runtime.phase==V3_PHASE_MENU && runtime.menu_reason==V3_MENU_BOOT);
  assert(v3_runtime_advance(&runtime,&in,250000)==0 && !runtime.game.tick && !runtime.compare_pending);
  assert(!v3_runtime_game_command(&runtime,1,level,7,9));
  assert(runtime.phase==V3_PHASE_PLAY && runtime.game.count==counts[level-1]);
  assert(v3_runtime_game_command(&runtime,1,level,7,10)==1);
  assert(!v3_runtime_game_command(&runtime,2,0,7,11));
  assert(runtime.phase==V3_PHASE_MENU && runtime.menu_reason==V3_MENU_REQUEST);
  uint32_t f=v3_runtime_status(&runtime,1,1,1,1,1);
  assert((f&(V3_STATUS_MENU|V3_STATUS_GAME_MENU_CAPABLE|V3_STATUS_PAUSED))==0x0d00);
  assert(!(f&V3_VALID_GPU_TIMING));
 }
 assert(!v3_level_count(0) && !v3_level_count(5));
 assert(v3_runtime_game_command(&runtime,1,5,7,12)<0);
 assert(v3_runtime_game_command(&runtime,2,1,7,12)<0);
}
static void test_start_requires_new_neutral(void) {
 assert(!v3_runtime_menu_init(&runtime,7,3));assert(!v3_runtime_game_command(&runtime,1,2,7,9));
 game_input in={.session=7,.sequence=9,.initialized=1,.neutral=1};
 int x=runtime.game.player_x;
 assert(v3_runtime_advance(&runtime,&in,16667)==1 && runtime.await_neutral);
 in.sequence=10;in.held=V3_KEY_RIGHT;in.neutral=0;
 assert(v3_runtime_advance(&runtime,&in,16667)==1 && runtime.game.player_x==x);
 in.sequence=11;in.held=0;in.neutral=1;
 assert(v3_runtime_advance(&runtime,&in,16667)==1 && !runtime.await_neutral);
 in.sequence=12;in.held=V3_KEY_RIGHT;in.neutral=0;
 assert(v3_runtime_advance(&runtime,&in,16667)==1 && runtime.game.player_x==x+4);
 in.pressed=V3_KEY_RESTART;uint32_t gen=runtime.scene_generation;
 assert(v3_runtime_advance(&runtime,&in,16667)==0 && runtime.scene_generation==gen+1);
 assert(runtime.game.count==128 && runtime.recording.count==0 && runtime.await_neutral);
 assert(runtime.game.player_x==480 && runtime.clock.accumulator_x60==0);
}
static void test_menu_death_stops_catchup(void) {
 assert(!v3_runtime_menu_init(&runtime,7,3));assert(!v3_runtime_game_command(&runtime,1,1,7,9));
 game_input in={.session=7,.sequence=10,.initialized=1,.neutral=1};
 runtime.game.hp=1;runtime.game.invulnerable=0;
 runtime.game.objects[0]=(bullet_object){.x=480*256,.y=480*256,.kind=0,.shape=0};
 assert(v3_runtime_advance(&runtime,&in,66667)==1);
 assert(runtime.game.hp==0 && runtime.game.tick==1 && runtime.phase==V3_PHASE_MENU);
 assert(runtime.menu_reason==V3_MENU_DEATH);
 for(unsigned i=0;i<300;i++) assert(!v3_runtime_advance(&runtime,&in,250000));
 assert(runtime.game.tick==1 && runtime.game.hp==0);
}
static void test_menu_aborts_replay(void) {
 /* Valid sealed record with death at the first tick; comparison must replay it. */
 assert(!v3_runtime_menu_init(&runtime,7,3));assert(!v3_runtime_game_command(&runtime,1,1,7,9));
 runtime.game.hp=1;runtime.game.invulnerable=0;
 runtime.game.objects[0]=(bullet_object){.x=480*256,.y=480*256,.kind=0};
 assert(!replay_init(&runtime.recording,&runtime.game,3));
 game_input in={0};
 for(unsigned i=0;i<600;i++) assert(!replay_record(&runtime.recording,&in));
 assert(!replay_seal(&runtime.recording));
 in.pressed=V3_KEY_COMPARE;runtime.await_neutral=0;
 assert(!v3_runtime_advance(&runtime,&in,0) && runtime.mode==V3_MODE_CPU);
 in.pressed=V3_KEY_RESTART;
 assert(v3_runtime_advance(&runtime,&in,0)==1 && runtime.game.hp==0 && runtime.phase==V3_PHASE_PLAY);
 assert(!v3_runtime_game_command(&runtime,2,0,7,12));
 assert(runtime.phase==V3_PHASE_MENU && runtime.mode==V3_MODE_LIVE && !runtime.compare_pending);
 assert(!v3_runtime_frame_done(&runtime));
}
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
 test_menu_levels();test_start_requires_new_neutral();test_menu_death_stops_catchup();test_menu_aborts_replay();
 puts("PASS V3 runtime menu/levels/neutral/death/abort and per-tick recording, 600-tick two-backend replay");
 return 0;
}
