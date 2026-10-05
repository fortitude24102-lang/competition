#ifndef EFINIX_INTERACTIVE_GAME_H
#define EFINIX_INTERACTIVE_GAME_H
#include "bullet_demo.h"
#include "input_state.h"
#define GAME_SHOT_SLOTS 8u
#define GAME_MAX_CATCHUP 4u
typedef struct {
 uint32_t accumulator_x60, total_steps, discarded_wall_us;
 uint16_t pending_pressed,pending_released;
 uint8_t slow, compare_requested;
} game_clock;
int game_reset(bullet_state *state,unsigned count,uint32_t seed);
/* One 1/60-second tick. 1 requests comparison; 0 ordinary update; <0 error.
 * Only pressed action bits trigger restart/comparison. */
int game_update(bullet_state *state,const game_input *input);
int game_build(const bullet_state *state,uint32_t dst,int network,int glow,
               unsigned capacity,bullet_stream *stream);
/* Bounded catch-up: never skips logical ticks; excess wall time is reported.
 * A zero-initialized clock is ready. At most four ticks per call. */
int game_advance(game_clock *clock,bullet_state *state,const game_input *input,
                 uint32_t elapsed_us);
#endif
