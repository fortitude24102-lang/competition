/* JTAG-only oracle: CPU-written lists/assets, actual DDR pixel readback.
 * Scratch disjoint from framebuffers, assets and private descriptor banks. */
#define main reference_main
#include "../src/main.c"
#undef main
#include "gpu_frame_list.h"
#include "benchmark.h"
#include "rgb565.h"
#include "bsp.h"
#define CHECK(c) do {if(!(c)){bsp_printf("FRAME_LIST_BOARD_FAIL,line=%d\r\n",__LINE__);return 1;}} while(0)
int main(void) {
 bsp_init();gpu_device d;gpu_frame_list f;gpu_instances i;
 CHECK(!gpu_init(&d,GPU_APB_BASE));CHECK(!gpu_frame_list_init(&f,&d,1) && f.present);
 CHECK(!gpu_instances_init(&i,&d));
 const gpu_instance_template t[3]={
  {GPU_OP_COPY,0x02d40000u,2,2,1,1,0},
  {GPU_OP_COLOR_KEY,0x02d40004u,2,2,1,1,0xf81fu},
  {GPU_OP_ALPHA,0x02d40008u,2,2,1,1,0}};
 CHECK(!gpu_instances_program(&i,t,3));d.next_tag=65535u;
 volatile uint32_t *src=(volatile uint32_t *)(uintptr_t)0x02d40000u;
 volatile uint32_t *dst=(volatile uint32_t *)(uintptr_t)0x02d40020u;
 gpu_instance *list=(gpu_instance *)(uintptr_t)GPU_FRAME_LIST_BANK_A;
 for(unsigned epoch=1;epoch<=2;epoch++) {
  uint16_t bg=epoch==1?0x07e0u:0x001fu,fg=epoch==1?0xf800u:0x07e0u;
  src[0]=bg;src[1]=0xf81fu;src[2]=fg;
  dst[-1]=0x12345678u;dst[0]=0x55441111u;dst[1]=0x89abcdefu;
  for(unsigned k=0;k<3;k++)list[k]=(gpu_instance){{k|(k==2?(256u|(128u<<16)):0u),0x02d40020u,0,0x00010001u}};
  CHECK(!gpu_frame_list_render(&f,GPU_FRAME_LIST_BANK_A,3,epoch,10000000u));
  gpu_platform_sync();uint32_t expected=0x55440000u|rgb565_global_alpha(fg,bg,128);
  CHECK(dst[0]==expected && dst[-1]==0x12345678u && dst[1]==0x89abcdefu);
  CHECK(d.last_done==(uint16_t)(65535u+epoch*3u-1u));
  CHECK(*(volatile uint32_t *)(uintptr_t)(GPU_APB_BASE+0x51c)==epoch);
  CHECK(*(volatile uint32_t *)(uintptr_t)(GPU_APB_BASE+0x528)==48u);
  bsp_printf("FRAME_LIST_BOARD,epoch=%d,pixel=%x,tag=%d,bytes=48,guards=PASS\r\n",epoch,dst[0],d.last_done);
 }
 /* Each bank ends in a distinct Alpha; repeating bank2 instead of reading
  * bank3/4 must change the independently checked final DDR pixel. */
 for(unsigned epoch=3;epoch<=4;epoch++) {
  src[0]=0x07e0u;src[1]=0xf81fu;src[2]=0xf800u;
  dst[-1]=0x12345678u;dst[0]=0x554407e0u;dst[1]=0x89abcdefu;
  volatile uint32_t *state_guard=(volatile uint32_t *)(uintptr_t)(GPU_FRAME_LIST_BANK_A+f.arena_items*16u);
  *state_guard=0x76543210u;
  const unsigned alpha[4]={128,64,192,96};
  for(unsigned k=0;k<f.arena_items;k++)list[k]=(gpu_instance){{k%1024u==1023?2u|256u|(alpha[k/1024u]<<16):k<1023?0u:1u,
   0x02d40020u,0,0x00010001u}};
  unsigned skip=epoch==4;
  d.next_tag=65535u;
  CHECK(!gpu_frame_list_render_span(&f,GPU_FRAME_LIST_BANK_A+16u*skip,f.arena_items-skip,epoch,10000000u));
  gpu_platform_sync();
  uint16_t pixel=0x07e0u;
  for(unsigned b=0;b<f.arena_items/1024u;b++)pixel=rgb565_global_alpha(0xf800u,pixel,(uint8_t)alpha[b]);
  CHECK(dst[0]==(0x55440000u|pixel));
  CHECK(dst[-1]==0x12345678u && dst[1]==0x89abcdefu && *state_guard==0x76543210u);
  CHECK(d.last_done==(uint16_t)(65535u+f.arena_items-skip-1u));
  CHECK(*(volatile uint32_t *)(uintptr_t)(GPU_APB_BASE+0x51c)==epoch);
  bsp_printf("FRAME_LIST_SPAN,epoch=%d,count=%d,pixel=%x,tag=%d,guards=PASS\r\n",
   epoch,f.arena_items-skip,dst[0],d.last_done);
 }
 bsp_printf("FRAME_LIST_BOARD_STOP,result=0,publish=PASS,copy_key_alpha=PASS,tagwrap=PASS\r\n");return 0;
}
