#ifndef EFINIX_GPU_ASSETS_H
#define EFINIX_GPU_ASSETS_H
#include "gpu.h"
#define GPU_ASSET_WORDS 64u
typedef struct {
    uint32_t address;
    uint16_t width, height, stride_bytes;
    const uint16_t *pixels;
} gpu_asset;
extern const gpu_asset gpu_player_asset;
size_t gpu_assets_upload_dense(volatile uint16_t *destination,size_t capacity_pixels);
#endif
