/* Real legacy driver plus the new frontend driver; only APB peer is modeled.
 * Breaks caught: unsafe absent-window probe, tag-credit divergence, repeated
 * Alpha after a partial fault, unbounded full/busy waiting. */
#include "gpu_instances.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[512];
static unsigned writes,commits,legacy_commits,absent_reads;
static int enabled,inject_fault,full;
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);
 if(r==GPU_REG_STATUS) return GPU_STATUS_EMPTY|(enabled?(1u<<14):0);
 if(r==0x400) { ++absent_reads; return enabled?GPU_INSTANCE_ID:0; }
 if(r==0x404) return regs[r/4]|(full?0:2u)|4u;
 return regs[r/4];
}
void gpu_io_write(uintptr_t a,uint32_t v) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);++writes;regs[r/4]=v;
 if(r==GPU_REG_CONTROL && (v&1)) {++legacy_commits;regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];}
 if(r==0x408) regs[0x404/4]=v==1?1:0;
 if(r==0x440) { ++commits;regs[GPU_REG_LAST_DONE/4]=regs[0x444/4]++;
  if(inject_fault && commits==2) regs[GPU_REG_ERROR/4]=9;
 }
}
void gpu_io_fence(void) {}
static gpu_device init(int present) {
 memset(regs,0,sizeof regs);enabled=present;inject_fault=full=0;
 writes=commits=legacy_commits=absent_reads=0;
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 gpu_device d;assert(!gpu_init(&d,GPU_APB_BASE));return d;
}
int main(void) {
 gpu_instance_template templates[16];assert(gpu_instances_templates(1,templates)==12);
 gpu_instance_stream stream={.count=3,.items={{{2,GPU_FRAMEBUFFER_A,0,0x00010001}},
  {{0x00700101,GPU_FRAMEBUFFER_A+2,0,0x00010001}},{{3,GPU_FRAMEBUFFER_A+4,0,0x00010001}}}};
 gpu_device d=init(0);gpu_instances frontend;
 assert(!gpu_instances_init(&frontend,&d) && !frontend.present && absent_reads==0);
 assert(!gpu_instances_render(&frontend,templates,&stream,100) && legacy_commits==3 && commits==0);
 assert(d.next_tag==4 && d.last_done==3 && !d.outstanding);
 d=init(1);assert(!gpu_instances_init(&frontend,&d) && frontend.present);
 assert(!gpu_instances_program(&frontend,templates,12));
 d.first_tag=d.next_tag=65535;d.last_done=65534;regs[GPU_REG_LAST_DONE/4]=65534;
 assert(!gpu_instances_render(&frontend,templates,&stream,100));
 assert(commits==3 && legacy_commits==0 && d.next_tag==2 && d.last_done==1 && !d.outstanding && !frontend.active);
 /* Literal transport check: last keyed template+destination+offset+size. */
 assert(regs[0x430/4]==3 && regs[0x434/4]==GPU_FRAMEBUFFER_A+4 && regs[0x438/4]==0 && regs[0x43c/4]==0x00010001);
 d=init(1);assert(!gpu_instances_init(&frontend,&d));assert(!gpu_instances_program(&frontend,templates,12));
 full=1;assert(gpu_instances_render(&frontend,templates,&stream,2)==GPU_DRIVER_TIMEOUT);
 assert(commits==0 && legacy_commits==0); /* No fallback/replay even on timeout. */
 d=init(1);assert(!gpu_instances_init(&frontend,&d));assert(!gpu_instances_program(&frontend,templates,12));
 inject_fault=1;assert(gpu_instances_render(&frontend,templates,&stream,100)==GPU_DRIVER_HARDWARE);
 assert(commits==2 && legacy_commits==0 && d.hardware_error==9); /* Alpha was accepted once. */
 assert(frontend.active && gpu_instances_render(&frontend,templates,&stream,100)==GPU_DRIVER_BUSY);
 assert(commits==2 && legacy_commits==0);
 d=init(1);assert(!gpu_instances_init(&frontend,&d));d.outstanding=1;
 writes=0;assert(gpu_instances_program(&frontend,templates,12)==GPU_DRIVER_BUSY && !writes);
 puts("INSTANCE_DRIVER,PASS,capability,fallback,tagwrap,transport,bounded_full,partial_fault_no_replay,busy");
}
