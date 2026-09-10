#include "assets.h"
#include "framebuffer.h"
#include "game.h"
#include "hud.h"
#include "bsp.h"
#include "gpio.h"
#include "soc.h"
#include "vexriscv.h"
uint64_t gpu_platform_cycles(void) {
 uint32_t hi,lo,again;
 do { __asm__ volatile("rdcycleh %0" : "=r"(hi)); __asm__ volatile("rdcycle %0" : "=r"(lo)); __asm__ volatile("rdcycleh %0" : "=r"(again)); } while(hi!=again);
 return ((uint64_t)hi<<32)|lo;
}
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 soc_write_buffer_flush();
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
static int fill_wait(gpu_device *d,uint32_t dst,uint16_t x,uint16_t y,uint16_t w,uint16_t h,uint16_t color) {
 uint16_t tag; int e=gpu_fill_async(d,dst+(uint32_t)y*1280u+(uint32_t)x*2u,1280,w,h,color,&tag);
 return e?e:gpu_wait_tag(d,tag,10000000u);
}
static int render_frame(gpu_device *d,const game_state *g,uint32_t dst,unsigned fps) {
 int e=fill_wait(d,dst,0,0,640,480,0); if(e) return e; uint16_t tag;
 e=gpu_copy_async(d,gpu_player_asset.address,dst+(uint32_t)g->player.y*1280u+(uint32_t)g->player.x*2u,
  gpu_player_asset.stride_bytes,1280,gpu_player_asset.width,gpu_player_asset.height,&tag);
 if(e || (e=gpu_wait_tag(d,tag,10000000u))) return e;
 for(unsigned i=0;i<GAME_MAX_ENEMIES;i++) if(g->enemies[i].active) {
  const game_object *o=&g->enemies[i]; e=fill_wait(d,dst,o->x,o->y,o->width,o->height,0xf800); if(e) return e;
 }
 for(unsigned i=0;i<GAME_MAX_BULLETS;i++) if(g->bullets[i].active) {
  const game_object *o=&g->bullets[i]; e=fill_wait(d,dst,o->x,o->y,o->width,o->height,0xffff); if(e) return e;
 }
 return hud_draw_fps(d,dst,1280,8,8,fps>999?999:fps,0xffff,2,10000000u);
}
int main(void) {
 bsp_init(); gpu_device d; int e=gpu_init(&d,GPU_APB_BASE);
 if(e) { bsp_printf("GPU unavailable: probe=%d; integration/board test pending\r\n",e); return 1; }
 if(gpu_assets_upload_dense((volatile uint16_t *)(uintptr_t)GPU_DENSE_ASSETS,GPU_ASSET_WORDS)!=GPU_ASSET_WORDS) return 1;
 gpu_platform_sync(); framebuffer_pair buffers; framebuffer_init(&buffers); game_state game; game_init(&game);
 uint64_t previous=gpu_platform_cycles(); unsigned fps=60;
 for(unsigned frame=0;frame<300;frame++) {
  uint32_t keys=~gpio_getInput(SYSTEM_GPIO_0_IO_CTRL);
  unsigned input=(keys&1?GAME_INPUT_LEFT:0)|(keys&2?GAME_INPUT_RIGHT:0)|(keys&4?GAME_INPUT_FIRE:0);
  game_step(&game,input,16); e=render_frame(&d,&game,buffers.back,fps); if(e) break;
  e=framebuffer_present(&d,&buffers,10000000u); if(e) break;
  uint64_t now=gpu_platform_cycles(),elapsed=now-previous; previous=now;
  if(elapsed) fps=(unsigned)(100000000u/elapsed);
 }
 if(e) { bsp_printf("GPU game stopped: result=%d hardware=%d (PRESENT requires lead Day14)\r\n",e,d.hardware_error); return 1; }
 bsp_printf("GPU game PASS: frames=300 objects=%d fps=%d\r\n",game.enemy_count+game.bullet_count+1,fps);
 return 0;
}
