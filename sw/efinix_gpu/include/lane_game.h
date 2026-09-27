#ifndef EFINIX_LANE_GAME_H
#define EFINIX_LANE_GAME_H
#include <stdint.h>
#define LANE_ROWS 5u
#define LANE_COLS 9u
#define LANE_MAX_PLANTS 32u
#define LANE_MAX_ENEMIES 32u
#define LANE_MAX_PROJECTILES 64u
#define LANE_INPUT_NEXT_ROW 1u
#define LANE_INPUT_NEXT_COL 2u
#define LANE_INPUT_PLANT 4u
#define LANE_INPUT_PAUSE 8u
typedef enum { LANE_PAUSED=0, LANE_PLAYING=1, LANE_WON=2, LANE_LOST=3 } lane_phase;
typedef struct { uint8_t row,col,hp,active; uint16_t cooldown; } lane_plant;
typedef struct { uint8_t row,active; int32_t x16; uint16_t hp,speed16; } lane_enemy;
typedef struct { uint8_t row,active; int32_t x16; uint16_t damage; uint32_t speed16; } lane_projectile;
typedef struct {
    uint32_t tick,score,coins,wave,rng,spawned_in_wave,previous_input;
    uint8_t selected_row,selected_col;
    lane_phase phase;
    lane_plant plants[LANE_MAX_PLANTS];
    lane_enemy enemies[LANE_MAX_ENEMIES];
    lane_projectile projectiles[LANE_MAX_PROJECTILES];
} lane_game_state;
void lane_game_init(lane_game_state *state,uint32_t seed);
void lane_game_step(lane_game_state *state,uint32_t input_mask);
int lane_game_plant(lane_game_state *state,uint8_t row,uint8_t col);
uint32_t lane_game_crc(const lane_game_state *state);
#endif
