/* Instrument the real runtime/logic, never skip validation or a restart tick. */
#include "v3_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned resets;
void __attribute__((no_instrument_function)) __cyg_profile_func_enter(void *fn,void *caller) {
 (void)caller;if(fn==(void *)bullet_reset_player)++resets;
}
void __attribute__((no_instrument_function)) __cyg_profile_func_exit(void *fn,void *caller) {
 (void)fn;(void)caller;
}
static v3_runtime r;
static bullet_state expected;
int main(void) {
 assert(!v3_runtime_init(&r,512,7,3));r.seal_words=256;
 for(unsigned trial=0;trial<3;trial++) {
  r.game.hp=0;r.game.game_over_ticks=1;r.game.tick=266;
  expected=r.game;
  game_input in={.held=V3_KEY_LEFT|V3_KEY_FIRE,.pressed=trial==1?V3_KEY_RESTART:trial==2?V3_KEY_COMPARE:0};
  assert(game_update(&expected,&in)>=0);resets=0;
  r.clock=(game_clock){0};
  assert(v3_runtime_advance(&r,&in,16667)==1);
  assert(!memcmp(&expected,&r.game,sizeof expected));
  if(!in.pressed)assert(!resets); /* Old path regenerates512 objects. */
 }
 assert(!v3_runtime_init(&r,512,7,3));r.seal_words=256;
 r.game.hp=0;r.game.game_over_ticks=1;r.game.objects[0].shape=99;
 expected=r.game;
 assert(v3_runtime_advance(&r,&(game_input){0},16667)==GPU_DRIVER_ARGUMENT);
 assert(!memcmp(&expected,&r.game,sizeof expected));
 /* Mid-game replay initial is not a canonical reset template. */
 assert(!v3_runtime_init(&r,512,7,3));r.seal_words=256;
 assert(v3_runtime_advance(&r,&(game_input){0},16667)==1);
 assert(!v3_runtime_set_epoch(&r,4));
 r.game.hp=0;r.game.game_over_ticks=1;expected=r.game;
 assert(!game_update(&expected,&(game_input){0}));resets=0;r.clock=(game_clock){0};
 assert(v3_runtime_advance(&r,&(game_input){0},16667)==1 && resets==1);
 assert(!memcmp(&expected,&r.game,sizeof expected));
 puts("PASS runtime reset snapshot: exact restart/input/tick, no regeneration, validation retained, epoch fallback");
}
