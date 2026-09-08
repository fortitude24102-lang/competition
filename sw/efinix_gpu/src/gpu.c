#include "gpu.h"
#ifdef GPU_TEST_BACKEND
uint32_t gpu_io_read(uintptr_t a);
void gpu_io_write(uintptr_t a,uint32_t v);
void gpu_io_fence(void);
#else
static uint32_t gpu_io_read(uintptr_t a) { return *(volatile uint32_t *)a; }
static void gpu_io_write(uintptr_t a,uint32_t v) { *(volatile uint32_t *)a=v; }
static void gpu_io_fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
#endif
static uint32_t rd(gpu_device *d,unsigned r) { return gpu_io_read(d->base+r); }
static void wr(gpu_device *d,unsigned r,uint32_t v) { gpu_io_write(d->base+r,v); }
int gpu_init(gpu_device *d,uintptr_t base) {
 if (!d || (base&3)) return GPU_DRIVER_ARGUMENT;
 *d=(gpu_device){.base=base};
 if(rd(d,GPU_REG_ID)!=GPU_ID_VALUE) return GPU_DRIVER_ID;
 if(rd(d,GPU_REG_VERSION)!=GPU_VERSION_VALUE) return GPU_DRIVER_VERSION;
 d->ready=1; return 0;
}
int gpu_fill_async(gpu_device *d,uint32_t dst,uint32_t stride,uint16_t w,uint16_t h,uint16_t color,uint16_t *tag) {
 if(!d || !d->ready || !tag) return GPU_DRIVER_ARGUMENT;
 if(d->pending) return GPU_DRIVER_BUSY;
 uint32_t status=rd(d,GPU_REG_STATUS);
 if(status&GPU_STATUS_FULL) return GPU_DRIVER_FULL;
 if((status&GPU_STATUS_BUSY) || !(status&GPU_STATUS_EMPTY)) return GPU_DRIVER_BUSY;
 d->hardware_error=rd(d,GPU_REG_ERROR)&GPU_ERROR_MASK;
 if(d->hardware_error) return GPU_DRIVER_HARDWARE;
 if(!w || !h) return GPU_ERROR_ZERO_SIZE;
 if((dst|stride)&1) return GPU_ERROR_MISALIGNED_ADDRESS;
 if(stride<(uint32_t)w*2) return GPU_ERROR_STRIDE_TOO_SMALL;
 if(dst<GPU_FRAMEBUFFER_A || (uint64_t)dst+(uint64_t)(h-1)*stride+w*2u>GPU_DDR_END_EXCLUSIVE) return GPU_ERROR_ADDRESS_RANGE;
 /* ponytail: one in-flight avoids absent completion history; queue later with hardware completion FIFO. */
 *tag=(uint16_t)(rd(d,GPU_REG_LAST_DONE)+1u);
 wr(d,GPU_REG_OP,GPU_OP_FILL); wr(d,GPU_REG_SRC_ADDR,0); wr(d,GPU_REG_DST_ADDR,dst);
 wr(d,GPU_REG_SIZE,gpu_pack_size(w,h)); wr(d,GPU_REG_SRC_STRIDE,0); wr(d,GPU_REG_DST_STRIDE,stride);
 wr(d,GPU_REG_COLOR_KEY,color); wr(d,GPU_REG_ALPHA_FLAGS,0); wr(d,GPU_REG_TAG,*tag);
 d->pending_tag=*tag; d->pending=1;
 gpu_io_fence(); wr(d,GPU_REG_CONTROL,GPU_CONTROL_SUBMIT); gpu_io_fence(); return 0;
}
int gpu_wait_tag(gpu_device *d,uint16_t tag,uint32_t poll_limit) {
 if(!d || !d->ready) return GPU_DRIVER_ARGUMENT;
 if(!d->pending || d->pending_tag!=tag) return GPU_DRIVER_TAG;
 while(poll_limit--) {
  d->hardware_error=rd(d,GPU_REG_ERROR)&GPU_ERROR_MASK;
  if(d->hardware_error) return GPU_DRIVER_HARDWARE;
  if((rd(d,GPU_REG_LAST_DONE)&GPU_LAST_DONE_MASK)==tag) {
   uint32_t s=rd(d,GPU_REG_STATUS);
   if(!(s&GPU_STATUS_BUSY) && (s&GPU_STATUS_EMPTY)) {
    gpu_io_fence(); d->hardware_error=rd(d,GPU_REG_ERROR)&GPU_ERROR_MASK;
    if(d->hardware_error) return GPU_DRIVER_HARDWARE;
    d->pending=0; return 0;
   }
  }
 }
 return GPU_DRIVER_TIMEOUT;
}
