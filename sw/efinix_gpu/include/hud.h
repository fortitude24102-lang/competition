#ifndef EFINIX_GPU_HUD_H
#define EFINIX_GPU_HUD_H
#include "gpu.h"
int hud_draw_fps(gpu_device *device,uint32_t destination,uint32_t stride,uint16_t x,uint16_t y,unsigned fps,uint16_t color,uint16_t scale,uint32_t poll_limit);
#endif
