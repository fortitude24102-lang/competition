#include <assert.h>
#include <stdio.h>
#include "benchmark.h"
static uint32_t regs[32]; static uint8_t cpu[614400],frame[614400];
uint64_t gpu_platform_cycles(void) { static unsigned n; return ++n; }
void gpu_platform_sync(void) {}
void gpu_io_fence(void) {}
uint32_t gpu_io_read(uintptr_t a) { return regs[(a-GPU_APB_BASE)/4]; }
void gpu_io_write(uintptr_t a,uint32_t v) {
 regs[(a-GPU_APB_BASE)/4]=v;
 if(a==GPU_APB_BASE+GPU_REG_CONTROL) {
  unsigned offset=regs[GPU_REG_DST_ADDR/4]-GPU_FRAMEBUFFER_A;
  unsigned w=regs[GPU_REG_SIZE/4]&65535,h=regs[GPU_REG_SIZE/4]>>16;
  for(unsigned y=0;y<h;y++) for(unsigned x=0;x<w;x++) {
   unsigned i=offset+y*regs[GPU_REG_DST_STRIDE/4]+x*2;
   assert(i+1<sizeof frame); frame[i]=regs[GPU_REG_COLOR_KEY/4]; frame[i+1]=regs[GPU_REG_COLOR_KEY/4]>>8;
  }
  regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];
 }
}
int main(void) {
 regs[GPU_REG_ID/4]=GPU_ID_VALUE; regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE; regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;
 gpu_device d; gpu_benchmark_result r;
 golden_surface c={cpu,sizeof cpu,640,480,1280},g={frame,sizeof frame,640,480,1280};
 assert(gpu_init(&d,GPU_APB_BASE)==0);
 assert(gpu_benchmark(&d,&c,&g,GPU_FRAMEBUFFER_A,8,&r)==0);
 assert(r.cpu_crc==r.gpu_crc && r.pixels>307200 && r.cpu_cycles==1 && r.gpu_cycles==1);
 puts("PASS: production benchmark/driver fill against independent byte-memory model; synthetic cycles only");
}
