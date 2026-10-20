#ifndef PERFORMANCE_CHALLENGE_H
#define PERFORMANCE_CHALLENGE_H
#include "gpu_instances.h"
#include "gpu_frame_list.h"
#include "interactive_game.h"
#include "v3_frame_stats.h"
#define PC_MAX_SPRITES V3_PERFORMANCE_MAX_SPRITES
#define PC_STATE_ADDRESS 0x02d30000u
#define PC_WARM_FRAMES 60u
#define PC_SEARCH_FRAMES 600u
#define PC_VERIFY_FRAMES 3600u
enum {PC_WARM=1,PC_SAMPLE,PC_VERIFY,PC_DONE,PC_CAPACITY,PC_FAILED};
typedef struct {int16_t x,y;int8_t dx,dy;uint8_t shape,pad;} pc_sprite;
typedef struct {
 pc_sprite sprites[PC_MAX_SPRITES];
 v3_frame_stats stats;
 uint32_t seed,tick,generation;
 unsigned target,maximum,low,high,best,warm,stage;
 uint8_t growing,confirming;
} pc_state;
_Static_assert(PC_STATE_ADDRESS+sizeof(pc_state)<=0x02d40000u,"performance DDR bound");
_Static_assert(PC_STATE_ADDRESS>=GPU_FRAME_LIST_BANK_A+GPU_FRAME_LIST_ARENA_ITEMS*16u,"performance state/list overlap");
_Static_assert(1u+PC_MAX_SPRITES+(PC_MAX_SPRITES+7u)/8u==GPU_FRAME_LIST_ARENA_ITEMS,"four descriptor bank capacity");
int pc_init(pc_state *,unsigned maximum,uint32_t seed);
int pc_advance(pc_state *,const game_input *);
/* Reject insufficient capacity before writing any descriptor. */
int pc_build(const pc_state *,uint32_t dst,int network,gpu_instance *,unsigned capacity,gpu_instance_stats *);
int pc_record(pc_state *,uint32_t hz,uint32_t work,uint32_t wall,
 uint32_t under,uint32_t errors,unsigned visible,unsigned alpha);
#endif
