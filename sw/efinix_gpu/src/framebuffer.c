#include "framebuffer.h"
void framebuffer_init(framebuffer_pair *buffers) {
 if(buffers) *buffers=(framebuffer_pair){GPU_FRAMEBUFFER_A,GPU_FRAMEBUFFER_B};
}
int framebuffer_present(gpu_device *device,framebuffer_pair *buffers,uint32_t poll_limit) {
 if(!buffers) return GPU_DRIVER_ARGUMENT;
 uint16_t tag; int result=gpu_present_async(device,buffers->back,&tag);
 if(result) return result;
 result=gpu_wait_tag(device,tag,poll_limit);
 if(!result) { uint32_t old=buffers->front; buffers->front=buffers->back; buffers->back=old; }
 return result;
}
