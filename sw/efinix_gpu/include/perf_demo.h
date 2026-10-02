#ifndef EFINIX_PERF_DEMO_H
#define EFINIX_PERF_DEMO_H
#include "golden_renderer.h"
#include "gpu_damage.h"
#define PERF_MAX_SPRITES 256u
#define PERF_WINDOW_FRAMES 30u
#define PERF_LOCAL_SPRITE 0x02800000u
#define PERF_LOCAL_ALPHA 0x02810000u
typedef struct { gpu_command commands[PERF_MAX_SPRITES+1]; unsigned count; } perf_stream;
typedef struct { uint64_t wall_ticks,render_ticks; unsigned frames; } perf_window;
/* Same deterministic frame sequence is replayed in CPU and GPU windows. */
int perf_build_frame(uint32_t dst,unsigned sprites,unsigned frame,int network,perf_stream *out);
void perf_init_local_assets(void);
int perf_render_cpu(const gpu_command *commands,unsigned count);
int perf_render_gpu(gpu_device *device,const gpu_command *commands,unsigned count,uint32_t polls);
int perf_render_gpu_damage(gpu_device *device,gpu_damage_state *damage,
 const gpu_command *commands,unsigned count,uint32_t epoch,
 gpu_damage_result *result,uint32_t polls);
/* Reporting windows are bounded to PERF_WINDOW_FRAMES, including overflow guards. */
int perf_window_add(perf_window *window,uint64_t wall,uint64_t render);
uint32_t perf_fps_x10(const perf_window *window,uint32_t hz);
uint32_t perf_render_us(const perf_window *window,uint32_t hz);
#endif
