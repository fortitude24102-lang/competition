#include <assert.h>
#include <stdio.h>
#include "gpu.h"
static uint32_t regs[32]; static unsigned writes, barriers;
uint32_t gpu_io_read(uintptr_t a) { return regs[(a-GPU_APB_BASE)/4]; }
void gpu_io_write(uintptr_t a,uint32_t v) { regs[(a-GPU_APB_BASE)/4]=v; ++writes; }
void gpu_io_fence(void) { ++barriers; }
int main(void) {
 gpu_device d={0}; uint16_t tag;
 assert(gpu_init(&d,GPU_APB_BASE)==GPU_DRIVER_ID);
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;
 assert(gpu_init(&d,GPU_APB_BASE)==GPU_DRIVER_VERSION);
 regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE; regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;
 assert(gpu_init(&d,GPU_APB_BASE)==0);
 tag=0xbeef;
 assert(gpu_fill_async(&d,GPU_FRAMEBUFFER_A,1280,0,2,0x1234,&tag)==GPU_ERROR_ZERO_SIZE && tag==0xbeef && !d.pending);
 assert(gpu_fill_async(&d,GPU_FRAMEBUFFER_A,1280,3,2,0x1234,&tag)==0 && tag==1);
 assert(writes==10 && regs[GPU_REG_SIZE/4]==0x20003 && regs[GPU_REG_CONTROL/4]==1 && barriers);
 assert(gpu_wait_tag(&d,0,2)==GPU_DRIVER_TAG);
 assert(gpu_wait_tag(&d,tag,2)==GPU_DRIVER_TIMEOUT);
 assert(gpu_fill_async(&d,GPU_FRAMEBUFFER_A,1280,3,2,0,&tag)==GPU_DRIVER_BUSY);
 regs[GPU_REG_LAST_DONE/4]=1;
 assert(gpu_wait_tag(&d,1,2)==0);
 regs[GPU_REG_STATUS/4]=GPU_STATUS_FULL;
 assert(gpu_fill_async(&d,GPU_FRAMEBUFFER_A,1280,3,2,0,&tag)==GPU_DRIVER_FULL);
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY; regs[GPU_REG_LAST_DONE/4]=65535;
 assert(gpu_fill_async(&d,GPU_FRAMEBUFFER_A,1280,3,2,0,&tag)==0 && tag==0);
 assert(gpu_wait_tag(&d,tag,1)==GPU_DRIVER_TIMEOUT);
 regs[GPU_REG_LAST_DONE/4]=0; regs[GPU_REG_ERROR/4]=9;
 assert(gpu_wait_tag(&d,tag,1)==GPU_DRIVER_HARDWARE && d.hardware_error==9);
 puts("PASS: production driver identity/version, submit fields, busy/full, timeout, tag wrap, hardware error");
}
