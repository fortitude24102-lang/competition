/* Breaks caught: compact builder changes clipping/order/Alpha or loses R7
 * fields; overflow/partial output is admitted as a usable frame. */
#include "gpu_instances.h"
#include <assert.h>
#include <stdio.h>
static bullet_state state;
static bullet_stream reference;
static gpu_instance_stream compact;
static gpu_instance_template templates[16];
static void same(const gpu_command *a,const gpu_command *b) {
 assert(a->op==b->op && a->src_addr==b->src_addr && a->dst_addr==b->dst_addr);
 assert(a->src_stride==b->src_stride && a->dst_stride==b->dst_stride);
 assert(a->width_pixels==b->width_pixels && a->height_pixels==b->height_pixels);
 assert(a->color==b->color && a->color_key==b->color_key && a->alpha==b->alpha && a->flags==b->flags);
}
int main(void) {
 assert(!bullet_reset(&state,512,7));
 assert(!gpu_instances_build(&state,GPU_FRAMEBUFFER_B,1,1,72,BULLET_MAX_COMMANDS,&compact));
 unsigned frames=0;
 for(unsigned network=0;network<2;network++) for(unsigned glow=0;glow<2;glow++) {
  assert(gpu_instances_templates(network,templates)==12);
  for(unsigned tier=32;tier<=512;tier*=2) {
   assert(!bullet_reset(&state,tier,7));
   for(unsigned tick=0;tick<600;tick++) {
    uint32_t dst=tick&1?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
    assert(!bullet_build_frame(&state,dst,network,glow,BULLET_MAX_COMMANDS,&reference));
    assert(!bullet_clip_background_for_hud(&reference,72));
    assert(!gpu_instances_build(&state,dst,network,glow,72,BULLET_MAX_COMMANDS,&compact));
    assert(reference.count==compact.count && reference.visible==compact.visible);
    assert(reference.scene_pixels==compact.scene_pixels && reference.alpha_commands==compact.alpha_commands);
    assert(reference.alpha_pixels==compact.alpha_pixels);
    for(unsigned i=0;i<compact.count;i++) {
     gpu_command command;
     assert(!gpu_instance_expand(templates,compact.items+i,(uint16_t)(65530u+i),&command));
     same(&reference.commands[i],&command); assert(command.tag==(uint16_t)(65530u+i));
    }
    assert(!bullet_step(&state)); ++frames;
   }
  }
 }
 /* Literal clip:8x8 shape0 at(-2,70) becomes src offset36,6x6 at(0,72). */
 assert(!bullet_reset(&state,1,7)); state.objects[0].x=-512;state.objects[0].y=70*256;
 state.objects[0].shape=0;
 assert(!gpu_instances_build(&state,GPU_FRAMEBUFFER_A,1,0,72,BULLET_MAX_COMMANDS,&compact));
 assert(compact.items[1].words[0]==2 && compact.items[1].words[1]==GPU_FRAMEBUFFER_A+72*1920);
 assert(compact.items[1].words[2]==36 && compact.items[1].words[3]==0x00060006);
 assert(gpu_instances_build(&state,GPU_FRAMEBUFFER_A,1,1,72,1,&compact)==GPU_DRIVER_FULL && !compact.count);
 assert(gpu_instances_build(&state,GPU_FRAMEBUFFER_A,1,1,540,10,&compact)==GPU_DRIVER_ARGUMENT && !compact.count);
 assert(gpu_instances_templates(1,templates)==12);
 gpu_instance bad={{2,GPU_FRAMEBUFFER_A,0xfffffffeu,0x00010001u}}; gpu_command command;
 assert(gpu_instance_expand(templates,&bad,1,&command)!=0);
 bad=(gpu_instance){{2,GPU_FRAMEBUFFER_A,0,0x00010009u}}; /* maxwidth8 */
 assert(gpu_instance_expand(templates,&bad,1,&command)!=0);
 bad=(gpu_instance){{0x01000002,GPU_FRAMEBUFFER_A,0,0x00010001u}};
 assert(gpu_instance_expand(templates,&bad,1,&command)!=0);
 bad=(gpu_instance){{16,GPU_FRAMEBUFFER_A,0,0x00010001u}};
 assert(gpu_instance_expand(templates,&bad,1,&command)!=0);
 printf("INSTANCE_BUILD,PASS,frames=%u,field_equivalence,clip,capacity,overflow,header,tagwrap\n",frames);
 return 0;
}
