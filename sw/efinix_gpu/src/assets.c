#include "assets.h"
static const uint16_t player_pixels[GPU_PLAYER_ASSET_WORDS]={
 0,0,0x07e0,0x07e0,0x07e0,0x07e0,0,0,
 0,0x07e0,0xffff,0x07e0,0x07e0,0xffff,0x07e0,0,
 0x07e0,0xffff,0xffff,0x07e0,0x07e0,0xffff,0xffff,0x07e0,
 0x07e0,0x07e0,0x07e0,0xffff,0xffff,0x07e0,0x07e0,0x07e0,
 0x07e0,0x07e0,0xffff,0xffff,0xffff,0xffff,0x07e0,0x07e0,
 0,0x07e0,0x07e0,0xffff,0xffff,0x07e0,0x07e0,0,
 0,0,0x07e0,0x07e0,0x07e0,0x07e0,0,0,
 0,0,0x001f,0,0,0x001f,0,0
};
const gpu_asset gpu_player_asset={GPU_DENSE_ASSETS,8,8,16,player_pixels};
static const uint16_t enemy_pixels[GPU_ENEMY_ASSET_WORDS]={
 0xf800,0xf800,0,0,0,0,0,0,0,0,0xf800,0xf800,
 0,0xf800,0xf800,0xf800,0,0,0,0,0xf800,0xf800,0xf800,0,
 0,0,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0,0,
 0,0xf800,0xf800,0xffff,0xf800,0xf800,0xf800,0xf800,0xffff,0xf800,0xf800,0,
 0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,
 0xf800,0,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0xf800,0,0xf800,
 0xf800,0,0xf800,0,0,0,0,0,0xf800,0,0xf800,
 0,0,0,0xf800,0xf800,0,0,0xf800,0xf800,0,0,0
};
const gpu_asset gpu_enemy_asset={GPU_DENSE_ASSETS+GPU_PLAYER_ASSET_WORDS*2u,12,8,24,enemy_pixels};
static const uint16_t demo_pixels[GPU_DEMO_ASSET_WORDS]={
 0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,
 0,0,0x07e0,0x07e0,0x07e0,0x07e0,0,0,
 0,0,0x07e0,0xffff,0xffff,0x07e0,0,0,
 0,0,0x07e0,0xffff,0xffff,0x07e0,0,0,
 0,0,0x07e0,0x07e0,0x07e0,0x07e0,0,0,
 0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0
};
const gpu_asset gpu_demo_asset={GPU_DENSE_ASSETS+(GPU_PLAYER_ASSET_WORDS+GPU_ENEMY_ASSET_WORDS)*2u,8,8,16,demo_pixels};
const gpu_sparse_asset gpu_player_sparse_asset={GPU_SPARSE_ASSETS,8,8,0,player_pixels};
const gpu_sparse_asset gpu_enemy_sparse_asset={GPU_SPARSE_ASSETS+GPU_SPARSE_SLOT_WORDS*4u,12,8,0,enemy_pixels};
const gpu_sparse_asset gpu_demo_sparse_asset={GPU_SPARSE_ASSETS+GPU_SPARSE_SLOT_WORDS*8u,8,8,0,demo_pixels};
size_t gpu_assets_upload_dense(volatile uint16_t *destination,size_t capacity_pixels) {
 if(!destination || capacity_pixels<GPU_ASSET_WORDS) return 0;
 for(size_t i=0;i<GPU_PLAYER_ASSET_WORDS;i++) destination[i]=player_pixels[i];
 for(size_t i=0;i<GPU_ENEMY_ASSET_WORDS;i++) destination[GPU_PLAYER_ASSET_WORDS+i]=enemy_pixels[i];
 for(size_t i=0;i<GPU_DEMO_ASSET_WORDS;i++) destination[GPU_PLAYER_ASSET_WORDS+GPU_ENEMY_ASSET_WORDS+i]=demo_pixels[i];
 return GPU_ASSET_WORDS;
}

int gpu_assets_upload_sparse(volatile uint32_t *destination,size_t capacity,
 size_t *player_words,size_t *enemy_words,size_t *demo_words) {
 if(!destination || !player_words || !enemy_words || !demo_words || capacity<GPU_SPARSE_SLOT_WORDS*3u)
  return SPARSE_PACK_ARGUMENT;
 static uint32_t scratch[GPU_SPARSE_SLOT_WORDS];
 size_t pw=0,ew=0;
 int e=sparse_pack_rgb565(player_pixels,8,8,8,0,scratch,GPU_SPARSE_SLOT_WORDS,&pw);
 if(e) return e;
 for(size_t i=0;i<pw;i++) destination[i]=scratch[i];
 e=sparse_pack_rgb565(enemy_pixels,12,8,12,0,scratch,GPU_SPARSE_SLOT_WORDS,&ew);
 if(e) return e;
 for(size_t i=0;i<ew;i++) destination[GPU_SPARSE_SLOT_WORDS+i]=scratch[i];
 size_t dw=0;
 e=sparse_pack_rgb565(demo_pixels,8,8,8,0,scratch,GPU_SPARSE_SLOT_WORDS,&dw);
 if(e) return e;
 for(size_t i=0;i<dw;i++) destination[GPU_SPARSE_SLOT_WORDS*2u+i]=scratch[i];
 *player_words=pw; *enemy_words=ew; *demo_words=dw;
 return SPARSE_PACK_OK;
}
