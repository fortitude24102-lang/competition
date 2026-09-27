/* Windows can reserve the board's low DDR addresses for its process heap.
 * Relocate ONLY host-test pointers; offsets/strides and firmware stay unchanged.
 * Force-include this file in all translation units of a mapped host test. */
#ifndef EFINIX_HOST_ADDRESSES_H
#define EFINIX_HOST_ADDRESSES_H
#include "perf_demo.h"
#include "bullet_demo.h"
#include "asset_catalog.h"
#ifdef _WIN32
#undef GPU_FRAMEBUFFER_A
#undef GPU_FRAMEBUFFER_B
#undef GPU_DENSE_ASSETS
#undef GPU_DDR_END_EXCLUSIVE
#define GPU_FRAMEBUFFER_A 0x20000000u
#define GPU_FRAMEBUFFER_B 0x20200000u
#define GPU_DENSE_ASSETS 0x20400000u
#define GPU_DDR_END_EXCLUSIVE 0x2e000000u
#undef PERF_LOCAL_SPRITE
#undef PERF_LOCAL_ALPHA
#define PERF_LOCAL_SPRITE 0x20800000u
#define PERF_LOCAL_ALPHA 0x20810000u
#undef ASSET_SCENE_ADDR
#undef ASSET_FLOWER_ADDR
#undef ASSET_ZOMBIE_WALK1_ADDR
#undef ASSET_ZOMBIE_WALK2_ADDR
#define ASSET_SCENE_ADDR 0x20400000u
#define ASSET_FLOWER_ADDR 0x20600000u
#define ASSET_ZOMBIE_WALK1_ADDR 0x20610000u
#define ASSET_ZOMBIE_WALK2_ADDR 0x20620000u
#undef BULLET_BACKGROUND_ADDR
#undef BULLET_ATLAS_ADDR
#define BULLET_BACKGROUND_ADDR 0x20900000u
#define BULLET_ATLAS_ADDR 0x20a00000u
#undef BULLET_LOCAL_BACKGROUND
#undef BULLET_LOCAL_ATLAS
#define BULLET_LOCAL_BACKGROUND 0x20b00000u
#define BULLET_LOCAL_ATLAS 0x20c00000u
#endif
#endif
