#include "bullet_demo.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
static int reference(unsigned shape,unsigned x,unsigned y) {
 if(x>=8 || y>=8)return 0;
 int dx=(int)x*2-7,dy=(int)y*2-7;
 if(dx<0)dx=-dx;
 if(dy<0)dy=-dy;
 int r=dx*dx+dy*dy;
 switch(shape) {
 case 0:return r<=49;
 case 1:return dx+dy<=8;
 case 2:return dx<=1 || (dx<=3 && dy<=3);
 case 3:return dx<=1 || dy<=1;
 case 4:return dx<=1 || dy<=1 || dx==dy;
 case 5:return r<=49 && r>=18;
 default:return 0;
 }
}
int main(void) {
 for(unsigned s=0;s<9;s++)for(unsigned y=0;y<10;y++)for(unsigned x=0;x<10;x++)
  assert(bullet_shape_opaque(s,x,y)==reference(s,x,y));
 assert(!bullet_shape_opaque(UINT32_MAX,0,0));
 assert(!bullet_shape_opaque(0,UINT32_MAX,0));
 assert(!bullet_shape_opaque(0,0,UINT32_MAX));
 puts("SHAPE_MASK,PASS,all_texels,all_shapes,out_of_bounds");
}
