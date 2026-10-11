/* Breaks caught: friendly inactive glow leaks, reordered Alpha, changed clip,
 * capacity overwrites, altered game state or a truncated published list. */
#include "gpu_instances.h"
#include "interactive_game.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static bullet_state state,before;
static bullet_stream reference;
static gpu_instance items[BULLET_MAX_COMMANDS+1];
static gpu_instance_template templates[16];
static uint8_t background[GPU_FRAME_BYTES],atlas[BULLET_ATLAS_BYTES];
static uint8_t old_pixels[GPU_FRAME_BYTES],list_pixels[GPU_FRAME_BYTES];
static void read_asset(const char *path,uint8_t *p,unsigned bytes) {
 FILE *f=fopen(path,"rb");assert(f);
 assert(fread(p,1,bytes,f)==bytes && fgetc(f)==EOF && !fclose(f));
}
static void render(const gpu_command *c,uint8_t *pixels,uint32_t base) {
 unsigned available;const uint8_t *p;
 if(c->src_addr>=BULLET_LOCAL_BACKGROUND && c->src_addr<BULLET_LOCAL_BACKGROUND+GPU_FRAME_BYTES) {
  unsigned offset=c->src_addr-BULLET_LOCAL_BACKGROUND;p=background+offset;available=GPU_FRAME_BYTES-offset;
 } else {
  assert(c->src_addr>=BULLET_LOCAL_ATLAS && c->src_addr<BULLET_LOCAL_ATLAS+BULLET_ATLAS_BYTES);
  unsigned offset=c->src_addr-BULLET_LOCAL_ATLAS;p=atlas+offset;available=BULLET_ATLAS_BYTES-offset;
 }
 golden_surface src={(uint8_t *)p,available,c->width_pixels,c->height_pixels,c->src_stride};
 golden_surface dst={pixels,GPU_FRAME_BYTES,960,540,1920};
 unsigned pixel=(c->dst_addr-base)/2u;
 enum gpu_error e=c->op==GPU_OP_COPY?golden_copy(&dst,pixel%960,pixel/960,&src,0,0,c->width_pixels,c->height_pixels):
  c->op==GPU_OP_COLOR_KEY?golden_color_key(&dst,pixel%960,pixel/960,&src,0,0,c->width_pixels,c->height_pixels,c->color_key):
  golden_alpha_blend(&dst,pixel%960,pixel/960,&src,0,0,c->width_pixels,c->height_pixels,c->alpha);
 assert(e==GPU_ERROR_NONE);
}
static void compare(uint32_t dst,int network,int glow,int pixels) {
 gpu_instance_stats stats;before=state;
 assert(!game_build(&state,dst,network,glow,BULLET_MAX_COMMANDS,&reference));
 assert(!bullet_clip_background_for_hud(&reference,72));
 items[BULLET_MAX_COMMANDS]=(gpu_instance){{0x12345678,0x89abcdef,0x12345678,0x89abcdef}};
 assert(!gpu_instances_build_into(&state,dst,network,glow,1,72,BULLET_MAX_COMMANDS,items,&stats));
 assert(!memcmp(&state,&before,sizeof state));
 assert(stats.count==reference.count && stats.visible==reference.visible);
 assert(stats.scene_pixels==reference.scene_pixels && stats.alpha_commands==reference.alpha_commands && stats.alpha_pixels==reference.alpha_pixels);
 assert(items[BULLET_MAX_COMMANDS].words[0]==0x12345678 && items[BULLET_MAX_COMMANDS].words[3]==0x89abcdef);
 assert(gpu_instances_templates(network,templates)==12);
 if(pixels) {memset(old_pixels,0x42,sizeof old_pixels);memset(list_pixels,0x42,sizeof list_pixels);}
 for(unsigned i=0;i<stats.count;i++) {
  gpu_command c;assert(!gpu_instance_expand(templates,items+i,(uint16_t)(65530u+i),&c));
  const gpu_command *r=reference.commands+i;
  assert(c.op==r->op && c.src_addr==r->src_addr && c.dst_addr==r->dst_addr);
  assert(c.src_stride==r->src_stride && c.dst_stride==r->dst_stride);
  assert(c.width_pixels==r->width_pixels && c.height_pixels==r->height_pixels);
  assert(c.alpha==r->alpha && c.color_key==r->color_key && c.color==r->color && c.flags==r->flags);
  assert(c.tag==(uint16_t)(65530u+i));
  if(pixels) {render(r,old_pixels,dst);render(&c,list_pixels,dst);}
 }
 if(pixels) assert(!memcmp(old_pixels,list_pixels,sizeof old_pixels));
}
int main(void) {
 read_asset("sw/efinix_gpu/assets/interactive/background.rgb565",background,sizeof background);
 read_asset("sw/efinix_gpu/assets/interactive/atlas.rgb565",atlas,sizeof atlas);
 unsigned frames=0,pixels=0;
 const unsigned tiers[]={64,128,256,512};
 for(unsigned n=0;n<2;n++) for(unsigned g=0;g<2;g++) for(unsigned t=0;t<4;t++) {
  assert(!game_reset(&state,tiers[t],7));
  for(unsigned tick=0;tick<600;tick++) {
   game_input in={.held=(uint16_t)(V3_KEY_FIRE|(tick%120<60?V3_KEY_RIGHT:V3_KEY_LEFT))};
   if(tick==245) in.pressed=V3_KEY_RESTART;
   assert(!game_update(&state,&in));
   int sample=!n && g && t==3 && (tick==59 || tick==299 || tick==599);
   compare(tick&1?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A,n,g,sample);++frames;pixels+=(unsigned)sample;
  }
 }
 assert(!bullet_reset(&state,1,7));state.objects[0].kind=3;state.objects[0].age=UINT16_MAX;
 /* Slot0 would also emit glow unless inactive friendly filtering is applied. */
 compare(GPU_FRAMEBUFFER_A,1,1,0);
 gpu_instance_stats stats;
 assert(!gpu_instances_build_into(&state,GPU_FRAMEBUFFER_A,1,1,1,72,BULLET_MAX_COMMANDS,items,&stats));
 assert(stats.count==9 && stats.visible==0 && stats.alpha_commands==4);
 assert(gpu_instances_build_into(&state,GPU_FRAMEBUFFER_A,1,1,0,72,BULLET_MAX_COMMANDS,items,&stats)==GPU_DRIVER_ARGUMENT && !stats.count);
 state.objects[0].kind=0;state.objects[0].age=0;state.objects[0].shape=0;
 state.objects[0].x=-512;state.objects[0].y=70*256;
 assert(!gpu_instances_build_into(&state,GPU_FRAMEBUFFER_A,1,0,1,72,BULLET_MAX_COMMANDS,items,&stats));
 assert(items[1].words[0]==2 && items[1].words[1]==GPU_FRAMEBUFFER_A+72*1920);
 assert(items[1].words[2]==36 && items[1].words[3]==0x00060006);
 memset(items,0xa5,sizeof items);
 assert(gpu_instances_build_into(&state,GPU_FRAMEBUFFER_A,1,1,1,72,1,items,&stats)==GPU_DRIVER_FULL);
 assert(!stats.count && !stats.visible && !stats.alpha_commands && !stats.scene_pixels && !stats.alpha_pixels);
 for(unsigned i=1;i<=BULLET_MAX_COMMANDS;i++) for(unsigned w=0;w<4;w++) assert(items[i].words[w]==0xa5a5a5a5);
 assert(gpu_instances_build_into(&state,GPU_FRAMEBUFFER_A,1,1,2,72,BULLET_MAX_COMMANDS,items,&stats)==GPU_DRIVER_ARGUMENT && !stats.count);
 assert(gpu_instances_build_into(&state,GPU_FRAMEBUFFER_A,1,1,1,72,BULLET_MAX_COMMANDS,NULL,&stats)==GPU_DRIVER_ARGUMENT && !stats.count);
 printf("FRAME_LIST_BUILD,PASS,frames=%u,pixels=%u,friendly_inactive,clip,order,capacity,state_immutable\n",frames,pixels);
 return 0;
}
