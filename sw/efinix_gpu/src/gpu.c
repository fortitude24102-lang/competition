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
static int begin_submit(gpu_device *d,uint16_t *tag) {
 if(!d || !d->ready || !tag) return GPU_DRIVER_ARGUMENT;
 if(d->pending) return GPU_DRIVER_BUSY;
 uint32_t status=rd(d,GPU_REG_STATUS);
 if(status&GPU_STATUS_FULL) return GPU_DRIVER_FULL;
 if((status&GPU_STATUS_BUSY) || !(status&GPU_STATUS_EMPTY)) return GPU_DRIVER_BUSY;
 d->hardware_error=rd(d,GPU_REG_ERROR)&GPU_ERROR_MASK;
 if(d->hardware_error) return GPU_DRIVER_HARDWARE;
 *tag=(uint16_t)(rd(d,GPU_REG_LAST_DONE)+1u); return 0;
}
static void submit(gpu_device *d,const gpu_command *c,uint16_t tag) {
 wr(d,GPU_REG_OP,c->op); wr(d,GPU_REG_SRC_ADDR,c->src_addr); wr(d,GPU_REG_DST_ADDR,c->dst_addr);
 wr(d,GPU_REG_SIZE,gpu_pack_size(c->width_pixels,c->height_pixels));
 wr(d,GPU_REG_SRC_STRIDE,c->src_stride); wr(d,GPU_REG_DST_STRIDE,c->dst_stride);
 wr(d,GPU_REG_COLOR_KEY,gpu_pack_color_key(c->color,c->color_key));
 wr(d,GPU_REG_ALPHA_FLAGS,gpu_pack_alpha_flags(c->alpha,c->flags)); wr(d,GPU_REG_TAG,tag);
 d->pending_tag=tag; d->pending=1;
 gpu_io_fence(); wr(d,GPU_REG_CONTROL,GPU_CONTROL_SUBMIT); gpu_io_fence();
}
int gpu_init(gpu_device *d,uintptr_t base) {
 if (!d || (base&3)) return GPU_DRIVER_ARGUMENT;
 *d=(gpu_device){.base=base};
 if(rd(d,GPU_REG_ID)!=GPU_ID_VALUE) return GPU_DRIVER_ID;
 if(rd(d,GPU_REG_VERSION)!=GPU_VERSION_VALUE) return GPU_DRIVER_VERSION;
 d->ready=1; return 0;
}
int gpu_fill_async(gpu_device *d,uint32_t dst,uint32_t stride,uint16_t w,uint16_t h,uint16_t color,uint16_t *tag) {
 uint16_t next; int e=begin_submit(d,&next); if(e) return e;
 if(!w || !h) return GPU_ERROR_ZERO_SIZE;
 if((dst|stride)&1) return GPU_ERROR_MISALIGNED_ADDRESS;
 if(stride<(uint32_t)w*2) return GPU_ERROR_STRIDE_TOO_SMALL;
 if(dst<GPU_FRAMEBUFFER_A || (uint64_t)dst+(uint64_t)(h-1)*stride+w*2u>GPU_DDR_END_EXCLUSIVE) return GPU_ERROR_ADDRESS_RANGE;
 /* ponytail: one in-flight avoids absent completion history; queue later with hardware completion FIFO. */
 gpu_command c={.op=GPU_OP_FILL,.dst_addr=dst,.dst_stride=stride,.width_pixels=w,.height_pixels=h,.color=color};
 *tag=next; submit(d,&c,next); return 0;
}
int gpu_copy_async(gpu_device *d,uint32_t src,uint32_t dst,uint32_t src_stride,uint32_t dst_stride,uint16_t w,uint16_t h,uint16_t *tag) {
 uint16_t next; int e=begin_submit(d,&next); if(e) return e;
 if(!w || !h) return GPU_ERROR_ZERO_SIZE;
 if((src|dst|src_stride|dst_stride)&1) return GPU_ERROR_MISALIGNED_ADDRESS;
 uint32_t row=(uint32_t)w*2u;
 if(src_stride<row || dst_stride<row) return GPU_ERROR_STRIDE_TOO_SMALL;
 uint64_t src_end=(uint64_t)src+(uint64_t)(h-1)*src_stride+row;
 uint64_t dst_end=(uint64_t)dst+(uint64_t)(h-1)*dst_stride+row;
 if(src<GPU_FRAMEBUFFER_A || dst<GPU_FRAMEBUFFER_A || src_end>GPU_DDR_END_EXCLUSIVE || dst_end>GPU_DDR_END_EXCLUSIVE) return GPU_ERROR_ADDRESS_RANGE;
 if((uint64_t)src<dst_end && (uint64_t)dst<src_end) return GPU_ERROR_OVERLAPPING_COPY;
 gpu_command c={.op=GPU_OP_COPY,.src_addr=src,.dst_addr=dst,.src_stride=src_stride,.dst_stride=dst_stride,.width_pixels=w,.height_pixels=h};
 *tag=next; submit(d,&c,next); return 0;
}
int gpu_present_async(gpu_device *d,uint32_t back_buffer,uint16_t *tag) {
 uint16_t next; int e=begin_submit(d,&next); if(e) return e;
 if(back_buffer!=GPU_FRAMEBUFFER_A && back_buffer!=GPU_FRAMEBUFFER_B) return GPU_ERROR_ADDRESS_RANGE;
 /* The shared validator checks every destination command as a non-empty
    surface.  PRESENT therefore carries the smallest legal geometry even
    though the swap controller only consumes dst_addr. */
 gpu_command c={.op=GPU_OP_PRESENT,.dst_addr=back_buffer,
                .dst_stride=2,.width_pixels=1,.height_pixels=1};
 *tag=next; submit(d,&c,next); return 0;
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
