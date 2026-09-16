#ifndef EFINIX_GPU_ASSETS_H
#define EFINIX_GPU_ASSETS_H
#include "gpu.h"
#include "sparse_format.h"
#define GPU_PLAYER_ASSET_WORDS 64u
#define GPU_ENEMY_ASSET_WORDS 96u
#define GPU_DEMO_ASSET_WORDS 64u
#define GPU_ASSET_WORDS (GPU_PLAYER_ASSET_WORDS+GPU_ENEMY_ASSET_WORDS+GPU_DEMO_ASSET_WORDS)
typedef struct {
    uint32_t address;
    uint16_t width, height, stride_bytes;
    const uint16_t *pixels;
} gpu_asset;
extern const gpu_asset gpu_player_asset;
extern const gpu_asset gpu_enemy_asset;
extern const gpu_asset gpu_demo_asset;
size_t gpu_assets_upload_dense(volatile uint16_t *destination,size_t capacity_pixels);
#define GPU_SPARSE_SLOT_WORDS 256u
typedef struct {
    uint32_t address;
    uint16_t width, height, transparent_key;
    const uint16_t *pixels;
} gpu_sparse_asset;
extern const gpu_sparse_asset gpu_player_sparse_asset;
extern const gpu_sparse_asset gpu_enemy_sparse_asset;
extern const gpu_sparse_asset gpu_demo_sparse_asset;
int gpu_assets_upload_sparse(volatile uint32_t *destination,size_t capacity_words,
                             size_t *player_words,size_t *enemy_words,size_t *demo_words);
#endif
