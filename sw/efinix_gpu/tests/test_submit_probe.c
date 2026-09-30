/* Catches diagnostic wrapper changing queued submit fields, timeout, or error
 * semantics, or double-counting blocked time as extra submission time. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GPU_TEST_BACKEND
#include "submit_probe.h"
static uint32_t registers[256];
static uint64_t ticks;
static unsigned full_reads,writes;
static uint64_t probe_clock(void) { ticks+=10; return ticks; }
uint32_t gpu_io_read(uintptr_t a) {
 ++ticks;
 if(a==GPU_APB_BASE+GPU_REG_STATUS && full_reads) {
  --full_reads; return GPU_STATUS_FULL;
 }
 return registers[(a-GPU_APB_BASE)/4];
}
void gpu_io_write(uintptr_t a,uint32_t v) { ++ticks; ++writes; registers[(a-GPU_APB_BASE)/4]=v; }
void gpu_io_fence(void) { ++ticks; }
static gpu_device init(void) {
 memset(registers,0,sizeof registers);
 registers[GPU_REG_ID/4]=GPU_ID_VALUE;
 registers[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 registers[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;
 gpu_device d; assert(gpu_init(&d,GPU_APB_BASE)==0); return d;
}
int main(void) {
 gpu_command c={.op=GPU_OP_FILL,.dst_addr=GPU_FRAMEBUFFER_A,.dst_stride=1920,
  .width_pixels=3,.height_pixels=2,.color=0x1234};
 gpu_device d=init(); uint16_t tag=0;
 submit_probe_enabled=1; submit_probe=(submit_probe_stats){0}; writes=0;
 assert(gpu_submit(&d,&c,2,&tag)==0 && tag==1 && d.outstanding==1);
 assert(writes==10 && registers[GPU_REG_SIZE/4]==0x20003);
 assert(submit_probe.calls==1 && submit_probe.blocked_calls==0 && submit_probe.blocked_ticks==0);
 d=init(); full_reads=2; submit_probe=(submit_probe_stats){0}; writes=0;
 assert(gpu_submit(&d,&c,2,&tag)==0 && tag==1 && writes==10);
 assert(submit_probe.blocked_calls==1 && submit_probe.blocked_ticks>0);
 assert(submit_probe.blocked_ticks<submit_probe.submit_ticks);
 assert(gpu_wait_tag(&d,tag,1)==GPU_DRIVER_TIMEOUT && submit_probe.wait_ticks>0);
 registers[GPU_REG_LAST_DONE/4]=tag;
 assert(gpu_wait_tag(&d,tag,1)==0 && !d.outstanding);
 d=init(); full_reads=1; writes=0; tag=0xbeef;
 assert(gpu_submit(&d,&c,0,&tag)==GPU_DRIVER_TIMEOUT && tag==0xbeef && writes==0 && !d.outstanding);
 full_reads=0; c.width_pixels=0;
 assert(gpu_submit(&d,&c,2,&tag)==GPU_ERROR_ZERO_SIZE && writes==0);
 c.width_pixels=3; registers[GPU_REG_ERROR/4]=9;
 assert(gpu_submit(&d,&c,2,&tag)==GPU_DRIVER_HARDWARE && writes==0);
 d=init(); full_reads=1; submit_probe_enabled=0;
 submit_probe_stats saved=submit_probe;
 assert(gpu_submit(&d,&c,1,&tag)==0 && tag==1);
 assert(submit_probe.calls==saved.calls && submit_probe.submit_ticks==saved.submit_ticks);
 puts("PASS diagnostic submit: real driver fields/errors/timeouts retained; retry time is a subset; disabled control uninstrumented");
}
