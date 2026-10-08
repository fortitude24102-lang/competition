#include "hud.h"
static uint8_t logo_enabled;
void hud_set_logo_enabled(int enabled) { logo_enabled=(uint8_t)(enabled!=0); }
int hud_logo_fits(char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS]) {
 if(!logo_enabled || !lines) return 0;
 for(unsigned line=0;line<HUD_COMPARISON_LINES;line++) {
  unsigned n=0;while(n<HUD_COMPARISON_COLUMNS && lines[line][n]) ++n;
  if(n==HUD_COMPARISON_COLUMNS || 8u+n*HUD_GLYPH_WIDTH>HUD_LOGO_X) return 0;
 }
 return 1;
}
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

/* Comparison HUD only: 5x7 at 2x scale, four blank pixels between cells.
 * Keep the older compact numeric HUD API and its geometry unchanged. */
static const uint8_t comparison_letters[26][7]={
 {14,17,17,31,17,17,17},{30,17,17,30,17,17,30},
 {14,17,16,16,16,17,14},{30,17,17,17,17,17,30},
 {31,16,16,30,16,16,31},{31,16,16,30,16,16,16},
 {14,17,16,23,17,17,15},{17,17,17,31,17,17,17},
 {14,4,4,4,4,4,14},{7,2,2,2,18,18,12},
 {17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
 {17,27,21,21,17,17,17},{17,25,25,21,19,19,17},
 {14,17,17,17,17,17,14},{30,17,17,30,16,16,16},
 {14,17,17,17,21,18,13},{30,17,17,30,20,18,17},
 {15,16,16,14,1,1,30},{31,4,4,4,4,4,4},
 {17,17,17,17,17,17,14},{17,17,17,17,17,10,4},
 {17,17,17,21,21,21,10},{17,17,10,4,10,17,17},
 {17,17,10,4,4,4,4},{31,1,2,4,8,16,31}
};
static const uint8_t comparison_digits[10][7]={
 {14,17,19,21,25,17,14},{4,12,4,4,4,4,14},
 {14,17,1,2,4,8,31},{30,1,1,14,1,1,30},
 {2,6,10,18,31,2,2},{31,16,16,30,1,1,30},
 {14,16,16,30,17,17,14},{31,1,2,4,8,8,8},
 {14,17,17,14,17,17,14},{14,17,17,15,1,1,14}
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
   p=number(p,(us[i]/100u)%10);
   if(!i && m->v3_mode && m->cpu_stale) text(p," STALE");
  } else text(p,"--  RENDER MS --");
 }
 char *p=text(lines[2],m->gpu_active?"MODE GPU  ":"MODE CPU  ");
 if(m->v3_mode) p=text(p,m->v3_mode==4?"MENU ":m->v3_mode==1?"LIVE ":"REPLAY ");
 p=text(p,m->bullet_demo?"BULLETS ":"N ");
 p=number(p,m->sprites);
 if(m->bullet_demo && m->gameplay) { p=text(p," ALPHA "); p=number(p,m->alpha_commands); }
 p=text(p,"  NET "); text(p,m->network_ready?"READY":"FAIL FALLBACK");
 if(m->v3_mode==4) text(lines[3],"SELECT LEVEL ON WEB  GAME FPS UNAVAILABLE");
 else if(m->bullet_demo && m->gameplay) {
  p=text(lines[3],"HP "); p=number(p,m->hp);
  p=text(p," SCORE "); p=number(p,m->score>999999u?999999u:m->score);
  p=text(p," GRAZE "); p=number(p,m->grazes>9999u?9999u:m->grazes);
  p=text(p," UFL "); p=number(p,m->underflows);
  p=text(p," ERR "); p=number(p,m->error_code);
  text(p,m->game_over?" OVER":m->invulnerable?" SHIELD":m->v3_mode?(m->logic_slow?" SLOW":" PLAY"):" AUTO");
 } else if(m->bullet_demo) {
  p=text(lines[3],"UFL "); p=number(p,m->underflows);
  p=text(p," ERR "); p=number(p,m->error_code);
  text(p,"  KEY1 LESS KEY2 MORE");
 } else text(lines[3],"KEY1 LESS KEY2 MORE  30 FRAME FPS WITH PRESENT");
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
  uint8_t rows[7];
  for(unsigned row=0;row<7;row++) rows[row]=
   ch>='A'&&ch<='Z'?comparison_letters[ch-'A'][row]:
   ch>='0'&&ch<='9'?comparison_digits[ch-'0'][row]:
   ch=='-'?(row==3?14:0):ch=='.'?(row==6?4:0):0;
  for(unsigned row=0;row<7;row++) {
   for(unsigned col=0;col<5;) {
    if(!(rows[row]&(16u>>col))) { ++col; continue; }
    unsigned first=col;
    while(col<5 && (rows[row]&(16u>>col))) ++col;
    unsigned mask=((1u<<(col-first))-1u)<<(5-col),end=row+1;
    unsigned neighbors=(first?16u>>(first-1):0)|(col<5?16u>>col:0);
    /* Coalesce identical vertical runs to keep the original 1024-command
     * scratch buffer, rather than expanding scarce bare-metal RAM. */
    while(end<7 && (rows[end]&(mask|neighbors))==mask) ++end;
    for(unsigned r=row;r<end;r++) rows[r]&=(uint8_t)~mask;
    e=append_fill(s,dst,GPU_FRAME_STRIDE,(uint16_t)(8+n*14+first*2),
     (uint16_t)(3+line*18+row*2),(uint16_t)((col-first)*2),
     (uint16_t)((end-row)*2),line==2?0x07e0:0xffff); if(e) return e;
   }
  }
 }
 if(hud_logo_fits(lines)) {
  if(s->count>=HUD_MAX_COMMANDS) return GPU_DRIVER_FULL;
  s->commands[s->count++]=(gpu_command){.op=GPU_OP_COPY,.src_addr=HUD_LOGO_ADDR,
   .dst_addr=dst+HUD_LOGO_Y*GPU_FRAME_STRIDE+HUD_LOGO_X*2u,
   .src_stride=HUD_LOGO_WIDTH*2u,.dst_stride=GPU_FRAME_STRIDE,
   .width_pixels=HUD_LOGO_WIDTH,.height_pixels=HUD_LOGO_HEIGHT};
 }
 return 0;
}

/* Reuse the exact existing bitmaps without changing the CPU raster path.
 * Opaque cells include the 3px top margin, 4px gutter and trailing black row. */
void hud_init_glyph_atlas(void) {
 _Static_assert(sizeof(HUD_GLYPH_CHARACTERS)-1u==HUD_GLYPH_COUNT,"glyph count");
 _Static_assert(HUD_CACHE_ADDR+HUD_CACHE_BYTES<=HUD_GLYPH_ATLAS_ADDR,"HUD/atlas separation");
 _Static_assert(HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES<=GPU_DDR_END_EXCLUSIVE,"glyph DDR bounds");
 _Static_assert(HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES<=HUD_LOGO_ADDR,"glyph/logo separation");
 _Static_assert(HUD_LOGO_ADDR+HUD_LOGO_BYTES<=0x02d00000u,"logo/runtime separation");
 _Static_assert(HUD_LOGO_X+HUD_LOGO_WIDTH<=GPU_FRAME_WIDTH && HUD_LOGO_Y+HUD_LOGO_HEIGHT<=HUD_CACHE_HEIGHT,"logo HUD bounds");
 uint16_t *out=(uint16_t *)(uintptr_t)HUD_GLYPH_ATLAS_ADDR;
 for(unsigned bank=0;bank<2;bank++) for(unsigned glyph=0;glyph<HUD_GLYPH_COUNT;glyph++) {
  unsigned char ch=(unsigned char)HUD_GLYPH_CHARACTERS[glyph];
  for(unsigned y=0;y<HUD_GLYPH_HEIGHT;y++) {
   unsigned row=y>=3 && y<17?(y-3)/2:7;
   unsigned bits=row==7?0:ch>='A'&&ch<='Z'?comparison_letters[ch-'A'][row]:
    ch>='0'&&ch<='9'?comparison_digits[ch-'0'][row]:
    ch=='-'?(row==3?14:0):ch=='.'?(row==6?4:0):0;
   for(unsigned x=0;x<HUD_GLYPH_WIDTH;x++)
    *out++=x<10 && (bits&(16u>>(x/2)))?(bank?0x07e0:0xffff):0;
  }
 }
}
