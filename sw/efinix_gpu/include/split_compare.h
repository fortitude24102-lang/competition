#ifndef SPLIT_COMPARE_H
#define SPLIT_COMPARE_H
#include "interactive_game.h"
#include "framebuffer.h"
#include "hud.h"
#include "split_view.h"
#define SPLIT_CPU_SURFACE 0x03000000u
#define SPLIT_GPU_SURFACE 0x03200000u
#define SPLIT_STATE_ADDRESS 0x03400000u
#define SPLIT_WINDOW_SECONDS 15u
typedef struct {
 bullet_state game,initial;game_clock clock;bullet_stream cpu_scene;
 uint64_t start,last_logic,elapsed_ticks[2],cpu_ticks[2],gpu_ticks[2],cpu_job_ticks,ready_ticks;
 uint64_t logic_ticks[2],build_ticks[2],copy_ticks[2];
 unsigned cpu_frames[2],gpu_frames[2],cpu_command,cpu_row,tier;
 uint32_t cpu_front,cpu_back,hud_epoch[2],cpu_generation,copied_generation[2];
 char hud_text[2][10][64];
 uint8_t done,prepared,started,cpu_ready,cpu_active,completed[2],cleared[2],stage;
} split_compare_state;
_Static_assert(SPLIT_CPU_SURFACE+GPU_FRAME_BYTES<=SPLIT_GPU_SURFACE,"split surfaces overlap");
_Static_assert(SPLIT_GPU_SURFACE+GPU_FRAME_BYTES<=SPLIT_STATE_ADDRESS,"split state overlap");
_Static_assert(SPLIT_STATE_ADDRESS+sizeof(split_compare_state)<=SPLIT_BACKGROUND,"split state/assets overlap");
int split_compare_init(split_compare_state *);
/* One independently presented GPU frame. CPU rasterization progresses while
 * GPU/PRESENT is pending; only newly displayed CPU frames are counted. */
int split_compare_step(split_compare_state *,gpu_device *,framebuffer_pair *,int network,
 bullet_stream *,hud_command_stream *,uint32_t hz,uint32_t polls,int (*service)(void *),void *context);
#endif
