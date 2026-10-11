#ifndef LIVE_PHASE_STATS_H
#define LIVE_PHASE_STATS_H
#include <stdint.h>
#include <string.h>
enum { LP_CONTROL, LP_LOGIC, LP_BUILD, LP_SYNC, LP_SCENE, LP_HUD_UPDATE,
 LP_HUD_COPY, LP_SNAPSHOT, LP_OTHER, LP_COUNT };
#define LP_SAMPLES 300u
typedef struct {
 uint64_t total[LP_COUNT],work,wall;
 uint32_t max[LP_COUNT],worst[LP_COUNT],samples[LP_SAMPLES];
 unsigned frames,misses,late;
 uint32_t max_work;
} live_phase_stats;
static inline int live_phase_record(live_phase_stats *s,const uint32_t *p,
 uint32_t work,uint32_t wall,uint32_t budget) {
 if(!s || !p || !budget || wall<work || s->frames>=LP_SAMPLES) return -1;
 uint64_t sum=0;for(unsigned i=0;i<LP_OTHER;i++) sum+=p[i];
 if(sum>work) return -1;
 for(unsigned i=0;i<LP_COUNT;i++) {
  uint32_t value=i==LP_OTHER?work-(uint32_t)sum:p[i];
  s->total[i]+=value;if(value>s->max[i]) s->max[i]=value;
  if(work>s->max_work) s->worst[i]=value;
 }
 if(work>s->max_work) s->max_work=work;
 s->samples[s->frames++]=work;s->work+=work;s->wall+=wall;
 s->misses+=work>budget;s->late+=wall>budget;return 0;
}
#endif
