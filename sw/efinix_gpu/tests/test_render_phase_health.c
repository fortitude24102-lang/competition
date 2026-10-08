#include <assert.h>
#include <stdio.h>
#include "render_phase_health.h"
int main(void) {
 assert(render_phase_health_ok(4,4,0)==1); /* Startup history is a baseline. */
 assert(render_phase_health_ok(4,5,0)==0); /* Including warmup/PRESENT. */
 assert(render_phase_health_ok(4,4,1)==0);
 assert(render_phase_health_ok(5,4,0)==0); /* Counter reset is not clean. */
 assert(render_phase_health_ok(UINT64_MAX,UINT64_MAX,0)==1);
 assert(render_phase_health_ok(UINT64_MAX,0,0)==0);
 puts("PASS render health: warmup and sampling share the same gate");
 return 0;
}
