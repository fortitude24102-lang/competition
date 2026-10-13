#include <assert.h>
#include <stdio.h>
#include "v3_frame_stats.h"
int main(void) {
 /* Missing/incorrect worst-frame retention hides the actual slow frame. */
 v3_worst_frame worst={0},candidate={.tick=17,.steps=2,.logic_us=4000,
  .build_us=4200,.scene_us=7400,.hud_us=1400,.work_us=17200,.wall_us=33277,
  .hp_before=0,.death_wait_before=1,.round_tick=0};
 assert(!v3_worst_frame_record(&worst,&candidate));
 assert(worst.tick==17 && worst.steps==2 && worst.other_us==200 && worst.work_us==17200);
 assert(!worst.hp_before && worst.death_wait_before==1 && !worst.round_tick);
 candidate.tick=18;candidate.work_us=17100;
 assert(!v3_worst_frame_record(&worst,&candidate) && worst.tick==17);
 candidate.work_us=20000;candidate.wall_us=19000;
 assert(v3_worst_frame_record(&worst,&candidate)<0 && worst.tick==17);
 candidate.wall_us=33277;candidate.logic_us=9000;
 assert(v3_worst_frame_record(&worst,&candidate)<0 && worst.tick==17);
 candidate.logic_us=5000;
 assert(!v3_worst_frame_record(&worst,&candidate) && worst.tick==18 && worst.other_us==2000);
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
