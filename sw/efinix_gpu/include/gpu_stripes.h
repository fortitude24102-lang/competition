#ifndef GPU_STRIPES_H
#define GPU_STRIPES_H
#include "gpu_frame_list.h"
#define GPU_STRIPE_CAPABILITY (1u<<16)
#define GPU_STRIPE_BASE 0x02e00000u
#define GPU_STRIPE_HEIGHT 8u
#define GPU_STRIPE_FIRST_Y 72u
#define GPU_STRIPE_COUNT 59u
#define GPU_STRIPE_SCENE_ADDR 0x02d40000u
#define GPU_STRIPE_BINS_ADDR 0x02d50000u
#define GPU_STRIPE_BIN_ITEMS 8192u
typedef struct {unsigned count,offset[GPU_STRIPE_COUNT+1u];} gpu_stripe_plan;
/* Whole-scene validation precedes output writes. Inputs, output, plan disjoint.
 * Stable ordering, original source stride and Alpha/Key semantics are retained. */
int gpu_stripes_build(const gpu_instance_template *templates,const gpu_instance *scene,
 unsigned count,uint32_t framebuffer,gpu_instance *bins,unsigned capacity,gpu_stripe_plan *plan);
int gpu_stripes_supported(gpu_device *gpu);
/* Exclusive GPU/list owner, input DDR frozen until return. Never retry/fallback
 * after any failure; caller must not PRESENT a partial strip-composed frame. */
int gpu_stripes_render(gpu_frame_list *list,int network,uint32_t framebuffer,
 const gpu_instance *scene,unsigned count,gpu_instance *bins,unsigned capacity,
 uint32_t epoch,uint32_t polls);
#endif
