#ifndef EFINIX_GPU_GAME_H
#define EFINIX_GPU_GAME_H
#include "gpu_regs.h"
#define GAME_MAX_BULLETS 32u
#define GAME_MAX_ENEMIES 16u
#define GAME_INPUT_LEFT 1u
#define GAME_INPUT_RIGHT 2u
#define GAME_INPUT_FIRE 4u
typedef struct { int16_t x,y,vx,vy; uint8_t width,height,active; } game_object;
typedef struct {
 game_object player,bullets[GAME_MAX_BULLETS],enemies[GAME_MAX_ENEMIES];
 uint16_t bullet_count,enemy_count;
 uint32_t tick;
} game_state;
void game_init(game_state *game);
void game_step(game_state *game,unsigned input,uint32_t delta_ms);
#endif
