#include "game.h"
void game_init(game_state *g) {
 if(!g) return;
 *g=(game_state){0}; g->player=(game_object){316,440,0,0,8,8,1};
 for(unsigned i=0;i<GAME_MAX_ENEMIES;i++) g->enemies[i]=(game_object){(int16_t)(24+(i%8)*76),(int16_t)(32+(i/8)*32),(int16_t)(i&1?1:-1),0,12,8,1};
 g->enemy_count=GAME_MAX_ENEMIES;
}
void game_step(game_state *g,unsigned input,uint32_t dt) {
 if(!g) return;
 int step=(int)(dt?dt:1);
 if((input&GAME_INPUT_LEFT) && !(input&GAME_INPUT_RIGHT)) g->player.x-=(int16_t)((2*step+15)/16);
 if((input&GAME_INPUT_RIGHT) && !(input&GAME_INPUT_LEFT)) g->player.x+=(int16_t)((2*step+15)/16);
 if(g->player.x<0) g->player.x=0;
 if(g->player.x>(int)(GPU_FRAME_WIDTH-g->player.width)) g->player.x=(int16_t)(GPU_FRAME_WIDTH-g->player.width);
 if((input&GAME_INPUT_FIRE) && g->tick%3==0) for(unsigned i=0;i<GAME_MAX_BULLETS;i++) if(!g->bullets[i].active) {
  g->bullets[i]=(game_object){(int16_t)(g->player.x+3),(int16_t)(g->player.y-4),0,-4,2,4,1}; break;
 }
 for(unsigned i=0;i<GAME_MAX_BULLETS;i++) if(g->bullets[i].active) {
  g->bullets[i].y+=(int16_t)((g->bullets[i].vy*step)/16);
  if(g->bullets[i].y<0) g->bullets[i].active=0;
 }
 for(unsigned i=0;i<GAME_MAX_ENEMIES;i++) if(g->enemies[i].active) {
  game_object *e=&g->enemies[i]; e->x+=(int16_t)((e->vx*step)/16);
  if(e->x<=0) { e->x=0; e->vx=1; }
  if(e->x>=(int)(GPU_FRAME_WIDTH-e->width)) { e->x=(int16_t)(GPU_FRAME_WIDTH-e->width); e->vx=-1; }
 }
 g->bullet_count=0; g->enemy_count=0;
 for(unsigned i=0;i<GAME_MAX_BULLETS;i++) g->bullet_count+=g->bullets[i].active;
 for(unsigned i=0;i<GAME_MAX_ENEMIES;i++) g->enemy_count+=g->enemies[i].active;
 g->tick++;
}
