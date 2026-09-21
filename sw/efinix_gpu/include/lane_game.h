#ifndef LANE_GAME_H
#define LANE_GAME_H
#include <stdint.h>
#define LANE_ROWS 5
#define LANE_COLS 9
#define LANE_MAX_PLANTS 32
#define LANE_MAX_ENEMIES 32
#define LANE_MAX_PROJECTILES 64
typedef enum { LANE_PAUSED=0, LANE_PLAYING=1, LANE_WON=2, LANE_LOST=3 } lane_phase;
typedef struct { uint8_t row,col,hp,active; uint16_t cooldown; } lane_plant;
typedef struct { uint8_t row,active; int32_t x16; uint16_t hp,speed16; } lane_enemy;
typedef struct { uint8_t row,active; int32_t x16; uint16_t damage,speed16; } lane_projectile;
typedef struct { uint32_t tick,score,coins,wave; uint8_t selected,spawned; lane_phase phase; lane_plant plants[LANE_MAX_PLANTS]; lane_enemy enemies[LANE_MAX_ENEMIES]; lane_projectile projectiles[LANE_MAX_PROJECTILES]; } lane_game_state;
void lane_game_init(lane_game_state *s, uint32_t seed);
void lane_game_step(lane_game_state *s, uint32_t input_mask);
int lane_game_plant(lane_game_state *s, uint8_t row, uint8_t col);
int lane_game_fire(lane_game_state *s, uint8_t row);
uint32_t lane_game_crc(const lane_game_state *s);
#define LANE_INPUT_PAUSE 1u
#define LANE_INPUT_PLANT 2u
#define LANE_INPUT_FIRE 4u
#endif
