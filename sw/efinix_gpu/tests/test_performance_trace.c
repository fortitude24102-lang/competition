#include "performance_trace.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static pc_state state;
int main(void) {
 pc_failure_trace trace={0};
 assert(!pc_init(&state,3640,7));state.target=2007;state.stage=PC_DONE;state.best=2007;state.stats.frames=3600;
 assert(pc_trace_record(&state,&trace,100000000,1671000,3327700,0,0,2007,251,200000,300000,500000,200000,1000000)==1);
 assert(state.stage==PC_FAILED && !state.best && state.stats.frames==3600);
 assert(trace.magic==PC_FAILURE_TRACE_MAGIC && trace.stage_before==4 && trace.stage_after==6);
 assert(trace.target==2007 && trace.frames==3600 && trace.work_ticks==1671000 && trace.wall_ticks==3327700);
 assert(trace.logic_ticks==200000 && trace.build_ticks==300000 && trace.scene_ticks==500000 && trace.hud_ticks==200000);
 assert(trace.other_ticks==471000 && trace.gpu_busy_ticks==1000000 && !trace.underflows && !trace.errors);
 pc_failure_trace frozen=trace;
 assert(!pc_trace_record(&state,&trace,100000000,1600000,1664200,0,0,2007,251,0,0,0,0,0));
 assert(!memcmp(&trace,&frozen,sizeof trace));
 /* A normal losing search sample is not a terminal failure or a scored result. */
 memset(&trace,0,sizeof trace);assert(!pc_init(&state,3640,7));state.stage=PC_SAMPLE;state.warm=0;
 assert(!pc_trace_record(&state,&trace,100000000,1800000,3327700,0,0,64,8,0,0,0,0,0));
 assert(!trace.magic && state.stats.work_misses==1 && state.stats.frames==1);
 assert(pc_trace_record(&state,&trace,100000000,1000000,1664200,1,0,64,8,0,0,0,0,0)==1);
 assert(trace.stage_before==2 && trace.underflows==1 && trace.frames==1);
 memset(&trace,0,sizeof trace);assert(!pc_init(&state,3640,7));
 assert(pc_trace_record(&state,&trace,100000000,10,9,0,0,64,8,0,0,0,0,0)==GPU_DRIVER_ARGUMENT && !trace.magic);
 state.stage=PC_CAPACITY;state.best=64;
 assert(!pc_trace_record(&state,&trace,100000000,1000000,1664200,0,0,64,8,0,0,0,0,0) && state.best==64 && !trace.magic);
 assert(pc_trace_record(&state,&trace,100000000,1000000,3327700,0,0,64,8,0,0,0,0,0)==1);
 assert(trace.stage_before==5 && trace.wall_ticks==3327700 && !state.best);
 puts("PASS actual PC scoring unchanged; first post-qualified work/wall/health failure frozen with phase costs, no search/malformed false capture");
}
