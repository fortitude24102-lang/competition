/* Catches the real legacy P5 policy accepting14 dropped frames out of300. */
#include "damage_acceptance.h"
#include <assert.h>
#include <stdio.h>
static benchmark_frame_sample samples[300];
int main(void) {
 unsigned cadence=0;
 for(unsigned i=0;i<300;i++) {
  uint32_t wall=i<286?1664000:3328000; /* nominal60.1 vs30.05 at100MHz */
  samples[i]=(benchmark_frame_sample){.fps=(uint16_t)(100000000u/wall),.sprite_count=512};
  cadence+=wall>100000000u/60u;
 }
 benchmark_run_summary summary;
 assert(!benchmark_summarize_run(samples,300,&summary));
 assert(cadence==14 && summary.p5_fps==60 && summary.stable_sprite_count==512);
 assert(!damage_run_qualified(&summary,300,0,cadence));
 for(unsigned i=0;i<300;i++) samples[i].fps=60;
 assert(!benchmark_summarize_run(samples,300,&summary));
 assert(damage_run_qualified(&summary,300,0,0));
 assert(!damage_run_qualified(&summary,299,0,0));
 assert(!damage_run_qualified(&summary,300,1,0));
 summary.total_underflows=1; assert(!damage_run_qualified(&summary,300,0,0));
 summary.total_underflows=0; summary.total_errors=1;
 assert(!damage_run_qualified(&summary,300,0,0));
 puts("DAMAGE_ACCEPTANCE,PASS,mixed_cadence14,zero_miss,work,under,error,incomplete");
 return 0;
}
