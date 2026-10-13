/* Real interactive logic/commands. No GPU, PC game loop or wall-clock RNG. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "replay_input.h"
static bullet_state state;
static bullet_stream scene;
static replay_recording record,bad;
static replay_cursor cursor;
static bullet_state replayed;
static uint32_t enemy_destination(unsigned enemy) {
 assert(!game_build(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene));
 for(unsigned i=0;i<scene.count;i++)
  if(scene.commands[i].src_addr==BULLET_LOCAL_ATLAS+BULLET_EMITTER_OFFSET+enemy*512u)
   return scene.commands[i].dst_addr;
 assert(0 && "living enemy missing");return 0;
}
static void moving_enemy_is_actually_rendered(void) {
 assert(!game_reset(&state,64,7));
 uint32_t before=enemy_destination(0);
 game_input input={0};
 for(unsigned i=0;i<180;i++) {
  state.invulnerable=60;assert(!game_update(&state,&input));
 }
 assert(enemy_destination(0)!=before);
}
static void waypoint_bounds_seed_and_continuity(void) {
 assert(!game_reset(&state,64,7));
 for(unsigned enemy=0;enemy<3;enemy++) {
  int old_x,old_y;assert(!bullet_enemy_position(&state,enemy,&old_x,&old_y));
  for(unsigned tick=1;tick<5000;tick++) {
   int x,y;state.round_tick=tick;
   assert(!bullet_enemy_position(&state,enemy,&x,&y));
   assert(x>=120 && x<=840 && y>=100 && y<=280);
   assert(x-old_x>=-3 && x-old_x<=3 && y-old_y>=-2 && y-old_y<=2);
   old_x=x;old_y=y;
  }
  state.round_tick=0;
 }
 state.round_tick=180;int x,y,other_x,other_y;
 assert(!bullet_enemy_position(&state,0,&x,&y));
 assert(!game_reset(&state,64,8));state.round_tick=180;
 assert(!bullet_enemy_position(&state,0,&other_x,&other_y));
 assert(x!=other_x || y!=other_y);
 assert(bullet_enemy_position(&state,3,&x,&y)==GPU_DRIVER_ARGUMENT);
}
static void park_hostiles(void) {
 for(unsigned i=0;i<state.count-GAME_SHOT_SLOTS;i++)
  state.objects[i]=(bullet_object){.x=16*256,.y=400*256,.kind=(uint8_t)(i%3)};
 state.invulnerable=60;
}
static void distinct_paths_and_velocity_changes(void) {
 assert(!game_reset(&state,64,7));
 unsigned mask=0;
 for(unsigned i=0;i<6;i++) mask|=1u<<state.objects[i].path;
 assert(mask==63u);
 park_hostiles();game_input in={0};
 state.objects[2]=(bullet_object){.x=400*256,.y=300*256,.vy=384,.kind=2,.path=2};
 state.objects[3]=(bullet_object){.x=400*256,.y=300*256,.vx=512,.kind=0,.path=3,.age=12};
 state.objects[4]=(bullet_object){.x=400*256,.y=300*256,.vy=192,.kind=1,.path=4,.age=8};
 state.objects[5]=(bullet_object){.x=951*256,.y=300*256,.vx=512,.vy=384,.kind=2,.path=5};
 assert(!game_update(&state,&in));
 assert(state.objects[2].vx==128); /* Q8 weave, first lobe. */
 assert(state.objects[3].vx==362 && state.objects[3].vy==362); /* arc turns */
 assert(state.objects[4].vy==224); /* acceleration, not constant velocity */
 assert(state.objects[5].vx==-512 && state.objects[5].x==952*256); /* ricochet */
 for(unsigned i=0;i<8;i++) assert(!game_update(&state,&in));
 assert(state.objects[2].vx!=128);
 /* Recycled shot: moving emitter is the actual origin, aimed at player once. */
 state.objects[1].age=500;assert(!game_update(&state,&in));
 int x,y;assert(!bullet_enemy_position(&state,1,&x,&y));
 assert(state.objects[1].x==x*256 && state.objects[1].y==y*256);
 assert(state.objects[1].vx>0 && state.objects[1].vy>0);
}
static void hit_rendered_enemy(unsigned enemy) {
 uint32_t off=enemy_destination(enemy)-GPU_FRAMEBUFFER_A;
 int cx=(int)(off%GPU_FRAME_STRIDE)/2+8,cy=(int)(off/GPU_FRAME_STRIDE)+8;
 state.objects[state.count-1]=(bullet_object){.x=(cx-4)*256,.y=(cy+4)*256,.vy=-2048,.kind=3,.shape=2};
 game_input in={0};assert(!game_update(&state,&in));
 assert(state.objects[state.count-1].age==UINT16_MAX);
}
static void victory_requires_three_kills_and_can_restart(void) {
 assert(!game_reset(&state,64,7));park_hostiles();
 for(unsigned enemy=0;enemy<3;enemy++) {
  for(unsigned shot=0;shot<6;shot++) {
   assert(!state.won);hit_rendered_enemy(enemy);
   assert(state.enemy_hp[enemy]==5u-shot);
  }
  assert(state.won==(enemy==2));
  assert(!game_build(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene));
  for(unsigned i=0;i<scene.count;i++)
   assert(scene.commands[i].src_addr!=BULLET_LOCAL_ATLAS+BULLET_EMITTER_OFFSET+enemy*512u);
  if(enemy<2) {
   /* A dead emitter cannot recycle an old projectile into a new one. */
   state.objects[enemy].age=500;
   game_input empty={0};assert(!game_update(&state,&empty));
   assert(state.objects[enemy].age==UINT16_MAX);
  }
 }
 uint32_t round=state.round_tick,score=state.score,tick=state.tick;
 int x=state.player_x,y=state.player_y;
 game_input in={.held=V3_KEY_RIGHT|V3_KEY_FIRE};
 assert(!game_update(&state,&in));
 assert(state.won && state.round_tick==round && state.tick==tick+1 && state.score==score);
 assert(state.player_x==x && state.player_y==y);
 assert(!game_build(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene));
 unsigned fills=0;
 for(unsigned i=0;i<scene.count;i++) {
  const gpu_command *c=&scene.commands[i];
  if(c->op==GPU_OP_FILL) ++fills;
  unsigned off=c->dst_addr-GPU_FRAMEBUFFER_A;
  assert((off/GPU_FRAME_STRIDE>=72 && off/GPU_FRAME_STRIDE+c->height_pixels<=540) || i==0);
 }
 assert(fills>10 && scene.count<=45); /* WIN + R fits even minimum pool capacity. */
 in.pressed=V3_KEY_RESTART;assert(!game_update(&state,&in));
 assert(!state.won && state.hp==3 && !state.round_tick && !state.score && state.enemy_hp[0]==6);
}
static void winning_tick_replays_identically(void) {
 assert(!game_reset(&state,64,7));park_hostiles();
 state.enemy_hp[0]=state.enemy_hp[1]=0;state.enemy_hp[2]=1;
 uint32_t off=enemy_destination(2)-GPU_FRAMEBUFFER_A;
 int cx=(int)(off%GPU_FRAME_STRIDE)/2+8,cy=(int)(off/GPU_FRAME_STRIDE)+8;
 state.objects[state.count-1]=(bullet_object){.x=(cx-4)*256,.y=(cy+4)*256,.vy=-2048,.kind=3,.shape=2};
 assert(!replay_init(&record,&state,3));
 game_input in={0};
 for(unsigned i=0;i<600;i++) {
  assert(!replay_record(&record,&in));assert(!game_update(&state,&in));
  assert(state.won && state.enemy_hp[2]==0 && state.round_tick==1);
 }
 assert(!replay_seal(&record));
 for(unsigned backend=0;backend<2;backend++) {
  assert(!replay_begin(&record,3,&replayed,&cursor));
  assert(!replayed.won && replayed.enemy_hp[2]==1);
  for(unsigned i=0;i<600;i++) {
   assert(replay_next(&record,&cursor,&in)==1);assert(!game_update(&replayed,&in));
   assert(replayed.won && replayed.round_tick==1);
  }
  assert(!memcmp(&state,&replayed,sizeof state));
 }
}
static void replay_protects_new_logical_fields(void) {
 assert(!game_reset(&state,64,7));assert(!replay_init(&record,&state,3));
 game_input in={0};
 for(unsigned i=0;i<600;i++) assert(!replay_record(&record,&in));
 assert(!replay_seal(&record));
 bad=record;--bad.initial.enemy_hp[0];
 assert(replay_begin(&bad,3,&state,&cursor)==GPU_DRIVER_ARGUMENT);
 bad=record;bad.initial.objects[2].path=1;
 assert(replay_begin(&bad,3,&state,&cursor)==GPU_DRIVER_ARGUMENT);
 bad=record;bad.initial.won=1;
 assert(replay_begin(&bad,3,&state,&cursor)==GPU_DRIVER_ARGUMENT);
}
int main(int argc,char **argv) {
 if(argc==1 || !strcmp(argv[1],"motion")) {moving_enemy_is_actually_rendered();waypoint_bounds_seed_and_continuity();}
 if(argc==1 || !strcmp(argv[1],"paths")) distinct_paths_and_velocity_changes();
 if(argc==1 || !strcmp(argv[1],"victory")) {victory_requires_three_kills_and_can_restart();winning_tick_replays_identically();}
 if(argc==1 || !strcmp(argv[1],"crc")) replay_protects_new_logical_fields();
 puts("PASS enemy campaign movement/paths/victory/replay fields");return 0;
}
