#include "split_view.h"
#include "interactive_game.h"
#include "benchmark.h"
static const struct {uint32_t offset;unsigned size;} tiles[]={
 {0,8},{128,8},{256,8},{384,8},{512,8},{640,8},
 {BULLET_PLAYER_OFFSET,16},{BULLET_GLOW_OFFSET,12},
 {BULLET_EMITTER_OFFSET,16},{BULLET_EMITTER_OFFSET+512,16},{BULLET_EMITTER_OFFSET+1024,16}
};
_Static_assert(SPLIT_BACKGROUND+480u*270u*2u<=SPLIT_ATLAS,"view assets overlap");
_Static_assert(!(BULLET_ATLAS_BYTES%4u) && BULLET_ATLAS_BYTES<=4096u,"four half-size phases fit original texture cache");
_Static_assert(SPLIT_ATLAS+BULLET_ATLAS_BYTES<=GPU_DDR_END_EXCLUSIVE,"view asset DDR bounds");
int split_view_prepare(int network,int (*service)(void *),void *context) {
 if(network!=0 && network!=1)return GPU_DRIVER_ARGUMENT;
 const uint16_t *bg=(const uint16_t *)(uintptr_t)(network?BULLET_BACKGROUND_ADDR:BULLET_LOCAL_BACKGROUND);
 uint16_t *small=(uint16_t *)(uintptr_t)SPLIT_BACKGROUND;
 for(unsigned y=0;y<270;y++) {
  for(unsigned x=0;x<480;x++)small[y*480+x]=bg[y*2u*960+x*2u];
  if(!(y%8) && service){int e=service(context);if(e)return e;}
 }
 uint32_t atlas=network?BULLET_ATLAS_ADDR:BULLET_LOCAL_ATLAS;
 for(unsigned phase=0;phase<4;phase++)for(unsigned i=0;i<sizeof tiles/sizeof *tiles;i++) {
  unsigned size=tiles[i].size;
  const uint16_t *src=(const uint16_t *)(uintptr_t)(atlas+tiles[i].offset);
  uint16_t *dst=(uint16_t *)(uintptr_t)(SPLIT_ATLAS+phase*(BULLET_ATLAS_BYTES/4u)+tiles[i].offset/4u);
  for(unsigned y=0;y<size/2;y++)for(unsigned x=0;x<size/2;x++)
   dst[y*(size/2)+x]=src[(y*2+(phase>>1))*size+x*2+(phase&1)];
 }
 gpu_platform_sync();return 0;
}
static int scale(gpu_command *c,int network,uint32_t destination) {
 if(c->dst_addr<GPU_FRAMEBUFFER_A || c->dst_addr-GPU_FRAMEBUFFER_A>=GPU_FRAME_BYTES ||
    c->dst_stride!=GPU_FRAME_STRIDE || c->flags || (c->dst_addr&1u))return GPU_DRIVER_ARGUMENT;
 unsigned offset=c->dst_addr-GPU_FRAMEBUFFER_A,x=(offset%GPU_FRAME_STRIDE)/2,y=offset/GPU_FRAME_STRIDE;
 unsigned dx=(x+1u)/2,dy=(y+1u)/2,w=(x+c->width_pixels+1u)/2-dx,h=(y+c->height_pixels+1u)/2-dy;
 if(x+c->width_pixels>960 || y+c->height_pixels>540)return GPU_DRIVER_ARGUMENT;
 if(!w || !h)return 1;
 if(c->op==GPU_OP_COPY) {
  if(offset || c->src_addr!=(network?BULLET_BACKGROUND_ADDR:BULLET_LOCAL_BACKGROUND) ||
     c->src_stride!=GPU_FRAME_STRIDE || c->width_pixels!=960 || c->height_pixels!=540)return GPU_DRIVER_ARGUMENT;
  c->src_addr=SPLIT_BACKGROUND;c->src_stride=960;
 } else if(c->op==GPU_OP_COLOR_KEY || c->op==GPU_OP_ALPHA) {
  uint32_t atlas=network?BULLET_ATLAS_ADDR:BULLET_LOCAL_ATLAS;
  unsigned i;
  for(i=0;i<sizeof tiles/sizeof *tiles;i++) {
   uint32_t base=atlas+tiles[i].offset,size=tiles[i].size;
   if(c->src_addr>=base && c->src_addr<base+size*size*2u) {
    if(c->src_stride!=size*2u || (c->src_addr&1u))return GPU_DRIVER_ARGUMENT;
    unsigned sx=((c->src_addr-base)%(size*2u))/2+dx*2u-x;
    unsigned sy=(c->src_addr-base)/(size*2u)+dy*2u-y;
    if(sx+(w-1u)*2u>=size || sy+(h-1u)*2u>=size)return GPU_DRIVER_ARGUMENT;
    unsigned phase=(sx&1u)|((sy&1u)<<1);
    c->src_addr=SPLIT_ATLAS+phase*(BULLET_ATLAS_BYTES/4u)+tiles[i].offset/4u+(sy/2u)*size+(sx/2u)*2u;
    c->src_stride=size;break;
   }
  }
  if(i==sizeof tiles/sizeof *tiles)return GPU_DRIVER_ARGUMENT;
 } else if(c->op!=GPU_OP_FILL)return GPU_DRIVER_ARGUMENT;
 c->dst_addr=destination+dy*GPU_FRAME_STRIDE+dx*2u;
 c->width_pixels=(uint16_t)w;c->height_pixels=(uint16_t)h;return 0;
}
static int legacy_view(const bullet_state *state,int network,uint32_t destination,bullet_stream *out) {
 if(!out || (destination&1u) || destination<GPU_FRAMEBUFFER_A ||
    (uint64_t)destination+269u*GPU_FRAME_STRIDE+960u>GPU_DDR_END_EXCLUSIVE)return GPU_DRIVER_ARGUMENT;
 int e=game_build(state,GPU_FRAMEBUFFER_A,network,1,BULLET_MAX_COMMANDS,out);if(e)return e;
 unsigned original=out->count,count=0;
 for(unsigned i=0;i<original;i++) {
  gpu_command c=out->commands[i];e=scale(&c,network,destination);
  if(e<0){out->count=0;return e;}
  if(!e)out->commands[count++]=c;
 }
 out->count=count;return 0;
}
_Static_assert(SPLIT_ATLAS+BULLET_ATLAS_BYTES<=SPLIT_INSTANCES,"view scratch overlaps atlas");
_Static_assert(SPLIT_INSTANCES+BULLET_MAX_COMMANDS*sizeof(gpu_instance)<=GPU_DDR_END_EXCLUSIVE,"view scratch DDR bounds");
int split_view_build(const bullet_state *state,int network,uint32_t destination,bullet_stream *out) {
 if(!state || !out || (destination&1u) || destination<GPU_FRAMEBUFFER_A ||
    (uint64_t)destination+269u*GPU_FRAME_STRIDE+960u>GPU_DDR_END_EXCLUSIVE)return GPU_DRIVER_ARGUMENT;
 /* Reuse the normal game's compact builder. WIN's few Fill rectangles keep
  * the existing fallback, without building/converting full commands per sprite. */
 if(state->won)return legacy_view(state,network,destination,out);
 gpu_instance *items=(gpu_instance *)(uintptr_t)SPLIT_INSTANCES;gpu_instance_stats stats;
 int e=gpu_instances_build_into(state,GPU_FRAMEBUFFER_A,network,1,1,0,BULLET_MAX_COMMANDS,items,&stats);
 out->count=0;if(e)return e;
 out->visible=stats.visible;out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 for(unsigned i=0;i<stats.count;i++) {
  const gpu_instance *v=items+i;unsigned id=v->words[0]&255u;
  if(!id) {
   out->commands[out->count++]=(gpu_command){.op=GPU_OP_COPY,.src_addr=SPLIT_BACKGROUND,.dst_addr=destination,
    .src_stride=960,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=480,.height_pixels=270};out->scene_pixels+=480u*270u;continue;
  }
  if(id>11){out->count=0;return GPU_DRIVER_ARGUMENT;}
  unsigned offset=v->words[1]-GPU_FRAMEBUFFER_A,y=offset/GPU_FRAME_STRIDE,x=(offset-y*GPU_FRAME_STRIDE)/2u;
  unsigned w=((v->words[3]&65535u)+1u-(x&1u))>>1,h=((v->words[3]>>16)+1u-(y&1u))>>1;
  if(!w || !h)continue;
  unsigned size=id==1?12:id<8?8:16,source=v->words[2]>>1;
  unsigned sx=id==1?source%12u:source&(size-1u),sy=id==1?source/12u:source>>(size==8?3:4);
  sx+=x&1u;sy+=y&1u;
  unsigned tile=id==1?BULLET_GLOW_OFFSET/4u:id<8?(id-2u)*32u:id==8?BULLET_PLAYER_OFFSET/4u:BULLET_EMITTER_OFFSET/4u+(id-9u)*128u;
  unsigned phase=(sx&1u)|((sy&1u)<<1);
  out->commands[out->count++]=(gpu_command){.op=(uint8_t)(id==1?GPU_OP_ALPHA:GPU_OP_COLOR_KEY),
   .src_addr=SPLIT_ATLAS+phase*(BULLET_ATLAS_BYTES/4u)+tile+(sy>>1)*size+(sx&~1u),
   .dst_addr=destination+((y+1u)>>1)*GPU_FRAME_STRIDE+((x+1u)&~1u),
   .src_stride=size,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=(uint16_t)w,.height_pixels=(uint16_t)h,
   .color_key=BULLET_COLOR_KEY,.alpha=(uint8_t)(v->words[0]>>16)};
  out->scene_pixels+=w*h;if(id==1){++out->alpha_commands;out->alpha_pixels+=w*h;}
 }
 return 0;
}
