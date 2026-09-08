#ifndef EFINIX_BENCHMARK_H
#define EFINIX_BENCHMARK_H
#include "golden_renderer.h"
typedef struct { uint64_t cpu_cycles,gpu_cycles; uint32_t pixels,cpu_crc,gpu_crc; } gpu_benchmark_result;
uint64_t gpu_platform_cycles(void);
/* Sapphire whole-cache/write-buffer synchronization, outside timed ranges. */
void gpu_platform_sync(void);
int gpu_benchmark(gpu_device *d,const golden_surface *cpu,const golden_surface *gpu,uint32_t gpu_address,uint32_t polls,gpu_benchmark_result *result);
#endif
