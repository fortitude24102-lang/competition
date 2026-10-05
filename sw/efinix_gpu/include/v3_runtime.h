#ifndef V3_RUNTIME_H
#define V3_RUNTIME_H
#include "replay_input.h"
enum v3_mode { V3_MODE_LIVE, V3_MODE_CPU, V3_MODE_GPU };
/* Large objects are caller-owned DDR/BSS, never the Sapphire 4 KiB stack. */
typedef struct {
 bullet_state game, live_saved;
 replay_recording recording;
 replay_cursor cursor;
 game_clock clock;
 uint32_t epoch;
 uint16_t replay_frames;
 uint8_t mode,compare_pending;
} v3_runtime;
int v3_runtime_init(v3_runtime *,unsigned count,uint32_t seed,uint32_t epoch);
int v3_runtime_advance(v3_runtime *,const game_input *,uint32_t elapsed_us);
int v3_runtime_frame_done(v3_runtime *);
int v3_runtime_set_epoch(v3_runtime *,uint32_t epoch);
/* Measurement provenance shared by HUD and wire telemetry. */
uint32_t v3_runtime_status(const v3_runtime *,int network,int connected,
 int gpu_valid,int cpu_valid,int cpu_fresh);
#endif
