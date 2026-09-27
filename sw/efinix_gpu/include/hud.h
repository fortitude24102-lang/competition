#ifndef EFINIX_GPU_HUD_H
#define EFINIX_GPU_HUD_H
#include "gpu.h"
#define HUD_MAX_COMMANDS 1024u
typedef struct {
 uint16_t fps, sprite_count, cpu_busy_permille, queue_high_watermark;
 uint16_t underflow_count, error_code;
 uint16_t render_stalls;
 uint8_t batch_mode, qos_adaptive;
} hud_metrics;
typedef struct { gpu_command commands[HUD_MAX_COMMANDS]; uint16_t count; } hud_command_stream;
int hud_draw_fps(gpu_device *device,uint32_t destination,uint32_t stride,uint16_t x,uint16_t y,unsigned fps,uint16_t color,uint16_t scale,uint32_t poll_limit);
int hud_build_metrics(uint32_t destination,uint32_t stride,uint16_t x,uint16_t y,const hud_metrics *metrics,hud_command_stream *stream);
typedef struct {
 uint32_t cpu_fps_x10,gpu_fps_x10,cpu_render_us,gpu_render_us;
 uint16_t sprites;
 uint8_t cpu_valid,gpu_valid,gpu_active,network_ready;
 uint8_t bullet_demo,error_code;
 uint32_t underflows;
} hud_comparison;
#define HUD_COMPARISON_LINES 4u
#define HUD_COMPARISON_COLUMNS 64u
int hud_comparison_text(const hud_comparison *metrics,char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS]);
int hud_build_comparison(uint32_t destination,const hud_comparison *metrics,hud_command_stream *stream);
#define HUD_CACHE_ADDR 0x02c10000u
#define HUD_CACHE_HEIGHT 72u
#define HUD_CACHE_BYTES (GPU_FRAME_STRIDE*HUD_CACHE_HEIGHT)
typedef struct {
 char text[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 uint32_t rebuilds;
 uint8_t valid;
} hud_raster_cache;
/* Zero-initialize cache; scratch must be static/BSS (too large for board stack).
 * Caller synchronizes DDR after update, before consuming the cached COPY. */
int hud_update_cache(const hud_comparison *metrics,hud_raster_cache *cache,hud_command_stream *scratch);
int hud_cached_command(uint32_t destination,const hud_raster_cache *cache,gpu_command *command);
#endif
