#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "gpu.h"

static uint32_t regs[64];
static unsigned writes;
uint32_t gpu_io_read(uintptr_t a) { return regs[(a-GPU_APB_BASE)/4]; }
void gpu_io_write(uintptr_t a,uint32_t v) { regs[(a-GPU_APB_BASE)/4]=v; ++writes; }
void gpu_io_fence(void) {}

static gpu_command command(void) {
 return (gpu_command){.op=7,.src_addr=GPU_DENSE_ASSETS,.dst_addr=GPU_FRAMEBUFFER_A+2,
  .src_stride=4,.dst_stride=10,.width_pixels=2,.height_pixels=2,
  .src_width_pixels=2,.src_height_pixels=2};
}
static void rejected(gpu_device *d,gpu_command c,int error) {
 unsigned before=writes,submitted=d->submitted_count;uint16_t next=d->next_tag,tag=0xbeef;
 assert(gpu_try_submit(d,&c,&tag)==error);
 assert(writes==before && d->submitted_count==submitted && d->next_tag==next && tag==0xbeef);
}
static void accepted(gpu_device *d,gpu_command c) {
 unsigned before=writes;uint16_t tag=0,assigned=d->next_tag;
 assert(gpu_try_submit(d,&c,&tag)==0);
 assert(tag==assigned && regs[GPU_REG_TAG/4]==assigned);
 assert(writes==before+11 && regs[GPU_REG_OP/4]==7);
 assert(regs[GPU_REG_SIZE/4]==((uint32_t)c.height_pixels<<16 | c.width_pixels));
 assert(regs[GPU_REG_ALPHA_FLAGS/4]==((uint32_t)c.flags<<16));
 assert(regs[GPU_REG_SRC_ADDR/4]==c.src_addr && regs[GPU_REG_DST_ADDR/4]==c.dst_addr);
 assert(regs[GPU_REG_TRANSFORM_SOURCE_SIZE/4]==((uint32_t)c.src_height_pixels<<16|c.src_width_pixels));
 assert(regs[GPU_REG_COLOR_KEY/4]==((uint32_t)c.color_key<<16));
 regs[GPU_REG_LAST_DONE/4]=tag;assert(gpu_wait_tag(d,tag,2)==0);
}
int main(void) {
 assert(sizeof(gpu_command)==32);
 assert(offsetof(gpu_command,color)==20 && offsetof(gpu_command,src_width_pixels)==20);
 assert(offsetof(gpu_command,tag)==26 && offsetof(gpu_command,src_height_pixels)==26);
 assert(offsetof(gpu_command,color_key)==22 && offsetof(gpu_command,flags)==24);
 assert(offsetof(gpu_command,op)==28 && offsetof(gpu_command,alpha)==29);
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY|(1u<<17);
 gpu_device d;assert(!gpu_init(&d,GPU_APB_BASE));gpu_command c=command();
 accepted(&d,c);
 for(unsigned flags=1;flags<=3;flags++) {c=command();c.flags=(uint16_t)flags;accepted(&d,c);}
 c=command();c.width_pixels=4;c.height_pixels=4;accepted(&d,c);
 c=command();c.src_stride=8;c.src_width_pixels=4;c.src_height_pixels=4;accepted(&d,c);
 c=command();c.src_stride=6;c.src_width_pixels=3;c.width_pixels=5;c.height_pixels=3;accepted(&d,c);
 c=command();c.flags=19;c.color_key=0xbeef;accepted(&d,c);
 uint16_t helper_tag=0;
 assert(!gpu_transform_blit_async(&d,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_A+2,4,10,2,2,4,4,
  GPU_TRANSFORM_HFLIP|GPU_TRANSFORM_COLOR_KEY,0xbeef,&helper_tag));
 assert(regs[GPU_REG_ALPHA_FLAGS/4]==0x00110000u && regs[GPU_REG_COLOR_KEY/4]==0xbeef0000u);
 regs[GPU_REG_LAST_DONE/4]=helper_tag;assert(!gpu_wait_tag(&d,helper_tag,2));
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;rejected(&d,command(),GPU_DRIVER_ARGUMENT);
 /* Old commands continue to work on old hardware with no transform capability. */
 uint16_t tag;assert(!gpu_fill_async(&d,GPU_FRAMEBUFFER_A,4,2,2,0x1234,&tag));
 regs[GPU_REG_LAST_DONE/4]=tag;assert(!gpu_wait_tag(&d,tag,2));
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY|(1u<<17);
 /* A scaling-only old BIT must reject gray before MMIO/tag changes. */
 c=command();c.flags=32;rejected(&d,c,GPU_DRIVER_ARGUMENT);
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY|(1u<<17)|(1u<<18);
 accepted(&d,c);
 c.flags=51;accepted(&d,c);
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY|(1u<<18);
 rejected(&d,c,GPU_DRIVER_ARGUMENT); /* Gray bit alone is not Transform. */
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY|(1u<<17)|(1u<<18);
 c=command();c.flags=64;rejected(&d,c,10);
 c=command();c.flags=12;rejected(&d,c,10);
 c=command();c.flags=4;rejected(&d,c,10);
 c=command();c.src_width_pixels=0;rejected(&d,c,GPU_ERROR_ZERO_SIZE);
 c=command();c.src_height_pixels=0;rejected(&d,c,GPU_ERROR_ZERO_SIZE);
 c=command();c.width_pixels=0;rejected(&d,c,GPU_ERROR_ZERO_SIZE);
 c=command();c.src_addr++;rejected(&d,c,GPU_ERROR_MISALIGNED_ADDRESS);
 c=command();c.dst_stride=3;rejected(&d,c,GPU_ERROR_MISALIGNED_ADDRESS);
 c=command();c.src_width_pixels=4;c.src_stride=4;rejected(&d,c,GPU_ERROR_STRIDE_TOO_SMALL);
 c=command();c.src_addr=GPU_DDR_END_EXCLUSIVE-4;rejected(&d,c,GPU_ERROR_ADDRESS_RANGE);
 c=command();c.dst_addr=GPU_DDR_END_EXCLUSIVE-4;rejected(&d,c,GPU_ERROR_ADDRESS_RANGE);
 c=command();c.src_stride=0xfffffffeu;rejected(&d,c,GPU_ERROR_ADDRESS_RANGE);
 c=command();c.dst_addr=c.src_addr;rejected(&d,c,GPU_ERROR_OVERLAPPING_COPY);
 c=command();c.op=GPU_OP_COPY;c.flags=1;rejected(&d,c,GPU_DRIVER_ARGUMENT);
 regs[GPU_REG_STATUS/4]=GPU_STATUS_FULL|(1u<<17);rejected(&d,command(),GPU_DRIVER_AGAIN);
 puts("PASS transform driver: capability, derived bounds, flags, MMIO, no partial submit, legacy commands");
}
