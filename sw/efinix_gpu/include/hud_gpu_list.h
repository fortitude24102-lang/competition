#ifndef HUD_GPU_LIST_H
#define HUD_GPU_LIST_H
#include "hud.h"
#include "gpu_frame_list.h"
/* Explicit V3_HUD_LIST candidate only. Slots0..11 retain the scene contract;
 * slots12..14 become glyph/finished HUD/logo Copy templates. Single owner. */
int hud_gpu_list_init(gpu_frame_list *list,int network);
/* Scene batch MUST already be retired before reusing its exact A/B bank.
 * Copies the complete 960x72 HUD to dst, including on unchanged text.
 * First rebuild/clear uses legacy Fill; partial list failure never replays.
 * Metadata commits only after all writes, including final HUD Copy, retire. */
int hud_render_gpu_list(gpu_frame_list *list,const hud_comparison *metrics,
 hud_raster_cache *cache,hud_command_stream *scratch,uint32_t destination,
 uint32_t bank,uint32_t epoch,uint32_t poll_limit);
#endif
