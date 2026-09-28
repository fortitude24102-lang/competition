#include "gpu.h"
#include "bullet_demo.h"
#include "perf_demo.h"
#include "rgb565.h"
#include "bsp.h"
#include "vexriscv.h"

uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}

static int run_pair(gpu_device *gpu,uint32_t key_dst,uint32_t alpha_dst) {
 gpu_command commands[2]={
  {.op=GPU_OP_COLOR_KEY,.src_addr=GPU_DENSE_ASSETS,.dst_addr=key_dst,
   .src_stride=8,.dst_stride=8,.width_pixels=4,.height_pixels=1,
   .color_key=BULLET_COLOR_KEY},
  {.op=GPU_OP_ALPHA,.src_addr=GPU_DENSE_ASSETS+8u,.dst_addr=alpha_dst,
   .src_stride=4,.dst_stride=4,.width_pixels=2,.height_pixels=1,.alpha=128}
 };
 return perf_render_gpu(gpu,commands,2,10000000u);
}

int main(void) {
 bsp_init();
 gpu_device gpu;
 int e=gpu_init(&gpu,GPU_APB_BASE);
 if(e) { bsp_printf("TEXTURE_CACHE_BOARD_FAIL,init=%d\r\n",e); return e; }
 volatile uint16_t *source=(volatile uint16_t *)(uintptr_t)GPU_DENSE_ASSETS;
 volatile uint16_t *key_dst=(volatile uint16_t *)(uintptr_t)(GPU_FRAMEBUFFER_A+0x1000u);
 volatile uint16_t *alpha_dst=(volatile uint16_t *)(uintptr_t)(GPU_FRAMEBUFFER_A+0x2000u);
 const uint16_t original_key[4]={0x1111,BULLET_COLOR_KEY,0x2222,0x3333};
 const uint16_t changed_key[4]={0xaaaa,0xbbbb,0xcccc,0xdddd};
 const uint16_t original_alpha[2]={0xf800,0x07e0};
 const uint16_t changed_alpha[2]={0x001f,0xffff};
 const uint16_t background[2]={0x0000,0xffff};
 for(unsigned i=0;i<4;i++) source[i]=original_key[i];
 for(unsigned i=0;i<2;i++) source[4+i]=original_alpha[i];
 for(unsigned i=6;i<16;i++) source[i]=(uint16_t)(0x4000u+i);
 gpu_platform_sync();
 e=gpu_texture_cache_load(&gpu,GPU_DENSE_ASSETS,32,10000000u);
 if(e) { bsp_printf("TEXTURE_CACHE_BOARD_FAIL,load=%d\r\n",e); return e; }
 for(unsigned i=0;i<4;i++) source[i]=changed_key[i];
 for(unsigned i=0;i<2;i++) source[4+i]=changed_alpha[i];
 for(unsigned i=0;i<4;i++) key_dst[i]=0x7777;
 for(unsigned i=0;i<2;i++) alpha_dst[i]=background[i];
 gpu_platform_sync();
 e=gpu_clear_perf(&gpu); if(e) return e;
 e=run_pair(&gpu,GPU_FRAMEBUFFER_A+0x1000u,GPU_FRAMEBUFFER_A+0x2000u); if(e) return e;
 gpu_platform_sync();
 const uint16_t cached_key[4]={0x1111,0x7777,0x2222,0x3333};
 for(unsigned i=0;i<4;i++) if(key_dst[i]!=cached_key[i]) {
  bsp_printf("TEXTURE_CACHE_BOARD_FAIL,cached_key=%d,actual=%x\r\n",i,key_dst[i]); return 1;
 }
 for(unsigned i=0;i<2;i++) if(alpha_dst[i]!=rgb565_global_alpha(original_alpha[i],background[i],128)) {
  bsp_printf("TEXTURE_CACHE_BOARD_FAIL,cached_alpha=%d,actual=%x\r\n",i,alpha_dst[i]); return 1;
 }
 gpu_perf_snapshot cached;
 e=gpu_read_perf_snapshot(&gpu,&cached); if(e) return e;
 if(cached.cache_bytes!=12u) {
  bsp_printf("TEXTURE_CACHE_BOARD_FAIL,cache_bytes=%d\r\n",(uint32_t)cached.cache_bytes); return 1;
 }

 e=gpu_texture_cache_invalidate(&gpu); if(e) return e;
 for(unsigned i=0;i<4;i++) key_dst[i]=0x7777;
 for(unsigned i=0;i<2;i++) alpha_dst[i]=background[i];
 gpu_platform_sync();
 e=gpu_clear_perf(&gpu); if(e) return e;
 e=run_pair(&gpu,GPU_FRAMEBUFFER_A+0x1000u,GPU_FRAMEBUFFER_A+0x2000u); if(e) return e;
 gpu_platform_sync();
 for(unsigned i=0;i<4;i++) if(key_dst[i]!=changed_key[i]) {
  bsp_printf("TEXTURE_CACHE_BOARD_FAIL,ddr_key=%d,actual=%x\r\n",i,key_dst[i]); return 1;
 }
 for(unsigned i=0;i<2;i++) if(alpha_dst[i]!=rgb565_global_alpha(changed_alpha[i],background[i],128)) {
  bsp_printf("TEXTURE_CACHE_BOARD_FAIL,ddr_alpha=%d,actual=%x\r\n",i,alpha_dst[i]); return 1;
 }
 gpu_perf_snapshot fallback;
 e=gpu_read_perf_snapshot(&gpu,&fallback); if(e) return e;
 if(fallback.cache_bytes || fallback.read_bytes!=16u) {
  bsp_printf("TEXTURE_CACHE_BOARD_FAIL,fallback_cache=%d,rd=%d\r\n",
   (uint32_t)fallback.cache_bytes,(uint32_t)fallback.read_bytes); return 1;
 }
 bsp_printf("TEXTURE_CACHE_BOARD_PASS,cached=%d,fallback_rd=%d\r\n",
  (uint32_t)cached.cache_bytes,(uint32_t)fallback.read_bytes);
 bsp_printf("TEXTURE_CACHE_BOARD_STOP,result=0,hardware=%d\r\n",gpu.hardware_error);
 return 0;
}
