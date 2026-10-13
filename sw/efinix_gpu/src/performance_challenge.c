#include "performance_challenge.h"
#include <string.h>
static void begin(pc_state *s,unsigned target,int confirm) {
 s->target=target;s->confirming=(uint8_t)confirm;s->warm=PC_WARM_FRAMES;
 s->stage=PC_WARM;s->stats=(v3_frame_stats){0};s->tick=0;++s->generation;
 for(unsigned i=0;i<target;i++)s->sprites[i]=(pc_sprite){
  .x=(int16_t)(16+(i%56u)*16u),.y=(int16_t)(80+(i/56u)*24u),
  .dx=(int8_t)((i&1u?-1:1)*(int)(1u+(i+s->seed)%3u)),
  .dy=(int8_t)((i&2u?-1:1)*(int)(1u+(2u*i+s->seed)%3u)),
  .shape=(uint8_t)((i+s->seed)%6u)};
}
int pc_init(pc_state *s,unsigned maximum,uint32_t seed) {
 if(!s || maximum<32 || maximum>PC_MAX_SPRITES)return GPU_DRIVER_ARGUMENT;
 memset(s,0,sizeof *s);s->seed=seed;s->maximum=maximum;s->high=maximum+1u;s->growing=1;
 begin(s,maximum<64?maximum:64,0);return 0;
}
static int move(int value,int *velocity,int low,int high) {
 value+=*velocity;
 if(value<low){value=2*low-value;*velocity=-*velocity;}
 if(value>high){value=2*high-value;*velocity=-*velocity;}
 return value;
}
int pc_advance(pc_state *s,const game_input *in) {
 if(!s || !in || s->target<32 || s->target>s->maximum || s->maximum>PC_MAX_SPRITES ||
    ((in->held|in->pressed|in->released)&~V3_KEY_MASK))return GPU_DRIVER_ARGUMENT;
 ++s->tick;
 for(unsigned i=0;i<s->target;i++) {
  pc_sprite *p=s->sprites+i;int dx=p->dx,dy=p->dy;
  if(!i && (in->held&(V3_KEY_LEFT|V3_KEY_RIGHT|V3_KEY_UP|V3_KEY_DOWN))) {
   int speed=in->held&V3_KEY_SLOW?1:3;
   int x=(!!(in->held&V3_KEY_RIGHT)-!!(in->held&V3_KEY_LEFT))*speed;
   int y=(!!(in->held&V3_KEY_DOWN)-!!(in->held&V3_KEY_UP))*speed;
   if(x || y){dx=x;dy=y;}
  }
  p->x=(int16_t)move(p->x,&dx,8,936);p->y=(int16_t)move(p->y,&dy,80,516);
  if(dx)p->dx=(int8_t)dx;
  if(dy)p->dy=(int8_t)dy;
  p->shape=(uint8_t)((i+s->seed+s->tick/8u)%6u);
 }
 return 0;
}
int pc_build(const pc_state *s,uint32_t dst,int network,gpu_instance *items,gpu_instance_stats *out) {
 if(!out)return GPU_DRIVER_ARGUMENT;
 *out=(gpu_instance_stats){0};
 if(!s || !items || s->target<32 || s->target>s->maximum || s->maximum>PC_MAX_SPRITES ||
   (network!=0 && network!=1) || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B))return GPU_DRIVER_ARGUMENT;
 for(unsigned i=0;i<s->target;i++)if(s->sprites[i].x<8 || s->sprites[i].x>936 ||
  s->sprites[i].y<80 || s->sprites[i].y>516 || s->sprites[i].shape>=6)return GPU_DRIVER_ARGUMENT;
 items[0]=(gpu_instance){{0,dst+72u*GPU_FRAME_STRIDE,72u*GPU_FRAME_STRIDE,gpu_pack_size(960,468)}};
 unsigned n=1,alpha=64u+(s->tick%16u)*4u;
 for(unsigned i=0;i<s->target;i+=8) {
  const pc_sprite *p=s->sprites+i;
  items[n++]=(gpu_instance){{1u|256u|(alpha<<16),
   dst+(uint32_t)(p->y-2)*GPU_FRAME_STRIDE+(uint32_t)(p->x-2)*2u,0,gpu_pack_size(12,12)}};
 }
 out->alpha_commands=(s->target+7u)/8u;out->alpha_pixels=out->alpha_commands*144u;
 for(unsigned i=0;i<s->target;i++) {
  const pc_sprite *p=s->sprites+i;unsigned size=i?8:16;
  items[n++]=(gpu_instance){{i?2u+p->shape:8u,dst+(uint32_t)p->y*GPU_FRAME_STRIDE+(uint32_t)p->x*2u,0,gpu_pack_size(size,size)}};
 }
 out->count=n;out->visible=s->target;
 out->scene_pixels=960u*468u+out->alpha_pixels+256u+(s->target-1u)*64u;return 0;
}
static void next(pc_state *s) {
 if(s->high-s->low<=1u || (s->low+s->high)/2u<32u) {
  if(s->low<32u){s->stage=PC_FAILED;s->best=0;return;}
  begin(s,s->low,1);return;
 }
 begin(s,(s->low+s->high)/2u,0);
}
int pc_record(pc_state *s,uint32_t hz,uint32_t work,uint32_t wall,
 uint32_t under,uint32_t errors,unsigned visible,unsigned alpha) {
 if(!s || !hz || s->target<32 || s->target>s->maximum || s->maximum>PC_MAX_SPRITES ||
  s->stage<PC_WARM || s->stage>PC_FAILED || wall<work)return GPU_DRIVER_ARGUMENT;
 if(under || errors || visible!=s->target || alpha!=(s->target+7u)/8u) {
  s->stage=PC_FAILED;s->best=0;return 1;
 }
 if(s->stage>=PC_DONE) {
  if(s->stage!=PC_FAILED && (work>hz/60u || wall>hz/40u)){s->stage=PC_FAILED;s->best=0;return 1;}
  return 0;
 }
 if(s->warm) {
  if(!--s->warm)s->stage=s->confirming?PC_VERIFY:PC_SAMPLE;
  return 0;
 }
 v3_frame_stats_add(&s->stats,hz,work,wall,0,under,errors,visible,alpha);
 unsigned goal=s->confirming?PC_VERIFY_FRAMES:PC_SEARCH_FRAMES;
 if(s->stats.frames<goal)return 0;
 int pass=!s->stats.work_misses && !s->stats.cadence_misses &&
  (uint64_t)s->stats.frames*hz>=(uint64_t)60u*s->stats.wall_ticks;
 if(s->confirming) {
  if(pass){s->best=s->target;s->stage=s->target==s->maximum?PC_CAPACITY:PC_DONE;return 1;}
  s->high=s->target;s->low=0;s->best=0;s->growing=0;next(s);return 1;
 }
 if(pass) {
  s->low=s->target;
  if(s->target==s->maximum){begin(s,s->target,1);return 1;}
  if(s->growing){unsigned n=s->target*2u;begin(s,n>s->maximum?s->maximum:n,0);return 1;}
 } else {s->high=s->target;s->growing=0;}
 next(s);return 1;
}
