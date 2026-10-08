#ifndef GAME_MENU_H
#define GAME_MENU_H
#include "hud.h"
typedef struct {
 uint32_t destination[2],generation[2];
 uint8_t valid_mask,network[2];
} game_menu_cache;
void game_menu_invalidate(game_menu_cache *cache);
int game_menu_draw(gpu_device *gpu,game_menu_cache *cache,unsigned buffer_index,
 uint32_t destination,uint32_t generation,int network_ready,hud_command_stream *scratch,uint32_t poll_limit);
#endif
