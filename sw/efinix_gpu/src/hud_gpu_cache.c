#include "hud.h"
#include "perf_demo.h"
#include <string.h>

static unsigned glyph_index(unsigned char ch) {
 return ch>='A'&&ch<='Z'?(unsigned)(ch-'A'):ch>='0'&&ch<='9'?26u+ch-'0':
  ch=='-'?36u:ch=='.'?37u:38u;
}

int hud_update_gpu_cache(gpu_device *gpu,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls) {
 if(!gpu || !gpu->ready || !m || !cache || !scratch || !polls) return GPU_DRIVER_ARGUMENT;
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS]={{0}};
 int e=hud_comparison_text(m,lines); if(e) return e;
 uint8_t show=(uint8_t)hud_logo_fits(lines);
 scratch->count=0;
 if(cache->valid && cache->logo_visible==show && !memcmp(cache->text,lines,sizeof lines)) return 0;
 _Static_assert(HUD_MAX_COMMANDS>=2u+HUD_COMPARISON_LINES*HUD_COMPARISON_COLUMNS,"HUD command capacity");
 _Static_assert(8u+HUD_COMPARISON_COLUMNS*HUD_GLYPH_WIDTH<=GPU_FRAME_WIDTH,"glyph line bounds");
 _Static_assert(HUD_COMPARISON_LINES*HUD_GLYPH_HEIGHT==HUD_CACHE_HEIGHT,"glyph row bounds");
 if(!cache->valid) scratch->commands[scratch->count++]=(gpu_command){
  .op=GPU_OP_FILL,.dst_addr=HUD_CACHE_ADDR,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=HUD_CACHE_HEIGHT};
 if(cache->valid && cache->logo_visible && !show) scratch->commands[scratch->count++]=(gpu_command){
  .op=GPU_OP_FILL,.dst_addr=HUD_CACHE_ADDR+HUD_LOGO_Y*GPU_FRAME_STRIDE+HUD_LOGO_X*2u,
  .dst_stride=GPU_FRAME_STRIDE,.width_pixels=HUD_LOGO_WIDTH,.height_pixels=HUD_LOGO_HEIGHT};
 for(unsigned line=0;line<HUD_COMPARISON_LINES;line++) for(unsigned n=0;n<HUD_COMPARISON_COLUMNS;n++) {
  unsigned char ch=(unsigned char)lines[line][n];
  if(cache->valid?ch==(unsigned char)cache->text[line][n]:!ch || ch==' ') continue;
  scratch->commands[scratch->count++]=(gpu_command){
   .op=GPU_OP_COPY,
   .src_addr=HUD_GLYPH_ATLAS_ADDR+(line==2?HUD_GLYPH_BANK_BYTES:0)+glyph_index(ch)*HUD_GLYPH_CELL_BYTES,
   .dst_addr=HUD_CACHE_ADDR+line*HUD_GLYPH_HEIGHT*GPU_FRAME_STRIDE+(8u+n*HUD_GLYPH_WIDTH)*2u,
   .src_stride=HUD_GLYPH_WIDTH*2u,.dst_stride=GPU_FRAME_STRIDE,
   .width_pixels=HUD_GLYPH_WIDTH,.height_pixels=HUD_GLYPH_HEIGHT};
 }
 /* Restore after clearing shortened text tails, which may touch this area. */
 if(show && (!cache->valid || !cache->logo_visible)) scratch->commands[scratch->count++]=(gpu_command){
  .op=GPU_OP_COPY,.src_addr=HUD_LOGO_ADDR,
  .dst_addr=HUD_CACHE_ADDR+HUD_LOGO_Y*GPU_FRAME_STRIDE+HUD_LOGO_X*2u,
  .src_stride=HUD_LOGO_WIDTH*2u,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=HUD_LOGO_WIDTH,.height_pixels=HUD_LOGO_HEIGHT};
 /* Partial DMA writes must never leave apparently valid old metadata. */
 cache->valid=0;
 e=perf_render_gpu(gpu,scratch->commands,scratch->count,polls); if(e) return e;
 memcpy(cache->text,lines,sizeof lines); cache->logo_visible=show; cache->valid=1; ++cache->rebuilds;
 return 0;
}
