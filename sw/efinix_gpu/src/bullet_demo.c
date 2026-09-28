#include "bullet_demo.h"
#include <string.h>
/* Q8 direction table: no floating-point/trigonometry in the RV32 frame loop. */
static const int16_t directions[16][2]={
 {256,0},{237,98},{181,181},{98,237},{0,256},{-98,237},{-181,181},{-237,98},
 {-256,0},{-237,-98},{-181,-181},{-98,-237},{0,-256},{98,-237},{181,-181},{237,-98}
};
static void spawn(bullet_state *s,unsigned i,int warm) {
 bullet_object *b=&s->objects[i];
 unsigned kind=i%3u;
 unsigned direction=((i/3u)+(s->seed^7u)+(kind==2?s->tick/8u:0u))&15u;
 unsigned radius=warm ? 16u+((i/48u)%10u)*16u : 0u;
 int cx=kind==1?240:kind==2?720:480,cy=kind==1?100:kind==2?220:280;
 if(kind==1) direction=1u+(i/3u)%7u; /* Downward fan. */
 b->x=cx*256+directions[direction][0]*(int)radius;
 b->y=cy*256+directions[direction][1]*(int)radius;
 b->vx=(int16_t)(directions[direction][0]*3/2);
 b->vy=(int16_t)(directions[direction][1]*3/2);
 b->kind=(uint8_t)kind; b->shape=(uint8_t)(i%BULLET_SHAPE_COUNT); b->age=0; b->grazed=0;
}
int bullet_reset(bullet_state *s,unsigned count,uint32_t seed) {
 if(!s || !count || count>BULLET_MAX_OBJECTS) return GPU_DRIVER_ARGUMENT;
 memset(s,0,sizeof *s); s->count=count; s->seed=seed;
 s->player_x=480; s->player_y=480; s->hp=BULLET_START_HP;
 for(unsigned i=0;i<count;i++) spawn(s,i,1);
 return 0;
}
static int pixel_coordinate(int32_t q8);
static void add_score(bullet_state *s,uint32_t points) {
 s->score=UINT32_MAX-s->score<points?UINT32_MAX:s->score+points;
}
int bullet_step(bullet_state *s) {
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || s->hp>BULLET_START_HP ||
    s->invulnerable>BULLET_PROTECTION_TICKS ||
    (!s->hp && (!s->game_over_ticks || s->game_over_ticks>BULLET_RESTART_TICKS)))
  return GPU_DRIVER_ARGUMENT;
 for(unsigned i=0;i<s->count;i++) if(s->objects[i].kind>2 ||
  s->objects[i].shape>=BULLET_SHAPE_COUNT) return GPU_DRIVER_ARGUMENT;
 ++s->tick;
 if(!s->hp) {
  if(!--s->game_over_ticks) {
   uint32_t tick=s->tick;
   int e=bullet_reset(s,s->count,s->seed); s->tick=tick; return e;
  }
  return 0;
 }
 ++s->round_tick;
 int phase=(int)(s->round_tick%240u);
 s->player_x=480+3*(phase<60?phase:phase<180?120-phase:phase-240);
 s->player_y=480;
 int protected=s->invulnerable!=0;
 if(protected) --s->invulnerable;
 if(!(s->round_tick%30u)) add_score(s,1);
 for(unsigned i=0;i<s->count;i++) {
  bullet_object *b=&s->objects[i];
  if(b->x<=-8*256 || b->x>=960*256 || b->y<64*256 || b->y>=540*256 ||
     b->age>=240u+i%120u) { spawn(s,i,0); continue; }
  b->x+=b->vx; b->y+=b->vy; ++b->age;
  int bx=pixel_coordinate(b->x),by=pixel_coordinate(b->y);
  /* Cheap broad phase, then at most 64 opacity texels for nearby bullets.
   * Hit core radius 3; graze radius 12. No all-pairs object collision. */
  if(bx<s->player_x-19 || bx>s->player_x+12 || by<s->player_y-19 || by>s->player_y+12) continue;
  int hit=0,near=0;
  for(unsigned y=0;y<8 && !hit;y++) for(unsigned x=0;x<8;x++) {
   if(!bullet_shape_opaque(b->shape,x,y)) continue;
   int dx=bx+(int)x-s->player_x,dy=by+(int)y-s->player_y;
   int r=dx*dx+dy*dy;
   if(r<=144) near=1;
   if(r<=9) { hit=1; break; }
  }
  if(hit) {
   if(!protected) {
    --s->hp; protected=1;
    spawn(s,i,0);
    if(!s->hp) { s->game_over_ticks=BULLET_RESTART_TICKS; s->invulnerable=0; break; }
    s->invulnerable=BULLET_PROTECTION_TICKS;
   }
  } else if(near && !b->grazed) {
   b->grazed=1; if(s->grazes!=UINT32_MAX) ++s->grazes; add_score(s,10);
  }
 }
 return 0;
}
int bullet_prepare_frame(bullet_state *s,unsigned count,unsigned frame,uint32_t seed) {
 if(frame>=BULLET_REPLAY_FRAMES) return GPU_DRIVER_ARGUMENT;
 int e=bullet_reset(s,count,seed); if(e) return e;
 for(unsigned f=0;f<frame;f++) { e=bullet_step(s); if(e) return e; }
 return 0;
}
static int append(bullet_stream *out,unsigned cap,const gpu_command *c) {
 if(out->count==cap) return GPU_DRIVER_FULL;
 out->commands[out->count++]=*c;
 out->scene_pixels+=(uint32_t)c->width_pixels*c->height_pixels;
 if(c->op==GPU_OP_ALPHA) {
  ++out->alpha_commands; out->alpha_pixels+=(uint32_t)c->width_pixels*c->height_pixels;
 }
 return 0;
}
int bullet_finish_window(bullet_state *s,bullet_state *start,int gpu_window) {
 if(!s || !start || s==start || !s->count || s->count>BULLET_MAX_OBJECTS ||
    start->count!=s->count || start->seed!=s->seed ||
    (gpu_window!=0 && gpu_window!=1)) return GPU_DRIVER_ARGUMENT;
 if(!gpu_window) *s=*start;
 else {
  if(s->tick>=BULLET_REPLAY_FRAMES) {
   int e=bullet_reset(s,s->count,s->seed); if(e) return e;
  }
  *start=*s;
 }
 return 0;
}
int bullet_shape_opaque(unsigned shape,unsigned x,unsigned y) {
 if(x>=8 || y>=8) return 0;
 int dx=(int)x*2-7,dy=(int)y*2-7;
 if(dx<0) dx=-dx;
 if(dy<0) dy=-dy;
 int r=dx*dx+dy*dy;
 switch(shape) {
  case 0:return r<=49; /* round */
  case 1:return dx+dy<=8; /* diamond */
  case 2:return dx<=1 || (dx<=3 && dy<=3); /* needle */
  case 3:return dx<=1 || dy<=1; /* cross */
  case 4:return dx<=1 || dy<=1 || dx==dy; /* eight-point star */
  case 5:return r<=49 && r>=18; /* hollow ring */
  default:return 0;
 }
}
static int sprite(bullet_stream *out,unsigned cap,uint32_t dst,uint32_t src,
 int x,int y,unsigned size,int alpha,int shape,int *visible) {
 *visible=0;
 if(x>=960 || x<=-(int)size || y>=540 || y<=72-(int)size) return 0;
 unsigned sx=x<0?(unsigned)-x:0,sy=y<72?(unsigned)(72-y):0;
 int dx=x<0?0:x,dy=y<72?72:y;
 unsigned w=size-sx,h=size-sy;
 if(w>960u-(unsigned)dx) w=960u-(unsigned)dx;
 if(h>540u-(unsigned)dy) h=540u-(unsigned)dy;
 if(shape>=0 && (sx || sy || w<size || h<size)) {
  /* Only clipped bullets need a bounded mask scan (at most 64 texels).
   * Full tiles for all six shapes are known to contain opaque pixels. */
  int opaque=0;
  for(unsigned ty=sy;ty<sy+h && !opaque;ty++) for(unsigned tx=sx;tx<sx+w;tx++)
   if(bullet_shape_opaque((unsigned)shape,tx,ty)) { opaque=1; break; }
  if(!opaque) return 0;
 }
 gpu_command c={.op=alpha?GPU_OP_ALPHA:GPU_OP_COLOR_KEY,
  .src_addr=src+(sy*size+sx)*2u,.dst_addr=dst+(unsigned)dy*GPU_FRAME_STRIDE+(unsigned)dx*2u,
  .src_stride=size*2u,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=(uint16_t)w,
  .height_pixels=(uint16_t)h,.color_key=BULLET_COLOR_KEY,.alpha=(uint8_t)alpha};
 int e=append(out,cap,&c); if(!e) *visible=1; return e;
}
static int pixel_coordinate(int32_t q8) {
 int n=q8/256;
 return q8<0 && q8%256 ? n-1:n;
}
int bullet_build_frame(const bullet_state *s,uint32_t dst,int network,int glow,unsigned cap,bullet_stream *out) {
 if(!out) return GPU_DRIVER_ARGUMENT;
 out->count=out->visible=out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || !cap || cap>BULLET_MAX_COMMANDS ||
    (network!=0 && network!=1) ||
    (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B)) return GPU_DRIVER_ARGUMENT;
 uint32_t atlas=network?BULLET_ATLAS_ADDR:BULLET_LOCAL_ATLAS;
 gpu_command bg={.op=GPU_OP_COPY,.src_addr=network?BULLET_BACKGROUND_ADDR:BULLET_LOCAL_BACKGROUND,.dst_addr=dst,
  .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT};
 int e=append(out,cap,&bg),v;
 /* Halos precede keyed cores, so blending does not dull the bullet faces. */
 for(unsigned i=0;!e && glow && i<s->count;i+=8u) {
  const bullet_object *b=&s->objects[i];
  e=sprite(out,cap,dst,atlas+BULLET_GLOW_OFFSET,
   pixel_coordinate(b->x)-2,pixel_coordinate(b->y)-2,12,64+(int)(s->tick%16u)*4,-1,&v);
 }
 for(unsigned i=0;!e && i<s->count;i++) {
  const bullet_object *b=&s->objects[i];
  if(b->kind>2 || b->shape>=BULLET_SHAPE_COUNT) { e=GPU_DRIVER_ARGUMENT; break; }
  e=sprite(out,cap,dst,atlas+b->shape*128u,
   pixel_coordinate(b->x),pixel_coordinate(b->y),8,0,b->shape,&v);
  if(!e) out->visible+=(unsigned)v;
 }
 if(!e && glow && s->hp) e=sprite(out,cap,dst,atlas+BULLET_GLOW_OFFSET,
  s->player_x-6,s->player_y-6,12,s->invulnerable?192:64,-1,&v);
 if(!e && s->hp) e=sprite(out,cap,dst,atlas+BULLET_PLAYER_OFFSET,s->player_x-8,s->player_y-8,16,0,-1,&v);
 static const int centers[3][2]={{480,280},{240,100},{720,220}};
 for(unsigned i=0;!e && i<3;i++) {
  if(glow) e=sprite(out,cap,dst,atlas+BULLET_GLOW_OFFSET,
   centers[i][0]-6,centers[i][1]-6,12,80,-1,&v);
  if(!e) e=sprite(out,cap,dst,atlas+BULLET_EMITTER_OFFSET+i*512u,
   centers[i][0]-8,centers[i][1]-8,16,0,-1,&v);
 }
 /* On failure the caller cannot accidentally render a truncated frame. */
 if(e) out->count=out->visible=out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 return e;
}
