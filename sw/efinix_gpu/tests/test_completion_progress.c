#include "gpu.h"
#include <assert.h>
#include <stdio.h>
static unsigned next_completion,reads,error;
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);
 if(r==GPU_REG_LAST_DONE){reads++;unsigned n=next_completion;if(next_completion<15)next_completion++;return (uint16_t)(65530u+n);}
 if(r==GPU_REG_ERROR)return error;
 return 0;
}
void gpu_io_write(uintptr_t a,uint32_t v){(void)a;(void)v;}
void gpu_io_fence(void){}
static gpu_device active(void){return (gpu_device){.base=GPU_APB_BASE,.ready=1,.first_tag=65530,.next_tag=10,.last_done=65529,.pending_tag=9,.pending=1,.outstanding=16,.submitted_count=16};}
int main(void) {
 gpu_device d=active();
 for(unsigned i=0;i<32 && d.outstanding;i++){int e=gpu_poll(&d,9);assert(e==0 || e==GPU_POLL_PENDING);}
 assert(!d.outstanding && d.last_done==9 && reads==16);
 d=active();next_completion=0;error=GPU_ERROR_AXI_RESPONSE;
 assert(gpu_poll(&d,9)==GPU_DRIVER_HARDWARE && d.hardware_error==GPU_ERROR_AXI_RESPONSE);
 d=active();next_completion=16;error=0;
 assert(gpu_poll(&d,9)==GPU_DRIVER_TAG && d.outstanding==16);
 puts("PASS completion progress:continuously advancing valid tags,16-bit wrap,sticky error after DONE,unsubmitted tag rejected");
}
