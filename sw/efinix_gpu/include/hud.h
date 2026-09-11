#ifndef EFINIX_GPU_HUD_H
#define EFINIX_GPU_HUD_H
#include "gpu.h"
#define HUD_MAX_COMMANDS 127u
typedef struct {
 uint16_t fps, sprite_count, cpu_busy_permille, queue_high_watermark;
 uint16_t underflow_count, error_code;
 uint8_t batch_mode;
} hud_metrics;
typedef struct { gpu_command commands[HUD_MAX_COMMANDS]; uint16_t count; } hud_command_stream;
int hud_draw_fps(gpu_device *device,uint32_t destination,uint32_t stride,uint16_t x,uint16_t y,unsigned fps,uint16_t color,uint16_t scale,uint32_t poll_limit);
int hud_build_metrics(uint32_t destination,uint32_t stride,uint16_t x,uint16_t y,const hud_metrics *metrics,hud_command_stream *stream);
#endif
