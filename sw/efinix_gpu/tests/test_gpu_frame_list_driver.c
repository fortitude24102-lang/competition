/* Real driver/MMIO boundary: catch unsupported-window reads, lost tag credit,
 * stale epochs, missing publish sync and replay after partial failure. */
#include "gpu_frame_list.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[512];
static unsigned enabled,extended,starts,legacy,new_reads,synced,syncs;
static int fault,timeout,wrong_epoch,wrong_count;
static unsigned fail_start,timeout_start;
static uint32_t addresses[8],counts[8],tags[8],epochs[8];
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);
 if(r==GPU_REG_STATUS) return GPU_STATUS_EMPTY|(13u<<8)|(enabled?(3u<<14):0)|(extended?(1u<<20):0);
 if(r>=0x400) {++new_reads;assert(enabled);}
 if(r==0x400)return GPU_INSTANCE_ID;
 if(r==0x500)return GPU_FRAME_LIST_ID;
 return regs[r/4];
}
void gpu_io_write(uintptr_t a,uint32_t v) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);regs[r/4]=v;
 if(r==GPU_REG_CONTROL && (v&1)){++legacy;regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];}
 if(r==0x508 && v==1) {
  assert(synced);synced=0;++starts;
  assert(starts<=8);
  addresses[starts-1]=regs[0x50c/4];counts[starts-1]=regs[0x510/4];
  tags[starts-1]=regs[0x514/4];epochs[starts-1]=regs[0x518/4];
  unsigned error=starts==fail_start?9u:(unsigned)fault;
  regs[0x504/4]=(timeout || starts==timeout_start)?1u:2u|(error?4u|(error<<8):0);
  regs[0x51c/4]=regs[0x518/4]+(unsigned)wrong_epoch;
  regs[0x524/4]=regs[0x510/4]-(unsigned)wrong_count;
  regs[0x520/4]=(uint16_t)(regs[0x514/4]+regs[0x510/4]-1u);
  regs[GPU_REG_LAST_DONE/4]=regs[0x520/4];
 }
}
void gpu_io_fence(void) {}
void gpu_platform_sync(void){synced=1;++syncs;}
static gpu_device init(int present) {
 memset(regs,0,sizeof regs);enabled=(unsigned)present;extended=present==2;
 starts=legacy=new_reads=synced=syncs=0;fault=timeout=wrong_epoch=wrong_count=0;
 fail_start=timeout_start=0;
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 gpu_device d;assert(!gpu_init(&d,GPU_APB_BASE));return d;
}
int main(void) {
 gpu_device d=init(0);gpu_frame_list f;
 assert(!gpu_frame_list_init(&f,&d,1) && !f.present && !new_reads);
 assert(gpu_frame_list_render(&f,0x02d20000,3,7,10)==GPU_DRIVER_ARGUMENT && !starts);
 d=init(1);assert(!gpu_frame_list_init(&f,&d,1) && f.present);
 d.next_tag=65535;d.last_done=65534;regs[GPU_REG_LAST_DONE/4]=65534;
 assert(!gpu_frame_list_render(&f,0x02d20000,3,0x12340007,10));
 assert(starts==1 && !legacy && syncs==1 && !f.active);
 assert(regs[0x50c/4]==0x02d20000 && regs[0x510/4]==3 && regs[0x514/4]==65535 && regs[0x518/4]==0x12340007);
 assert(d.next_tag==2 && d.last_done==1 && d.submitted_count==3 && !d.outstanding && !d.pending && d.queue_high_watermark==13);
 assert(!gpu_frame_list_render(&f,0x02d24000,585,8,10));
 assert(d.next_tag==587 && d.last_done==586 && d.submitted_count==588 && !d.outstanding && starts==2);
 unsigned n=starts;
 assert(gpu_frame_list_render(&f,0x02d23ff0,2,1,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render(&f,0xfffffff0,2,1,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render(&f,0x02d20000,1025,1,10)==GPU_DRIVER_ARGUMENT);
 assert(starts==n);
 fault=9;assert(gpu_frame_list_render(&f,0x02d20000,3,9,10)==GPU_DRIVER_HARDWARE);
 assert(f.active && !legacy && d.hardware_error==9);
 gpu_frame_list replacement;
 assert(gpu_frame_list_init(&replacement,&d,1)==GPU_DRIVER_HARDWARE); // init isn't a reset/replay escape.
 n=starts;assert(gpu_frame_list_render(&f,0x02d20000,3,9,10)==GPU_DRIVER_BUSY && starts==n);
 d=init(1);assert(!gpu_frame_list_init(&f,&d,1));timeout=1;
 assert(gpu_frame_list_render(&f,0x02d20000,3,7,2)==GPU_DRIVER_TIMEOUT && f.active && starts==1 && !legacy);
 for(unsigned i=0;i<2;i++) {
  d=init(1);assert(!gpu_frame_list_init(&f,&d,1));wrong_epoch=i==0;wrong_count=i==1;
  assert(gpu_frame_list_render(&f,0x02d20000,3,7,10)==GPU_DRIVER_TAG && f.active && starts==1 && !legacy);
 }
 d=init(1);assert(!gpu_frame_list_init(&f,&d,1));regs[0x504/4]=1;
 assert(gpu_frame_list_render(&f,0x02d20000,3,7,10)==GPU_DRIVER_BUSY && !starts);
 /* Both banks are one immutable scene; no bank may be replayed on failure. */
 d=init(1);assert(!gpu_frame_list_init(&f,&d,1));
 d.next_tag=65535;d.last_done=65534;regs[GPU_REG_LAST_DONE/4]=65534;
 assert(!gpu_frame_list_render_span(&f,0x02d20000,2048,19,10));
 assert(starts==2 && !legacy && d.submitted_count==2048 && !f.active);
 assert(addresses[0]==0x02d20000 && counts[0]==1024 && tags[0]==65535);
 assert(addresses[1]==0x02d24000 && counts[1]==1024 && tags[1]==1023);
 assert(epochs[0]==19 && epochs[1]==19 && d.next_tag==2047 && d.last_done==2046);
 d=init(1);assert(!gpu_frame_list_init(&f,&d,1));
 assert(!gpu_frame_list_render_span(&f,0x02d20010,2047,20,10));
 assert(starts==2 && counts[0]==1023 && addresses[1]==0x02d24000 && counts[1]==1024);
 n=starts;
 assert(gpu_frame_list_render_span(&f,0x02d20000,2049,1,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render_span(&f,0x02d24000,1025,1,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render_span(&f,0x02d20001,1,1,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render_span(&f,0xfffffff0,UINT32_MAX,1,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render_span(&f,0x02d20000,0,1,10)==GPU_DRIVER_ARGUMENT && starts==n);
 for(unsigned t=0;t<2;t++) {
  d=init(1);assert(!gpu_frame_list_init(&f,&d,1));
  if(t)timeout_start=2;else fail_start=2;
  assert(gpu_frame_list_render_span(&f,0x02d20000,1025,22,2)==(t?GPU_DRIVER_TIMEOUT:GPU_DRIVER_HARDWARE));
  assert(starts==2 && d.submitted_count==1024 && f.active && !d.ready && !legacy);
  assert(gpu_frame_list_render_span(&f,0x02d20000,1025,22,2)==GPU_DRIVER_BUSY && starts==2);
 }
 d=init(2);assert(!gpu_frame_list_init(&f,&d,1) && f.arena_items==4096);
 d.next_tag=65535;d.last_done=65534;regs[GPU_REG_LAST_DONE/4]=65534;
 assert(!gpu_frame_list_render_span(&f,0x02d20000,4096,31,10));
 assert(starts==4 && d.submitted_count==4096 && d.next_tag==4095 && d.last_done==4094);
 for(unsigned i=0;i<4;i++) {
  assert(addresses[i]==0x02d20000u+i*16384u && counts[i]==1024);
  assert(tags[i]==(uint16_t)(65535u+i*1024u) && epochs[i]==31);
 }
 n=starts;
 assert(gpu_frame_list_render_span(&f,0x02d20000,4097,32,10)==GPU_DRIVER_ARGUMENT);
 assert(gpu_frame_list_render_span(&f,0x02d2fff0,2,32,10)==GPU_DRIVER_ARGUMENT && starts==n);
 d=init(1);assert(!gpu_frame_list_init(&f,&d,1) && f.arena_items==2048);
 assert(gpu_frame_list_render_span(&f,0x02d20000,4096,32,10)==GPU_DRIVER_ARGUMENT && !starts);
 for(unsigned t=0;t<2;t++) {
  d=init(2);assert(!gpu_frame_list_init(&f,&d,1));
  if(t)timeout_start=3;else fail_start=3;
  assert(gpu_frame_list_render_span(&f,0x02d20000,4096,32,2)==(t?GPU_DRIVER_TIMEOUT:GPU_DRIVER_HARDWARE));
  assert(starts==3 && d.submitted_count==2048 && f.active && !d.ready);
  assert(gpu_frame_list_render_span(&f,0x02d20000,4096,32,2)==GPU_DRIVER_BUSY && starts==3);
 }
 puts("FRAME_LIST_DRIVER,PASS,legacy_safe,tagwrap,4banks,4096items,epoch,publish,full_range_before_START,no_replay");
}
