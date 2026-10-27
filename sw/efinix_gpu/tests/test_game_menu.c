#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "game_menu.h"
static uint32_t regs[64],done,fail_at;
static unsigned count;
static unsigned six_levels;
static gpu_command commands[512];
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);
 if(r==GPU_REG_ID)return GPU_ID_VALUE;
 if(r==GPU_REG_VERSION)return GPU_VERSION_VALUE;
 if(r==GPU_REG_LAST_DONE)return done;
 if(r==GPU_REG_STATUS)return GPU_STATUS_EMPTY;
 if(r==GPU_REG_ERROR)return fail_at && count>=fail_at?GPU_ERROR_AXI_RESPONSE:0;
 return 0;
}
void gpu_io_write(uintptr_t a,uint32_t v) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);assert(r<sizeof regs);regs[r/4]=v;
 if(r==GPU_REG_CONTROL) {
  gpu_command c={.op=(uint8_t)regs[GPU_REG_OP/4],.src_addr=regs[GPU_REG_SRC_ADDR/4],
   .dst_addr=regs[GPU_REG_DST_ADDR/4],.src_stride=regs[GPU_REG_SRC_STRIDE/4],
   .dst_stride=regs[GPU_REG_DST_STRIDE/4],.width_pixels=(uint16_t)regs[GPU_REG_SIZE/4],
   .height_pixels=(uint16_t)(regs[GPU_REG_SIZE/4]>>16),.color=(uint16_t)regs[GPU_REG_COLOR_KEY/4]};
  assert(count<512);commands[count++]=c;done=regs[GPU_REG_TAG/4];
 }
}
void gpu_io_fence(void) {}
static void check_frame(uint32_t dst) {
 const unsigned xs[]={96,496,96,496,96,496},ys[]={144,144,232,232,320,320};unsigned cards=0,glyphs=0;
 const unsigned old_ys[]={144,144,288,288};
 for(unsigned i=0;i<count;i++) {
  const gpu_command *c=&commands[i];unsigned off=c->dst_addr-dst,x=(off%GPU_FRAME_STRIDE)/2,y=off/GPU_FRAME_STRIDE;
  assert(x+c->width_pixels<=960 && y>=72 && y+c->height_pixels<=540);
  assert(c->dst_stride==GPU_FRAME_STRIDE);
  if(c->width_pixels==368 && c->height_pixels==(six_levels?80u:104u)) {
   assert(cards<(six_levels?6u:4u) && x==xs[cards] && y==(six_levels?ys[cards]:old_ys[cards]));++cards;
  }
  if(c->op==GPU_OP_COPY) {
   assert(c->width_pixels==14 && c->height_pixels==18);
   assert(c->src_addr>=HUD_GLYPH_ATLAS_ADDR && c->src_addr<HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES);
   ++glyphs;
  } else assert(c->op==GPU_OP_FILL);
 }
 assert(cards==(six_levels?6u:4u) && glyphs>70);
 /* Independently decode emitted labels, not a call to the text builder. */
 const char *labels[]={"LEVEL 1 - 64 SPRITES","LEVEL 2 - 128 SPRITES","LEVEL 3 - 256 SPRITES","LEVEL 4 - 512 SPRITES","LEVEL 5 - 786 SPRITES","LEVEL 6 - 1024 SPRITES"};
 for(unsigned k=0;k<(six_levels?6u:4u);k++) {
  char text[40]={0};unsigned n=0;
  for(unsigned i=0;i<count;i++) {
   gpu_command *c=&commands[i];unsigned off=c->dst_addr-dst;
   if(c->op==GPU_OP_COPY && off/GPU_FRAME_STRIDE==(six_levels?ys[k]+14u:old_ys[k]+20u) && off%GPU_FRAME_STRIDE>=2*(xs[k]+16) && off%GPU_FRAME_STRIDE<2*(xs[k]+360)) {
    unsigned glyph=((c->src_addr-HUD_GLYPH_ATLAS_ADDR)%HUD_GLYPH_BANK_BYTES)/HUD_GLYPH_CELL_BYTES;
    assert(glyph<39 && n<sizeof text-1);text[n++]=HUD_GLYPH_CHARACTERS[glyph];
   }
  }
  assert(!strcmp(text,labels[k]));
 }
}
int main(void) {
 static hud_command_stream scratch;game_menu_cache c={0};gpu_device d;
 assert(!gpu_init(&d,GPU_APB_BASE));
 assert(!game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,1,0,&scratch,1000));check_frame(GPU_FRAMEBUFFER_A);
 unsigned first=count;
 assert(!game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,1,0,&scratch,1000) && count==first);
 count=0;assert(!game_menu_draw(&d,&c,1,GPU_FRAMEBUFFER_B,1,0,&scratch,1000));check_frame(GPU_FRAMEBUFFER_B);
 count=0;assert(!game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,1,1,&scratch,1000));
 assert(count<35 && commands[0].height_pixels==18); /* only the connection hint */
 count=0;fail_at=1;game_menu_invalidate(&c);
 assert(game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,2,1,&scratch,1000)<0 && !(c.valid_mask&1));
 assert(game_menu_draw(&d,&c,2,GPU_FRAMEBUFFER_A,2,1,&scratch,1000)<0);
 fail_at=0;count=0;c.performance=1;game_menu_invalidate(&c);
 assert(!game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,3,1,&scratch,1000));
 unsigned strips=0;
 for(unsigned i=0;i<count;i++) if(commands[i].width_pixels==768 && commands[i].height_pixels==48) {
  assert(commands[i].dst_addr==GPU_FRAMEBUFFER_A+412u*GPU_FRAME_STRIDE+192);++strips;
 }
 assert(strips==1);check_frame(GPU_FRAMEBUFFER_A);
 /* Changing the number of cards must invalidate an otherwise identical cache. */
 count=0;six_levels=1;c.levels=6;
 assert(!game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,3,1,&scratch,1000));check_frame(GPU_FRAMEBUFFER_A);
 count=0;assert(!game_menu_draw(&d,&c,1,GPU_FRAMEBUFFER_B,3,1,&scratch,1000));check_frame(GPU_FRAMEBUFFER_B);
 for(unsigned bank=0;bank<2;bank++) {
  count=0;c.selected_level=4;
  uint32_t dst=bank?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
  assert(!game_menu_draw(&d,&c,bank,dst,3,1,&scratch,1000));check_frame(dst);
  unsigned yellow=0;
  for(unsigned i=0;i<count;i++) if(commands[i].op==GPU_OP_FILL && commands[i].color==0xffe0) {
   assert(commands[i].dst_addr==dst+232u*GPU_FRAME_STRIDE+496u*2 && commands[i].width_pixels==368);++yellow;
  }
  assert(yellow==1 && c.drawn_selection[bank]==4);
  unsigned drawn=count;
  assert(!game_menu_draw(&d,&c,bank,dst,3,1,&scratch,1000) && count==drawn);
 }
 count=0;c.comparison=1;c.selected_level=7;
 assert(!game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,3,1,&scratch,1000));check_frame(GPU_FRAMEBUFFER_A);
 unsigned exhibit=0;
 for(unsigned i=0;i<count;i++)if(commands[i].op==GPU_OP_FILL && commands[i].color==0xffe0) {
  assert(commands[i].dst_addr==GPU_FRAMEBUFFER_A+464u*GPU_FRAME_STRIDE+192 && commands[i].width_pixels==768);exhibit++;
 }
 assert(exhibit==1);
 count=0;fail_at=1;c.selected_level=1;
 assert(game_menu_draw(&d,&c,0,GPU_FRAMEBUFFER_A,3,1,&scratch,1000)<0);
 assert(!(c.valid_mask&1) && c.drawn_selection[0]==7); /* Failed redraw cannot advance cache. */
 puts("PASS real GPU menu MMIO geometry/glyph labels, two buffers, static zero-submit, dirty hint and failure invalidation");
}
