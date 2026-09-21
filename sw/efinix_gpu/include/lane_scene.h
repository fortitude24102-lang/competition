#ifndef LANE_SCENE_H
#define LANE_SCENE_H
#include "lane_game.h"
#include "gpu.h"
#define LANE_SCENE_MAX_COMMANDS 128
typedef struct { gpu_command commands[LANE_SCENE_MAX_COMMANDS]; uint16_t count; uint32_t crc; } lane_scene;
int lane_scene_build(const lane_game_state *state, uint32_t destination, lane_scene *out);
#endif
