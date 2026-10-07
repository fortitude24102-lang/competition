/* Real driver emits real APB shadow fields; CONTROL snapshots are the boundary.
 * Catches stale op/size/alpha/key, missing initialization or lost tag/commit. */
#include "gpu.h"
#include "bullet_demo.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[64];
static unsigned writes,commits,fences,full_reads;
static const gpu_command *expected;
uint32_t gpu_io_read(uintptr_t a) {
 if(a==GPU_APB_BASE+GPU_REG_STATUS && full_reads) {--full_reads;return GPU_STATUS_FULL;}
 return regs[(a-GPU_APB_BASE)/4];
}
void gpu_io_write(uintptr_t a,uint32_t value) {
 unsigned offset=(unsigned)(a-GPU_APB_BASE);regs[offset/4]=value;++writes;
 if(offset==GPU_REG_CONTROL && value==1) {
  assert(expected);
  assert(regs[GPU_REG_OP/4]==expected->op);
  assert(regs[GPU_REG_SRC_ADDR/4]==expected->src_addr);
  assert(regs[GPU_REG_DST_ADDR/4]==expected->dst_addr);
  assert(regs[GPU_REG_SIZE/4]==((uint32_t)expected->height_pixels<<16|expected->width_pixels));
  assert(regs[GPU_REG_SRC_STRIDE/4]==expected->src_stride);
  assert(regs[GPU_REG_DST_STRIDE/4]==expected->dst_stride);
  assert(regs[GPU_REG_COLOR_KEY/4]==((uint32_t)expected->color_key<<16|expected->color));
  assert(regs[GPU_REG_ALPHA_FLAGS/4]==((uint32_t)expected->flags<<16|expected->alpha));
  ++commits;regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];
 }
}
void gpu_io_fence(void) {++fences;}
static void send(gpu_device *d,const gpu_command *c) {
 uint16_t tag=0xbeef,want=d->next_tag;expected=c;
 assert(!gpu_submit(d,c,100,&tag) && tag==want && regs[GPU_REG_TAG/4]==want);
 assert(!gpu_wait_tag(d,tag,100));
 expected=0;
}
int main(void) {
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;regs[GPU_REG_LAST_DONE/4]=65534;
 gpu_device d;assert(!gpu_init(&d,GPU_APB_BASE));
 gpu_command c={.op=GPU_OP_COLOR_KEY,.src_addr=0x02400000,.dst_addr=0x02000000,
  .src_stride=16,.dst_stride=1920,.width_pixels=8,.height_pixels=8,.color_key=0xf81f};
 send(&d,&c);assert(writes==10 && commits==1 && fences==2 && d.next_tag==0);
 writes=0;c.dst_addr+=16;send(&d,&c);
 assert(writes==3 && commits==2 && fences==4 && d.next_tag==1);
 writes=0;send(&d,&c);assert(writes==2); /* tag/CONTROL never elided. */
 c.op=GPU_OP_ALPHA;c.alpha=128;c.width_pixels=3;c.height_pixels=2;c.src_stride=12;
 send(&d,&c);c.op=GPU_OP_COPY;c.alpha=0;c.color_key=0;send(&d,&c);
 c=(gpu_command){.op=GPU_OP_FILL,.dst_addr=0x02000000,.dst_stride=1920,
  .width_pixels=4,.height_pixels=1,.color=0x1234};send(&d,&c);
 c=(gpu_command){.op=GPU_OP_SPARSE,.src_addr=0x06000000,.dst_addr=0x02000000,
  .dst_stride=1920,.width_pixels=4,.height_pixels=1};send(&d,&c);
 c=(gpu_command){.op=GPU_OP_PRESENT,.dst_addr=0x02200000};writes=0;send(&d,&c);
 assert(writes==10); /* CPU compare PRESENT remains original full writes. */
 c=(gpu_command){.op=GPU_OP_COLOR_KEY,.src_addr=0x02400000,.dst_addr=0x02000000,
  .src_stride=16,.dst_stride=1920,.width_pixels=8,.height_pixels=8,.color_key=0xf81f};send(&d,&c);
 uint16_t tag=0xbeef;writes=0;c.flags=1;
 assert(gpu_submit(&d,&c,2,&tag)==GPU_DRIVER_ARGUMENT && !writes && tag==0xbeef);
 c.flags=0;full_reads=2;
 assert(gpu_submit(&d,&c,1,&tag)==GPU_DRIVER_TIMEOUT && !writes && tag==0xbeef);
 full_reads=2;expected=&c;assert(!gpu_submit(&d,&c,2,&tag) && writes==2);
 assert(!gpu_wait_tag(&d,tag,100));expected=0;
 regs[GPU_REG_ERROR/4]=9;writes=0;
 assert(gpu_submit(&d,&c,1,&tag)==GPU_DRIVER_HARDWARE && !writes);
 /* Reset/reinit must resynchronize every word, including zero-valued fields. */
 regs[GPU_REG_ERROR/4]=0;for(unsigned r=GPU_REG_OP/4;r<=GPU_REG_ALPHA_FLAGS/4;r++) regs[r]=0xdeadbeef;
 assert(!gpu_init(&d,GPU_APB_BASE));writes=0;send(&d,&c);assert(writes==10);
 static bullet_state state;static bullet_stream stream;
 unsigned start_writes=writes,start_commits=commits;
 static const unsigned tiers[]={32,64,128,256,512};
 for(unsigned tier=0;tier<5;tier++) {
  assert(!bullet_reset(&state,tiers[tier],7));
  for(unsigned tick=0;tick<600;tick++) {
   assert(!bullet_build_frame(&state,tick&1?GPU_FRAMEBUFFER_A:GPU_FRAMEBUFFER_B,1,1,BULLET_MAX_COMMANDS,&stream));
   assert(!bullet_clip_background_for_hud(&stream,72));
   for(unsigned i=0;i<stream.count;i++) send(&d,stream.commands+i);
   assert(!bullet_step(&state));
  }
 }
 unsigned sent=commits-start_commits,mmio=writes-start_writes;
 assert(sent>600000 && mmio<sent*6u);
 printf("PASS real delta submit: mixed op fields, tag wrap, full/retry/error/reinit, R7 frames=3000 commands=%u writes=%u versus_full=%u\n",sent,mmio,sent*10u);
}
