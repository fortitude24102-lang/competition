#ifndef V3_FRAME_STATS_H
#define V3_FRAME_STATS_H
#include <stdint.h>
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
