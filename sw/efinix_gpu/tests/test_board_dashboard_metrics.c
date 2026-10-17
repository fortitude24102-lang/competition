/* JTAG-only counting firmware: fixed active scene, NOT gameplay qualification.
 * No UART in the timed loop. Logic/build are measured CPU regions, not total
 * CPU utilization; render-call and PRESENT include software busy polling. */
#define main reference_main
#include "../src/main.c"
#undef main
#include "performance_challenge.h"
#include "gpu_frame_list.h"
#define CHECK(c) do {if(!(c)){bsp_printf("DASHBOARD_METRICS_FAIL,line=%d,error=%d\r\n",__LINE__,d.hardware_error);return 1;}} while(0)
static unsigned micros(uint64_t ticks) {return (unsigned)(ticks/(BSP_CLINT_HZ/1000000u));}
int main(void) {
 bsp_init();gpu_device d={0};gpu_frame_list f;framebuffer_pair buffers;
 CHECK(!gpu_init(&d,GPU_APB_BASE));CHECK(!gpu_frame_list_init(&f,&d,0) && f.present);
 CHECK(!gpu_set_qos(&d,256,1536,1));
 bullet_init_local_assets();gpu_platform_sync();
 CHECK(!gpu_texture_cache_load(&d,BULLET_LOCAL_ATLAS,(BULLET_ATLAS_BYTES+3u)&~3u,10000000u));
 framebuffer_init(&buffers);
 CHECK(!framebuffer_present(&d,&buffers,10000000u));
 uint64_t settle=gpu_platform_cycles();while(gpu_platform_cycles()-settle<BSP_CLINT_HZ/20u) {}
 pc_state *state=(pc_state *)(uintptr_t)PC_STATE_ADDRESS;
 gpu_instance *items=(gpu_instance *)(uintptr_t)GPU_FRAME_LIST_BANK_A;
 const unsigned targets[]={512,1536};
 bsp_printf("DASHBOARD_METRICS_START,hz=%d,warm=30,frames=600,local=1,hud=0,control=0\r\n",BSP_CLINT_HZ);
 for(unsigned trial=0;trial<2;trial++) {
  unsigned target=targets[trial];CHECK(!pc_init(state,PC_MAX_SPRITES,7));state->target=target;
  for(unsigned i=0;i<target;i++)state->sprites[i]=(pc_sprite){
   .x=(int16_t)(16+(i%56u)*16u),.y=(int16_t)(80+((i/56u)%19u)*24u),
   .dx=(int8_t)((i&1u?-1:1)*(int)(1u+(i+7u)%3u)),
   .dy=(int8_t)((i&2u?-1:1)*(int)(1u+(2u*i+7u)%3u)),.shape=(uint8_t)((i+7u)%6u)};
  uint64_t logic=0,build=0,render=0,present=0,wall=0,work=0,max_work=0;
  uint64_t previous=gpu_platform_cycles(),window_start=0;
  unsigned misses=0;gpu_perf_snapshot before={0},after={0};gpu_instance_stats stats={0};
  for(unsigned frame=0;frame<630;frame++) {
   if(frame==30) {window_start=previous;CHECK(!gpu_read_perf_snapshot(&d,&before));}
   uint64_t a=gpu_platform_cycles();
   CHECK(!pc_advance(state,&(game_input){0}));uint64_t b=gpu_platform_cycles();
   CHECK(!pc_build(state,buffers.back,0,items,GPU_FRAME_LIST_ARENA_ITEMS,&stats));
   uint64_t c=gpu_platform_cycles();gpu_platform_sync();uint64_t r=gpu_platform_cycles();
   CHECK(!gpu_frame_list_render_span(&f,GPU_FRAME_LIST_BANK_A,stats.count,frame+1u,10000000u));
   uint64_t e=gpu_platform_cycles();
   CHECK(!framebuffer_present(&d,&buffers,10000000u));uint64_t z=gpu_platform_cycles();
   CHECK(stats.visible==target && stats.alpha_commands==(target+7u)/8u && !d.hardware_error);
   if(frame>=30) {
    logic+=b-a;build+=c-b;render+=e-r;present+=z-e;wall+=z-previous;work+=e-previous;
    if(e-previous>max_work)max_work=e-previous;
    misses+=(e-previous>BSP_CLINT_HZ/60u);
   }
   previous=z; /* Include inter-frame checks in the following measured frame. */
  }
  CHECK(!gpu_read_perf_snapshot(&d,&after));
  CHECK(wall==previous-window_start); /* Every one of the600 PRESENT intervals must be included. */
  CHECK(after.underflows==before.underflows && after.pixels-before.pixels==(uint64_t)stats.scene_pixels*600u);
  CHECK(logic+build+render+present<=wall && state->tick==630);
  bsp_printf("DASHBOARD_METRICS,target=%d,alpha=%d,frames=600,wall_us=%d,work_us=%d,max_work_us=%d,logic_us=%d,build_us=%d,render_call_us=%d,present_us=%d,gpu_busy_us=%d,pixels=%d,rd=%d,wr=%d,cache=%d,under=%d,error=%d,work_miss=%d,state_crc=%x,list_crc=%x\r\n",
   target,stats.alpha_commands,micros(wall),micros(work),micros(max_work),micros(logic),micros(build),
   micros(render),micros(present),(unsigned)((after.cycles-before.cycles)/100u),
   (unsigned)(after.pixels-before.pixels),(unsigned)(after.read_bytes-before.read_bytes),
   (unsigned)(after.write_bytes-before.write_bytes),(unsigned)(after.cache_bytes-before.cache_bytes),
   (unsigned)(after.underflows-before.underflows),d.hardware_error,misses,
   golden_crc32(state->sprites,target*sizeof *state->sprites),golden_crc32(items,stats.count*sizeof *items));
 }
 bsp_printf("DASHBOARD_METRICS_STOP,result=0\r\n");return 0;
}
