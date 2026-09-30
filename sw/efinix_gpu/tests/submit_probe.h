/* Diagnostic only: include instead of separately linking gpu.c. No release ABI change.
 * The retry interval includes refresh, repeated validation/status reads, and the
 * successful retry. It is queue-pressure time, NOT a pure AXI/APB stall counter. */
#ifndef GPU_SUBMIT_PROBE_H
#define GPU_SUBMIT_PROBE_H
#include "gpu.h"
typedef struct {
 uint64_t submit_ticks,blocked_ticks,wait_ticks;
 unsigned calls,blocked_calls;
} submit_probe_stats;
static submit_probe_stats submit_probe;
static int submit_probe_enabled;
static uint64_t probe_clock(void);
#define gpu_submit unprofiled_gpu_submit
#define gpu_wait_tag unprofiled_gpu_wait_tag
#include "../src/gpu.c"
#undef gpu_submit
#undef gpu_wait_tag
int gpu_wait_tag(gpu_device *d,uint16_t tag,uint32_t polls) {
 if(!submit_probe_enabled) return unprofiled_gpu_wait_tag(d,tag,polls);
 uint64_t start=probe_clock();
 int e=unprofiled_gpu_wait_tag(d,tag,polls);
 submit_probe.wait_ticks+=probe_clock()-start;
 return e;
}
int gpu_submit(gpu_device *d,const gpu_command *c,uint32_t polls,uint16_t *tag) {
 if(!submit_probe_enabled) return unprofiled_gpu_submit(d,c,polls,tag);
 uint64_t start=probe_clock(),blocked_start=0;
 int blocked=0,e;
 for(;;) {
  e=gpu_try_submit(d,c,tag);
  if(e!=GPU_DRIVER_AGAIN) break;
  if(!blocked) { blocked=1; blocked_start=probe_clock(); }
  if(!polls--) { e=GPU_DRIVER_TIMEOUT; break; }
  e=refresh(d); if(e) break;
 }
 uint64_t end=probe_clock();
 submit_probe.submit_ticks+=end-start; ++submit_probe.calls;
 if(blocked) { submit_probe.blocked_ticks+=end-blocked_start; ++submit_probe.blocked_calls; }
 return e;
}
#endif
