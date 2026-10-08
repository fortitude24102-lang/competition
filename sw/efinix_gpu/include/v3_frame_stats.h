#ifndef V3_FRAME_STATS_H
#define V3_FRAME_STATS_H
#include <stdint.h>
/* Game-only published results. Incomplete CPU replay never replaces a result. */
typedef struct {
 uint32_t cpu_fps,cpu_us,gpu_fps,gpu_us,pending_cpu_fps,pending_cpu_us,generation;
 uint8_t menu,cpu_fresh;
} v3_scene_metrics;
static inline void v3_scene_metrics_transition(v3_scene_metrics *m,uint32_t generation,int menu) {
 if(m->generation==generation)return;
 if(m->menu && !menu)m->cpu_fps=m->cpu_us=0;
 m->pending_cpu_fps=m->pending_cpu_us=m->gpu_fps=m->gpu_us=0;m->cpu_fresh=0;
 m->generation=generation;m->menu=(uint8_t)(menu!=0);
}
static inline void v3_scene_metrics_cpu_done(v3_scene_metrics *m) {
 if(m->pending_cpu_fps) {
  m->cpu_fps=m->pending_cpu_fps;m->cpu_us=m->pending_cpu_us;m->cpu_fresh=1;
 }
 m->pending_cpu_fps=m->pending_cpu_us=0;
}
typedef struct {
 uint32_t frames,work_misses,cadence_misses,underflows,errors;
 uint32_t max_work_ticks,max_wall_ticks,max_log_ticks,min_visible,max_visible;
 uint32_t min_alpha,max_alpha;
 uint64_t work_ticks,wall_ticks,log_ticks;
} v3_frame_stats;
static inline void v3_frame_stats_add(v3_frame_stats *s,uint32_t hz,
 uint32_t work,uint32_t wall,uint32_t log,uint32_t under,uint32_t errors,
 unsigned visible,unsigned alpha) {
 if(!s->frames) {
  s->min_visible=visible;s->min_alpha=alpha;
 }
 ++s->frames;
 s->work_misses+=work>hz/60u;
 s->cadence_misses+=wall>hz/40u;
 s->underflows+=under;s->errors+=errors;
 s->work_ticks+=work;s->wall_ticks+=wall;s->log_ticks+=log;
 if(work>s->max_work_ticks) s->max_work_ticks=work;
 if(wall>s->max_wall_ticks) s->max_wall_ticks=wall;
 if(log>s->max_log_ticks) s->max_log_ticks=log;
 if(visible<s->min_visible) s->min_visible=visible;
 if(visible>s->max_visible) s->max_visible=visible;
 if(alpha<s->min_alpha) s->min_alpha=alpha;
 if(alpha>s->max_alpha) s->max_alpha=alpha;
}
#endif
