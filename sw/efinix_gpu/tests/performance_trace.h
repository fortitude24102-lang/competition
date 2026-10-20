#ifndef PERFORMANCE_TRACE_H
#define PERFORMANCE_TRACE_H
#include "performance_challenge.h"
/* Diagnostic-only DDR snapshot. Neither packets nor normal firmware ABI change. */
#define PC_FAILURE_TRACE_ADDRESS 0x02d3f000u
#define PC_FAILURE_TRACE_MAGIC 0x50544631u
typedef struct {
 uint32_t magic,target,stage_before,stage_after,frames,hz;
 uint32_t work_ticks,wall_ticks,logic_ticks,build_ticks,scene_ticks,hud_ticks;
 uint32_t gpu_busy_ticks,other_ticks,underflows,errors,visible,alpha;
} pc_failure_trace;
_Static_assert(PC_STATE_ADDRESS+sizeof(pc_state)<=PC_FAILURE_TRACE_ADDRESS,"trace/state separation");
_Static_assert(PC_FAILURE_TRACE_ADDRESS+sizeof(pc_failure_trace)<=0x02d40000u,"trace DDR bound");
static inline int pc_trace_record(pc_state *s,pc_failure_trace *trace,uint32_t hz,
 uint32_t work,uint32_t wall,uint32_t under,uint32_t errors,unsigned visible,unsigned alpha,
 uint32_t logic,uint32_t build,uint32_t scene,uint32_t hud,uint32_t busy) {
 unsigned prior=s->stage;
 int e=pc_record(s,hz,work,wall,under,errors,visible,alpha);
 if(e>=0 && s->stage==PC_FAILED && !trace->magic) {
  uint64_t parts=(uint64_t)logic+build+scene+hud;
  *trace=(pc_failure_trace){.target=s->target,.stage_before=prior,.stage_after=s->stage,
   .frames=s->stats.frames,.hz=hz,.work_ticks=work,.wall_ticks=wall,
   .logic_ticks=logic,.build_ticks=build,.scene_ticks=scene,.hud_ticks=hud,
   .gpu_busy_ticks=busy,.other_ticks=parts<=work?work-(uint32_t)parts:UINT32_MAX,
   .underflows=under,.errors=errors,.visible=visible,.alpha=alpha};
  trace->magic=PC_FAILURE_TRACE_MAGIC; /* Freeze the first failure, not its cheap followers. */
 }
 return e;
}
#endif
