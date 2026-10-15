#include "bullet_demo.h"
#include <string.h>
/* Q8 direction table: no floating-point/trigonometry in the RV32 frame loop. */
static const int16_t directions[16][2]={
 {256,0},{237,98},{181,181},{98,237},{0,256},{-98,237},{-181,181},{-237,98},
 {-256,0},{-237,-98},{-181,-181},{-98,-237},{0,-256},{98,-237},{181,-181},{237,-98}
};
static const int centers[3][2]={{480,280},{240,100},{720,220}};
static uint32_t waypoint(uint32_t seed,unsigned enemy,uint32_t segment) {
 uint32_t n=seed^((enemy+1u)*UINT32_C(0x9e3779b9))^(segment*UINT32_C(0x85ebca6b));
 n^=n>>16;n*=UINT32_C(0x7feb352d);n^=n>>15;
 return n;
}
int bullet_campaign_valid(const bullet_state *s) {
 if(!s || s->interactive>1 || s->won>1) return 0;
 unsigned alive=0;
 for(unsigned i=0;i<BULLET_ENEMY_COUNT;i++) {
  if(s->enemy_hp[i]>BULLET_ENEMY_HP) return 0;
  alive|=s->enemy_hp[i];
 }
 return !s->interactive?(!alive && !s->won):s->won?(!alive && s->hp):alive!=0;
}
int bullet_enemy_position(const bullet_state *s,unsigned enemy,int *x,int *y) {
 if(!s || enemy>=BULLET_ENEMY_COUNT || !x || !y) return GPU_DRIVER_ARGUMENT;
 *x=centers[enemy][0];*y=centers[enemy][1];
 /* At the initial interpolation endpoint phase=0, segment=0, so the
  * waypoint contributes zero. Avoid computing/hash-dividing it per object. */
 if(!s->interactive || !s->round_tick) return 0;
 static const int minimum_y[]={184,100,156};
 uint32_t segment=s->round_tick/120u,phase=s->round_tick%120u;
 uint32_t next=waypoint(s->seed,enemy,segment);
 int ax=*x,ay=*y;
 if(segment) {
  uint32_t previous=waypoint(s->seed,enemy,segment-1u);
  ax=*x-120+(int)(previous%241u);ay=minimum_y[enemy]+(int)((previous>>16)%97u);
 }
 int bx=*x-120+(int)(next%241u),by=minimum_y[enemy]+(int)((next>>16)%97u);
 *x=ax+(bx-ax)*(int)phase/120;*y=ay+(by-ay)*(int)phase/120;
 return 0;
}
static void spawn(bullet_state *s,unsigned i,int warm) {
 bullet_object *b=&s->objects[i];
 unsigned kind=i%3u;
 unsigned wave=(s->round_tick/60u)&3u;
 unsigned direction=((i/3u)+(s->seed^7u)+(kind==2?s->tick/8u:0u)+wave*4u)&15u;
 unsigned radius=warm ? 16u+((i/48u)%10u)*16u : 0u;
 int cx=kind==1?240:kind==2?720:480,cy=kind==1?100:kind==2?220:280;
 if(s->interactive) (void)bullet_enemy_position(s,kind,&cx,&cy);
 if(kind==1) direction=1u+(i/3u)%5u+((wave&1u)?2u:0u); /* Right/left-biased downward fans. */
 b->x=cx*256+directions[direction][0]*(int)radius;
 b->y=cy*256+directions[direction][1]*(int)radius;
 int speed=6+(int)wave; /* Q8 speed 1.5, 1.75, 2, 2.25 pixels/update. */
 b->vx=(int16_t)(directions[direction][0]*speed/4);
 b->vy=(int16_t)(directions[direction][1]*speed/4);
 b->kind=(uint8_t)kind; b->shape=(uint8_t)((i+wave)%BULLET_SHAPE_COUNT); b->age=0; b->grazed=0;b->path=0;
 if(!s->interactive) return;
 if(!s->enemy_hp[kind]) {b->age=UINT16_MAX;return;}
 b->path=(uint8_t)((i+s->round_tick/180u)%BULLET_PATH_COUNT);
 switch(b->path) {
  case 1: { /* Aim at spawn only: no impossible continuously homing bullets. */
   int dx=s->player_x*256-b->x,dy=s->player_y*256-b->y;
   int ax=dx<0?-dx:dx,ay=dy<0?-dy:dy,m=ax>ay?ax:ay;
   b->vx=(int16_t)(m?dx*512/m:0);b->vy=(int16_t)(m?dy*512/m:512);break;
  }
  case 2:b->vx=(int16_t)(((int)(i%5u)-2)*96+128);b->vy=384;break;
  case 3:b->vx=(int16_t)(directions[(i/3u)&15u][0]*2);b->vy=(int16_t)(directions[(i/3u)&15u][1]*2);break;
  case 4:b->vx=(int16_t)(((int)(i%5u)-2)*96);b->vy=192;break;
  case 5:b->vx=(i&1u)?512:-512;b->vy=384;break;
  default:break; /* Straight radial/fan, inherited Q8 speed. */
 }
}
static int reset(bullet_state *s,unsigned count,uint32_t seed,int interactive) {
 if(!s || !count || count>BULLET_MAX_OBJECTS) return GPU_DRIVER_ARGUMENT;
 memset(s,0,sizeof *s); s->count=count; s->seed=seed;
 s->player_x=480; s->player_y=480; s->hp=BULLET_START_HP;
 s->interactive=(uint8_t)interactive;
 if(interactive)for(unsigned i=0;i<BULLET_ENEMY_COUNT;i++)s->enemy_hp[i]=BULLET_ENEMY_HP;
 for(unsigned i=0;i<count;i++) spawn(s,i,1);
 return 0;
}
int bullet_reset(bullet_state *s,unsigned count,uint32_t seed) {
 return reset(s,count,seed,0);
}
int bullet_reset_player(bullet_state *s,unsigned count,uint32_t seed) {
 /* Set the final mode BEFORE spawning: the previous noninteractive pass was
  * immediately overwritten and doubled work on every interactive restart. */
 return reset(s,count,seed,1);
}
static int pixel_coordinate(int32_t q8);
static void add_score(bullet_state *s,uint32_t points) {
 s->score=UINT32_MAX-s->score<points?UINT32_MAX:s->score+points;
}
static int step(bullet_state *s,int manual,int player_x,int player_y,const bullet_state *initial) {
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || s->hp>BULLET_START_HP || !bullet_campaign_valid(s) ||
    s->invulnerable>BULLET_PROTECTION_TICKS ||
    (!s->hp && (!s->game_over_ticks || s->game_over_ticks>BULLET_RESTART_TICKS)))
  return GPU_DRIVER_ARGUMENT;
 if(manual && (player_x<8 || player_x>952 || player_y<80 || player_y>532))
  return GPU_DRIVER_ARGUMENT;
 for(unsigned i=0;i<s->count;i++) if(s->objects[i].kind>(manual?3:2) ||
  s->objects[i].shape>=BULLET_SHAPE_COUNT || (s->interactive && s->objects[i].path>=BULLET_PATH_COUNT)) return GPU_DRIVER_ARGUMENT;
 ++s->tick;
 if(manual && s->won) return 0;
 if(!s->hp) {
  if(!--s->game_over_ticks) {
   uint32_t tick=s->tick;
   if(manual && s->interactive && initial && initial!=s && initial->interactive &&
      initial->count==s->count && initial->seed==s->seed && !initial->tick && !initial->round_tick &&
      initial->hp==BULLET_START_HP && !initial->won) {
    *s=*initial;s->tick=tick;return 0;
   }
   int e=manual && s->interactive?bullet_reset_player(s,s->count,s->seed):bullet_reset(s,s->count,s->seed);
   s->tick=tick; return e;
  }
  return 0;
 }
 ++s->round_tick;
 int phase=(int)(s->round_tick%240u);
 s->player_x=manual?player_x:480+3*(phase<60?phase:phase<180?120-phase:phase-240);
 s->player_y=manual?player_y:480;
 int protected=s->invulnerable!=0;
 if(protected) --s->invulnerable;
 if(!(s->round_tick%30u)) add_score(s,1);
 for(unsigned i=0;i<s->count;i++) {
  bullet_object *b=&s->objects[i];
  if(b->kind==3) {
   if(b->age==UINT16_MAX) continue;
   b->x+=b->vx; b->y+=b->vy; ++b->age;
   int bx=pixel_coordinate(b->x)+4,by=pixel_coordinate(b->y)+4;
   if(bx<0 || bx>=960 || by<72 || by>=540) { b->age=UINT16_MAX; continue; }
   for(unsigned enemy=0;enemy<3;enemy++) {
    if(s->interactive && !s->enemy_hp[enemy]) continue;
    int tx,ty;(void)bullet_enemy_position(s,enemy,&tx,&ty);
    int dx=bx-tx,dy=by-ty;
    if(dx>=-10 && dx<=10 && dy>=-10 && dy<=10) {
     b->age=UINT16_MAX; add_score(s,25);
     if(s->interactive && !--s->enemy_hp[enemy]) {
      add_score(s,200);
      s->won=(uint8_t)(!s->enemy_hp[0] && !s->enemy_hp[1] && !s->enemy_hp[2]);
     }
     break;
    }
   }
   if(s->won) break;
   continue;
  }
  if(s->interactive && b->age==UINT16_MAX) continue;
  if(b->x<=-8*256 || b->x>=960*256 || b->y<64*256 || b->y>=540*256 ||
     b->age>=240u+i%120u) { spawn(s,i,0); continue; }
  if(s->interactive) switch(b->path) {
   case 2:b->vx=(int16_t)(((int)(i%5u)-2)*96+directions[(b->age/4u)&15u][0]/2);break;
   case 3: {unsigned angle=(i/3u+b->age/12u)&15u;
    b->vx=(int16_t)(directions[angle][0]*2);b->vy=(int16_t)(directions[angle][1]*2);break;}
   case 4:if(!(b->age%8u) && b->vy<896) b->vy+=32;break;
   default:break;
  }
  b->x+=b->vx; b->y+=b->vy; ++b->age;
  if(s->interactive && b->path==5) {
   if(b->x<0) {b->x=0;b->vx=(int16_t)-b->vx;}
   if(b->x>952*256) {b->x=952*256;b->vx=(int16_t)-b->vx;}
  }
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
int bullet_step(bullet_state *s) { return step(s,0,0,0,NULL); }
int bullet_step_player(bullet_state *s,int x,int y) { return step(s,1,x,y,NULL); }
int bullet_step_player_cached(bullet_state *s,int x,int y,const bullet_state *initial) {
 return step(s,1,x,y,initial);
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
static int victory_banner(bullet_stream *out,unsigned cap,uint32_t dst) {
 /* Vertical runs: only 29 text rectangles, no new texture or font resource.
  * With panel/player/background this fits even BULLET_OBJECT_CAPACITY=32. */
 static const uint8_t columns[4][5]={{127,32,24,32,127},{65,65,127,65,65},
  {127,6,24,96,127},{127,9,25,41,70}}; /* W I N R */
 gpu_command c={.op=GPU_OP_FILL,.dst_addr=dst+176u*GPU_FRAME_STRIDE+360u*2u,
  .dst_stride=GPU_FRAME_STRIDE,.width_pixels=240,.height_pixels=156,.color=0x000b};
 int e=append(out,cap,&c);
 for(unsigned glyph=0;!e && glyph<4;glyph++) {
  unsigned scale=glyph==3?3u:8u,left=glyph==3?472u:404u+glyph*56u,top=glyph==3?282u:208u;
  c.color=glyph==3?0xffe0:0x07e0;c.width_pixels=(uint16_t)scale;
  for(unsigned x=0;!e && x<5;x++) for(unsigned y=0;!e && y<7;) {
   if(!(columns[glyph][x]&(1u<<y))) {++y;continue;}
   unsigned start=y;
   do {++y;} while(y<7 && (columns[glyph][x]&(1u<<y)));
   c.dst_addr=dst+(top+start*scale)*GPU_FRAME_STRIDE+(left+x*scale)*2u;
   c.height_pixels=(uint16_t)((y-start)*scale);e=append(out,cap,&c);
  }
 }
 return e;
}
static int build_frame(const bullet_state *s,uint32_t dst,int network,int glow,unsigned cap,bullet_stream *out,int manual) {
 if(!out) return GPU_DRIVER_ARGUMENT;
 out->count=out->visible=out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || !cap || cap>BULLET_MAX_COMMANDS || !bullet_campaign_valid(s) ||
    (network!=0 && network!=1) ||
    (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B)) return GPU_DRIVER_ARGUMENT;
 uint32_t atlas=network?BULLET_ATLAS_ADDR:BULLET_LOCAL_ATLAS;
 gpu_command bg={.op=GPU_OP_COPY,.src_addr=network?BULLET_BACKGROUND_ADDR:BULLET_LOCAL_BACKGROUND,.dst_addr=dst,
  .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT};
 int e=append(out,cap,&bg),v;
 int victory=manual && s->won;
 /* Halos precede keyed cores, so blending does not dull the bullet faces. */
 for(unsigned i=0;!e && !victory && glow && i<s->count;i+=8u) {
  const bullet_object *b=&s->objects[i];
  if(manual && (b->kind==3 || s->interactive) && b->age==UINT16_MAX) continue;
  e=sprite(out,cap,dst,atlas+BULLET_GLOW_OFFSET,
   pixel_coordinate(b->x)-2,pixel_coordinate(b->y)-2,12,64+(int)(s->tick%16u)*4,-1,&v);
 }
 for(unsigned i=0;!e && !victory && i<s->count;i++) {
  const bullet_object *b=&s->objects[i];
  if(b->kind>(manual?3:2) || b->shape>=BULLET_SHAPE_COUNT) { e=GPU_DRIVER_ARGUMENT; break; }
  if((b->kind==3 || (manual && s->interactive)) && b->age==UINT16_MAX) continue;
  e=sprite(out,cap,dst,atlas+b->shape*128u,
   pixel_coordinate(b->x),pixel_coordinate(b->y),8,0,b->shape,&v);
  if(!e) out->visible+=(unsigned)v;
 }
 if(!e && glow && s->hp) e=sprite(out,cap,dst,atlas+BULLET_GLOW_OFFSET,
  s->player_x-6,s->player_y-6,12,s->invulnerable?192:64,-1,&v);
 if(!e && s->hp) e=sprite(out,cap,dst,atlas+BULLET_PLAYER_OFFSET,s->player_x-8,s->player_y-8,16,0,-1,&v);
 unsigned warning=s->round_tick%60u;
 int emitter_alpha=s->hp && warning>=44u?80+(int)(warning-43u)*8:80;
 for(unsigned i=0;!e && i<3;i++) {
  if(manual && s->interactive && !s->enemy_hp[i]) continue;
  int cx=centers[i][0],cy=centers[i][1];
  if(manual) (void)bullet_enemy_position(s,i,&cx,&cy);
  if(glow) e=sprite(out,cap,dst,atlas+BULLET_GLOW_OFFSET,
   cx-6,cy-6,12,emitter_alpha,-1,&v);
  if(!e) e=sprite(out,cap,dst,atlas+BULLET_EMITTER_OFFSET+i*512u,
   cx-8,cy-8,16,0,-1,&v);
 }
 if(!e && victory) e=victory_banner(out,cap,dst);
 /* On failure the caller cannot accidentally render a truncated frame. */
 if(e) out->count=out->visible=out->scene_pixels=out->alpha_commands=out->alpha_pixels=0;
 return e;
}
int bullet_build_frame(const bullet_state *s,uint32_t dst,int network,int glow,unsigned cap,bullet_stream *out) {
 return build_frame(s,dst,network,glow,cap,out,0);
}
int bullet_build_frame_player(const bullet_state *s,uint32_t dst,int network,int glow,unsigned cap,bullet_stream *out) {
 return build_frame(s,dst,network,glow,cap,out,1);
}
int bullet_clip_background_for_hud(bullet_stream *s,unsigned hud_height) {
 if(!s || !s->count || hud_height>=GPU_FRAME_HEIGHT) return GPU_DRIVER_ARGUMENT;
 const gpu_command *c=&s->commands[0];
 uint64_t bytes=(uint64_t)GPU_FRAME_STRIDE*GPU_FRAME_HEIGHT;
 if(c->op!=GPU_OP_COPY || c->width_pixels!=GPU_FRAME_WIDTH ||
    c->height_pixels!=GPU_FRAME_HEIGHT || c->src_stride!=GPU_FRAME_STRIDE ||
    c->dst_stride!=GPU_FRAME_STRIDE ||
    (c->dst_addr!=GPU_FRAMEBUFFER_A && c->dst_addr!=GPU_FRAMEBUFFER_B) ||
    (uint64_t)c->src_addr+bytes>GPU_DDR_END_EXCLUSIVE ||
    s->scene_pixels<GPU_FRAME_WIDTH*GPU_FRAME_HEIGHT) return GPU_DRIVER_ARGUMENT;
 uint32_t skip=hud_height*GPU_FRAME_STRIDE;
 s->commands[0].src_addr+=skip;
 s->commands[0].dst_addr+=skip;
 s->commands[0].height_pixels=(uint16_t)(GPU_FRAME_HEIGHT-hud_height);
 s->scene_pixels-=GPU_FRAME_WIDTH*hud_height;
 return 0;
}
