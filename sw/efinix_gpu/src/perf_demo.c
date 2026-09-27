#include "perf_demo.h"
#include "asset_catalog.h"
#include "assets.h"
#include <limits.h>

void perf_init_local_assets(void) {
 /* Expand the existing player art to the same 64x80 footprint as network art. */
 volatile uint16_t *key=(volatile uint16_t *)(uintptr_t)PERF_LOCAL_SPRITE;
 volatile uint16_t *alpha=(volatile uint16_t *)(uintptr_t)PERF_LOCAL_ALPHA;
 for(unsigned y=0;y<80;y++) for(unsigned x=0;x<64;x++) {
  uint16_t p=gpu_player_asset.pixels[(y/10)*8+x/8];
  key[y*64+x]=p?p:ASSET_COLOR_KEY;
  alpha[y*64+x]=(uint16_t)(0x001fu | ((x/2u)<<11));
 }
}

int perf_build_frame(uint32_t dst,unsigned sprites,unsigned frame,int network,perf_stream *s) {
 if(!s || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B) ||
    sprites<4 || sprites>PERF_MAX_SPRITES) return GPU_DRIVER_ARGUMENT;
 s->count=0;
 s->commands[s->count++]=(gpu_command){.op=network?GPU_OP_COPY:GPU_OP_FILL,
  .src_addr=ASSET_SCENE_ADDR,.src_stride=GPU_FRAME_STRIDE,
  .dst_addr=dst,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=GPU_FRAME_WIDTH,
  .height_pixels=GPU_FRAME_HEIGHT,.color=0x18e3};
 for(unsigned i=0;i<sprites;i++) {
  unsigned x=(i*137u+(frame%897u)*5u)%897u;
  unsigned y=76u+(i*73u+(frame%385u)*3u)%385u;
  int alpha=(i%4u)==3u;
  uint32_t src=PERF_LOCAL_SPRITE;
  if(network) src=i%3u==0?ASSET_FLOWER_ADDR:
   ((frame/8u)&1u)?ASSET_ZOMBIE_WALK2_ADDR:ASSET_ZOMBIE_WALK1_ADDR;
  s->commands[s->count++]=(gpu_command){.op=alpha?GPU_OP_ALPHA:GPU_OP_COLOR_KEY,
   .src_addr=alpha?PERF_LOCAL_ALPHA:src,.dst_addr=dst+y*GPU_FRAME_STRIDE+x*2u,
   .src_stride=128,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=64,.height_pixels=80,
   .color_key=ASSET_COLOR_KEY,.alpha=112};
 }
 return 0;
}

int perf_render_cpu(const gpu_command *commands,unsigned count) {
 if(!commands || !count) return GPU_DRIVER_ARGUMENT;
 for(unsigned i=0;i<count;i++) {
  const gpu_command *c=&commands[i];
  uint32_t base=c->dst_addr>=GPU_FRAMEBUFFER_B?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
  if(c->dst_addr<base || c->dst_addr-base>=GPU_FRAME_BYTES ||
     c->dst_stride!=GPU_FRAME_STRIDE || (c->dst_addr&1u)) return GPU_DRIVER_ARGUMENT;
  unsigned offset=c->dst_addr-base;
  golden_surface dst={(uint8_t *)(uintptr_t)base,GPU_FRAME_BYTES,
   GPU_FRAME_WIDTH,GPU_FRAME_HEIGHT,GPU_FRAME_STRIDE};
  uint16_t x=(uint16_t)((offset%GPU_FRAME_STRIDE)/2),y=(uint16_t)(offset/GPU_FRAME_STRIDE);
  uint64_t bytes=c->height_pixels?(uint64_t)(c->height_pixels-1)*c->src_stride+c->width_pixels*2u:0;
  golden_surface src={(uint8_t *)(uintptr_t)c->src_addr,(size_t)bytes,
   c->width_pixels,c->height_pixels,c->src_stride};
  int e;
  if(c->op!=GPU_OP_FILL && (c->src_addr<GPU_DENSE_ASSETS ||
      (uint64_t)c->src_addr+bytes>GPU_DDR_END_EXCLUSIVE)) return GPU_DRIVER_ARGUMENT;
  switch(c->op) {
  case GPU_OP_FILL: e=golden_fill(&dst,x,y,c->width_pixels,c->height_pixels,c->color); break;
  case GPU_OP_COPY: e=golden_copy(&dst,x,y,&src,0,0,c->width_pixels,c->height_pixels); break;
  case GPU_OP_COLOR_KEY: e=golden_color_key(&dst,x,y,&src,0,0,c->width_pixels,c->height_pixels,c->color_key); break;
  case GPU_OP_ALPHA: e=golden_alpha_blend(&dst,x,y,&src,0,0,c->width_pixels,c->height_pixels,c->alpha); break;
  default: return GPU_DRIVER_ARGUMENT;
  }
  if(e) return e;
 }
 return 0;
}

int perf_render_gpu(gpu_device *d,const gpu_command *commands,unsigned count,uint32_t polls) {
 if(!d || !commands || !count) return GPU_DRIVER_ARGUMENT;
 uint16_t tag=0;
 for(unsigned i=0;i<count;i++) {
  int e=gpu_submit(d,&commands[i],polls,&tag); if(e) return e;
 }
 return gpu_wait_tag(d,tag,polls);
}

int perf_window_add(perf_window *w,uint64_t wall,uint64_t render) {
 if(!w || !wall || render>wall || w->frames>=PERF_WINDOW_FRAMES ||
    UINT64_MAX-w->wall_ticks<wall || UINT64_MAX-w->render_ticks<render)
  return GPU_DRIVER_ARGUMENT;
 w->wall_ticks+=wall; w->render_ticks+=render; ++w->frames; return 0;
}
uint32_t perf_fps_x10(const perf_window *w,uint32_t hz) {
 if(!w || !w->wall_ticks || !w->frames || w->frames>PERF_WINDOW_FRAMES || !hz) return 0;
 uint64_t n=(uint64_t)w->frames*hz*10u/w->wall_ticks;
 return n>=UINT32_MAX?UINT32_MAX:(uint32_t)n;
}
uint32_t perf_render_us(const perf_window *w,uint32_t hz) {
 if(!w || !w->frames || w->frames>PERF_WINDOW_FRAMES || !hz) return 0;
 uint64_t divisor=(uint64_t)w->frames*hz;
 uint64_t whole=w->render_ticks/divisor;
 if(whole>UINT32_MAX/1000000u) return UINT32_MAX;
 /* frames<=30 and hz<=UINT32_MAX keep the remainder product below 2^64. */
 uint64_t n=whole*1000000u+(w->render_ticks%divisor)*1000000u/divisor;
 return n>=UINT32_MAX?UINT32_MAX:(uint32_t)n;
}
