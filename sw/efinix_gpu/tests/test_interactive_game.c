#include "interactive_game.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static bullet_state s,other;
static bullet_stream stream;
static unsigned active_shots(void) {
 unsigned n=0;
 for(unsigned i=0;i<s.count;i++) if(s.objects[i].kind==3 && s.objects[i].age!=UINT16_MAX) ++n;
 return n;
}
int main(void) {
 game_input input={0};
 assert(!game_reset(&s,32,7));
 for(unsigned n=0;n<20;n++) assert(!game_update(&s,&input));
 assert(s.player_x==480 && s.player_y==480 && s.tick==20 && !active_shots());
 input.held=V3_KEY_RIGHT; assert(!game_update(&s,&input) && s.player_x==484);
 input.held=V3_KEY_RIGHT|V3_KEY_SLOW; assert(!game_update(&s,&input) && s.player_x==485);
 input.held=V3_KEY_RIGHT|V3_KEY_UP; assert(!game_update(&s,&input));
 assert(s.player_x==488 && s.player_y==477);
 input.held=V3_KEY_RIGHT|V3_KEY_LEFT|V3_KEY_UP|V3_KEY_DOWN;
 assert(!game_update(&s,&input) && s.player_x==488 && s.player_y==477);
 input.held=V3_KEY_RIGHT; s.player_x=951; s.player_y=532;
 assert(!game_update(&s,&input) && s.player_x==952);
 input.held=V3_KEY_UP; s.player_y=81;
 assert(!game_update(&s,&input) && s.player_y==80);
 input=(game_input){.held=V3_KEY_RESTART,.pressed=V3_KEY_RESTART};
 s.score=999; assert(!game_update(&s,&input) && s.score==0 && s.round_tick==0);
 input.pressed=0; input.held|=V3_KEY_RIGHT;
 assert(!game_update(&s,&input) && s.round_tick==1 && s.player_x==484);
 input=(game_input){.pressed=V3_KEY_COMPARE};
 assert(game_update(&s,&input)==1);
 assert(!game_reset(&s,512,7)); input=(game_input){.held=V3_KEY_FIRE};
 assert(!game_update(&s,&input) && active_shots()==1);
 unsigned shot=s.count-GAME_SHOT_SLOTS;
 assert(s.objects[shot].x==476*256 && s.objects[shot].y==464*256);
 assert(!game_update(&s,&input) && s.objects[shot].y==456*256);
 input.held=0; unsigned before=active_shots();
 assert(!game_update(&s,&input) && active_shots()==before);
 s.objects[shot].x=476*256; s.objects[shot].y=288*256;
 uint32_t score=s.score;
 assert(!game_update(&s,&input) && s.score==score+25 && s.objects[shot].age==UINT16_MAX);
 assert(!game_build(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 assert(stream.count<=585 && stream.alpha_commands<=68 && stream.alpha_pixels<=9792);
 assert(stream.alpha_commands==67); /* Inactive shot must not leave a ghost halo. */
 assert(game_build(&s,GPU_FRAMEBUFFER_A,0,1,1,&stream)==GPU_DRIVER_FULL && !stream.count);
 /* Manual collision uses the same opacity-aware hit core as R7. */
 assert(!game_reset(&s,32,7));
 s.objects[0].x=476*256; s.objects[0].y=476*256;
 s.objects[0].vx=s.objects[0].vy=0; s.objects[0].shape=0;
 assert(!game_update(&s,&input) && s.hp==2 && s.invulnerable==60);
 s.hp=0; s.game_over_ticks=1;
 assert(!game_update(&s,&input) && s.hp==3 && s.round_tick==0);
 assert(!active_shots() && s.objects[s.count-GAME_SHOT_SLOTS].kind==3);
 other=s; input.held=0x100;
 assert(game_update(&s,&input)==GPU_DRIVER_ARGUMENT && !memcmp(&s,&other,sizeof s));
 input=(game_input){.held=V3_KEY_RIGHT,.pressed=V3_KEY_RESTART};
 game_clock clock={0}; assert(!game_reset(&s,32,7));
 assert(game_advance(&clock,&s,&input,100000)==4 && clock.slow);
 assert(s.player_x==492 && s.round_tick==3); /* Restart executes once. */
 assert(clock.total_steps==4 && clock.accumulator_x60==2000000);
 input.pressed=0;
 assert(game_advance(&clock,&s,&input,0)==2 && !clock.slow && s.round_tick==5);
 assert(game_advance(&clock,&s,&input,1000000)==4 && clock.slow && clock.discarded_wall_us);
 clock=(game_clock){0}; assert(!game_reset(&s,32,7)); s.score=99;
 input=(game_input){.pressed=V3_KEY_RESTART};
 assert(!game_advance(&clock,&s,&input,1000));
 input.pressed=0;
 assert(game_advance(&clock,&s,&input,16000)==1 && s.score==0 && s.round_tick==0);
 s.player_x=INT32_MAX; other=s;
 assert(game_update(&s,&input)==GPU_DRIVER_ARGUMENT && !memcmp(&s,&other,sizeof s));
 puts("PASS interactive game: manual/slow/diagonal/bounds/fire/hit/restart/compare/budget/bounded clock");
 return 0;
}
