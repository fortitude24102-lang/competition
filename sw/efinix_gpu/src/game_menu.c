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
    dst!=(index?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A)) return GPU_DRIVER_ARGUMENT;
 _Static_assert(HUD_MAX_COMMANDS>=256,"menu scratch capacity");
 uint8_t bit=(uint8_t)(1u<<index),ready=(uint8_t)(network!=0);
 int full=!(c->valid_mask&bit) || c->generation[index]!=generation || c->destination[index]!=dst;
 s->count=0;
 if(!full && c->network[index]==ready)return 0;
 c->valid_mask&=(uint8_t)~bit;
 if(full) {
  fill(s,dst,0,72,960,468,0);
  text(s,dst,270,96,"SELECT DIFFICULTY",1);
  const unsigned xs[]={96,496,96,496},ys[]={144,144,288,288};
  const char *labels[]={"LEVEL 1 - 64 SPRITES","LEVEL 2 - 128 SPRITES","LEVEL 3 - 256 SPRITES","LEVEL 4 - 512 SPRITES"};
  for(unsigned i=0;i<4;i++) {
   fill(s,dst,xs[i],ys[i],368,104,0x07e0);
   fill(s,dst,xs[i]+2,ys[i]+2,364,100,0);
   text(s,dst,xs[i]+16,ys[i]+20,labels[i],0);
   text(s,dst,xs[i]+16,ys[i]+56,"SELECT ON WEB",1);
  }
  text(s,dst,96,436,"SELECT A LEVEL ON THE WEB PAGE",0);
 }
 fill(s,dst,96,480,600,18,0);
 text(s,dst,96,480,ready?"WEB CONTROL READY":"WAITING FOR WEB CONTROL",ready);
 uint16_t tag=0;
 for(unsigned i=0;i<s->count;i++) {int e=gpu_submit(gpu,&s->commands[i],polls,&tag);if(e)return e;}
 int e=gpu_wait_tag(gpu,tag,polls);if(e)return e;
 c->destination[index]=dst;c->generation[index]=generation;c->network[index]=ready;c->valid_mask|=bit;
 return 0;
}
