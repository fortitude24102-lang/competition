/* Real planner output expanded into the unchanged pixel oracle, not a second planner. */
#include "gpu_stripes.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static gpu_instance_template templates[16];
static gpu_instance input[6],bins[32];
static uint16_t original[960*540],striped[960*540],scratch[960*8],asset[16*16];
static void draw(uint16_t *pixels,unsigned height,const gpu_command *c,uint32_t base) {
 unsigned off=(c->dst_addr-base)/2u;
 golden_surface dst={(uint8_t *)pixels,960u*height*2u,960,(uint16_t)height,1920};
 golden_surface src={(uint8_t *)asset,sizeof asset,16,16,32};
 unsigned so=(c->src_addr-0x02400000u)/2u;
 assert((c->op==GPU_OP_ALPHA?golden_alpha_blend(&dst,off%960,off/960,&src,so%16,so/16,
  c->width_pixels,c->height_pixels,c->alpha):golden_color_key(&dst,off%960,off/960,&src,so%16,so/16,
  c->width_pixels,c->height_pixels,c->color_key))==GPU_ERROR_NONE);
}
int main(void) {
 templates[0]=(gpu_instance_template){GPU_OP_COPY,0x02600000,1920,1920,960,540,0};
 templates[1]=(gpu_instance_template){GPU_OP_ALPHA,0x02400000,32,1920,16,16,0xbeef};
 templates[2]=(gpu_instance_template){GPU_OP_COLOR_KEY,0x02400000,32,1920,16,16,0xbeef};
 input[0]=(gpu_instance){{0,GPU_FRAMEBUFFER_B+72*1920,72*1920,468u<<16|960u}};
 unsigned ys[]={72,79,80,529,536};
 for(unsigned i=1;i<6;i++)input[i]=(gpu_instance){{(i&1?0x800101u:2u),
  GPU_FRAMEBUFFER_B+ys[i-1]*1920+202,0,(i==5?4u:8u)<<16|8u}};
 for(unsigned i=0;i<256;i++)asset[i]=(uint16_t)(i%3?i*251u:0xbeef);
 for(unsigned i=0;i<960*540;i++)original[i]=striped[i]=(uint16_t)(i*3u);
 gpu_stripe_plan plan;
 assert(!gpu_stripes_build(templates,input,6,GPU_FRAMEBUFFER_B,bins,32,&plan));
 assert(plan.count>5 && plan.offset[GPU_STRIPE_COUNT]==plan.count);
 for(unsigned i=1;i<6;i++) {gpu_command c;assert(!gpu_instance_expand(templates,input+i,0,&c));draw(original,540,&c,GPU_FRAMEBUFFER_B);}
 for(unsigned s=0;s<GPU_STRIPE_COUNT;s++) {
  unsigned y=72+s*8,h=y+8>540?540-y:8;
  memcpy(scratch,striped+y*960,h*1920);
  for(unsigned i=plan.offset[s];i<plan.offset[s+1];i++) {
   gpu_command c;assert(!gpu_instance_expand(templates,bins+i,0,&c));
   assert(c.dst_addr>=GPU_STRIPE_BASE && c.dst_addr+(c.height_pixels-1u)*1920+c.width_pixels*2u<=GPU_STRIPE_BASE+h*1920);
   draw(scratch,h,&c,GPU_STRIPE_BASE);
  }
  memcpy(striped+y*960,scratch,h*1920);
 }
 assert(!memcmp(original,striped,sizeof original));
 gpu_instance saved[32];memset(bins,0xa5,sizeof bins);memcpy(saved,bins,sizeof bins);
 assert(gpu_stripes_build(templates,input,6,GPU_FRAMEBUFFER_B,bins,1,&plan)==GPU_DRIVER_FULL);
 assert(!memcmp(saved,bins,sizeof bins) && !plan.count);
 input[5].words[2]=0xfffffffeu;
 assert(gpu_stripes_build(templates,input,6,GPU_FRAMEBUFFER_B,bins,32,&plan)==GPU_DRIVER_ARGUMENT);
 assert(!memcmp(saved,bins,sizeof bins) && !plan.count);
 input[5].words[2]=0; input[5].words[1]=GPU_FRAMEBUFFER_B+71*1920;
 assert(gpu_stripes_build(templates,input,6,GPU_FRAMEBUFFER_B,bins,32,&plan)==GPU_DRIVER_ARGUMENT);
 assert(!memcmp(saved,bins,sizeof bins));
 puts("STRIPES,PASS,stable_order,alpha_key_pixels,cropped_source_stride,last4,halfword,preflight,capacity_canary");
}
