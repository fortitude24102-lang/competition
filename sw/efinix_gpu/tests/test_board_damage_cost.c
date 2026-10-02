/* Measure on the retained legacy word-Copy backend, with scanout active.
 * No CPU optimization, no Flash. Initialize network assets BEFORE PRESENT. */
#define main reference_main
#include "../src/main.c"
#undef main
#include "gpu_damage.h"
static gpu_command copies[64];
int main(void) {
 bsp_init(); gpu_device gpu; int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 int net=bullet_prepare_assets(GPU_APB_BASE,1);
 bsp_printf("DAMAGE_COST_START,network_result=%d,hz=%d\r\n",net,BSP_CLINT_HZ);
 if(net) return net;
 e=gpu_set_qos(&gpu,256,1536,1); if(e) return e;
 framebuffer_pair buffers; framebuffer_init(&buffers);
 copies[0]=(gpu_command){.op=GPU_OP_FILL,.dst_addr=buffers.back,.dst_stride=1920,
  .width_pixels=960,.height_pixels=540,.color=0x18e3};
 e=perf_render_gpu(&gpu,copies,1,10000000u); if(e) goto stop;
 e=framebuffer_present(&gpu,&buffers,10000000u); if(e) goto stop;
 static const unsigned widths[]={16,32,64,256,960,960,16,32,16};
 static const unsigned heights[]={16,32,64,32,16,468,16,32,1};
 static const unsigned counts[]={1,1,1,1,1,1,64,16,64};
 gpu_damage_cost unit={0,0,256};
 for(unsigned k=0;k<9;k++) {
  for(unsigned i=0;i<counts[k];i++) copies[i]=(gpu_command){.op=GPU_OP_COPY,
   .src_addr=BULLET_BACKGROUND_ADDR+72*1920,.dst_addr=buffers.back+72*1920,
   .src_stride=1920,.dst_stride=1920,.width_pixels=widths[k],.height_pixels=heights[k]};
  uint32_t bytes,bursts; (void)gpu_damage_copy_cost(copies,&unit,&bytes,&bursts);
  for(unsigned trial=0;trial<5;trial++) {
   gpu_perf_snapshot a,b; e=gpu_read_perf_snapshot(&gpu,&a); if(e) goto stop;
   gpu_platform_sync(); uint64_t start=gpu_platform_cycles();
   e=perf_render_gpu(&gpu,copies,counts[k],10000000u); if(e) goto stop;
   gpu_platform_sync(); uint64_t ticks=gpu_platform_cycles()-start;
   e=gpu_read_perf_snapshot(&gpu,&b); if(e) goto stop;
   unsigned under=(unsigned)(b.underflows-a.underflows);
   bsp_printf("DAMAGE_COST,k=%d,trial=%d,w=%d,h=%d,count=%d,ticks=%d,busy=%d,bytes=%d,bursts=%d,under=%d,error=%d\r\n",
    k,trial,widths[k],heights[k],counts[k],(unsigned)ticks,(unsigned)(b.cycles-a.cycles),
    bytes*counts[k],bursts*counts[k],under,gpu.hardware_error);
   if(under || gpu.hardware_error) { e=GPU_DRIVER_HARDWARE; goto stop; }
  }
 }
stop:
 bsp_printf("DAMAGE_COST_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error); return e;
}
