#include "gpu_stripes.h"
#include "benchmark.h"
#include <string.h>
static int range_overlap(const void *a,size_t na,const void *b,size_t nb) {
 uintptr_t x=(uintptr_t)a,y=(uintptr_t)b;
 return x<=y?y-x<na:x-y<nb;
}
int gpu_stripes_build(const gpu_instance_template *t,const gpu_instance *scene,
 unsigned count,uint32_t frame,gpu_instance *bins,unsigned capacity,gpu_stripe_plan *p) {
 if(!p)return GPU_DRIVER_ARGUMENT;
 memset(p,0,sizeof *p);
 if(!t || !scene || !bins || !count || count>GPU_FRAME_LIST_ARENA_ITEMS ||
  !capacity || capacity>GPU_STRIPE_BIN_ITEMS ||
  (frame!=GPU_FRAMEBUFFER_A && frame!=GPU_FRAMEBUFFER_B) ||
  range_overlap(scene,count*sizeof *scene,bins,capacity*sizeof *bins))return GPU_DRIVER_ARGUMENT;
 unsigned histogram[GPU_STRIPE_COUNT]={0};
 /* Pass1 validates every descriptor and computes exact capacity before writes. */
 for(unsigned i=0;i<count;i++) {
  gpu_command c;
  if(gpu_instance_expand(t,scene+i,0,&c))return GPU_DRIVER_ARGUMENT;
  if(!i) {
   if(c.op!=GPU_OP_COPY || scene[0].words[0] || c.dst_addr!=frame+72u*1920u ||
    c.src_addr!=t[0].src_base+72u*1920u || c.src_stride!=1920 || c.dst_stride!=1920 ||
    c.width_pixels!=960 || c.height_pixels!=468)return GPU_DRIVER_ARGUMENT;
   continue;
  }
  if((c.op!=GPU_OP_ALPHA && c.op!=GPU_OP_COLOR_KEY) || c.dst_stride!=1920 || c.dst_addr<frame)
   return GPU_DRIVER_ARGUMENT;
  uint32_t offset=c.dst_addr-frame;
  unsigned y=offset/1920u,x=(offset%1920u)/2u;
  if(y<72 || y>=540 || c.height_pixels>540u-y || c.width_pixels>960u-x)return GPU_DRIVER_ARGUMENT;
  unsigned first=(y-72u)/8u,last=(y+c.height_pixels-1u-72u)/8u;
  for(unsigned s=first;s<=last;s++)++histogram[s];
 }
 unsigned total=0;
 for(unsigned s=0;s<GPU_STRIPE_COUNT;s++) {p->offset[s]=total;total+=histogram[s];}
 if(total>capacity) {memset(p,0,sizeof *p);return GPU_DRIVER_FULL;}
 p->offset[GPU_STRIPE_COUNT]=total;
 /* Pass2: stable counting sort by Y strip. No strip-times-scene rescan. */
 for(unsigned s=0;s<GPU_STRIPE_COUNT;s++)histogram[s]=p->offset[s];
 for(unsigned i=1;i<count;i++) {
  const gpu_instance *v=scene+i;unsigned id=v->words[0]&255u;
  unsigned y=(v->words[1]-frame)/1920u,x=(v->words[1]-frame)%1920u;
  unsigned h=v->words[3]>>16,w=v->words[3]&65535u;
  unsigned first=(y-72u)/8u,last=(y+h-1u-72u)/8u;
  for(unsigned s=first;s<=last;s++) {
   unsigned top=72u+s*8u,lo=y>top?y:top,hi=y+h<top+8u?y+h:top+8u;
   bins[histogram[s]++]=(gpu_instance){{v->words[0],GPU_STRIPE_BASE+(lo-top)*1920u+x,
    v->words[2]+(lo-y)*t[id].src_stride,gpu_pack_size((uint16_t)w,(uint16_t)(hi-lo))}};
  }
 }
 p->count=total;return 0;
}
int gpu_stripes_supported(gpu_device *d) {
 if(!d || !d->ready)return 0;
#ifdef GPU_TEST_BACKEND
 extern uint32_t gpu_io_read(uintptr_t a);
 return (gpu_io_read(d->base+GPU_REG_STATUS)&GPU_STRIPE_CAPABILITY)!=0;
#else
 return (*(volatile uint32_t *)(d->base+GPU_REG_STATUS)&GPU_STRIPE_CAPABILITY)!=0;
#endif
}
static int transfer(gpu_device *d,uint32_t src,uint32_t dst,unsigned h,uint32_t polls) {
 gpu_command c={.op=GPU_OP_COPY,.src_addr=src,.dst_addr=dst,.src_stride=1920,
  .dst_stride=1920,.width_pixels=960,.height_pixels=(uint16_t)h};
 uint16_t tag;int e=gpu_submit(d,&c,polls,&tag);return e?e:gpu_wait_tag(d,tag,polls);
}
int gpu_stripes_render(gpu_frame_list *f,int network,uint32_t frame,const gpu_instance *scene,
 unsigned count,gpu_instance *bins,unsigned capacity,uint32_t epoch,uint32_t polls) {
 if(!f || !f->gpu || !f->present || f->active || !polls ||
  (network!=0 && network!=1) || !gpu_stripes_supported(f->gpu))return GPU_DRIVER_ARGUMENT;
 gpu_instance_template templates[16];gpu_stripe_plan p;
 gpu_instances_templates(network,templates);
 int e=gpu_stripes_build(templates,scene,count,frame,bins,capacity,&p);if(e)return e;
 gpu_platform_sync();
 for(unsigned s=0;s<GPU_STRIPE_COUNT;s++) {
  unsigned y=72u+s*8u,h=y+8u>540u?540u-y:8u;
  e=transfer(f->gpu,templates[0].src_base+y*1920u,GPU_STRIPE_BASE,h,polls);if(e)return e;
  unsigned start=p.offset[s],n=p.offset[s+1]-start;
  /* Reuse the already guarded two-bank list ABI, never extend its DDR whitelist. */
  while(n) {
   unsigned batch=n>GPU_FRAME_LIST_ARENA_ITEMS?GPU_FRAME_LIST_ARENA_ITEMS:n;
   memcpy((void *)(uintptr_t)GPU_FRAME_LIST_BANK_A,bins+start,batch*sizeof *bins);
   e=gpu_frame_list_render_span(f,GPU_FRAME_LIST_BANK_A,batch,epoch,polls);if(e)return e;
   start+=batch;n-=batch;
  }
  e=transfer(f->gpu,GPU_STRIPE_BASE,frame+y*1920u,h,polls);if(e)return e;
 }
 return 0;
}
