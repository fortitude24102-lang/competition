#include "game_menu.h"
#include <string.h>
void game_menu_invalidate(game_menu_cache *c) {if(c)c->valid_mask=0;}
static void fill(hud_command_stream *s,uint32_t dst,unsigned x,unsigned y,unsigned w,unsigned h,unsigned color) {
 s->commands[s->count++]=(gpu_command){.op=GPU_OP_FILL,.dst_addr=dst+y*GPU_FRAME_STRIDE+x*2,
  .dst_stride=GPU_FRAME_STRIDE,.width_pixels=(uint16_t)w,.height_pixels=(uint16_t)h,.color=(uint16_t)color};
}
static void text(hud_command_stream *s,uint32_t dst,unsigned x,unsigned y,const char *str,int green) {
 for(unsigned n=0;str[n];n++) {
  const char *glyph=strchr(HUD_GLYPH_CHARACTERS,str[n]);
  unsigned index=glyph?(unsigned)(glyph-HUD_GLYPH_CHARACTERS):38u;
  s->commands[s->count++]=(gpu_command){.op=GPU_OP_COPY,
   .src_addr=HUD_GLYPH_ATLAS_ADDR+(green?HUD_GLYPH_BANK_BYTES:0)+index*HUD_GLYPH_CELL_BYTES,
   .src_stride=HUD_GLYPH_WIDTH*2,.dst_addr=dst+y*GPU_FRAME_STRIDE+(x+n*HUD_GLYPH_WIDTH)*2,
   .dst_stride=GPU_FRAME_STRIDE,.width_pixels=HUD_GLYPH_WIDTH,.height_pixels=HUD_GLYPH_HEIGHT};
 }
}
int game_menu_draw(gpu_device *gpu,game_menu_cache *c,unsigned index,uint32_t dst,
 uint32_t generation,int network,hud_command_stream *s,uint32_t polls) {
 if(!gpu || !gpu->ready || !c || !s || index>1 || !polls ||
    dst!=(index?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A) ||
    (c->levels && c->levels!=4 && c->levels!=6)) return GPU_DRIVER_ARGUMENT;
 _Static_assert(HUD_MAX_COMMANDS>=256,"menu scratch capacity");
 uint8_t bit=(uint8_t)(1u<<index),ready=(uint8_t)(network!=0);
 unsigned levels=c->levels==6?6u:4u;
 unsigned selected=c->selected_level<=levels?c->selected_level:0;
 int full=!(c->valid_mask&bit) || c->generation[index]!=generation || c->destination[index]!=dst || c->drawn_levels[index]!=levels || c->drawn_selection[index]!=selected;
 s->count=0;
 if(!full && c->network[index]==ready)return 0;
 c->valid_mask&=(uint8_t)~bit;
 if(full) {
  fill(s,dst,0,72,960,468,0);
  text(s,dst,270,96,"SELECT DIFFICULTY",1);
  const unsigned xs[]={96,496,96,496,96,496},ys[]={144,144,232,232,320,320},old_ys[]={144,144,288,288};
  const char *labels[]={"LEVEL 1 - 64 SPRITES","LEVEL 2 - 128 SPRITES","LEVEL 3 - 256 SPRITES","LEVEL 4 - 512 SPRITES","LEVEL 5 - 786 SPRITES","LEVEL 6 - 1024 SPRITES"};
  for(unsigned i=0;i<levels;i++) {
   unsigned y=levels==6?ys[i]:old_ys[i],h=levels==6?80u:104u;
   fill(s,dst,xs[i],y,368,h,selected==i+1u?0xffe0:0x07e0);
   fill(s,dst,xs[i]+2,y+2,364,h-4,0);
   text(s,dst,xs[i]+16,y+(levels==6?14u:20u),labels[i],0);
   text(s,dst,xs[i]+16,y+(levels==6?46u:56u),selected?"MID TO START":"SELECT ON WEB",1);
  }
  if(c->performance) {
   fill(s,dst,96,412,768,48,0x07e0);
   fill(s,dst,98,414,764,44,0);
   text(s,dst,108,426,"PERFORMANCE - 60 FPS SPRITE LIMIT",1);
  } else text(s,dst,96,436,"SELECT A LEVEL ON THE WEB PAGE",0);
 }
 fill(s,dst,96,480,600,18,0);
 text(s,dst,96,480,selected?"STICK SELECT - MID START":ready?"WEB CONTROL READY":"WAITING FOR WEB CONTROL",selected || ready);
 uint16_t tag=0;
 for(unsigned i=0;i<s->count;i++) {int e=gpu_submit(gpu,&s->commands[i],polls,&tag);if(e)return e;}
 int e=gpu_wait_tag(gpu,tag,polls);if(e)return e;
 c->destination[index]=dst;c->generation[index]=generation;c->network[index]=ready;c->drawn_levels[index]=(uint8_t)levels;c->drawn_selection[index]=(uint8_t)selected;c->valid_mask|=bit;
 return 0;
}
