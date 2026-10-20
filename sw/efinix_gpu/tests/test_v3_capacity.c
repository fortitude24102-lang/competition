#include <assert.h>
#include <stdio.h>
#include "v3_runtime.h"
static v3_runtime runtime;
static bullet_stream stream;
int main(void) {
 const unsigned counts[]={64,128,256,512,786,1024};
 assert(sizeof(runtime)+0x02d00000u<=0x02d10000u);
 for(unsigned level=1;level<=6;level++) {
  assert(v3_level_count(level)==counts[level-1]);
  assert(!v3_runtime_menu_init(&runtime,7,0x30002));
  assert(v3_runtime_status(&runtime,1,1,1,0,0)&(1u<<14));
  assert(!v3_runtime_game_command(&runtime,V3_GAME_START,level,7,1));
  assert(runtime.game.count==counts[level-1] && runtime.phase==V3_PHASE_PLAY);
  runtime.await_neutral=0;
  assert(v3_runtime_advance(&runtime,&(game_input){.pressed=V3_KEY_RESTART},16667)==0);
  assert(runtime.game.count==counts[level-1] && runtime.await_neutral);
  runtime.game.hp=0;
  assert(!v3_runtime_advance(&runtime,&(game_input){0},16667) && runtime.phase==V3_PHASE_MENU);
 }
 assert(!v3_level_count(0) && !v3_level_count(7));
 assert(!v3_runtime_init(&runtime,1024,7,0x30001));
 game_input input={.held=V3_KEY_FIRE};
 unsigned max_visible=0,max_alpha=0;
 for(unsigned i=0;i<600;i++) {
  assert(v3_runtime_advance(&runtime,&input,16667)==1);
  assert(!game_build(&runtime.game,GPU_FRAMEBUFFER_A,1,1,BULLET_MAX_COMMANDS,&stream));
  assert(stream.count<=1161 && stream.visible<=1024);
  if(stream.visible>max_visible) max_visible=stream.visible;
  if(stream.alpha_commands>max_alpha) max_alpha=stream.alpha_commands;
  assert(!v3_runtime_frame_done(&runtime));
 }
 assert(max_visible>=1000 && max_alpha>=125);
 assert(v3_runtime_init(&runtime,1025,7,0x30001)<0);
 puts("PASS6levels exact64/128/256/512/786/1024,DDRbound,restart/death; 1024host600frames; NOT board FPS");
}
