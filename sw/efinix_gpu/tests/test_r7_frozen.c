#include "bullet_demo.h"
#include <assert.h>
#include <stdio.h>
static bullet_state state;
static bullet_stream scene;
static uint32_t digest;
static void word(uint32_t v) {
 for(unsigned b=0;b<4;b++) { digest^=(v>>(8*b))&255u; digest*=16777619u; }
}
static uint32_t trajectory(unsigned count) {
 digest=2166136261u;
 assert(!bullet_reset(&state,count,7));
 for(unsigned tick=0;tick<600;tick++) {
  word(state.tick); word(state.round_tick); word(state.score); word(state.grazes);
  word((uint32_t)state.player_x); word((uint32_t)state.player_y);
  word(state.hp); word(state.invulnerable); word(state.game_over_ticks);
  for(unsigned i=0;i<count;i++) {
   const bullet_object *b=&state.objects[i];
   word((uint32_t)b->x); word((uint32_t)b->y); word((uint32_t)b->vx); word((uint32_t)b->vy);
   word(b->age); word(b->kind); word(b->shape); word(b->grazed);
  }
  assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene));
  word(scene.count); word(scene.visible); word(scene.scene_pixels);
  word(scene.alpha_commands); word(scene.alpha_pixels);
  for(unsigned i=0;i<scene.count;i++) {
   const gpu_command *c=&scene.commands[i];
   word(c->op); word(c->src_addr); word(c->dst_addr); word(c->src_stride); word(c->dst_stride);
   word(c->width_pixels); word(c->height_pixels); word(c->color_key); word(c->alpha);
  }
  assert(!bullet_step(&state));
 }
 return digest;
}
int main(void) {
 static const unsigned tiers[]={32,128,512};
#ifndef R7_CAPTURE
 static const uint32_t expected[]={0x0cec877au,0x225e4a68u,0x598a29dfu};
#endif
 for(unsigned i=0;i<3;i++) {
  uint32_t actual=trajectory(tiers[i]);
  printf("R7_FROZEN,tier=%u,ticks=600,digest=%08x\n",tiers[i],actual);
#ifndef R7_CAPTURE
  assert(actual==expected[i]);
#endif
 }
 puts("PASS R7 frozen 79a0b7f state and command semantics");
 return 0;
}
