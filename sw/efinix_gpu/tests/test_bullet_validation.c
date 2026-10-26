#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "bullet_demo.h"
static bullet_state canonical,state,before;
int main(void) {
 unsigned checks=0,rejected=0;
 for(unsigned interactive=0;interactive<2;interactive++)for(unsigned manual=0;manual<2;manual++) {
  assert(!(interactive?bullet_reset_player(&canonical,BULLET_MAX_OBJECTS,7):bullet_reset(&canonical,BULLET_MAX_OBJECTS,7)));
  const unsigned indices[]={0,BULLET_MAX_OBJECTS/2,BULLET_MAX_OBJECTS-1};
  for(unsigned at=0;at<3;at++)for(unsigned field=0;field<3;field++)for(unsigned value=0;value<256;value++) {
   state=canonical;
   bullet_object *b=&state.objects[indices[at]];
   if(field==0)b->kind=(uint8_t)value;
   else if(field==1)b->shape=(uint8_t)value;
   else b->path=(uint8_t)value;
   before=state;
   int invalid=field==0?value>(manual?3u:2u):field==1?value>=BULLET_SHAPE_COUNT:interactive && value>=BULLET_PATH_COUNT;
   int result=manual?bullet_step_player(&state,480,480):bullet_step(&state);
   assert(result==(invalid?GPU_DRIVER_ARGUMENT:0));
   if(invalid){assert(!memcmp(&state,&before,sizeof state));++rejected;}
   ++checks;
  }
 }
 printf("PASS object validation: checks=%u rejected_unchanged=%u, all byte values, first/middle/last, auto/manual and interactive/legacy\n",checks,rejected);
}
