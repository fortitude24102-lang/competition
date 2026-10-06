#include "gpu_instances.h"
#include <string.h>
#ifdef GPU_TEST_BACKEND
uint32_t gpu_io_read(uintptr_t a);
void gpu_io_write(uintptr_t a,uint32_t v);
void gpu_io_fence(void);
#else
static uint32_t gpu_io_read(uintptr_t a) { return *(volatile uint32_t *)a; }
static void gpu_io_write(uintptr_t a,uint32_t v) { *(volatile uint32_t *)a=v; }
static void gpu_io_fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
#endif
static uint32_t rd(gpu_instances *i,unsigned offset) { return gpu_io_read(i->gpu->base+offset); }
static void wr(gpu_instances *i,unsigned offset,uint32_t data) { gpu_io_write(i->gpu->base+offset,data); }
int gpu_instances_init(gpu_instances *i,gpu_device *d) {
 if(!i || !d || !d->ready) return GPU_DRIVER_ARGUMENT;
 *i=(gpu_instances){.gpu=d};
 /* Existing STATUS is safe on old hardware; unsupported0400 may PSLVERR.
  * Never probe that new address unless the compiled capability is present. */
 if(!(rd(i,GPU_REG_STATUS)&GPU_INSTANCE_CAPABILITY)) return 0;
 if(rd(i,0x400)!=GPU_INSTANCE_ID) return GPU_DRIVER_ID;
 i->present=1;return 0;
}
int gpu_instances_program(gpu_instances *i,const gpu_instance_template *t,unsigned n) {
 if(!i || !i->gpu || !t || !n || n>16) return GPU_DRIVER_ARGUMENT;
 if(!i->present) return 0;
 if(i->active || i->gpu->outstanding || (rd(i,GPU_REG_STATUS)&GPU_STATUS_BUSY)) return GPU_DRIVER_BUSY;
 for(unsigned j=0;j<n;j++) {
  gpu_instance probe={{j|(t[j].op==GPU_OP_ALPHA?256u:0),GPU_FRAMEBUFFER_A,0,
   gpu_pack_size((uint16_t)t[j].width_max,(uint16_t)t[j].height_max)}};
  gpu_command command;
  if(gpu_instance_expand(t,&probe,0,&command)) return GPU_DRIVER_ARGUMENT;
 }
 for(unsigned j=0;j<n;j++) {
  const gpu_instance_template *v=t+j;
  uint32_t fields[7]={v->op,v->src_base,v->src_stride,v->dst_stride,v->width_max,v->height_max,v->key};
  wr(i,0x40c,j);
  for(unsigned f=0;f<7;f++) wr(i,0x410+f*4u,fields[f]);
 }
 gpu_io_fence();return (rd(i,0x404)&8u)?GPU_DRIVER_ARGUMENT:0;
}
int gpu_instances_render(gpu_instances *i,const gpu_instance_template *t,const gpu_instance_stream *s,uint32_t polls) {
 if(!i || !i->gpu || !t || !s || !s->count || s->count>BULLET_MAX_COMMANDS || !polls) return GPU_DRIVER_ARGUMENT;
 gpu_device *d=i->gpu;
 if(i->active || d->outstanding) return GPU_DRIVER_BUSY;
 if(i->present) {
  if(rd(i,GPU_REG_STATUS)&GPU_STATUS_BUSY) return GPU_DRIVER_BUSY;
  if(rd(i,GPU_REG_ERROR)) return GPU_DRIVER_HARDWARE;
  wr(i,0x444,d->next_tag);wr(i,0x408,1);gpu_io_fence();
  if(rd(i,0x404)&8u) return GPU_DRIVER_ARGUMENT;
  i->active=1;
 }
 uint16_t last=0;
 for(unsigned j=0;j<s->count;j++) {
  gpu_command c;int e=gpu_instance_expand(t,s->items+j,d->next_tag,&c);
  if(e) return e; // Partial frames are NEVER replayed through the old path.
  if(!i->present) { e=gpu_submit(d,&c,polls,&last);if(e) return e;continue; }
  uint32_t budget=polls;
  for(;;) {
   if(d->outstanding) { e=gpu_poll(d,d->pending_tag);if(e<0) return e; }
   else { d->hardware_error=(uint8_t)rd(i,GPU_REG_ERROR);if(d->hardware_error) return GPU_DRIVER_HARDWARE; }
   uint32_t status=rd(i,0x404);
   if(status&8u) return GPU_DRIVER_ARGUMENT;
   if((status&2u) && d->outstanding<GPU_COMMAND_QUEUE_DEPTH) break;
   if(!budget--) return GPU_DRIVER_TIMEOUT;
  }
  for(unsigned f=0;f<4;f++) wr(i,0x430+f*4u,s->items[j].words[f]);
  gpu_io_fence();wr(i,0x440,1);gpu_io_fence();
  if(rd(i,0x404)&8u) return GPU_DRIVER_ARGUMENT;
  last=d->next_tag++;++d->submitted_count;++d->outstanding;
  d->pending=1;d->pending_tag=last;
  if(d->outstanding>d->queue_high_watermark) d->queue_high_watermark=d->outstanding;
 }
 int e=gpu_wait_tag(d,last,polls);if(e) return e;
 if(i->present) {
  wr(i,0x408,2);gpu_io_fence();
  if(rd(i,0x404)&1u) return GPU_DRIVER_BUSY;
  i->active=0;
 }
 return 0;
}
unsigned gpu_instances_templates(int network,gpu_instance_template t[GPU_INSTANCE_TEMPLATES]) {
 if(!t || (network!=0 && network!=1)) return 0;
 memset(t,0,sizeof(*t)*GPU_INSTANCE_TEMPLATES);
 uint32_t atlas=network?BULLET_ATLAS_ADDR:BULLET_LOCAL_ATLAS;
 t[0]=(gpu_instance_template){GPU_OP_COPY,network?BULLET_BACKGROUND_ADDR:BULLET_LOCAL_BACKGROUND,
  GPU_FRAME_STRIDE,GPU_FRAME_STRIDE,GPU_FRAME_WIDTH,GPU_FRAME_HEIGHT,0};
 for(unsigned i=1;i<12;i++) {
  unsigned size=i==1?12:i<8?8:16;
  unsigned offset=i==1?BULLET_GLOW_OFFSET:i<8?(i-2u)*128u:
   i==8?BULLET_PLAYER_OFFSET:BULLET_EMITTER_OFFSET+(i-9u)*512u;
  t[i]=(gpu_instance_template){i==1?GPU_OP_ALPHA:GPU_OP_COLOR_KEY,atlas+offset,
   size*2u,GPU_FRAME_STRIDE,size,size,BULLET_COLOR_KEY};
 }
 return 12;
}
int gpu_instance_expand(const gpu_instance_template *t,const gpu_instance *i,uint16_t tag,gpu_command *c) {
 if(!t || !i || !c) return GPU_DRIVER_ARGUMENT;
 unsigned id=i->words[0]&255u,flags=(i->words[0]>>8)&255u,a=(i->words[0]>>16)&255u;
 if(id>=16 || (i->words[0]>>24)) return GPU_DRIVER_ARGUMENT;
 const gpu_instance_template *v=t+id;
 unsigned w=i->words[3]&65535u,h=i->words[3]>>16;
 if((v->op!=GPU_OP_COPY && v->op!=GPU_OP_COLOR_KEY && v->op!=GPU_OP_ALPHA) ||
  flags!=(v->op==GPU_OP_ALPHA) || (v->op!=GPU_OP_ALPHA && a) ||
  !w || !h || !v->width_max || v->width_max>65535 || !v->height_max || v->height_max>65535 ||
  w>v->width_max || h>v->height_max || v->key>65535 ||
  ((v->src_stride|v->dst_stride|v->src_base|i->words[1]|i->words[2])&1u) ||
  v->src_stride<w*2u || v->dst_stride<w*2u) return GPU_DRIVER_ARGUMENT;
 uint64_t src=(uint64_t)v->src_base+i->words[2];
 uint64_t span=(uint64_t)i->words[2]+(uint64_t)(h-1u)*v->src_stride+w*2u;
 uint64_t limit=(uint64_t)(v->height_max-1u)*v->src_stride+v->width_max*2u;
 uint64_t src_end=src+(uint64_t)(h-1u)*v->src_stride+w*2u;
 uint64_t dst_end=(uint64_t)i->words[1]+(uint64_t)(h-1u)*v->dst_stride+w*2u;
 if(span>limit || src>UINT32_MAX || src<GPU_FRAMEBUFFER_A || src_end>GPU_DDR_END_EXCLUSIVE ||
  i->words[1]<GPU_FRAMEBUFFER_A || dst_end>GPU_DDR_END_EXCLUSIVE ||
  ((v->op==GPU_OP_COPY || v->op==GPU_OP_ALPHA) && src<dst_end && i->words[1]<src_end &&
   !(v->op==GPU_OP_ALPHA && src==i->words[1] && v->src_stride==v->dst_stride))) return GPU_DRIVER_ARGUMENT;
 *c=(gpu_command){.op=(uint8_t)v->op,.src_addr=(uint32_t)src,.dst_addr=i->words[1],
  .src_stride=v->src_stride,.dst_stride=v->dst_stride,.width_pixels=(uint16_t)w,
  .height_pixels=(uint16_t)h,.color_key=(uint16_t)v->key,.alpha=(uint8_t)a,.tag=tag};
 return 0;
}
static int append(gpu_instance_stream *s,unsigned cap,unsigned id,uint32_t dst,
 unsigned offset,unsigned w,unsigned h,unsigned alpha) {
 if(s->count==cap) return GPU_DRIVER_FULL;
 s->items[s->count++]=(gpu_instance){{id|(id==1?256u:0)|(alpha<<16),dst,offset,gpu_pack_size((uint16_t)w,(uint16_t)h)}};
 s->scene_pixels+=w*h;
 if(id==1) { ++s->alpha_commands; s->alpha_pixels+=w*h; }
 return 0;
}
/* R7 clipping/opacity decisions are kept byte-equivalent by600tick tests.
 * No old gpu_command is constructed then converted on this GPU-only path. */
static int sprite(gpu_instance_stream *s,unsigned cap,uint32_t dst,unsigned id,
 int x,int y,unsigned size,unsigned alpha,int shape,int *visible) {
 *visible=0;
 if(x>=960 || x<=-(int)size || y>=540 || y<=72-(int)size) return 0;
 unsigned sx=x<0?(unsigned)-x:0,sy=y<72?(unsigned)(72-y):0;
 unsigned dx=x<0?0:(unsigned)x,dy=y<72?72:(unsigned)y,w=size-sx,h=size-sy;
 if(w>960u-dx) w=960u-dx;
 if(h>540u-dy) h=540u-dy;
 if(shape>=0 && (sx || sy || w<size || h<size)) {
  int opaque=0;
  for(unsigned ty=sy;ty<sy+h && !opaque;ty++) for(unsigned tx=sx;tx<sx+w;tx++)
   if(bullet_shape_opaque((unsigned)shape,tx,ty)) { opaque=1; break; }
  if(!opaque) return 0;
 }
 int e=append(s,cap,id,dst+dy*GPU_FRAME_STRIDE+dx*2u,(sy*size+sx)*2u,w,h,alpha);
 if(!e) *visible=1;
 return e;
}
static int coordinate(int32_t q8) { int x=q8/256;return q8<0 && q8%256?x-1:x; }
int gpu_instances_build(const bullet_state *s,uint32_t dst,int network,int glow,
 unsigned hud,unsigned cap,gpu_instance_stream *out) {
 if(!out) return GPU_DRIVER_ARGUMENT;
 out->count=out->visible=out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || !cap || cap>BULLET_MAX_COMMANDS ||
  (network!=0 && network!=1) || (glow!=0 && glow!=1) || hud>=GPU_FRAME_HEIGHT ||
  (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B)) return GPU_DRIVER_ARGUMENT;
 int e=append(out,cap,0,dst+hud*GPU_FRAME_STRIDE,hud*GPU_FRAME_STRIDE,
  GPU_FRAME_WIDTH,GPU_FRAME_HEIGHT-hud,0),v;
 for(unsigned i=0;!e && glow && i<s->count;i+=8u) {
  const bullet_object *b=s->objects+i;
  e=sprite(out,cap,dst,1,coordinate(b->x)-2,coordinate(b->y)-2,12,64+(s->tick%16u)*4,-1,&v);
 }
 for(unsigned i=0;!e && i<s->count;i++) {
  const bullet_object *b=s->objects+i;
  if(b->kind>2 || b->shape>=BULLET_SHAPE_COUNT) {e=GPU_DRIVER_ARGUMENT;break;}
  e=sprite(out,cap,dst,2u+b->shape,coordinate(b->x),coordinate(b->y),8,0,b->shape,&v);
  if(!e) out->visible+=(unsigned)v;
 }
 if(!e && glow && s->hp) e=sprite(out,cap,dst,1,s->player_x-6,s->player_y-6,12,s->invulnerable?192:64,-1,&v);
 if(!e && s->hp) e=sprite(out,cap,dst,8,s->player_x-8,s->player_y-8,16,0,-1,&v);
 static const int centers[3][2]={{480,280},{240,100},{720,220}};
 unsigned warning=s->round_tick%60u;
 unsigned emitter_alpha=s->hp && warning>=44u?80+(warning-43u)*8:80;
 for(unsigned i=0;!e && i<3;i++) {
  if(glow) e=sprite(out,cap,dst,1,centers[i][0]-6,centers[i][1]-6,12,emitter_alpha,-1,&v);
  if(!e) e=sprite(out,cap,dst,9u+i,centers[i][0]-8,centers[i][1]-8,16,0,-1,&v);
 }
 if(e) out->count=out->visible=out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 return e;
}
