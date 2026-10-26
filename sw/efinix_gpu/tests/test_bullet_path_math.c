#include <assert.h>
#include <stdio.h>
#include "bullet_demo.h"
static bullet_state state;
static const int old_direction[16][2]={
 {256,0},{237,98},{181,181},{98,237},{0,256},{-98,237},{-181,181},{-237,98},
 {-256,0},{-237,-98},{-181,-181},{-98,-237},{0,-256},{98,-237},{181,-181},{237,-98}
};
int main(void) {
 unsigned checked=0,expired=0;
 for(unsigned path=2;path<=3;path++) for(unsigned age=0;age<360;age++) {
  assert(!bullet_reset_player(&state,BULLET_MAX_OBJECTS,7));
  for(unsigned i=0;i<state.count;i++) state.objects[i]=(bullet_object){
   .x=480*256,.y=200*256,.vx=17,.vy=31,.age=(uint16_t)age,.kind=0,.shape=0,.path=(uint8_t)path};
  assert(!bullet_step_player(&state,8,532));
  for(unsigned i=0;i<state.count;i++) {
   const bullet_object *b=&state.objects[i];
   if(age>=240+i%120u) {assert(b->age==0);++expired;continue;}
   int vx,vy;
   if(path==2) {vx=((int)(i%5u)-2)*96+old_direction[(age/4u)&15u][0]/2;vy=31;}
   else {unsigned angle=(i/3u+age/12u)&15u;vx=old_direction[angle][0]*2;vy=old_direction[angle][1]*2;}
   assert(b->vx==vx && b->vy==vy && b->age==age+1);
   assert(b->x==480*256+vx && b->y==200*256+vy);
   ++checked;
  }
 }
 printf("PASS original path arithmetic: capacity=%u valid=%u expired=%u, negative odd halves and every index/age\n",BULLET_MAX_OBJECTS,checked,expired);
}
