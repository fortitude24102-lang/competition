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
