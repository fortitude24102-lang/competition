#include "interactive_game.h"
#include <limits.h>
static unsigned shot_start(const bullet_state *s) {
 unsigned slots=s->count>GAME_SHOT_SLOTS?GAME_SHOT_SLOTS:s->count/2u;
 return s->count-slots;
}
static void reserve_shots(bullet_state *s) {
 for(unsigned i=shot_start(s);i<s->count;i++) if(s->objects[i].kind!=3)
  s->objects[i]=(bullet_object){.kind=3,.shape=2,.age=UINT16_MAX};
}
int game_reset(bullet_state *s,unsigned count,uint32_t seed) {
 int e=bullet_reset(s,count,seed);
 if(!e) reserve_shots(s);
 return e;
}
static int clamp(int value,int low,int high) { return value<low?low:value>high?high:value; }
int game_update(bullet_state *s,const game_input *in) {
 if(!s || !in || !s->count || s->count>BULLET_MAX_OBJECTS ||
    s->player_x<8 || s->player_x>952 || s->player_y<80 || s->player_y>532 ||
    ((in->held|in->pressed|in->released)&~V3_KEY_MASK)) return GPU_DRIVER_ARGUMENT;
 if(in->pressed&V3_KEY_RESTART) return game_reset(s,s->count,s->seed);
 int dx=!!(in->held&V3_KEY_RIGHT)-!!(in->held&V3_KEY_LEFT);
 int dy=!!(in->held&V3_KEY_DOWN)-!!(in->held&V3_KEY_UP);
 int speed=(in->held&V3_KEY_SLOW)?1:(dx && dy)?3:4;
 int x=clamp(s->player_x+dx*speed,8,952),y=clamp(s->player_y+dy*speed,80,532);
 int e=bullet_step_player(s,x,y);
 if(e) return e;
 reserve_shots(s); /* Also restore reserved slots after automatic restart. */
 if(s->hp && (in->held&V3_KEY_FIRE) && s->round_tick%6u==1u)
  for(unsigned i=shot_start(s);i<s->count;i++) if(s->objects[i].age==UINT16_MAX) {
   s->objects[i]=(bullet_object){.x=(s->player_x-4)*256,.y=(s->player_y-16)*256,
    .vy=-2048,.kind=3,.shape=2};
   break;
  }
 return !!(in->pressed&V3_KEY_COMPARE);
}
int game_build(const bullet_state *s,uint32_t dst,int network,int glow,unsigned cap,bullet_stream *out) {
 return bullet_build_frame_player(s,dst,network,glow,cap,out);
}
static void lost_time(game_clock *c,uint32_t us) {
 c->discarded_wall_us=UINT32_MAX-c->discarded_wall_us<us?UINT32_MAX:c->discarded_wall_us+us;
}
int game_advance(game_clock *c,bullet_state *s,const game_input *in,uint32_t elapsed_us) {
 if(!c || !s || !in || c->accumulator_x60>4000000u) return GPU_DRIVER_ARGUMENT;
 c->slow=0; c->compare_requested=0;
 if(elapsed_us>250000u) { lost_time(c,elapsed_us-250000u); elapsed_us=250000u; c->slow=1; }
 c->accumulator_x60+=elapsed_us*60u;
 c->pending_pressed|=in->pressed; c->pending_released|=in->released;
 unsigned n=0;
 game_input tick_input=*in;
 tick_input.pressed=c->pending_pressed; tick_input.released=c->pending_released;
 while(c->accumulator_x60>=1000000u && n<GAME_MAX_CATCHUP) {
  int e=game_update(s,&tick_input);
  if(e<0) return e;
  c->accumulator_x60-=1000000u; ++c->total_steps; ++n;
  c->pending_pressed=c->pending_released=0;
  tick_input.pressed=tick_input.released=0;
  if(e) { c->compare_requested=1; break; }
 }
 if(c->accumulator_x60>=1000000u) c->slow=1;
 if(c->accumulator_x60>4000000u) {
  lost_time(c,(c->accumulator_x60-4000000u)/60u);
  c->accumulator_x60=4000000u;
 }
 return (int)n;
}
