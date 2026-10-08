#include <assert.h>
#include <stdio.h>
#include "v3_frame_stats.h"
int main(void) {
 v3_scene_metrics m={.cpu_fps=100,.gpu_fps=600,.cpu_fresh=1};
 v3_scene_metrics_transition(&m,1,1);assert(m.cpu_fps==100 && !m.cpu_fresh && !m.gpu_fps);
 v3_scene_metrics_transition(&m,2,0);assert(!m.cpu_fps);
 m.pending_cpu_fps=110;m.pending_cpu_us=90000;assert(!m.cpu_fps);
 v3_scene_metrics_transition(&m,3,1);assert(!m.pending_cpu_fps && !m.cpu_fps);
 v3_scene_metrics_transition(&m,4,0);m.pending_cpu_fps=120;m.pending_cpu_us=80000;
 v3_scene_metrics_cpu_done(&m);assert(m.cpu_fps==120 && m.cpu_us==80000 && m.cpu_fresh);
 v3_scene_metrics_transition(&m,5,0);assert(m.cpu_fps==120 && !m.cpu_fresh); /* R same level */
 v3_frame_stats s={0};
 /* A17ms work frame misses its deadline even though old20ms test accepts it.
    Cadence gets half a period tolerance, never two-refresh30FPS acceptance. */
 v3_frame_stats_add(&s,100000000u,1700000,1664000,600000,0,0,248,35);
 assert(s.frames==1 && s.work_misses==1 && s.cadence_misses==0);
 assert(s.min_visible==248 && s.max_visible==248 && s.min_alpha==35);
 v3_frame_stats_add(&s,100000000u,1400000,3330000,0,2,1,240,34);
 assert(s.frames==2 && s.work_misses==1 && s.cadence_misses==1);
 assert(s.underflows==2 && s.errors==1 && s.max_wall_ticks==3330000);
 assert(s.min_visible==240 && s.max_visible==248 && s.max_alpha==35);
 assert(s.work_ticks==3100000 && s.wall_ticks==4994000 && s.log_ticks==600000);
 assert(s.max_work_ticks==1700000 && s.max_log_ticks==600000);
 v3_frame_stats_add(&s,100000000u,1666666,2500000,0,0,0,256,36);
 assert(s.work_misses==1 && s.cadence_misses==1); /* Inclusive boundaries. */
 puts("PASS V3 strict frame budget, cadence, totals and real workload range");
}
