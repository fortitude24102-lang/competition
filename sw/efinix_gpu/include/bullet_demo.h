#ifndef EFINIX_BULLET_DEMO_H
#define EFINIX_BULLET_DEMO_H
#include "gpu.h"
#define BULLET_MAX_OBJECTS 512u
#define BULLET_MAX_TRAILS (BULLET_MAX_OBJECTS/8u)
#define BULLET_MAX_COMMANDS (BULLET_MAX_OBJECTS+8u+BULLET_MAX_TRAILS+1u)
#define BULLET_START_HP 3u
#define BULLET_PROTECTION_TICKS 60u
#define BULLET_RESTART_TICKS 120u
#define BULLET_BACKGROUND_ADDR 0x02900000u
#define BULLET_ATLAS_ADDR 0x02a00000u
#define BULLET_LOCAL_BACKGROUND 0x02b00000u
#define BULLET_LOCAL_ATLAS 0x02c00000u
#define BULLET_SHAPE_COUNT 6u
#define BULLET_PLAYER_OFFSET (BULLET_SHAPE_COUNT*128u)
#define BULLET_GLOW_OFFSET (BULLET_PLAYER_OFFSET+512u)
#define BULLET_EMITTER_OFFSET (BULLET_GLOW_OFFSET+288u)
#define BULLET_ATLAS_BYTES (BULLET_EMITTER_OFFSET+3u*512u)
#define BULLET_COLOR_KEY 0xf81fu
#define BULLET_REPLAY_FRAMES 600u
_Static_assert(BULLET_BACKGROUND_ADDR+GPU_FRAME_BYTES<=BULLET_ATLAS_ADDR,"network asset separation");
_Static_assert(BULLET_ATLAS_ADDR+BULLET_ATLAS_BYTES<=BULLET_LOCAL_BACKGROUND,"fallback cannot overlap DMA");
_Static_assert(BULLET_LOCAL_BACKGROUND+GPU_FRAME_BYTES<=BULLET_LOCAL_ATLAS,"local asset separation");
_Static_assert(BULLET_LOCAL_ATLAS+BULLET_ATLAS_BYTES<=GPU_DDR_END_EXCLUSIVE,"asset DDR bounds");
typedef struct { int32_t x,y; int16_t vx,vy; uint16_t age; uint8_t kind,shape,grazed; } bullet_object;
typedef struct {
 bullet_object objects[BULLET_MAX_OBJECTS];
 uint32_t seed,tick; unsigned count;
 int player_x,player_y; /* Deterministic auto-pilot; physical input remains deferred. */
 uint32_t round_tick,score,grazes;
 uint16_t invulnerable,game_over_ticks;
 uint8_t hp;
} bullet_state;
typedef struct {
 gpu_command commands[BULLET_MAX_COMMANDS];
 unsigned count,visible; uint32_t scene_pixels;
 unsigned alpha_commands; uint32_t alpha_pixels;
} bullet_stream;
int bullet_reset(bullet_state *state,unsigned count,uint32_t seed);
/* Analytic atlas mask for clipped visibility; zero for invalid shape/texel. */
int bullet_shape_opaque(unsigned shape,unsigned x,unsigned y);
int bullet_step(bullet_state *state);
int bullet_build_frame(const bullet_state *state,uint32_t dst,int network,int glow,
                      unsigned capacity,bullet_stream *stream);
int bullet_prepare_frame(bullet_state *state,unsigned count,unsigned frame,uint32_t seed);
int bullet_finish_window(bullet_state *state,bullet_state *start,int gpu_window);
void bullet_init_local_assets(void);
int bullet_load_network_assets(uintptr_t base,uint32_t session);
/* Failure regenerates disjoint local assets, even if a DMA abort is unfinished. */
int bullet_prepare_assets(uintptr_t base,uint32_t session);
#endif
