#include "benchmark.h"
#include "bsp.h"
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
int main(void) {
 bsp_init(); gpu_device d; int e=gpu_init(&d,GPU_APB_BASE);
 if(e) { bsp_printf("GPU unavailable: probe=%d; integration/board test pending\r\n",e); return 1; }
 golden_surface cpu={(uint8_t *)GPU_FRAMEBUFFER_B,GPU_FRAME_BYTES,640,480,1280};
 golden_surface gpu={(uint8_t *)GPU_FRAMEBUFFER_A,GPU_FRAME_BYTES,640,480,1280};
 gpu_benchmark_result r; e=gpu_benchmark(&d,&cpu,&gpu,GPU_FRAMEBUFFER_A,10000000,&r);
 if(e) { bsp_printf("GPU test failed: result=%d hardware=%d\r\n",e,d.hardware_error); return 1; }
 bsp_printf("scene=fill4 pixels=%d CPU cycles hi:lo=%x:%x GPU submit+wait CPU cycles=%x:%x CRC=%x/%x\r\n",r.pixels,(uint32_t)(r.cpu_cycles>>32),(uint32_t)r.cpu_cycles,(uint32_t)(r.gpu_cycles>>32),(uint32_t)r.gpu_cycles,r.cpu_crc,r.gpu_crc);
 return 0;
}
