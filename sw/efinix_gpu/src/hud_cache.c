#include "hud.h"
#include "bullet_demo.h"
#include "golden_renderer.h"
#include <string.h>
_Static_assert(BULLET_LOCAL_ATLAS+BULLET_ATLAS_BYTES<=HUD_CACHE_ADDR,"HUD disjoint from local and network assets");
_Static_assert(HUD_CACHE_ADDR+HUD_CACHE_BYTES<=GPU_DDR_END_EXCLUSIVE,"HUD DDR bounds");
int hud_update_cache(const hud_comparison *m,hud_raster_cache *cache,hud_command_stream *scratch) {
 if(!m || !cache || !scratch) return GPU_DRIVER_ARGUMENT;
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS]={{0}};
 int e=hud_comparison_text(m,lines); if(e) return e;
 uint8_t show=(uint8_t)hud_logo_fits(lines);
 if(cache->valid && cache->logo_visible==show && !memcmp(cache->text,lines,sizeof lines)) return 0;
 e=hud_build_comparison(GPU_FRAMEBUFFER_A,m,scratch); if(e) return e;
 cache->valid=0;
 golden_surface surface={(uint8_t *)(uintptr_t)HUD_CACHE_ADDR,HUD_CACHE_BYTES,
  GPU_FRAME_WIDTH,HUD_CACHE_HEIGHT,GPU_FRAME_STRIDE};
 for(unsigned n=0;n<scratch->count;n++) {
  const gpu_command *c=&scratch->commands[n];
  if(c->dst_stride!=GPU_FRAME_STRIDE || c->dst_addr<GPU_FRAMEBUFFER_A)
   return GPU_DRIVER_ARGUMENT;
  uint32_t offset=c->dst_addr-GPU_FRAMEBUFFER_A;
  if(offset>=HUD_CACHE_BYTES || (offset&1u)) return GPU_DRIVER_ARGUMENT;
  if(c->op==GPU_OP_FILL) {
   e=golden_fill(&surface,(uint16_t)((offset%GPU_FRAME_STRIDE)/2u),
    (uint16_t)(offset/GPU_FRAME_STRIDE),c->width_pixels,c->height_pixels,c->color);
  } else if(c->op==GPU_OP_COPY && c->src_addr==HUD_LOGO_ADDR &&
   c->src_stride==HUD_LOGO_WIDTH*2u && c->width_pixels==HUD_LOGO_WIDTH && c->height_pixels==HUD_LOGO_HEIGHT) {
   golden_surface source={(uint8_t *)(uintptr_t)HUD_LOGO_ADDR,HUD_LOGO_BYTES,
    HUD_LOGO_WIDTH,HUD_LOGO_HEIGHT,HUD_LOGO_WIDTH*2u};
   e=golden_copy(&surface,(uint16_t)((offset%GPU_FRAME_STRIDE)/2u),
    (uint16_t)(offset/GPU_FRAME_STRIDE),&source,0,0,HUD_LOGO_WIDTH,HUD_LOGO_HEIGHT);
  } else return GPU_DRIVER_ARGUMENT;
  if(e) return e;
 }
 memcpy(cache->text,lines,sizeof lines); cache->logo_visible=show; cache->valid=1; ++cache->rebuilds;
 return 0;
}
int hud_cached_command(uint32_t dst,const hud_raster_cache *cache,gpu_command *command) {
 if(!cache || !cache->valid || !command || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B))
  return GPU_DRIVER_ARGUMENT;
 *command=(gpu_command){.op=GPU_OP_COPY,.src_addr=HUD_CACHE_ADDR,.dst_addr=dst,
  .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=HUD_CACHE_HEIGHT};
 return 0;
}
