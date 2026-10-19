/* JTAG-only diagnostic. Stage timings perturb overlap, NOT game FPS. */
#define main reference_main
#include "../src/main.c"
#undef main
#include "performance_challenge.h"
#include "gpu_frame_list.h"
#define CHECK(c) do {if(!(c)){bsp_printf("SPRITE_PHASE_FAIL,line=%d,hardware=%d\r\n",__LINE__,d.hardware_error);return 1;}} while(0)
int main(void) {
 bsp_init();gpu_device d;gpu_frame_list f;framebuffer_pair buffers;
 CHECK(!gpu_init(&d,GPU_APB_BASE));CHECK(!gpu_frame_list_init(&f,&d,0) && f.present);
#if GPU_AXI_DIAGNOSTICS
 CHECK((*(volatile uint32_t *)(d.base+GPU_REG_STATUS)&(1u<<19))!=0);
 CHECK(*(volatile uint32_t *)(d.base+0x600)==0x41585046u);
#endif
 CHECK(!gpu_set_qos(&d,256,1536,1));
 bullet_init_local_assets();gpu_platform_sync();
 CHECK(!gpu_texture_cache_load(&d,BULLET_LOCAL_ATLAS,(BULLET_ATLAS_BYTES+3u)&~3u,10000000u));
 framebuffer_init(&buffers);
 CHECK(!framebuffer_present(&d,&buffers,10000000u));
 uint64_t warm=gpu_platform_cycles();while(gpu_platform_cycles()-warm<BSP_CLINT_HZ/20u) {}
 pc_state *state=(pc_state *)(uintptr_t)PC_STATE_ADDRESS;
 gpu_instance *items=(gpu_instance *)(uintptr_t)GPU_FRAME_LIST_BANK_A;
 const unsigned targets[]={512,1040};const char *names[]={"BACKGROUND","ALPHA","KEY","FULL"};
 for(unsigned t=0;t<2;t++) {
  CHECK(!pc_init(state,PC_MAX_SPRITES,7));state->target=targets[t];
  /* pc_init starts at64. Initialize EVERY tested sprite, not just that first cohort. */
  for(unsigned k=0;k<state->target;k++)state->sprites[k]=(pc_sprite){
   .x=(int16_t)(16+(k%56u)*16u),.y=(int16_t)(80+((k/56u)%19u)*24u),
   .dx=(int8_t)((k&1u?-1:1)*(int)(1u+(k+7u)%3u)),
   .dy=(int8_t)((k&2u?-1:1)*(int)(1u+(2u*k+7u)%3u)),.shape=(uint8_t)((k+7u)%6u)};
  for(unsigned tick=0;tick<3;tick++) {
   game_input input={0};for(unsigned j=0;j<11;j++)CHECK(!pc_advance(state,&input));
   gpu_instance_stats stats;CHECK(!pc_build(state,buffers.back,0,items,GPU_FRAME_LIST_ARENA_ITEMS,&stats));
   CHECK(stats.visible==targets[t] && stats.alpha_commands==(targets[t]+7u)/8u);
   bsp_printf("SPRITE_FIXTURE,target=%d,tick=%d,list_crc=%x\r\n",targets[t],state->tick,
    golden_crc32(items,stats.count*sizeof *items));
   gpu_platform_sync();
   const unsigned starts[]={0,1,1+stats.alpha_commands,0};
   const unsigned counts[]={1,stats.alpha_commands,stats.visible,stats.count};
   for(unsigned stage=0;stage<4;stage++) {
    CHECK(!gpu_clear_perf(&d));uint64_t start=gpu_platform_cycles();
#if GPU_AXI_DIAGNOSTICS
    *(volatile uint32_t *)(d.base+0x604)=3;gpu_platform_sync();
#endif
    CHECK(!gpu_frame_list_render_span(&f,GPU_FRAME_LIST_BANK_A+starts[stage]*16u,counts[stage],1u+stage+tick*4u,10000000u));
#if GPU_AXI_DIAGNOSTICS
    *(volatile uint32_t *)(d.base+0x604)=0;gpu_platform_sync();
#endif
    uint64_t elapsed=gpu_platform_cycles()-start;gpu_perf_snapshot p;CHECK(!gpu_read_perf_snapshot(&d,&p));
    bsp_printf("SPRITE_PHASE,target=%d,tick=%d,stage=%s,count=%d,ticks=%d,busy=%d,stalls=%d,rd=%d,wr=%d,cache=%d,under=%d,scan_grants=%d\r\n",
     targets[t],state->tick,names[stage],counts[stage],(uint32_t)elapsed,(uint32_t)p.cycles,
     (uint32_t)p.stalls,(uint32_t)p.read_bytes,(uint32_t)p.write_bytes,(uint32_t)p.cache_bytes,(uint32_t)p.underflows,(uint32_t)p.scanout_grants);
    CHECK(!p.underflows);
#if GPU_AXI_DIAGNOSTICS
    uint32_t counters[16];for(unsigned i=0;i<16;i++)counters[i]=*(volatile uint32_t *)(d.base+0x610+i*4u);
    CHECK(counters[15] && counters[15]<BSP_CLINT_HZ*40u);
    bsp_printf("AXI_PHASE,target=%d,tick=%d,stage=%s,wbeat=%d,wgap=%d,wstall=%d,bwait=%d,awstall=%d,awqos=%d,rbeat=%d,rgap=%d,rstall=%d,arstall=%d,arqos=%d,rcredit=%d,bcount=%d,awcount=%d,rsink=%d,window=%d\r\n",
     targets[t],state->tick,names[stage],counters[0],counters[1],counters[2],counters[3],counters[4],counters[5],
     counters[6],counters[7],counters[8],counters[9],counters[10],counters[11],counters[12],counters[13],counters[14],counters[15]);
    CHECK(counters[12]==counters[13]);
#endif
   }
   CHECK(!framebuffer_present(&d,&buffers,10000000u));
  }
 }
 bsp_printf("SPRITE_PHASE_STOP,result=0,hardware=%d\r\n",d.hardware_error);return 0;
}
