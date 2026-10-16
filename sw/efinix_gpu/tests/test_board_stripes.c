/* JTAG-only: identical ordered scene through DDR vs local strip path, actual pixels. */
#define main reference_main
#include "../src/main.c"
#undef main
#include "gpu_stripes.h"
#include "performance_challenge.h"
#define CHECK(c) do {if(!(c)){bsp_printf("STRIPE_BOARD_FAIL,line=%d\r\n",__LINE__);return 1;}} while(0)
int main(void) {
 bsp_init();gpu_device d;gpu_frame_list f;
 CHECK(!gpu_init(&d,GPU_APB_BASE));CHECK(gpu_stripes_supported(&d));
 CHECK(!gpu_frame_list_init(&f,&d,0) && f.present);
 bullet_init_local_assets();gpu_platform_sync();
 CHECK(!gpu_texture_cache_load(&d,BULLET_LOCAL_ATLAS,(BULLET_ATLAS_BYTES+3u)&~3u,10000000u));
 gpu_instance *items=(gpu_instance *)(uintptr_t)GPU_STRIPE_SCENE_ADDR;
 gpu_instance *bins=(gpu_instance *)(uintptr_t)GPU_STRIPE_BINS_ADDR;
 pc_state *state=(pc_state *)(uintptr_t)PC_STATE_ADDRESS;
 const unsigned targets[]={64,512,1024,1819};
 for(unsigned trial=0;trial<4;trial++) {
  unsigned target=targets[trial];CHECK(!pc_init(state,PC_MAX_SPRITES,7));state->target=target;
  for(unsigned k=0;k<target;k++)state->sprites[k]=(pc_sprite){
   .x=(int16_t)(9+(k%56u)*16u),.y=(int16_t)(80+((k/56u)%19u)*24u),
   .dx=1,.dy=1,.shape=(uint8_t)(k%6u)};
  /* Boundary/last4 clips and overlapping Alpha/Key, all sprites remain active. */
  state->sprites[0].y=80;state->sprites[target-1].y=516;
  for(unsigned b=0;b<2;b++) {
   volatile uint16_t *frame=(volatile uint16_t *)(uintptr_t)(b?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A);
   for(unsigned k=0;k<960*540;k++)frame[k]=0xa55a;
   frame[960*540]=0x5aa5;
  }
  gpu_instance_stats stats;uint64_t ticks[2];uint32_t crc[2];gpu_perf_snapshot perf[2];
  for(unsigned path=0;path<2;path++) {
   uint32_t frame=path?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
   CHECK(!pc_build(state,frame,0,items,GPU_FRAME_LIST_ARENA_ITEMS,&stats));
   gpu_platform_sync();CHECK(!gpu_clear_perf(&d));uint64_t start=gpu_platform_cycles();
   if(path) {CHECK(!gpu_stripes_render(&f,0,frame,items,stats.count,bins,GPU_STRIPE_BIN_ITEMS,trial+10u,10000000u));}
   else {
    memcpy((void *)(uintptr_t)GPU_FRAME_LIST_BANK_A,items,stats.count*sizeof *items);
    CHECK(!gpu_frame_list_render_span(&f,GPU_FRAME_LIST_BANK_A,stats.count,trial+1u,10000000u));
   }
   ticks[path]=gpu_platform_cycles()-start;CHECK(!gpu_read_perf_snapshot(&d,perf+path));
   gpu_platform_sync();crc[path]=golden_crc32((const void *)(uintptr_t)frame,GPU_FRAME_BYTES);
   CHECK(*(volatile uint16_t *)(uintptr_t)(frame+GPU_FRAME_BYTES)==0x5aa5);
  }
  CHECK(crc[0]==crc[1]);
  bsp_printf("STRIPE_BOARD,target=%d,alpha=%d,crc=%x,ddr_ticks=%d,stripe_ticks=%d,render_wr_ddr=%d,render_wr_stripe=%d,guards=PASS\r\n",
   target,stats.alpha_commands,crc[0],(uint32_t)ticks[0],(uint32_t)ticks[1],
   (uint32_t)perf[0].write_bytes,(uint32_t)perf[1].write_bytes);
 }
 bsp_printf("STRIPE_BOARD_STOP,result=0,hardware=%d,pixel_equivalence=PASS\r\n",d.hardware_error);return 0;
}
