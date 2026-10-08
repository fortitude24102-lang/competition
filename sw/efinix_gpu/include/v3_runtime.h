#ifndef V3_RUNTIME_H
#define V3_RUNTIME_H
#include "replay_input.h"
enum v3_mode { V3_MODE_LIVE, V3_MODE_CPU, V3_MODE_GPU };
enum { V3_PHASE_MENU=0,V3_PHASE_PLAY=1 };
enum { V3_MENU_BOOT=0,V3_MENU_DEATH=1,V3_MENU_REQUEST=2 };
/* Large objects are caller-owned DDR/BSS, never the Sapphire 4 KiB stack. */
typedef struct {
 bullet_state game, live_saved;
 replay_recording recording;
 replay_cursor cursor;
 game_clock clock;
 uint32_t epoch;
 uint16_t replay_frames;
 uint8_t mode,compare_pending;
 uint8_t phase,level,menu_reason,menu_enabled,await_neutral;
 uint32_t scene_generation,neutral_session,neutral_sequence;
} v3_runtime;
int v3_runtime_init(v3_runtime *,unsigned count,uint32_t seed,uint32_t epoch);
unsigned v3_level_count(unsigned level);
int v3_runtime_menu_init(v3_runtime *,uint32_t seed,uint32_t epoch);
int v3_runtime_game_command(v3_runtime *,unsigned opcode,unsigned level,uint32_t session,uint32_t sequence);
int v3_runtime_advance(v3_runtime *,const game_input *,uint32_t elapsed_us);
int v3_runtime_frame_done(v3_runtime *);
int v3_runtime_set_epoch(v3_runtime *,uint32_t epoch);
/* Measurement provenance shared by HUD and wire telemetry. */
uint32_t v3_runtime_status(const v3_runtime *,int network,int connected,
 int gpu_valid,int cpu_valid,int cpu_fresh);
#endif
