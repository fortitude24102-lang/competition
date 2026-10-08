#ifndef V3_DEMO_H
#define V3_DEMO_H
#include "framebuffer.h"
#include "bullet_demo.h"
#include "hud.h"
#include "v3_runtime.h"
int v3_apply_game_command(v3_runtime *,nc_device *,const nc_game_command *);
int v3_demo_run(gpu_device *,framebuffer_pair *,int network,
 bullet_stream *,hud_command_stream *,hud_raster_cache *);
#endif
