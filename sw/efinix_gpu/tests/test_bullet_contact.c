#include "bullet_demo.h"
#include <assert.h>
#include <stdio.h>

/* Independent original analytic shapes and per-texel distance oracle.
 * Detects an incorrect bit, axis, radius or hit/graze precedence. */
static int opaque(unsigned shape,int x,int y) {
 int dx=x*2-7,dy=y*2-7;
 if(dx<0)dx=-dx;
 if(dy<0)dy=-dy;
 int r=dx*dx+dy*dy;
 switch(shape) {
 case 0:return r<=49;
 case 1:return dx+dy<=8;
 case 2:return dx<=1 || (dx<=3 && dy<=3);
 case 3:return dx<=1 || dy<=1;
 case 4:return dx<=1 || dy<=1 || dx==dy;
 default:return r<=49 && r>=18;
 }
}
static bullet_state initial,state;
static void lifetime_boundaries(void) {
 assert(!bullet_reset_player(&initial,BULLET_MAX_OBJECTS,7));
 for(unsigned i=0;i<initial.count;i++)initial.objects[i].age=UINT16_MAX;
 /* Inactive earlier objects must still advance the loop's lifetime phase. */
 for(unsigned i=0;i<initial.count;i++)for(unsigned expired=0;expired<2;expired++) {
  state=initial;
  bullet_object *b=&state.objects[i];
  b->kind=0;b->path=0;b->x=100*256;b->y=120*256;b->vx=16;b->vy=0;
  b->age=(uint16_t)(239+i%120u+expired);
  assert(!bullet_step_player(&state,480,480));
  assert(b->age==(expired?0:240+i%120u));
  if(!expired)assert(b->x==100*256+16 && b->y==120*256);
 }
 printf("LIFETIME,PASS,indices=%u,before_expiry,at_expiry,inactive_prefix\n",initial.count);
}
int main(void) {
 lifetime_boundaries();
 assert(!bullet_reset_player(&initial,32,7));
 for(unsigned i=0;i<initial.count;i++)initial.objects[i].age=UINT16_MAX;
 unsigned cases=0;
 for(unsigned shape=0;shape<6;shape++)for(int dy=-23;dy<=16;dy++)
 for(int dx=-23;dx<=16;dx++) {
  int hit=0,near=0;
  for(int y=0;y<8;y++)for(int x=0;x<8;x++)if(opaque(shape,x,y)) {
   int r=(dx+x)*(dx+x)+(dy+y)*(dy+y);
   hit|=r<=9;near|=r<=144;
  }
  for(unsigned protected=0;protected<2;protected++)for(unsigned grazed=0;grazed<2;grazed++) {
   state=initial;
   state.invulnerable=(uint16_t)protected;
   bullet_object *b=&state.objects[0];
   b->x=(480+dx)*256;b->y=(480+dy)*256;
   b->vx=b->vy=0;b->age=1;b->shape=(uint8_t)shape;b->path=0;b->grazed=(uint8_t)grazed;
   assert(!bullet_step_player(&state,480,480));
   assert(state.hp==BULLET_START_HP-(hit && !protected));
   unsigned graze=(unsigned)(!hit && near && !grazed);
   assert(state.grazes==graze && state.score==10u*graze);
   ++cases;
  }
 }
 printf("CONTACT_MASK,PASS,cases=%u,all_offsets,shield,prior_graze,hit_precedence\n",cases);
}
