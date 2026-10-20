/* Include the actual normal main/loop. Only diagnostic wrappers change code
 * placement; this BIN is NOT a production performance qualification. No UART
 * or DDR snapshot writes during sampling; freeze only the first fatal frame. */
#define main reference_main
#include "../src/main.c"
#undef main
/*1024 main uses this private macro; do not substitute the loop's parameter. */
#undef overlay
#include "performance_trace.h"
#include <string.h>
static uint32_t trace_logic,trace_hud;
#define TRACE ((pc_failure_trace *)(uintptr_t)PC_FAILURE_TRACE_ADDRESS)
static int trace_init(pc_state *s,unsigned maximum,uint32_t seed) {
 memset(TRACE,0,sizeof *TRACE);trace_logic=trace_hud=0;
 return pc_init(s,maximum,seed);
}
static int trace_advance(pc_state *s,const game_input *input) {
 uint64_t t=gpu_platform_cycles();int e=pc_advance(s,input);
 trace_logic=(uint32_t)(gpu_platform_cycles()-t);return e;
}
static int trace_draw(gpu_device *d,const hud_comparison *m,hud_framebuffer_cache *cache,
 hud_command_stream *scratch,uint32_t dst,uint32_t polls) {
 uint64_t t=gpu_platform_cycles();int e=hud_render_gpu_direct(d,m,cache,scratch,dst,polls);
 trace_hud=(uint32_t)(gpu_platform_cycles()-t);return e;
}
int main(void) {return reference_main();}
#define pc_init trace_init
#define pc_advance trace_advance
#define hud_render_gpu_direct trace_draw
#define pc_record(s,hz,work,wall,under,errors,visible,alpha) \
 pc_trace_record(s,TRACE,hz,work,wall,under,errors,visible,alpha,trace_logic, \
 build_us*(BSP_CLINT_HZ/1000000u),render_us*(BSP_CLINT_HZ/1000000u),trace_hud,(uint32_t)(after.cycles-before.cycles))
#include "../src/v3_demo.c"
