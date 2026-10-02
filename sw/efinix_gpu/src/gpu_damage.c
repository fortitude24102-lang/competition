#include "gpu_damage.h"
#include <string.h>
/* GPU command planning only: -Os emits DIV/REM even for constant1920 on rv32.
 * O2 uses reciprocal MULH/shifts. CPU golden renderer/build flags stay frozen. */
#if defined(__GNUC__)
#pragma GCC optimize ("O2")
#endif
void gpu_damage_invalidate(gpu_damage_state *s) {
 if(s) { s->valid[0]=s->valid[1]=s->pending=0; }
}
int gpu_damage_init(gpu_damage_state *s,const gpu_damage_config *c) {
 if(!s || !c || (c->tile!=16 && c->tile!=32) || c->gap>4 ||
    !c->capacity || c->capacity>GPU_DAMAGE_RECTS || !c->cost.word_cycles_x256)
  return GPU_DRIVER_ARGUMENT;
 memset(s,0,sizeof *s); s->config=*c; return 0;
}
/* Legacy DenseBlit issues rows separately; each direction is split at 256
 * words and 4 KiB. Tile copies are aligned, so no hidden halfword padding. */
static unsigned bursts(uint32_t a,unsigned n) {
 n=(n+(a&3u)+3u)&~3u; a&=~3u;
 unsigned boundary=4096u-(a&4095u);
 if(n<=boundary) return (n+1023u)>>10;
 return ((boundary+1023u)>>10)+((n-boundary+1023u)>>10);
}
static unsigned copy_bursts(const gpu_command *c) {
 unsigned n=0,h=c->height_pixels,period=0,limit=h;
 /* 1920-byte rows repeat their 4 KiB phase every32 rows. Exact, not an
  * approximation; avoid rescanning hundreds of identical phases on Sapphire. */
 if(c->src_stride==1920 && c->dst_stride==1920 && h>=32) { period=32; limit=32; }
 for(unsigned y=0;y<limit;y++) {
  n+=bursts(c->src_addr+y*c->src_stride,c->width_pixels*2u);
  n+=bursts(c->dst_addr+y*c->dst_stride,c->width_pixels*2u);
 }
 if(period) {
  n*=h>>5;
  for(unsigned y=0;y<(h&31u);y++) {
   n+=bursts(c->src_addr+y*1920u,c->width_pixels*2u);
   n+=bursts(c->dst_addr+y*1920u,c->width_pixels*2u);
  }
 }
 return n;
}
static uint64_t estimate(unsigned commands,uint32_t bytes,uint32_t n,const gpu_damage_cost *m) {
 return (uint64_t)commands*m->command_cycles+(uint64_t)n*m->burst_cycles+
  ((uint64_t)bytes*m->word_cycles_x256>>8);
}
uint64_t gpu_damage_copy_cost(const gpu_command *c,const gpu_damage_cost *m,
 uint32_t *bytes,uint32_t *burst_count) {
 uint32_t n=copy_bursts(c),b=c->width_pixels*c->height_pixels*2u;
 if(bytes) *bytes=b;
 if(burst_count) *burst_count=n;
 return estimate(1,b,n,m);
}
static int covered(const uint8_t *mask,unsigned index) { return (mask[index>>3]>>(index&7u))&1u; }
static int invalid(gpu_damage_state *s) {
 gpu_damage_invalidate(s); return GPU_DRIVER_ARGUMENT;
}
static void full(const gpu_command *bg,gpu_damage_result *p,unsigned reason) {
 p->commands[0]=*bg; p->count=1; p->reason=reason;
 p->bytes=898560u; p->cost=p->full_cost;
}
int gpu_damage_plan(gpu_damage_state *s,const gpu_command *c,unsigned count,
 uint32_t epoch,gpu_damage_result *p) {
 if(!s || !p || !c || !count) return invalid(s);
 if(s->pending) return GPU_DRIVER_BUSY;
 const gpu_command *bg=c;
 uint32_t base=bg->dst_addr-72u*1920u;
 if((base!=GPU_FRAMEBUFFER_A && base!=GPU_FRAMEBUFFER_B) ||
    bg->op!=GPU_OP_COPY || bg->flags || (bg->src_addr&3u) ||
    bg->src_addr<GPU_DENSE_ASSETS+72u*1920u ||
    (uint64_t)bg->src_addr+898560u>GPU_DDR_END_EXCLUSIVE ||
    bg->width_pixels!=960 || bg->height_pixels!=468 ||
    bg->src_stride!=1920 || bg->dst_stride!=1920) return invalid(s);
 unsigned b=base==GPU_FRAMEBUFFER_B,tile=s->config.tile,shift=tile==16?4:5;
 unsigned cols=tile==16?60:30,rows=tile==16?30:15;
 if((tile!=16 && tile!=32) || !s->config.capacity ||
    s->config.capacity>GPU_DAMAGE_RECTS) return invalid(s);
 if(s->epoch!=epoch || s->background!=bg->src_addr) {
  if(s->background!=bg->src_addr) s->full_cost=0;
  gpu_damage_invalidate(s); s->epoch=epoch; s->background=bg->src_addr;
 }
 memset(s->next,0,sizeof s->next);
 for(unsigned i=1;i<count;i++) {
  const gpu_command *v=c+i;
  if((v->op!=GPU_OP_ALPHA && v->op!=GPU_OP_COLOR_KEY &&
      v->op!=GPU_OP_COPY && v->op!=GPU_OP_FILL) || v->flags ||
     v->dst_addr<base || v->dst_addr>=base+GPU_FRAME_BYTES ||
     (v->dst_addr&1u) || v->dst_stride!=1920 ||
     !v->width_pixels || !v->height_pixels) return invalid(s);
  unsigned off=v->dst_addr-base,x=(off%1920u)/2u,y=off/1920u;
  if(y<72 || x+v->width_pixels>960 || y+v->height_pixels>540) return invalid(s);
  for(unsigned ty=(y-72u)>>shift;ty<=((y-72u+v->height_pixels-1u)>>shift);ty++)
   for(unsigned tx=x>>shift;tx<=((x+v->width_pixels-1u)>>shift);tx++) {
    unsigned index=ty*cols+tx; s->next[index>>3]|=(uint8_t)(1u<<(index&7u));
   }
 }
 p->count=p->reason=p->bytes=p->bursts=0; p->cost=0;
 if(!s->full_cost) s->full_cost=gpu_damage_copy_cost(bg,&s->config.cost,0,&s->full_bursts);
 uint32_t full_bursts=s->full_bursts; p->full_cost=s->full_cost;
 if(!s->valid[b]) { full(bg,p,GPU_DAMAGE_COLD); p->bursts=full_bursts; }
 else {
  /* O(tiles + rectangles), not the research probe's O(rectangles squared). */
  for(unsigned x=0;x<cols;x++) s->last_rect[x]=-1;
  for(unsigned y=0;y<rows;y++) for(unsigned x=0;x<cols;) {
   if(!covered(s->history[b],y*cols+x)) { ++x; continue; }
   unsigned start=x;
   while(x<cols) {
    if(covered(s->history[b],y*cols+x)) { ++x; continue; }
    unsigned next=x;
    while(next<cols && !covered(s->history[b],y*cols+next)) ++next;
    if(next==cols || next-x>s->config.gap) break;
    x=next;
   }
   unsigned py=72u+y*tile,h=tile;
   if(py+h>540) h=540-py;
   int last=s->last_rect[start];
   if(last>=0 && p->commands[last].width_pixels==(x-start)*tile &&
      p->commands[last].dst_addr+(uint32_t)p->commands[last].height_pixels*1920u==base+py*1920u+start*tile*2u)
    p->commands[last].height_pixels+=h;
   else {
    if(p->count==s->config.capacity) {
     full(bg,p,GPU_DAMAGE_CAPACITY); p->bursts=full_bursts; goto ready;
    }
    uint32_t offset=y*tile*1920u+start*tile*2u;
    p->commands[p->count]=*bg;
    p->commands[p->count].src_addr+=offset;
    p->commands[p->count].dst_addr+=offset;
    p->commands[p->count].width_pixels=(x-start)*tile;
    p->commands[p->count].height_pixels=h;
    s->last_rect[start]=(int16_t)p->count++;
   }
  }
  for(unsigned i=0;i<p->count;i++) {
   const gpu_command *v=p->commands+i;
   p->bytes+=v->width_pixels*v->height_pixels*2u; p->bursts+=copy_bursts(v);
  }
  p->cost=estimate(p->count,p->bytes,p->bursts,&s->config.cost);
  if(p->cost>=p->full_cost) { full(bg,p,GPU_DAMAGE_COST); p->bursts=full_bursts; }
 }
ready:
 s->buffer=(uint8_t)b; s->pending=1;
 return (int)p->count;
}
void gpu_damage_commit(gpu_damage_state *s,int success) {
 if(!s) return;
 if(!success) { gpu_damage_invalidate(s); return; }
 if(s->pending) {
  memcpy(s->history[s->buffer],s->next,sizeof s->next);
  s->valid[s->buffer]=1; s->pending=0;
 }
}
