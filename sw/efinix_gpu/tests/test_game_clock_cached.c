#include "interactive_game.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static bullet_state a,b,initial;static game_clock ca,cb;
int main(void){
 for(unsigned tier=0;tier<2;tier++) {
  assert(!game_reset(&initial,tier?512:256,7));a=b=initial;ca=cb=(game_clock){0};
  for(unsigned n=0;n<1200;n++) {
   game_input input={.held=(uint16_t)(n%9==0?V3_KEY_FIRE:0),.pressed=(uint16_t)(n%137==0?V3_KEY_RESTART:0)};
   const uint32_t times[]={16667,0,50000,250000,31667};
   int x=game_advance(&ca,&a,&input,times[n%5]),y=game_advance_cached(&cb,&b,&input,times[n%5],&initial);
   assert(x==y && !memcmp(&ca,&cb,sizeof ca) && !memcmp(&a,&b,sizeof a));
  }
 }
 puts("PASS cached clock:2400 mixed-time/fire/restart updates,full game and clock equal original path");
}
