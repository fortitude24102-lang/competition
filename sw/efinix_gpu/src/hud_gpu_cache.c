#include "hud.h"
#include "perf_demo.h"
#include <string.h>
#ifndef V3_HUD_LIST
#define V3_HUD_LIST 0
#endif
#ifndef V3_HUD_DIRECT
#define V3_HUD_DIRECT 0
#endif
#if V3_HUD_LIST && V3_HUD_DIRECT
#error "Choose one HUD candidate"
#endif
#if V3_HUD_LIST
#include "hud_gpu_list.h"
int hud_gpu_list_init(gpu_frame_list *list,int network) {
 if(!list || !list->gpu || !list->gpu->ready || !list->present ||
    (network!=0 && network!=1))return GPU_DRIVER_ARGUMENT;
 if(list->active)return GPU_DRIVER_BUSY;
 list->hud_ready=0;
 gpu_instance_template t[16];
 if(gpu_instances_templates(network,t)!=12)return GPU_DRIVER_ARGUMENT;
 t[12]=(gpu_instance_template){GPU_OP_COPY,HUD_GLYPH_ATLAS_ADDR,HUD_GLYPH_WIDTH*2u,
  GPU_FRAME_STRIDE,HUD_GLYPH_WIDTH,HUD_GLYPH_ATLAS_BYTES/(HUD_GLYPH_WIDTH*2u),0};
 t[13]=(gpu_instance_template){GPU_OP_COPY,HUD_CACHE_ADDR,GPU_FRAME_STRIDE,
  GPU_FRAME_STRIDE,GPU_FRAME_WIDTH,HUD_CACHE_HEIGHT,0};
 t[14]=(gpu_instance_template){GPU_OP_COPY,HUD_LOGO_ADDR,HUD_LOGO_WIDTH*2u,
  GPU_FRAME_STRIDE,HUD_LOGO_WIDTH,HUD_LOGO_HEIGHT,0};
 gpu_instances frontend={.gpu=list->gpu,.present=1};
 int e=gpu_instances_program(&frontend,t,15);if(!e)list->hud_ready=1;
 return e;
}
static int render_hud_batch(gpu_frame_list *list,const hud_command_stream *s,
 uint32_t dst,uint32_t bank,uint32_t epoch,uint32_t polls) {
 gpu_command copy={.op=GPU_OP_COPY,.src_addr=HUD_CACHE_ADDR,.dst_addr=dst,
  .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=HUD_CACHE_HEIGHT};
 /* ponytail: preserve the existing Fill path for rebuild/clear. Do not grow
  * the RTL list ABI for rare transitions; no fallback AFTER partial issue. */
 int legacy=s->count==0;
 for(unsigned i=0;i<s->count;i++)if(s->commands[i].op==GPU_OP_FILL)legacy=1;
 if(legacy) {
  int e=s->count?perf_render_gpu(list->gpu,s->commands,s->count,polls):0;
  return e?e:perf_render_gpu(list->gpu,&copy,1,polls);
 }
 if(s->count>HUD_COMPARISON_LINES*HUD_COMPARISON_COLUMNS+1u)return GPU_DRIVER_ARGUMENT;
 gpu_instance *items=(gpu_instance *)(uintptr_t)bank;
 for(unsigned i=0;i<s->count;i++) {
  const gpu_command *c=s->commands+i;unsigned id;
  if(c->op!=GPU_OP_COPY || c->dst_stride!=GPU_FRAME_STRIDE)return GPU_DRIVER_ARGUMENT;
  if(c->src_addr>=HUD_GLYPH_ATLAS_ADDR &&
     (uint64_t)c->src_addr+HUD_GLYPH_CELL_BYTES<=HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES &&
     !((c->src_addr-HUD_GLYPH_ATLAS_ADDR)%HUD_GLYPH_CELL_BYTES) &&
     c->src_stride==HUD_GLYPH_WIDTH*2u && c->width_pixels==HUD_GLYPH_WIDTH && c->height_pixels==HUD_GLYPH_HEIGHT)id=12;
  else if(c->src_addr==HUD_LOGO_ADDR && c->src_stride==HUD_LOGO_WIDTH*2u &&
          c->width_pixels==HUD_LOGO_WIDTH && c->height_pixels==HUD_LOGO_HEIGHT)id=14;
  else return GPU_DRIVER_ARGUMENT;
  items[i]=(gpu_instance){{id,c->dst_addr,c->src_addr-(id==12?HUD_GLYPH_ATLAS_ADDR:HUD_LOGO_ADDR),
   gpu_pack_size(c->width_pixels,c->height_pixels)}};
 }
 items[s->count]=(gpu_instance){{13,dst,0,gpu_pack_size(GPU_FRAME_WIDTH,HUD_CACHE_HEIGHT)}};
 return gpu_frame_list_render(list,bank,s->count+1u,epoch,polls);
}
#endif

static unsigned glyph_index(unsigned char ch) {
 return ch>='A'&&ch<='Z'?(unsigned)(ch-'A'):ch>='0'&&ch<='9'?26u+ch-'0':
  ch=='-'?36u:ch=='.'?37u:38u;
}

#if V3_HUD_LIST
static int update_gpu_cache(gpu_device *gpu,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls,
 gpu_frame_list *list,uint32_t dst,uint32_t bank,uint32_t epoch) {
#elif V3_HUD_DIRECT
static int update_gpu_target(gpu_device *gpu,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls,uint32_t target) {
#else
int hud_update_gpu_cache(gpu_device *gpu,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls) {
#endif
 if(!gpu || !gpu->ready || !m || !cache || !scratch || !polls) return GPU_DRIVER_ARGUMENT;
#if !V3_HUD_DIRECT
 const uint32_t target=HUD_CACHE_ADDR;
#endif
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS]={{0}};
 int e=hud_comparison_text(m,lines); if(e) return e;
 uint8_t show=(uint8_t)hud_logo_fits(lines);
 scratch->count=0;
 if(cache->valid && cache->logo_visible==show && !memcmp(cache->text,lines,sizeof lines)) {
 #if V3_HUD_LIST
  if(list) {
   cache->valid=0;e=render_hud_batch(list,scratch,dst,bank,epoch,polls);
   if(!e)cache->valid=1;
   return e;
  }
 #endif
  return 0;
 }
 _Static_assert(HUD_MAX_COMMANDS>=2u+HUD_COMPARISON_LINES*HUD_COMPARISON_COLUMNS,"HUD command capacity");
 _Static_assert(8u+HUD_COMPARISON_COLUMNS*HUD_GLYPH_WIDTH<=GPU_FRAME_WIDTH,"glyph line bounds");
 _Static_assert(HUD_COMPARISON_LINES*HUD_GLYPH_HEIGHT==HUD_CACHE_HEIGHT,"glyph row bounds");
 if(!cache->valid) scratch->commands[scratch->count++]=(gpu_command){
  .op=GPU_OP_FILL,.dst_addr=target,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=HUD_CACHE_HEIGHT};
 if(cache->valid && cache->logo_visible && !show) scratch->commands[scratch->count++]=(gpu_command){
  .op=GPU_OP_FILL,.dst_addr=target+HUD_LOGO_Y*GPU_FRAME_STRIDE+HUD_LOGO_X*2u,
  .dst_stride=GPU_FRAME_STRIDE,.width_pixels=HUD_LOGO_WIDTH,.height_pixels=HUD_LOGO_HEIGHT};
 for(unsigned line=0;line<HUD_COMPARISON_LINES;line++) for(unsigned n=0;n<HUD_COMPARISON_COLUMNS;n++) {
  unsigned char ch=(unsigned char)lines[line][n];
  if(cache->valid?ch==(unsigned char)cache->text[line][n]:!ch || ch==' ') continue;
  scratch->commands[scratch->count++]=(gpu_command){
   .op=GPU_OP_COPY,
   .src_addr=HUD_GLYPH_ATLAS_ADDR+(line==2?HUD_GLYPH_BANK_BYTES:0)+glyph_index(ch)*HUD_GLYPH_CELL_BYTES,
   .dst_addr=target+line*HUD_GLYPH_HEIGHT*GPU_FRAME_STRIDE+(8u+n*HUD_GLYPH_WIDTH)*2u,
   .src_stride=HUD_GLYPH_WIDTH*2u,.dst_stride=GPU_FRAME_STRIDE,
   .width_pixels=HUD_GLYPH_WIDTH,.height_pixels=HUD_GLYPH_HEIGHT};
 }
 /* Restore after clearing shortened text tails, which may touch this area. */
 if(show && (!cache->valid || !cache->logo_visible)) scratch->commands[scratch->count++]=(gpu_command){
  .op=GPU_OP_COPY,.src_addr=HUD_LOGO_ADDR,
  .dst_addr=target+HUD_LOGO_Y*GPU_FRAME_STRIDE+HUD_LOGO_X*2u,
  .src_stride=HUD_LOGO_WIDTH*2u,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=HUD_LOGO_WIDTH,.height_pixels=HUD_LOGO_HEIGHT};
 /* Partial DMA writes must never leave apparently valid old metadata. */
 cache->valid=0;
 #if V3_HUD_LIST
 if(list)e=render_hud_batch(list,scratch,dst,bank,epoch,polls);
 else
 #endif
 e=perf_render_gpu(gpu,scratch->commands,scratch->count,polls);
 if(e) return e;
 memcpy(cache->text,lines,sizeof lines); cache->logo_visible=show; cache->valid=1; ++cache->rebuilds;
 return 0;
}
#if V3_HUD_LIST
int hud_update_gpu_cache(gpu_device *gpu,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls) {
 return update_gpu_cache(gpu,m,cache,scratch,polls,0,0,0,0);
}
int hud_render_gpu_list(gpu_frame_list *list,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t dst,
 uint32_t bank,uint32_t epoch,uint32_t polls) {
 if(!list || !list->gpu || !list->present || !list->hud_ready ||
    (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B) ||
    (bank!=GPU_FRAME_LIST_BANK_A && bank!=GPU_FRAME_LIST_BANK_B))return GPU_DRIVER_ARGUMENT;
 if(list->active)return GPU_DRIVER_BUSY;
 return update_gpu_cache(list->gpu,m,cache,scratch,polls,list,dst,bank,epoch);
}
#endif
#if V3_HUD_DIRECT
int hud_update_gpu_cache(gpu_device *gpu,const hud_comparison *m,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t polls) {
 return update_gpu_target(gpu,m,cache,scratch,polls,HUD_CACHE_ADDR);
}
int hud_render_gpu_direct(gpu_device *gpu,const hud_comparison *m,
 hud_framebuffer_cache *cache,hud_command_stream *scratch,uint32_t dst,uint32_t polls) {
 if(!cache || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B))return GPU_DRIVER_ARGUMENT;
 return update_gpu_target(gpu,m,&cache->buffers[dst==GPU_FRAMEBUFFER_B],scratch,polls,dst);
}
#endif
