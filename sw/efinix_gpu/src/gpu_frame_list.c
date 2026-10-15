#include "gpu_frame_list.h"
#include "benchmark.h"
#ifdef GPU_TEST_BACKEND
uint32_t gpu_io_read(uintptr_t a);
void gpu_io_write(uintptr_t a,uint32_t v);
void gpu_io_fence(void);
#else
static uint32_t gpu_io_read(uintptr_t a){return *(volatile uint32_t *)a;}
static void gpu_io_write(uintptr_t a,uint32_t v){*(volatile uint32_t *)a=v;}
static void gpu_io_fence(void){__asm__ volatile("fence iorw,iorw" ::: "memory");}
#endif
static uint32_t rd(gpu_frame_list *f,unsigned r){return gpu_io_read(f->gpu->base+r);}
static void wr(gpu_frame_list *f,unsigned r,uint32_t v){gpu_io_write(f->gpu->base+r,v);}
int gpu_frame_list_init(gpu_frame_list *f,gpu_device *d,int network) {
 if(!f || !d || (network!=0 && network!=1))return GPU_DRIVER_ARGUMENT;
 if(d->hardware_error)return GPU_DRIVER_HARDWARE;
 if(!d->ready)return GPU_DRIVER_ARGUMENT;
 *f=(gpu_frame_list){.gpu=d};
 uint32_t capability=rd(f,GPU_REG_STATUS);
 if(!(capability&GPU_FRAME_LIST_CAPABILITY))return 0; // Safe old address only.
 if(!(capability&GPU_INSTANCE_CAPABILITY) || rd(f,0x500)!=GPU_FRAME_LIST_ID)return GPU_DRIVER_ID;
 uint32_t status=rd(f,0x504);
 if(status&4u) {d->hardware_error=(uint8_t)(status>>8);d->ready=0;return GPU_DRIVER_HARDWARE;}
 if(status&1u)return GPU_DRIVER_BUSY;
 gpu_instances frontend;gpu_instance_template templates[16];
 int e=gpu_instances_init(&frontend,d);if(e)return e;
 unsigned n=gpu_instances_templates(network,templates);
 e=gpu_instances_program(&frontend,templates,n);if(e)return e;
 f->present=1;return 0;
}
int gpu_frame_list_render(gpu_frame_list *f,uint32_t address,unsigned count,uint32_t epoch,uint32_t polls) {
 if(f && f->active)return GPU_DRIVER_BUSY;
 uint64_t end=(uint64_t)address+(uint64_t)count*16u;
 if(!f || !f->gpu || !f->gpu->ready || !f->present || !polls || !count || count>1024 ||
   (address&15u) || address<GPU_FRAME_LIST_BANK_A || end>GPU_FRAME_LIST_BANK_B+16384u ||
   ((uint64_t)address>>14)!=((end-1u)>>14))return GPU_DRIVER_ARGUMENT;
 gpu_device *d=f->gpu;
 if(rd(f,0x504)&1u)return GPU_DRIVER_BUSY;
 if(d->outstanding) {int e=gpu_wait_tag(d,d->pending_tag,polls);if(e)return e;}
 if(rd(f,GPU_REG_STATUS)&GPU_STATUS_BUSY)return GPU_DRIVER_BUSY;
 d->hardware_error=(uint8_t)rd(f,GPU_REG_ERROR);
 if(d->hardware_error)return GPU_DRIVER_HARDWARE;
 uint16_t first=d->next_tag,last=(uint16_t)(first+count-1u);
 gpu_platform_sync(); // fence + official custom cache path; never CSR810.
 wr(f,0x50c,address);wr(f,0x510,count);wr(f,0x514,first);wr(f,0x518,epoch);
 gpu_io_fence();f->active=1;wr(f,0x508,1);gpu_io_fence();
 for(uint32_t n=0;n<polls;n++) {
  uint32_t status=rd(f,0x504);
  if(status&4u) {d->hardware_error=(uint8_t)(status>>8);d->ready=0;return GPU_DRIVER_HARDWARE;}
  if(!(status&2u))continue;
  if((status&1u) || rd(f,0x51c)!=epoch || rd(f,0x524)!=count || rd(f,0x520)!=last ||
     (uint16_t)rd(f,GPU_REG_LAST_DONE)!=last){d->ready=0;return GPU_DRIVER_TAG;}
  d->hardware_error=(uint8_t)rd(f,GPU_REG_ERROR);
  if(d->hardware_error){d->ready=0;return GPU_DRIVER_HARDWARE;}
  d->submitted_count+=count;d->next_tag=(uint16_t)(first+count);d->last_done=last;
  d->pending=0;d->outstanding=0;d->pending_tag=last;
  uint8_t high=(uint8_t)((rd(f,GPU_REG_STATUS)>>8)&31u);
  if(high>d->queue_high_watermark)d->queue_high_watermark=high;
  f->active=0;return 0;
 }
 d->ready=0;return GPU_DRIVER_TIMEOUT;
}
int gpu_frame_list_render_span(gpu_frame_list *f,uint32_t address,unsigned count,uint32_t epoch,uint32_t polls) {
 if(f && f->active)return GPU_DRIVER_BUSY;
 uint64_t end=(uint64_t)address+(uint64_t)count*16u;
 if(!f || !f->gpu || !f->gpu->ready || !f->present || !polls || !count ||
    count>GPU_FRAME_LIST_ARENA_ITEMS || (address&15u) || address<GPU_FRAME_LIST_BANK_A ||
    end>GPU_FRAME_LIST_BANK_B+16384u)return GPU_DRIVER_ARGUMENT;
 while(count) {
  unsigned n=(16384u-(address&16383u))/16u;
  if(n>count)n=count;
  int e=gpu_frame_list_render(f,address,n,epoch,polls);if(e)return e;
  address+=n*16u;count-=n;
 }
 return 0;
}
