#ifndef GPU_FRAME_LIST_H
#define GPU_FRAME_LIST_H
#include "gpu_instances.h"
#define GPU_FRAME_LIST_ID 0x464c5431u
#define GPU_FRAME_LIST_CAPABILITY (1u<<15)
#define GPU_FRAME_LIST_BANK_A 0x02d20000u
#define GPU_FRAME_LIST_BANK_B 0x02d24000u
typedef struct { gpu_device *gpu;uint8_t present,active; } gpu_frame_list;
int gpu_frame_list_init(gpu_frame_list *list,gpu_device *gpu,int network);
/* Single owner, immutable list/templates/assets through retirement. Uses
 * official cache sync before START. Failure poisons this owner: no replay or
 * reuse until coordinated GPU/system reset, never a local AXI-client reset. */
int gpu_frame_list_render(gpu_frame_list *list,uint32_t address,unsigned count,
 uint32_t epoch,uint32_t polls);
#endif
