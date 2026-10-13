#ifndef V3_FRAME_STATS_H
#define V3_FRAME_STATS_H
#include <stdint.h>
/* Terminal diagnostics only: exclusive CPU intervals, overlapping GPU busy. */
typedef struct {
 uint32_t tick,steps,logic_us,build_us,scene_us,hud_us,other_us;
 uint32_t busy_us,work_us,wall_us,hp,seal_event;
 uint32_t hp_before,death_wait_before,round_tick;
} v3_worst_frame;
static inline int v3_worst_frame_record(v3_worst_frame *worst,const v3_worst_frame *frame) {
 if(!worst || !frame)return -1;
 uint64_t phases=(uint64_t)frame->logic_us+frame->build_us+frame->scene_us+frame->hud_us;
 if(phases>frame->work_us || frame->wall_us<frame->work_us)return -1;
 if(frame->work_us>worst->work_us) {
  *worst=*frame;worst->other_us=frame->work_us-(uint32_t)phases;
 }
 return 0;
}
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
