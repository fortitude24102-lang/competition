/* Board-only Copy oracle; no production firmware or CPU baseline changes. */
#include "perf_demo.h"
#include "framebuffer.h"
#include "bsp.h"
#include "vexriscv.h"
uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
int main(void) {
 bsp_init(); gpu_device gpu;
 int e=gpu_init(&gpu,GPU_APB_BASE); if(e) return e;
 e=gpu_set_qos(&gpu,256,1536,1); if(e) return e;
 static const unsigned widths[]={960,514,3,8},heights[]={468,3,2,3},strides[]={1920,1028,6,24};
 volatile uint16_t *src=(volatile uint16_t *)0x02400ff8u;
 /* Fixture writes run BEFORE the first PRESENT enables scanout. Otherwise
  * CPU's bulk DDR writes confound the DMA-only underflow measurement. */
 for(unsigned i=0;i<960u*468u;i++) src[i]=(uint16_t)(i*73u);
 for(unsigned trial=0;trial<4;trial++) {
  volatile uint16_t *dst=(volatile uint16_t *)(uintptr_t)(0x02600ff4u+trial*0x100000u);
  unsigned words=strides[trial]/2u*heights[trial];
  for(unsigned i=0;i<words;i++) dst[i]=0xa55a;
  dst[-1]=dst[words]=0xa55a;
 }
 gpu_platform_sync();
 framebuffer_pair buffers; framebuffer_init(&buffers);
 gpu_command fill={.op=GPU_OP_FILL,.dst_addr=buffers.back,.dst_stride=GPU_FRAME_STRIDE,
  .width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT,.color=0x18e3};
 e=perf_render_gpu(&gpu,&fill,1,10000000u); if(e) return e;
 e=framebuffer_present(&gpu,&buffers,10000000u); if(e) return e;
 uint64_t warm=gpu_platform_cycles();
 while(gpu_platform_cycles()-warm<BSP_CLINT_HZ/20u) {}
 for(unsigned trial=0;trial<4;trial++) {
  volatile uint16_t *dst=(volatile uint16_t *)(uintptr_t)(0x02600ff4u+trial*0x100000u);
  unsigned words=strides[trial]/2u*heights[trial];
  gpu_platform_sync();
  gpu_perf_snapshot before,after;
  e=gpu_read_perf_snapshot(&gpu,&before); if(e) goto stop;
  gpu_command copy={.op=GPU_OP_COPY,.src_addr=(uint32_t)(uintptr_t)src,.dst_addr=(uint32_t)(uintptr_t)dst,
   .src_stride=strides[trial],.dst_stride=strides[trial],.width_pixels=widths[trial],.height_pixels=heights[trial]};
  uint64_t start=gpu_platform_cycles();
  e=perf_render_gpu(&gpu,&copy,1,10000000u); if(e) goto stop;
  gpu_platform_sync();
  unsigned us=(unsigned)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u));
  e=gpu_read_perf_snapshot(&gpu,&after); if(e) goto stop;
  unsigned mismatch=dst[-1]!=0xa55a || dst[words]!=0xa55a;
  for(unsigned y=0;y<heights[trial];y++) for(unsigned x=0;x<strides[trial]/2u;x++) {
   unsigned i=y*strides[trial]/2u+x;
   uint16_t expected=x<widths[trial]?(uint16_t)(i*73u):0xa55a;
   mismatch+=dst[i]!=expected;
  }
  unsigned bytes=widths[trial]*heights[trial]*2u;
  /* Legacy reads round each row to whole words; flattened odd-width Copy
   * reads only the continuous logical bytes. Both must write exact pixels. */
  unsigned row_reads=((widths[trial]*2u+3u)&~3u)*heights[trial];
  uint64_t reads=after.read_bytes-before.read_bytes;
  unsigned failed=mismatch || after.pixels-before.pixels!=bytes/2u ||
   (reads!=bytes && reads!=row_reads) || after.write_bytes-before.write_bytes!=bytes ||
   after.underflows!=before.underflows || gpu.hardware_error;
  bsp_printf("COPY_BOARD,trial=%d,width=%d,height=%d,stride=%d,us=%d,mismatch=%d,rd=%d,wr=%d,under=%d,failed=%d\r\n",
   trial,widths[trial],heights[trial],strides[trial],us,mismatch,
   (unsigned)(after.read_bytes-before.read_bytes),(unsigned)(after.write_bytes-before.write_bytes),
   (unsigned)(after.underflows-before.underflows),failed);
  if(failed) {e=GPU_DRIVER_HARDWARE; goto stop;}
 }
stop:
 bsp_printf("COPY_BOARD_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error);
 return e;
}
