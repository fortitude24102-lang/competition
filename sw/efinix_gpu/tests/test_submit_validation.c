/* Real production function-entry instrumentation: detects repeated descriptor
 * validation during hardware queue waits. Only the external APB peer is fake. */
#include <assert.h>
#include <stdio.h>
#define GPU_TEST_BACKEND
#include "../src/gpu.c"
static unsigned validations,full_reads,writes;
static uint32_t registers[256];
void __attribute__((no_instrument_function)) __cyg_profile_func_enter(void *fn,void *caller) {
 (void)caller;if(fn==(void *)validate) ++validations;
}
void __attribute__((no_instrument_function)) __cyg_profile_func_exit(void *fn,void *caller) {
 (void)fn;(void)caller;
}
uint32_t gpu_io_read(uintptr_t a) {
 if(a==GPU_APB_BASE+GPU_REG_STATUS && full_reads) {--full_reads;return GPU_STATUS_FULL;}
 return registers[(a-GPU_APB_BASE)/4];
}
void gpu_io_write(uintptr_t a,uint32_t value) {registers[(a-GPU_APB_BASE)/4]=value;++writes;}
void gpu_io_fence(void) {}
int main(void) {
 registers[GPU_REG_ID/4]=GPU_ID_VALUE;registers[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 registers[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;
 gpu_device d;assert(!gpu_init(&d,GPU_APB_BASE));
 gpu_command c={.op=GPU_OP_COPY,.src_addr=GPU_DENSE_ASSETS,.src_stride=32,
  .dst_addr=GPU_FRAMEBUFFER_A,.dst_stride=1920,.width_pixels=3,.height_pixels=2};
 uint16_t tag=0xbeef;full_reads=2;validations=writes=0;
 assert(!gpu_submit(&d,&c,2,&tag) && tag==1 && d.outstanding==1 && writes==10);
 assert(validations==1); /* Old queue-full path revalidates three times. */
 full_reads=2;validations=writes=0;tag=0xbeef;
 assert(gpu_submit(&d,&c,1,&tag)==GPU_DRIVER_TIMEOUT && tag==0xbeef && !writes);
 assert(validations==1);
 full_reads=2;c.width_pixels=0;validations=0;
 assert(gpu_submit(&d,&c,1,&tag)==GPU_ERROR_ZERO_SIZE && full_reads==2 && !writes);
 assert(validations==1);
 c.width_pixels=3;full_reads=2;validations=0;
 assert(gpu_try_submit(&d,&c,&tag)==GPU_DRIVER_AGAIN && validations==1 && !writes);
 full_reads=0;registers[GPU_REG_ERROR/4]=9;
 assert(gpu_submit(&d,&c,1,&tag)==GPU_DRIVER_HARDWARE && !writes);
 assert(gpu_submit(0,&c,1,&tag)==GPU_DRIVER_ARGUMENT);
 puts("PASS real GPU submit validates once across queue waits; public try validates; guards/timeouts/errors retained");
}
