#ifndef V3_DEMO_H
#define V3_DEMO_H
#include "framebuffer.h"
#include "bullet_demo.h"
#include "hud.h"
#include "v3_runtime.h"
#include "gpu_instances.h"
/* GPU-only scene dispatch. WIN uses existing Fill commands; CPU unchanged. */
int v3_build_gpu_scene(const bullet_state *,uint32_t,int,int,gpu_instance *,bullet_stream *,int *);
int v3_apply_game_command(v3_runtime *,nc_device *,const nc_game_command *);
int v3_demo_run(gpu_device *,framebuffer_pair *,int network,
 bullet_stream *,hud_command_stream *,hud_raster_cache *);
#endif
