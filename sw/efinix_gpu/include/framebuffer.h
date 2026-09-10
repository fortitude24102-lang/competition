#ifndef EFINIX_GPU_FRAMEBUFFER_H
#define EFINIX_GPU_FRAMEBUFFER_H
#include "gpu.h"
typedef struct { uint32_t front,back; } framebuffer_pair;
void framebuffer_init(framebuffer_pair *buffers);
int framebuffer_present(gpu_device *device,framebuffer_pair *buffers,uint32_t poll_limit);
#endif
