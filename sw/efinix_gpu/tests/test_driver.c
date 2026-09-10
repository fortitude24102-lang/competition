#include <assert.h>
#include <stdio.h>
#include <string.h>
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

 /* Day 14/15: color key and alpha submit fields + guard paths */
 memset(regs, 0, sizeof regs); writes = 0; barriers = 0;
 regs[GPU_REG_ID/4]=GPU_ID_VALUE; regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;
 gpu_device k={0};
 assert(gpu_init(&k,GPU_APB_BASE)==0);
 uint16_t ktag=0, atag=0;
 assert(gpu_color_key_async(&k,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A,32,1280,3,2,0xf81f,&ktag)==0 && ktag==1);
 assert(regs[GPU_REG_OP/4]==GPU_OP_COLOR_KEY);
 assert(regs[GPU_REG_SRC_ADDR/4]==GPU_DENSE_ASSETS);
 assert(regs[GPU_REG_DST_ADDR/4]==GPU_FRAMEBUFFER_A);
 assert(regs[GPU_REG_SIZE/4]==gpu_pack_size(3,2));
 assert(regs[GPU_REG_SRC_STRIDE/4]==32);
 assert(regs[GPU_REG_DST_STRIDE/4]==1280);
 assert(regs[GPU_REG_COLOR_KEY/4]==gpu_pack_color_key(0,0xf81f));
 assert(regs[GPU_REG_TAG/4]==1);
 assert(regs[GPU_REG_CONTROL/4]==1);
 regs[GPU_REG_LAST_DONE/4]=1;
 assert(gpu_wait_tag(&k,1,2)==0);
 assert(gpu_alpha_async(&k,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A,32,1280,3,2,128,&atag)==0 && atag==2);
 assert(regs[GPU_REG_OP/4]==GPU_OP_ALPHA);
 assert(regs[GPU_REG_ALPHA_FLAGS/4]==gpu_pack_alpha_flags(128,0));
 regs[GPU_REG_LAST_DONE/4]=2;
 assert(gpu_wait_tag(&k,2,2)==0);
 assert(gpu_color_key_async(&k,GPU_FRAMEBUFFER_A,GPU_FRAMEBUFFER_A,1280,1280,640,480,0,&ktag)==GPU_ERROR_OVERLAPPING_COPY);
 assert(gpu_alpha_async(&k,GPU_FRAMEBUFFER_A,GPU_FRAMEBUFFER_A,1280,1280,640,480,0,&atag)==GPU_ERROR_OVERLAPPING_COPY);
 assert(gpu_color_key_async(&k,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A,32,1280,0,2,0,&ktag)==GPU_ERROR_ZERO_SIZE);
 assert(gpu_alpha_async(&k,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A,32,1280,3,0,0,&atag)==GPU_ERROR_ZERO_SIZE);
 assert(gpu_color_key_async(&k,GPU_DENSE_ASSETS+1,GPU_FRAMEBUFFER_A,32,1280,3,2,0,&ktag)==GPU_ERROR_MISALIGNED_ADDRESS);
 assert(gpu_alpha_async(&k,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A,4,1280,3,2,0,&atag)==GPU_ERROR_STRIDE_TOO_SMALL);
 assert(gpu_color_key_async(&k,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A,32,1280,3,2,0x1234,&ktag)==0 && ktag==3);
 puts("PASS: production driver identity/version, submit fields, busy/full, timeout, tag wrap, hardware error, color key/alpha fields and guards");
}
