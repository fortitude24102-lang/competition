#ifndef EFINIX_REPLAY_INPUT_H
#define EFINIX_REPLAY_INPUT_H
#include "interactive_game.h"
#define REPLAY_INPUT_TICKS 600u
#define REPLAY_INPUT_VERSION 1u
typedef struct {
 bullet_state initial;
 uint16_t keys[REPLAY_INPUT_TICKS];
 uint32_t seed,resource_epoch,crc32;
 uint16_t count;
 uint8_t sealed;
} replay_recording;
typedef struct { uint16_t index,previous; uint8_t active; } replay_cursor;
int replay_init(replay_recording *record,const bullet_state *initial,uint32_t epoch);
int replay_record(replay_recording *record,const game_input *input);
int replay_seal(replay_recording *record);
int replay_begin(const replay_recording *record,uint32_t epoch,
                 bullet_state *state,replay_cursor *cursor);
/* 1 returns a tick, 0 is end of recording, negative is an error.
 * Action bits store per-tick events, not repeated held restart requests. */
int replay_next(const replay_recording *record,replay_cursor *cursor,game_input *input);
#endif
