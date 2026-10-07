#include <assert.h>
#include <stdio.h>
#include "v3_runtime.h"
static v3_runtime runtime;
static bullet_stream stream;
int main(void) {
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
 puts("PASS1024 host capacity,600 real interactive frames,visible>=1000,Alpha>=125,1025 rejected; NOT board FPS");
}
