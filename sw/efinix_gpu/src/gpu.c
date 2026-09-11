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

static int surface(uint32_t address,uint32_t stride,uint16_t width,uint16_t height) {
 if(!width || !height) return GPU_ERROR_ZERO_SIZE;
 if((address|stride)&1u) return GPU_ERROR_MISALIGNED_ADDRESS;
 uint32_t row=(uint32_t)width*2u;
 if(stride<row) return GPU_ERROR_STRIDE_TOO_SMALL;
 uint64_t end=(uint64_t)address+(uint64_t)(height-1u)*stride+row;
 if(address<GPU_FRAMEBUFFER_A || end>GPU_DDR_END_EXCLUSIVE) return GPU_ERROR_ADDRESS_RANGE;
 return 0;
}

static int validate(const gpu_command *c) {
 if(!c || c->flags) return GPU_DRIVER_ARGUMENT;
 int e;
 if(c->op==GPU_OP_FILL) return surface(c->dst_addr,c->dst_stride,c->width_pixels,c->height_pixels);
 if(c->op==GPU_OP_PRESENT)
  return c->dst_addr==GPU_FRAMEBUFFER_A || c->dst_addr==GPU_FRAMEBUFFER_B ? 0 : GPU_ERROR_ADDRESS_RANGE;
 if(c->op!=GPU_OP_COPY && c->op!=GPU_OP_COLOR_KEY && c->op!=GPU_OP_ALPHA)
  return GPU_ERROR_INVALID_OPCODE;
 e=surface(c->src_addr,c->src_stride,c->width_pixels,c->height_pixels); if(e) return e;
 e=surface(c->dst_addr,c->dst_stride,c->width_pixels,c->height_pixels); if(e) return e;
 uint32_t row=(uint32_t)c->width_pixels*2u;
 uint64_t src_end=(uint64_t)c->src_addr+(uint64_t)(c->height_pixels-1u)*c->src_stride+row;
 uint64_t dst_end=(uint64_t)c->dst_addr+(uint64_t)(c->height_pixels-1u)*c->dst_stride+row;
 if((uint64_t)c->src_addr<dst_end && (uint64_t)c->dst_addr<src_end)
  return GPU_ERROR_OVERLAPPING_COPY;
 return 0;
}

static int refresh(gpu_device *d) {
 uint16_t done=0,confirm=0;
 uint8_t error=0;
 for(unsigned attempt=0;attempt<3;attempt++) {
  done=(uint16_t)(rd(d,GPU_REG_LAST_DONE)&GPU_LAST_DONE_MASK);
  error=(uint8_t)(rd(d,GPU_REG_ERROR)&GPU_ERROR_MASK);
  confirm=(uint16_t)(rd(d,GPU_REG_LAST_DONE)&GPU_LAST_DONE_MASK);
  if(done==confirm) break;
  if(attempt==2) return GPU_DRIVER_TAG;
 }
 uint16_t advance=(uint16_t)(done-d->last_done);
 if(advance) {
  /* RTL keeps the first nonzero error sticky, so an in-order LAST_DONE jump
     safely retires every earlier tag in the same batch. */
  if(advance>d->outstanding) return GPU_DRIVER_TAG;
  d->hardware_error=error;
  if(d->hardware_error) return GPU_DRIVER_HARDWARE;
  d->outstanding=(uint8_t)(d->outstanding-advance);
  d->last_done=done;
  d->pending=d->outstanding!=0;
 }
 else {
  d->hardware_error=error;
  if(d->hardware_error) return GPU_DRIVER_HARDWARE;
 }
 return 0;
}

static void write_command(gpu_device *d,const gpu_command *c,uint16_t tag) {
 wr(d,GPU_REG_OP,c->op); wr(d,GPU_REG_SRC_ADDR,c->src_addr); wr(d,GPU_REG_DST_ADDR,c->dst_addr);
 wr(d,GPU_REG_SIZE,gpu_pack_size(c->width_pixels,c->height_pixels));
 wr(d,GPU_REG_SRC_STRIDE,c->src_stride); wr(d,GPU_REG_DST_STRIDE,c->dst_stride);
 wr(d,GPU_REG_COLOR_KEY,gpu_pack_color_key(c->color,c->color_key));
 wr(d,GPU_REG_ALPHA_FLAGS,gpu_pack_alpha_flags(c->alpha,c->flags)); wr(d,GPU_REG_TAG,tag);
 gpu_io_fence(); wr(d,GPU_REG_CONTROL,GPU_CONTROL_SUBMIT); gpu_io_fence();
}

int gpu_init(gpu_device *d,uintptr_t base) {
 if(!d || (base&3u)) return GPU_DRIVER_ARGUMENT;
 *d=(gpu_device){.base=base};
 if(rd(d,GPU_REG_ID)!=GPU_ID_VALUE) return GPU_DRIVER_ID;
 if(rd(d,GPU_REG_VERSION)!=GPU_VERSION_VALUE) return GPU_DRIVER_VERSION;
 d->last_done=(uint16_t)(rd(d,GPU_REG_LAST_DONE)&GPU_LAST_DONE_MASK);
 d->next_tag=(uint16_t)(d->last_done+1u);
 d->first_tag=d->next_tag;
 d->ready=1;
 return 0;
}

int gpu_try_submit(gpu_device *d,const gpu_command *c,uint16_t *tag) {
 if(!d || !d->ready || !tag) return GPU_DRIVER_ARGUMENT;
 int e=validate(c); if(e) return e;
 d->hardware_error=(uint8_t)(rd(d,GPU_REG_ERROR)&GPU_ERROR_MASK);
 if(d->hardware_error) return GPU_DRIVER_HARDWARE;
 uint32_t status=rd(d,GPU_REG_STATUS);
 uint8_t level=(uint8_t)(status&GPU_STATUS_QUEUE_LEVEL_MASK);
 if(level>d->queue_high_watermark) d->queue_high_watermark=level;
 if((status&GPU_STATUS_FULL) || d->outstanding>=GPU_COMMAND_QUEUE_DEPTH) return GPU_DRIVER_AGAIN;
 uint16_t assigned=d->next_tag++;
 write_command(d,c,assigned);
 ++d->submitted_count;
 ++d->outstanding;
 d->pending=1;
 d->pending_tag=assigned;
 if(d->outstanding>d->queue_high_watermark) d->queue_high_watermark=d->outstanding;
 *tag=assigned;
 return 0;
}

int gpu_submit(gpu_device *d,const gpu_command *c,uint32_t poll_limit,uint16_t *tag) {
 while(1) {
  int e=gpu_try_submit(d,c,tag);
  if(e!=GPU_DRIVER_AGAIN) return e;
  if(!poll_limit--) return GPU_DRIVER_TIMEOUT;
  e=refresh(d); if(e) return e;
 }
}

static int known_tag(const gpu_device *d,uint16_t tag) {
 uint16_t offset=(uint16_t)(tag-d->first_tag);
 return d->submitted_count && (d->submitted_count>UINT16_MAX || offset<d->submitted_count);
}

int gpu_poll(gpu_device *d,uint16_t tag) {
 if(!d || !d->ready) return GPU_DRIVER_ARGUMENT;
 if(!known_tag(d,tag)) return GPU_DRIVER_TAG;
 int e=refresh(d); if(e) return e;
 uint16_t first_pending=(uint16_t)(d->next_tag-d->outstanding);
 if(d->outstanding && (uint16_t)(tag-first_pending)<d->outstanding) return GPU_POLL_PENDING;
 return 0;
}

int gpu_fill_async(gpu_device *d,uint32_t dst,uint32_t stride,uint16_t w,uint16_t h,uint16_t color,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_FILL,.dst_addr=dst,.dst_stride=stride,.width_pixels=w,.height_pixels=h,.color=color};
 return gpu_try_submit(d,&c,tag);
}
int gpu_copy_async(gpu_device *d,uint32_t src,uint32_t dst,uint32_t ss,uint32_t ds,uint16_t w,uint16_t h,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_COPY,.src_addr=src,.dst_addr=dst,.src_stride=ss,.dst_stride=ds,.width_pixels=w,.height_pixels=h};
 return gpu_try_submit(d,&c,tag);
}
int gpu_color_key_async(gpu_device *d,uint32_t src,uint32_t dst,uint32_t ss,uint32_t ds,uint16_t w,uint16_t h,uint16_t key,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_COLOR_KEY,.src_addr=src,.dst_addr=dst,.src_stride=ss,.dst_stride=ds,.width_pixels=w,.height_pixels=h,.color_key=key};
 return gpu_try_submit(d,&c,tag);
}
int gpu_alpha_async(gpu_device *d,uint32_t src,uint32_t dst,uint32_t ss,uint32_t ds,uint16_t w,uint16_t h,uint8_t alpha,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_ALPHA,.src_addr=src,.dst_addr=dst,.src_stride=ss,.dst_stride=ds,.width_pixels=w,.height_pixels=h,.alpha=alpha};
 return gpu_try_submit(d,&c,tag);
}
int gpu_present_async(gpu_device *d,uint32_t back,uint16_t *tag) {
 gpu_command c={.op=GPU_OP_PRESENT,.dst_addr=back,.dst_stride=2,.width_pixels=1,.height_pixels=1};
 return gpu_try_submit(d,&c,tag);
}
int gpu_wait_tag(gpu_device *d,uint16_t tag,uint32_t poll_limit) {
 if(!d || !d->ready) return GPU_DRIVER_ARGUMENT;
 if(!known_tag(d,tag)) return GPU_DRIVER_TAG;
 while(poll_limit--) {
  int e=gpu_poll(d,tag);
  if(e!=GPU_POLL_PENDING) return e;
 }
 return GPU_DRIVER_TIMEOUT;
}
