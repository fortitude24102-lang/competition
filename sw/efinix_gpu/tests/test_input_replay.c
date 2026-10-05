#include "replay_input.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static replay_recording record,bad;
static replay_cursor a,b;
static bullet_state initial,cpu,gpu,live;
static bullet_stream cs,gs;
static game_input trace(unsigned tick) {
 game_input in={0};
 in.held=V3_KEY_FIRE|(tick%120<60?V3_KEY_RIGHT:V3_KEY_LEFT);
 if(tick%90<30) in.held|=V3_KEY_SLOW;
 if(tick==245 || tick==246) in.pressed=V3_KEY_RESTART;
 return in;
}
int main(void) {
 assert(!game_reset(&initial,128,7)); live=initial;
 assert(!replay_init(&record,&initial,3));
 assert(replay_begin(&record,3,&cpu,&a)==GPU_DRIVER_ARGUMENT);
 for(unsigned tick=0;tick<600;tick++) {
  game_input in=trace(tick);
  assert(!replay_record(&record,&in));
  assert(!game_update(&live,&in));
 }
 game_input in={0};
 assert(replay_record(&record,&in)==GPU_DRIVER_FULL);
 assert(!replay_seal(&record) && record.crc32);
 assert(replay_record(&record,&in)==GPU_DRIVER_ARGUMENT);
 assert(replay_begin(&record,4,&cpu,&a)==GPU_DRIVER_ARGUMENT);
 assert(!replay_begin(&record,3,&cpu,&a));
 assert(!replay_begin(&record,3,&gpu,&b));
 /* CPU can take arbitrary wall time: both streams consume only recorded ticks. */
 for(unsigned tick=0;tick<600;tick++) {
  game_input ci,gi;
  assert(replay_next(&record,&a,&ci)==1);
  assert(replay_next(&record,&b,&gi)==1);
  assert(ci.held==gi.held && ci.pressed==gi.pressed);
  assert(!game_update(&cpu,&ci) && !game_update(&gpu,&gi));
  assert(!memcmp(&cpu,&gpu,sizeof cpu));
  assert(!game_build(&cpu,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&cs));
  assert(!game_build(&gpu,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&gs));
  assert(cs.count==gs.count && cs.visible==gs.visible);
  for(unsigned n=0;n<cs.count;n++) {
   const gpu_command *x=&cs.commands[n],*y=&gs.commands[n];
   assert(x->op==y->op && x->alpha==y->alpha && x->src_addr==y->src_addr &&
    x->dst_addr==y->dst_addr && x->src_stride==y->src_stride && x->dst_stride==y->dst_stride &&
    x->width_pixels==y->width_pixels && x->height_pixels==y->height_pixels && x->color_key==y->color_key);
  }
 }
 assert(!memcmp(&cpu,&live,sizeof cpu));
 assert(!replay_next(&record,&a,&in));
 bad=record; bad.keys[300]^=V3_KEY_UP;
 assert(replay_begin(&bad,3,&cpu,&a)==GPU_DRIVER_ARGUMENT);
 bad=record; bad.initial.player_x++;
 assert(replay_begin(&bad,3,&cpu,&a)==GPU_DRIVER_ARGUMENT);
 bad=record; bad.resource_epoch++;
 assert(replay_begin(&bad,4,&cpu,&a)==GPU_DRIVER_ARGUMENT);
 assert(!replay_begin(&record,3,&cpu,&a) && !memcmp(&cpu,&initial,sizeof cpu));
 puts("PASS input replay: 600 live/CPU/GPU ticks, repeated action events, state/command equivalence, CRC/epoch/capacity");
 return 0;
}
