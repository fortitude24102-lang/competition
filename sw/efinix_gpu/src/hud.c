#include "hud.h"
static const uint8_t digits[10][5]={
 {7,5,5,5,7},{2,6,2,2,7},{7,1,7,4,7},{7,1,7,1,7},{5,5,7,1,1},
 {7,4,7,1,7},{7,4,7,5,7},{7,1,1,1,1},{7,5,7,5,7},{7,5,7,1,7}
};
int hud_draw_fps(gpu_device *d,uint32_t dst,uint32_t stride,uint16_t x,uint16_t y,unsigned fps,uint16_t color,uint16_t scale,uint32_t polls) {
 if(!d || !scale || fps>999) return GPU_DRIVER_ARGUMENT;
 unsigned values[3]={fps/100,(fps/10)%10,fps%10},first=values[0]?0:values[1]?1:2;
 for(unsigned n=first;n<3;n++) for(unsigned row=0;row<5;row++) for(unsigned col=0;col<3;col++) if(digits[values[n]][row]&(4u>>col)) {
  uint32_t px=x+(n-first)*4u*scale+col*scale,py=y+row*scale; uint16_t tag;
  int e=gpu_fill_async(d,dst+py*stride+px*2u,stride,scale,scale,color,&tag); if(e) return e;
  e=gpu_wait_tag(d,tag,polls); if(e) return e;
 }
 return 0;
}
