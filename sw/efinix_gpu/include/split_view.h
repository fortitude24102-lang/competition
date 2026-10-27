#ifndef SPLIT_VIEW_H
#define SPLIT_VIEW_H
#include "bullet_demo.h"
#include "gpu_instances.h"
#define SPLIT_BACKGROUND 0x03600000u
#define SPLIT_ATLAS 0x03700000u
#define SPLIT_INSTANCES 0x03800000u
#define SPLIT_VIEW_WIDTH 480u
#define SPLIT_VIEW_HEIGHT 270u
int split_view_prepare(int network,int (*service)(void *),void *context);
/* Exact nearest-neighbor half-size view, including clipped/odd-origin layers.
 * Identical converted commands/assets are used by both renderers. */
int split_view_build(const bullet_state *,int network,uint32_t destination,bullet_stream *);
#endif
