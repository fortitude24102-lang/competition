#ifndef EFINIX_BENCHMARK_H
#define EFINIX_BENCHMARK_H
#include "golden_renderer.h"
typedef struct { uint64_t cpu_cycles,gpu_cycles; uint32_t pixels,cpu_crc,gpu_crc; } gpu_benchmark_result;
#define BENCHMARK_FRAME_COUNT 300u
#define BENCHMARK_MIN_CAPACITY_SAMPLES 30u
enum gpu_submit_mode { GPU_SUBMIT_WAIT_EACH=0, GPU_SUBMIT_BATCH=1 };
typedef struct {
 uint64_t cpu_cycles;
 uint32_t command_count, wait_count;
 uint16_t queue_high_watermark, waits_per_command_permille;
} gpu_submit_metrics;
typedef struct {
 uint16_t fps, sprite_count, underflow_count, error_count;
} benchmark_frame_sample;
typedef struct {
 uint16_t p5_fps, stable_sprite_count;
 uint32_t total_underflows, total_errors;
} benchmark_run_summary;
uint64_t gpu_platform_cycles(void);
/* Sapphire whole-cache/write-buffer synchronization, outside timed ranges. */
void gpu_platform_sync(void);
int gpu_benchmark(gpu_device *d,const golden_surface *cpu,const golden_surface *gpu,uint32_t gpu_address,uint32_t polls,gpu_benchmark_result *result);
int gpu_benchmark_submit_stream(gpu_device *device,const gpu_command *commands,size_t count,
 enum gpu_submit_mode mode,uint32_t poll_limit,gpu_submit_metrics *metrics);
int benchmark_summarize_run(const benchmark_frame_sample *samples,size_t count,benchmark_run_summary *summary);
#endif
