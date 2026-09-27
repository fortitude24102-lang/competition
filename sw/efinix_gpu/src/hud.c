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
 if(!m || !s || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B) || stride<GPU_FRAME_STRIDE || (stride&1u) ||
  (uint32_t)x+151u>GPU_FRAME_WIDTH || (uint32_t)y+5u>GPU_FRAME_HEIGHT)
  return GPU_DRIVER_ARGUMENT;
 *s=(hud_command_stream){0};
 const unsigned values[7]={m->fps,m->sprite_count,m->cpu_busy_permille,
  m->queue_high_watermark,m->underflow_count,m->render_stalls,m->error_code};
 for(unsigned i=0;i<7;i++) {
  uint16_t color=i>=4 && values[i] ? 0xf800 : 0xffff;
  int e=append_number(s,dst,stride,(uint16_t)(x+i*20u),y,values[i],color);
  if(e) return e;
 }
 int e=append_fill(s,dst,stride,(uint16_t)(x+144u),y,3,5,m->batch_mode?0x07e0:0x001f);
 if(e) return e;
 return append_fill(s,dst,stride,(uint16_t)(x+148u),y,3,5,m->qos_adaptive?0x07e0:0xf800);
}

static const uint8_t letters[26][5]={
 {2,5,7,5,5},{6,5,6,5,6},{3,4,4,4,3},{6,5,5,5,6},{7,4,6,4,7},
 {7,4,6,4,4},{3,4,5,5,3},{5,5,7,5,5},{7,2,2,2,7},{1,1,1,5,2},
 {5,5,6,5,5},{4,4,4,4,7},{5,7,7,5,5},{5,7,7,7,5},{2,5,5,5,2},
 {6,5,6,4,4},{2,5,5,3,1},{6,5,6,5,5},{3,4,2,1,6},{7,2,2,2,2},
 {5,5,5,5,7},{5,5,5,5,2},{5,5,7,7,5},{5,5,2,5,5},{5,5,2,2,2},{7,1,2,4,7}
};
/* Fixed labels plus bounded unsigned fields fit in 64 columns. Avoid pulling
 * the full bare-metal printf formatter into the 124 KiB firmware RAM. */
static char *text(char *out,const char *s) {
 while(*s) *out++=*s++;
 *out=0; return out;
}
static char *number(char *out,uint32_t n) {
 char reverse[10]; unsigned count=0;
 do { reverse[count++]=(char)('0'+n%10u); n/=10u; } while(n);
 while(count) *out++=reverse[--count];
 *out=0; return out;
}
int hud_comparison_text(const hud_comparison *m,char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS]) {
 if(!m || !lines) return GPU_DRIVER_ARGUMENT;
 uint32_t fps[2]={m->cpu_fps_x10,m->gpu_fps_x10},us[2]={m->cpu_render_us,m->gpu_render_us};
 unsigned valid[2]={m->cpu_valid,m->gpu_valid};
 for(unsigned i=0;i<2;i++) {
  unsigned f=fps[i]>99999?99999:fps[i],ms=us[i]/1000u;
  if(ms>99999) ms=99999;
  char *p=text(lines[i],i?"GPU FPS ":"CPU FPS ");
  if(valid[i]) {
   p=number(p,f/10); p=text(p,"."); p=number(p,f%10);
   p=text(p,"  RENDER MS "); p=number(p,ms); p=text(p,".");
   number(p,(us[i]/100u)%10);
  } else text(p,"--  RENDER MS --");
 }
 char *p=text(lines[2],m->gpu_active?"MODE GPU  N ":"MODE CPU  N ");
 p=number(p,m->sprites); p=text(p,"  NET "); text(p,m->network_ready?"READY":"FAIL FALLBACK");
 text(lines[3],"KEY1 LESS KEY2 MORE  30 FRAME FPS WITH PRESENT");
 return 0;
}
int hud_build_comparison(uint32_t dst,const hud_comparison *m,hud_command_stream *s) {
 if(!s || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B)) return GPU_DRIVER_ARGUMENT;
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 int e=hud_comparison_text(m,lines); if(e) return e;
 s->count=0;
 e=append_fill(s,dst,GPU_FRAME_STRIDE,0,0,GPU_FRAME_WIDTH,72,0x0000); if(e) return e;
 for(unsigned line=0;line<HUD_COMPARISON_LINES;line++) for(unsigned n=0;lines[line][n];n++) {
  unsigned char ch=(unsigned char)lines[line][n];
  for(unsigned row=0;row<5;row++) {
   unsigned bits=ch>='A'&&ch<='Z'?letters[ch-'A'][row]:
    ch>='0'&&ch<='9'?digits[ch-'0'][row]:ch=='-'?(row==2?7:0):ch=='.'?(row==4?2:0):0;
   for(unsigned col=0;col<3;) {
    if(!(bits&(4u>>col))) { ++col; continue; }
    unsigned first=col;
    while(col<3 && (bits&(4u>>col))) ++col;
    e=append_fill(s,dst,GPU_FRAME_STRIDE,(uint16_t)(8+n*8+first*2),
     (uint16_t)(5+line*16+row*2),(uint16_t)((col-first)*2),2,line==2?0x07e0:0xffff); if(e) return e;
   }
  }
 }
 return 0;
}
