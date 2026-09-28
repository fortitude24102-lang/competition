#include "bullet_demo.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static bullet_state s,first,window;
static bullet_stream stream;
static void place(unsigned i,int x,int y) {
 s.objects[i].x=x*256; s.objects[i].y=y*256;
 s.objects[i].vx=s.objects[i].vy=0;
 s.objects[i].shape=0; s.objects[i].age=0; s.objects[i].grazed=0;
}
int main(void) {
 assert(!bullet_reset(&s,2,7) && s.hp==3 && s.score==0);
 place(0,479,476); place(1,479,476); /* Next auto-pilot point is (483,480). */
 assert(!bullet_step(&s));
 assert(s.player_x==483 && s.hp==2 && s.invulnerable==60);
 assert(s.objects[0].age==0 && !s.objects[0].grazed);
 /* Protection consumes exactly two future updates, not just one. */
 s.invulnerable=2;
 for(unsigned n=0;n<2;n++) {
  place(0,s.player_x-1,476); assert(!bullet_step(&s)); assert(s.hp==2);
 }
 assert(!s.invulnerable);
 place(0,s.player_x-1,476); assert(!bullet_step(&s) && s.hp==1);
 assert(!bullet_reset(&s,1,7));
 place(0,493,476); /* Nearby opaque texels are outside the 3-pixel hit core. */
 assert(!bullet_step(&s) && s.hp==3 && s.grazes==1 && s.score==10);
 assert(s.objects[0].grazed);
 assert(!bullet_step(&s) && s.grazes==1 && s.score==10);
 s.objects[0].y=600*256; /* Recycling an already-grazed bullet clears its flag. */
 assert(!bullet_step(&s) && !s.objects[0].grazed);
 place(0,s.player_x+13,476);
 assert(!bullet_step(&s) && s.grazes==2 && s.score==20 && s.objects[0].grazed);
 assert(!bullet_reset(&s,1,7));
 s.score=UINT32_MAX-5; s.grazes=UINT32_MAX; place(0,493,476);
 assert(!bullet_step(&s) && s.score==UINT32_MAX && s.grazes==UINT32_MAX);
 /* Invalid shape is rejected before advancing any gameplay state. */
 assert(!bullet_reset(&s,1,7));
 place(0,493,476); s.objects[0].shape=6;
 first=s; assert(bullet_step(&s)==GPU_DRIVER_ARGUMENT && !memcmp(&first,&s,sizeof s));
 assert(!bullet_reset(&s,1,7)); place(0,479,476); s.hp=1;
 assert(!bullet_step(&s) && s.hp==0 && s.game_over_ticks==120);
 unsigned tick=s.tick; first=s;
 for(unsigned n=0;n<119;n++) assert(!bullet_step(&s) && s.hp==0);
 assert(!memcmp(s.objects,first.objects,sizeof s.objects) && s.tick==tick+119);
 assert(!bullet_step(&s) && s.hp==3 && s.round_tick==0 && s.tick==tick+120);
 assert(s.score==0 && s.grazes==0);
 static const unsigned times[]={1,60,120,180,239};
 static const int xs[]={483,660,480,300,477};
 for(unsigned n=0;n<5;n++) {
  assert(!bullet_reset(&s,1,7)); s.round_tick=times[n]-1;
  assert(!bullet_step(&s) && s.player_x==xs[n]);
 }
 /* Four 60-tick waves reuse the same slots, but change the launch pattern.
  * Check both radial/spiral lanes and the alternating biased fan. */
 static const int wave_vx[]={384,0,-512,0,384};
 static const int wave_vy[]={0,448,0,-576,0};
 static const int fan_vx[]={355,171,474,220,355};
 static const int fan_vy[]={147,414,196,533,147};
 for(unsigned wave=0;wave<5;wave++) {
  assert(!bullet_reset(&s,3,7));
  s.round_tick=wave ? wave*60u-1u : 0u;
  for(unsigned i=0;i<3;i++) s.objects[i].x=960*256;
  assert(!bullet_step(&s));
  assert(s.objects[0].vx==wave_vx[wave] && s.objects[0].vy==wave_vy[wave]);
  assert(s.objects[0].shape==(wave&3u));
  assert(s.objects[1].vx==fan_vx[wave] && s.objects[1].vy==fan_vy[wave]);
  assert(s.objects[2].vx==wave_vx[wave] && s.objects[2].vy==wave_vy[wave]);
 }
 /* The maximum-density unattended showcase must reach all four waves before
  * its first death, rather than merely supporting forced phase fixtures. */
 assert(!bullet_reset(&s,512,7));
 unsigned seen_waves=0;
 for(unsigned frame=0;frame<240u && s.hp;frame++) {
  assert(!bullet_step(&s));
  for(unsigned i=0;i<s.count;i++) if(s.objects[i].age==0) {
   unsigned wave=(s.objects[i].shape+BULLET_SHAPE_COUNT-i%BULLET_SHAPE_COUNT)%BULLET_SHAPE_COUNT;
   if(wave<4u) seen_waves|=1u<<wave;
  }
 }
 assert(seen_waves==15u);
 /* The existing three Alpha halos telegraph a wave change for 16 ticks.
  * Their geometry and the overall command/pixel budget stay fixed. */
 assert(!bullet_reset(&s,1,7));
 s.round_tick=59;
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 unsigned warning_count=stream.count,warning_alpha=stream.alpha_commands;
 uint32_t warning_pixels=stream.alpha_pixels;
 for(unsigned n=0;n<3;n++) {
  const gpu_command *c=&stream.commands[stream.count-6u+n*2u];
  assert(c->op==GPU_OP_ALPHA && c->alpha==208);
 }
 s.round_tick=60;
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 assert(stream.count==warning_count && stream.alpha_commands==warning_alpha &&
        stream.alpha_pixels==warning_pixels);
 for(unsigned n=0;n<3;n++) assert(stream.commands[stream.count-6u+n*2u].alpha==80);
 s.round_tick=43;
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 assert(stream.commands[stream.count-6u].alpha==80);
 s.round_tick=44;
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 assert(stream.commands[stream.count-6u].alpha==88);
 s.hp=0; s.round_tick=59;
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 assert(stream.commands[stream.count-6u].alpha==80);
 /* Full effect budget and no partial stream on exhaustion. */
 assert(!bullet_reset(&s,512,7));
 for(unsigned i=0;i<512;i++) place(i,100,100);
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
 assert(stream.count==585 && stream.alpha_commands==68 && stream.alpha_pixels==9792);
 assert(bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,1,584,&stream)==GPU_DRIVER_FULL);
 assert(stream.count==0 && stream.alpha_commands==0 && stream.alpha_pixels==0);
 assert(!bullet_build_frame(&s,GPU_FRAMEBUFFER_A,0,0,BULLET_MAX_COMMANDS,&stream));
 assert(stream.count==517 && stream.alpha_commands==0);
 /* Gameplay, hit flags and effects remain part of the CPU/GPU state snapshot. */
 assert(!bullet_reset(&s,32,7)); place(0,479,476); window=s;
 for(unsigned n=0;n<30;n++) assert(!bullet_step(&s));
 first=s;
 assert(!bullet_finish_window(&s,&window,0));
 for(unsigned n=0;n<30;n++) assert(!bullet_step(&s));
 assert(!memcmp(&s,&first,sizeof s));
 puts("PASS gameplay: hit/protection/graze/death/restart/autopilot/effect budget/replay/overflow/graze recycle");
 return 0;
}
