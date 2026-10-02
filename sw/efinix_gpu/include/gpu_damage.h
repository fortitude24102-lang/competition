#ifndef EFINIX_GPU_DAMAGE_H
#define EFINIX_GPU_DAMAGE_H
#include "gpu.h"
#define GPU_DAMAGE_HUD 72u
#define GPU_DAMAGE_TILES 1800u
#define GPU_DAMAGE_MASK_BYTES 225u
#define GPU_DAMAGE_RECTS 128u
/* Command/burst coefficients in cycles; per-word coefficient in cycles*256.
 * GPU and CLINT both100MHz on the verified baseline.
 * Model charges BOTH AXI directions; costs are not an FPS guarantee. */
typedef struct { uint32_t command_cycles,burst_cycles,word_cycles_x256; } gpu_damage_cost;
typedef struct { unsigned tile,gap,capacity; gpu_damage_cost cost; } gpu_damage_config;
#define GPU_DAMAGE_DEFAULT_CONFIG {16,4,128,{517,64,164}}
enum { GPU_DAMAGE_PARTIAL, GPU_DAMAGE_COLD, GPU_DAMAGE_CAPACITY, GPU_DAMAGE_COST };
typedef struct {
 gpu_command commands[GPU_DAMAGE_RECTS];
 unsigned count,reason;
 uint32_t bytes,bursts;
 uint64_t cost,full_cost;
} gpu_damage_result;
/* Allocate in BSS, not the official Sapphire's 4 KiB stack. One producer. */
typedef struct {
 gpu_damage_config config;
 uint8_t history[2][GPU_DAMAGE_MASK_BYTES],next[GPU_DAMAGE_MASK_BYTES];
 int16_t last_rect[60];
 uint32_t epoch,background;
 uint32_t full_bursts;
 uint64_t full_cost;
 uint8_t valid[2],pending,buffer;
} gpu_damage_state;
int gpu_damage_init(gpu_damage_state *state,const gpu_damage_config *config);
void gpu_damage_invalidate(gpu_damage_state *state);
/* Only R7's background Copy at y=72, 960x468, then ROI sprites is accepted.
 * Return restoration count (possibly zero), or negative without submitting.
 * Caller submits result, then ALL commands[1..] once, waits, and commits.
 * Invalidate BOTH histories on any external CPU write, resource replacement,
 * render/HUD/PRESENT error, or reset. Never replay Alpha after partial failure. */
int gpu_damage_plan(gpu_damage_state *state,const gpu_command *commands,
 unsigned count,uint32_t epoch,gpu_damage_result *result);
void gpu_damage_commit(gpu_damage_state *state,int success);
uint64_t gpu_damage_copy_cost(const gpu_command *command,const gpu_damage_cost *cost,
 uint32_t *bytes,uint32_t *bursts);
#endif
