#ifndef EFINIX_GPU_ASSETS_H
#define EFINIX_GPU_ASSETS_H
#include "gpu.h"
#define GPU_PLAYER_ASSET_WORDS 64u
#define GPU_ENEMY_ASSET_WORDS 96u
#define GPU_ASSET_WORDS (GPU_PLAYER_ASSET_WORDS+GPU_ENEMY_ASSET_WORDS)
typedef struct {
    uint32_t address;
    uint16_t width, height, stride_bytes;
    const uint16_t *pixels;
} gpu_asset;
extern const gpu_asset gpu_player_asset;
extern const gpu_asset gpu_enemy_asset;
size_t gpu_assets_upload_dense(volatile uint16_t *destination,size_t capacity_pixels);
#endif
