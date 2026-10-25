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
static int floor_reference(int32_t q8) {
 int whole=q8/256;
 return whole-(q8<0 && q8%256);
}
static void fractional_contacts(void) {
 assert(!bullet_reset_player(&initial,32,7));
 for(unsigned i=0;i<initial.count;i++)initial.objects[i].age=UINT16_MAX;
 /* Left screen edge gives negative fractional Q8 with legal player coordinates. */
 static const int32_t xs[]={-2047,-1793,-257,-256,-255,-1,0,1,255,256,257,2047};
 static const int32_t ys[]={64*256,68*256-1,68*256,72*256-1,72*256,
  76*256-1,76*256,80*256-1,80*256,80*256+1,84*256-1,84*256};
 unsigned cases=0;
 for(unsigned shape=0;shape<6;shape++)
 for(unsigned ix=0;ix<sizeof xs/sizeof xs[0];ix++)
 for(unsigned iy=0;iy<sizeof ys/sizeof ys[0];iy++) {
  state=initial;state.player_x=8;state.player_y=80;
  bullet_object *b=&state.objects[0];
  b->x=xs[ix];b->y=ys[iy];b->vx=b->vy=0;b->age=1;
  b->kind=0;b->path=0;b->shape=(uint8_t)shape;
  int hit=0,near=0,bx=floor_reference(b->x),by=floor_reference(b->y);
  for(int y=0;y<8;y++)for(int x=0;x<8;x++)if(opaque(shape,x,y)) {
   int dx=bx+x-8,dy=by+y-80,r=dx*dx+dy*dy;
   hit|=r<=9;near|=r<=144;
  }
  assert(!bullet_step_player(&state,8,80));
  assert(state.hp==BULLET_START_HP-hit);
  assert(state.grazes==(unsigned)(!hit && near));
  assert(state.score==(unsigned)(!hit && near)*10u);
  ++cases;
 }
 static const int32_t friendly_x[]={-1025,-1024,100*256,100*256};
 static const int32_t friendly_y[]={100*256,100*256,68*256-1,68*256};
 for(unsigned i=0;i<4;i++) {
  state=initial;
  bullet_object *b=&state.objects[0];
  b->kind=3;b->age=0;b->x=friendly_x[i];b->y=friendly_y[i];b->vx=b->vy=0;
  assert(!bullet_step_player(&state,480,480));
  assert(b->age==(i%2u?1:UINT16_MAX));
 }
 printf("LOGIC_Q8,PASS,contact_cases=%u,negative_fraction,friendly_screen_edges\n",cases);
}
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
 fractional_contacts();
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
