#ifndef EFINIX_LANE_SCENE_H
#define EFINIX_LANE_SCENE_H
#include "lane_game.h"
#include "gpu.h"
#define LANE_SCENE_MAX_COMMANDS (1u+LANE_MAX_PLANTS+LANE_MAX_ENEMIES+LANE_MAX_PROJECTILES)
typedef struct {
    gpu_command commands[LANE_SCENE_MAX_COMMANDS];
    uint16_t count, sprite_count;
} lane_scene;
int lane_scene_build(const lane_game_state *state,uint32_t destination,lane_scene *out);
#endif
