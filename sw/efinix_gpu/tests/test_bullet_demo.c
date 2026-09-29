#include "bullet_demo.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static bullet_state state,replay;
static bullet_state frames[30],start;
static bullet_stream scene;
static void reject_clip_unchanged(bullet_stream value,unsigned height) {
 bullet_stream before=value;
 assert(bullet_clip_background_for_hud(&value,height)==GPU_DRIVER_ARGUMENT);
 assert(!memcmp(&value,&before,sizeof value));
}
int main(void) {
 /* Missing reset/motion would leave these independently specified coordinates wrong. */
 assert(bullet_reset(&state,32,7)==0);
 assert(state.count==32 && state.player_x==480 && state.player_y==480);
 assert(state.objects[0].x==496*256 && state.objects[0].y==280*256);
 assert(bullet_step(&state)==0);
 assert(state.objects[0].x==496*256+384 && state.objects[0].y==280*256);
 assert(state.tick==1);
 assert(bullet_reset(&state,513,7)==GPU_DRIVER_ARGUMENT);
 assert(bullet_reset(&state,0,7)==GPU_DRIVER_ARGUMENT);
 assert(bullet_reset(NULL,32,7)==GPU_DRIVER_ARGUMENT);
 assert(bullet_prepare_frame(&state,512,37,7)==0);
 assert(bullet_prepare_frame(&replay,512,37,7)==0);
 assert(!memcmp(&state,&replay,sizeof state));
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene)==0);
 assert(scene.visible>0 && scene.visible<=512 && scene.count<=BULLET_MAX_COMMANDS);
 assert(scene.commands[0].op==GPU_OP_COPY && scene.commands[0].width_pixels==960);
 bullet_stream before=scene;
 assert(!bullet_clip_background_for_hud(&scene,72));
 assert(scene.commands[0].src_addr==BULLET_LOCAL_BACKGROUND+138240u);
 assert(scene.commands[0].dst_addr==GPU_FRAMEBUFFER_A+138240u);
 assert(scene.commands[0].height_pixels==468 && scene.commands[0].width_pixels==960);
 assert(scene.commands[0].src_stride==1920 && scene.commands[0].dst_stride==1920);
 assert(scene.scene_pixels==before.scene_pixels-69120u);
 assert(scene.count==before.count && scene.visible==before.visible &&
  scene.alpha_commands==before.alpha_commands && scene.alpha_pixels==before.alpha_pixels);
 assert(!memcmp(scene.commands+1,before.commands+1,(scene.count-1u)*sizeof scene.commands[0]));
 assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_B,1,1,BULLET_MAX_COMMANDS,&scene));
 assert(!bullet_clip_background_for_hud(&scene,72));
 assert(scene.commands[0].src_addr==BULLET_BACKGROUND_ADDR+138240u);
 assert(scene.commands[0].dst_addr==GPU_FRAMEBUFFER_B+138240u && scene.commands[0].height_pixels==468);
 assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&scene));
 before=scene; assert(!bullet_clip_background_for_hud(&scene,0));
 assert(!memcmp(&scene,&before,sizeof scene));
 assert(bullet_clip_background_for_hud(NULL,72)==GPU_DRIVER_ARGUMENT);
 bullet_stream invalid={0}; reject_clip_unchanged(invalid,72);
 invalid=before; reject_clip_unchanged(invalid,540);
 invalid=before; invalid.commands[0].op=GPU_OP_FILL; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.commands[0].width_pixels=959; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.commands[0].height_pixels=539; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.commands[0].src_stride=1918; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.commands[0].dst_stride=1918; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.commands[0].dst_addr=GPU_FRAMEBUFFER_A+2; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.commands[0].src_addr=GPU_DDR_END_EXCLUSIVE-GPU_FRAME_BYTES+2u; reject_clip_unchanged(invalid,72);
 invalid=before; invalid.scene_pixels=GPU_FRAME_WIDTH*GPU_FRAME_HEIGHT-1u; reject_clip_unchanged(invalid,72);
 unsigned planes=0,shapes=0;
 for(unsigned i=0;i<state.count;i++) shapes|=1u<<state.objects[i].shape;
 assert(shapes==63);
 for(unsigned i=0;i<scene.count;i++) {
  const gpu_command *c=&scene.commands[i];
  if(c->src_addr>=BULLET_LOCAL_ATLAS+BULLET_EMITTER_OFFSET && c->op==GPU_OP_COLOR_KEY) {
   assert(c->width_pixels==16 && c->height_pixels==16); ++planes;
  }
 }
 assert(planes==3);
 for(unsigned i=0;i<scene.count;i++) {
  const gpu_command *c=&scene.commands[i];
  unsigned off=c->dst_addr-GPU_FRAMEBUFFER_A;
  assert(c->width_pixels && c->height_pixels);
  assert(off%GPU_FRAME_STRIDE+c->width_pixels*2u<=GPU_FRAME_STRIDE);
  assert((uint64_t)off+(c->height_pixels-1u)*GPU_FRAME_STRIDE+c->width_pixels*2u<=GPU_FRAME_BYTES);
 }
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,1,&scene)==GPU_DRIVER_FULL);
 assert(scene.count==0 && scene.visible==0);
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A+2,0,0,520,&scene)==GPU_DRIVER_ARGUMENT);
 assert(bullet_prepare_frame(&state,32,600,7)==GPU_DRIVER_ARGUMENT);
 assert(bullet_reset(&state,1,7)==0);
 state.objects[0].x=-3*256; state.objects[0].y=100*256;
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene)==0);
 assert(scene.visible==1 && scene.commands[1].width_pixels==5);
 assert(scene.commands[1].src_addr==BULLET_LOCAL_ATLAS+6);
 assert(scene.commands[1].dst_addr==GPU_FRAMEBUFFER_A+100*GPU_FRAME_STRIDE);
 state.objects[0].x=958*256; state.objects[0].y=535*256;
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene)==0);
 assert(scene.visible==1 && scene.commands[1].width_pixels==2 && scene.commands[1].height_pixels==5);
 state.objects[0].x=959*256; state.objects[0].y=539*256;
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene)==0 && scene.visible==0);
 state.objects[0].x=-8*256;
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene)==0 && scene.visible==0);
 /* Literal single-column coverage distinguishes needle from circle clipping. */
 state.objects[0].x=959*256; state.objects[0].y=100*256;
 state.objects[0].shape=2;
 assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene) && scene.visible==0);
 state.objects[0].shape=1;
 assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene) && scene.visible==1);
 state.objects[0].shape=5;
 assert(!bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene) && scene.visible==0);
 state.objects[0].shape=6;
 assert(bullet_build_frame(&state,GPU_FRAMEBUFFER_A,0,0,520,&scene)==GPU_DRIVER_ARGUMENT && scene.count==0);
 /* All slots are recycled, not dynamically allocated, during a long replay. */
 assert(bullet_reset(&state,512,7)==0);
 for(unsigned f=0;f<10000;f++) assert(bullet_step(&state)==0);
 assert(state.count==512);
 assert(!bullet_reset(&state,32,7)); start=state;
 for(unsigned f=0;f<30;f++) { frames[f]=state; assert(!bullet_step(&state)); }
 assert(!bullet_finish_window(&state,&start,0));
 for(unsigned f=0;f<30;f++) {
  assert(!memcmp(&state,&frames[f],sizeof state)); assert(!bullet_step(&state));
 }
 assert(!bullet_finish_window(&state,&start,1));
 assert(start.tick==30 && !memcmp(&state,&start,sizeof state));
 state.tick=600;
 assert(!bullet_finish_window(&state,&start,1) && state.tick==0 && start.tick==0);
 assert(bullet_finish_window(NULL,&start,1)==GPU_DRIVER_ARGUMENT);
 puts("PASS bullet state: deterministic motion, replay, clipping, capacity, recycling");
 return 0;
}
