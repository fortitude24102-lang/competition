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
typedef struct {
 uint64_t cpu_cycles, render_stalls, underflows, render_grants, scanout_grants;
 uint32_t frame_crc;
} gpu_qos_sample;
typedef struct {
 gpu_qos_sample fixed, adaptive;
 uint32_t dense_bytes, sparse_bytes;
} gpu_qos_benchmark_result;
typedef struct {
 gpu_perf_snapshot dense, sparse;
 uint64_t dense_cpu_cycles, sparse_cpu_cycles;
 uint32_t dense_crc, sparse_crc, dense_asset_bytes, sparse_asset_bytes;
} gpu_sparse_benchmark_result;
uint64_t gpu_platform_cycles(void);
/* Sapphire whole-cache/write-buffer synchronization, outside timed ranges. */
void gpu_platform_sync(void);
int gpu_benchmark(gpu_device *d,const golden_surface *cpu,const golden_surface *gpu,uint32_t gpu_address,uint32_t polls,gpu_benchmark_result *result);
int gpu_benchmark_submit_stream(gpu_device *device,const gpu_command *commands,size_t count,
 enum gpu_submit_mode mode,uint32_t poll_limit,gpu_submit_metrics *metrics);
int benchmark_summarize_run(const benchmark_frame_sample *samples,size_t count,benchmark_run_summary *summary);
uint16_t benchmark_counter_delta(uint64_t current,uint64_t *previous);
uint32_t gpu_command_stream_hash(const gpu_command *commands,size_t count,uint32_t seed);
int gpu_qos_benchmark_validate(const gpu_qos_benchmark_result *result);
int gpu_benchmark_qos_compare(gpu_device *device,const gpu_command *commands,size_t count,
 uint32_t poll_limit,const void *frame,size_t frame_bytes,uint32_t dense_bytes,
 uint32_t sparse_bytes,gpu_qos_benchmark_result *result);
int gpu_benchmark_sparse_compare(gpu_device *device,const gpu_command *dense_commands,
 const gpu_command *sparse_commands,size_t count,uint32_t poll_limit,
 const void *dense_frame,const void *sparse_frame,size_t frame_bytes,
 uint32_t dense_asset_bytes,uint32_t sparse_asset_bytes,
 gpu_sparse_benchmark_result *result);
#endif
