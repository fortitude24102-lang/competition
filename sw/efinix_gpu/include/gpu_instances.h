#ifndef GPU_INSTANCES_H
#define GPU_INSTANCES_H
#include "bullet_demo.h"
#define GPU_INSTANCE_ID 0x494e5331u
#define GPU_INSTANCE_BASE 0x0400u
#define GPU_INSTANCE_CAPABILITY (1u<<14)
#define GPU_INSTANCE_TEMPLATES 16u
typedef struct { uint32_t words[4]; } gpu_instance;
typedef struct { uint32_t op,src_base,src_stride,dst_stride,width_max,height_max,key; } gpu_instance_template;
_Static_assert(sizeof(gpu_instance)==16,"compact APB descriptor");
typedef struct {
 unsigned count,visible,alpha_commands;
 uint32_t scene_pixels,alpha_pixels;
} gpu_instance_stats;
typedef struct {
 gpu_instance items[BULLET_MAX_COMMANDS];
 unsigned count,visible,alpha_commands;
 uint32_t scene_pixels,alpha_pixels;
} gpu_instance_stream;
typedef struct { gpu_device *gpu; uint8_t present,active; } gpu_instances;
unsigned gpu_instances_templates(int network,gpu_instance_template templates[GPU_INSTANCE_TEMPLATES]);
int gpu_instance_expand(const gpu_instance_template *templates,const gpu_instance *instance,uint16_t tag,gpu_command *command);
int gpu_instances_build(const bullet_state *state,uint32_t dst,int network,int glow,
 unsigned hud_height,unsigned capacity,gpu_instance_stream *out);
/* items has capacity writable slots; state/items/stats must be disjoint.
 * Writes directly to the caller's buffer (which may be private DDR).
 * On any failure stats is zero: do not publish a partially written list.
 * manual=0 retains R7 rejection of kind3; manual=1 handles friendly slots. */
int gpu_instances_build_into(const bullet_state *state,uint32_t dst,int network,int glow,
 int manual,unsigned hud_height,unsigned capacity,gpu_instance *items,gpu_instance_stats *stats);
int gpu_instances_init(gpu_instances *instances,gpu_device *gpu);
int gpu_instances_program(gpu_instances *instances,const gpu_instance_template *templates,unsigned count);
int gpu_instances_render(gpu_instances *instances,const gpu_instance_template *templates,
 const gpu_instance_stream *stream,uint32_t polls);
#endif
