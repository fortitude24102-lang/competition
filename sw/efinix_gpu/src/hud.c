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

static int append_fill(hud_command_stream *s,uint32_t dst,uint32_t stride,
 uint16_t x,uint16_t y,uint16_t w,uint16_t h,uint16_t color) {
 if(s->count>=HUD_MAX_COMMANDS) return GPU_DRIVER_FULL;
 s->commands[s->count++]=(gpu_command){.op=GPU_OP_FILL,
  .dst_addr=dst+(uint32_t)y*stride+(uint32_t)x*2u,.dst_stride=stride,
  .width_pixels=w,.height_pixels=h,.color=color};
 return 0;
}

static int append_number(hud_command_stream *s,uint32_t dst,uint32_t stride,
 uint16_t x,uint16_t y,unsigned value,uint16_t color) {
 if(value>999) value=999;
 unsigned v[3]={value/100,(value/10)%10,value%10};
 unsigned first=v[0]?0:v[1]?1:2;
 for(unsigned n=first;n<3;n++) for(unsigned row=0;row<5;row++) {
  unsigned bits=digits[v[n]][row];
  for(unsigned col=0;col<3;) {
   if(!(bits&(4u>>col))) { ++col; continue; }
   unsigned start=col;
   while(col<3 && (bits&(4u>>col))) ++col;
   int e=append_fill(s,dst,stride,(uint16_t)(x+(n-first)*4u+start),
    (uint16_t)(y+row),(uint16_t)(col-start),1,color);
   if(e) return e;
  }
 }
 return 0;
}

int hud_build_metrics(uint32_t dst,uint32_t stride,uint16_t x,uint16_t y,
 const hud_metrics *m,hud_command_stream *s) {
 if(!m || !s || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B) || stride<1280 || (stride&1u) ||
  (uint32_t)x+127u>GPU_FRAME_WIDTH || (uint32_t)y+5u>GPU_FRAME_HEIGHT)
  return GPU_DRIVER_ARGUMENT;
 *s=(hud_command_stream){0};
 const unsigned values[6]={m->fps,m->sprite_count,m->cpu_busy_permille,
  m->queue_high_watermark,m->underflow_count,m->error_code};
 for(unsigned i=0;i<6;i++) {
  uint16_t color=i>=4 && values[i] ? 0xf800 : 0xffff;
  int e=append_number(s,dst,stride,(uint16_t)(x+i*20u),y,values[i],color);
  if(e) return e;
 }
 return append_fill(s,dst,stride,(uint16_t)(x+124u),y,3,5,m->batch_mode?0x07e0:0x001f);
}
