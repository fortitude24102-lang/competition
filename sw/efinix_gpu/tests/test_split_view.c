#define _GNU_SOURCE
#include "split_view.h"
#include "perf_demo.h"
#include "interactive_game.h"
#include <assert.h>
#include <stdio.h>
#include <sys/mman.h>
static bullet_state state;static bullet_stream native,small;
void gpu_platform_sync(void){}
int main(void){
 assert(mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,0x01900000,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0)==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 uint16_t *bg=(uint16_t *)(uintptr_t)BULLET_LOCAL_BACKGROUND,*atlas=(uint16_t *)(uintptr_t)BULLET_LOCAL_ATLAS;
 for(unsigned i=0;i<960*540;i++)bg[i]=(uint16_t)(i*173u+(i/960)*93u);
 for(unsigned i=0;i<BULLET_ATLAS_BYTES/2;i++)atlas[i]=i%7?(uint16_t)(i*331u):BULLET_COLOR_KEY;
 assert(!split_view_prepare(0,NULL,NULL));
 for(unsigned tier=0;tier<2;tier++)for(unsigned phase=0;phase<4;phase++)for(unsigned tick=0;tick<4;tick++) {
  assert(!game_reset(&state,tier?512:256,7));
  for(unsigned i=0;i<state.count-8;i++) {
   state.objects[i].x=(int32_t)((int)(i*31u%976u)-8+(int)(phase&1u))*256;
   state.objects[i].y=(int32_t)(65+(i*43u%478u)+(phase>>1))*256;
  }
  state.player_x=480+(int)(phase&1u);state.player_y=480+(int)(phase>>1);state.tick=tick;
  assert(!game_build(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&native));
  assert(!perf_render_cpu(native.commands,native.count));
  assert(!split_view_build(&state,0,0x03000000u,&small));
  for(unsigned i=0;i<small.count;i++)if(small.commands[i].op==GPU_OP_COLOR_KEY || small.commands[i].op==GPU_OP_ALPHA) {
   gpu_command *c=small.commands+i;
   assert(c->src_addr>=SPLIT_ATLAS && (uint64_t)c->src_addr+(c->height_pixels-1u)*c->src_stride+c->width_pixels*2u<=SPLIT_ATLAS+BULLET_ATLAS_BYTES);
  }
  assert(!perf_render_cpu_surface(small.commands,small.count,0x03000000u));
  const uint16_t *full=(const uint16_t *)(uintptr_t)GPU_FRAMEBUFFER_A,*half=(const uint16_t *)(uintptr_t)0x03000000u;
  for(unsigned y=0;y<270;y++)for(unsigned x=0;x<480;x++)assert(half[y*960+x]==full[y*2u*960+x*2u]);
 }
 puts("PASS half-size views:32 actual game scenes,odd phases,clipping,Key/Alpha/overlap,all129600 pixels equal full-render nearest sampling");return 0;
}
