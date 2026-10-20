#ifndef GPU_FRAME_LIST_H
#define GPU_FRAME_LIST_H
#include "gpu_instances.h"
#define GPU_FRAME_LIST_ID 0x464c5431u
#define GPU_FRAME_LIST_CAPABILITY (1u<<15)
#define GPU_FRAME_LIST_BANK_A 0x02d20000u
#define GPU_FRAME_LIST_BANK_B 0x02d24000u
#define GPU_FRAME_LIST_BANK_ITEMS 1024u
#define GPU_FRAME_LIST_LEGACY_ITEMS (2u*GPU_FRAME_LIST_BANK_ITEMS)
#define GPU_FRAME_LIST_ARENA_ITEMS (4u*GPU_FRAME_LIST_BANK_ITEMS)
#define GPU_FRAME_LIST_EXTENDED_CAPABILITY (1u<<20)
typedef struct { gpu_device *gpu;uint16_t arena_items;uint8_t present,active;
#if defined(V3_HUD_LIST) && V3_HUD_LIST
 uint8_t hud_ready; /* Compile every translation unit with the same setting. */
#endif
} gpu_frame_list;
int gpu_frame_list_init(gpu_frame_list *list,gpu_device *gpu,int network);
/* Single owner, immutable list/templates/assets through retirement. Uses
 * official cache sync before START. Failure poisons this owner: no replay or
 * reuse until coordinated GPU/system reset, never a local AXI-client reset. */
int gpu_frame_list_render(gpu_frame_list *list,uint32_t address,unsigned count,
 uint32_t epoch,uint32_t polls);
/* Own the actual arena through retirement. Validate the whole range before any
 * START; preserve order across bank boundaries. Never replay after failure. */
int gpu_frame_list_render_span(gpu_frame_list *list,uint32_t address,unsigned count,
 uint32_t epoch,uint32_t polls);
#endif
