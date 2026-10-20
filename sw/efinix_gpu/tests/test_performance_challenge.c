#include "performance_challenge.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static pc_state state;
static gpu_instance descriptors[4097];
static void frame(int pass) {
 assert(pc_record(&state,100000000,pass?1500000:1700000,pass?1663900:3327800,0,0,state.target,(state.target+7)/8)>=0);
}
static void trial(int pass) {
 unsigned generation=state.generation;
 for(unsigned i=0;i<4000 && generation==state.generation && state.stage<PC_DONE;i++)frame(pass);
 assert(state.generation!=generation || state.stage>=PC_DONE);
}
int main(void) {
 assert(!pc_init(&state,1819,7));
 for(unsigned i=0;i<5;i++)trial(1);
 assert(state.target==1819);
 for(unsigned i=0;i<state.target;i++)assert(state.sprites[i].y>=80 && state.sprites[i].y<=516);
 gpu_instance_stats stats;
 memset(descriptors,0xa5,sizeof descriptors);
 assert(pc_build(&state,GPU_FRAMEBUFFER_A,1,descriptors,2047,&stats)==GPU_DRIVER_ARGUMENT);
 assert(!stats.count && descriptors[0].words[0]==0xa5a5a5a5u);
 assert(!pc_build(&state,GPU_FRAMEBUFFER_A,1,descriptors,2048,&stats));
 assert(stats.count==2048 && stats.visible==1819 && stats.alpha_commands==228);
 assert(descriptors[2048].words[0]==0xa5a5a5a5u && descriptors[2048].words[3]==0xa5a5a5a5u);
 for(unsigned t=0;t<120;t++) {
  assert(!pc_advance(&state,&(game_input){0}));
  assert(!pc_build(&state,GPU_FRAMEBUFFER_B,1,descriptors,2048,&stats));
  for(unsigned i=0;i<1819;i++) {
   const pc_sprite *p=state.sprites+i;const gpu_instance *d=descriptors+229+i;
   assert(p->x>=8 && p->x<=936 && p->y>=80 && p->y<=516);
   assert(d->words[1]==GPU_FRAMEBUFFER_B+(uint32_t)p->y*1920u+(uint32_t)p->x*2u);
   assert(d->words[0]==(i?2u+p->shape:8u));
  }
 }
 assert(!pc_init(&state,909,7) && state.target==64 && !state.best);
 for(unsigned i=0;i<900;i++) {
  assert(!pc_advance(&state,&(game_input){0}));
  for(unsigned n=0;n<state.target;n++)assert(state.sprites[n].x>=8 && state.sprites[n].x<=936 && state.sprites[n].y>=80 && state.sprites[n].y<=516);
 }
 assert(!pc_init(&state,909,7));for(unsigned i=0;i<4;i++)trial(1);assert(state.target==909);
 assert(!pc_build(&state,GPU_FRAMEBUFFER_B,1,descriptors,2048,&stats));
 assert(stats.count==1024 && stats.visible==909 && stats.alpha_commands==114);
 assert(descriptors[0].words[0]==0 && descriptors[0].words[1]==GPU_FRAMEBUFFER_B+138240);
 assert(descriptors[1].words[0]==0x00400101u && descriptors[1].words[3]==0x000c000cu);
 assert(descriptors[115].words[0]==8 && descriptors[115].words[3]==0x00100010u);
 static pc_sprite old[909];
 for(unsigned t=0;t<120;t++) {
  for(unsigned i=0;i<909;i++)old[i]=state.sprites[i];
  assert(!pc_advance(&state,&(game_input){0}));
  assert(!pc_build(&state,GPU_FRAMEBUFFER_A,1,descriptors,2048,&stats));
  for(unsigned i=0;i<909;i++) {
   pc_sprite p=state.sprites[i];
   assert(p.x!=old[i].x || p.y!=old[i].y);
   /* Independent per-object destination and atlas reference, not builder reuse. */
   gpu_instance *d=descriptors+115+i;
   assert(d->words[1]==GPU_FRAMEBUFFER_A+(uint32_t)p.y*1920u+(uint32_t)p.x*2u);
   assert(d->words[0]==(i?2u+(i+7u+state.tick/8u)%6u:8u));
  }
 }
 assert(!pc_init(&state,3640,7));
 while(state.target!=3640)trial(1);
 memset(descriptors,0xa5,sizeof descriptors);
 assert(pc_build(&state,GPU_FRAMEBUFFER_A,1,descriptors,4095,&stats)==GPU_DRIVER_ARGUMENT);
 assert(!stats.count && descriptors[0].words[0]==0xa5a5a5a5u);
 assert(!pc_build(&state,GPU_FRAMEBUFFER_A,1,descriptors,4096,&stats));
 assert(stats.count==4096 && stats.visible==3640 && stats.alpha_commands==455);
 assert(descriptors[4096].words[0]==0xa5a5a5a5u && descriptors[4096].words[3]==0xa5a5a5a5u);
 for(unsigned i=0;i<3640;i++) {
  assert(descriptors[456+i].words[0]==(i?2u+state.sprites[i].shape:8u));
  assert(descriptors[456+i].words[1]==GPU_FRAMEBUFFER_A+(uint32_t)state.sprites[i].y*1920u+(uint32_t)state.sprites[i].x*2u);
 }
 assert(PC_STATE_ADDRESS>=GPU_FRAME_LIST_BANK_A+4096u*16u && PC_STATE_ADDRESS+sizeof(state)<=0x02d40000u);
 assert(pc_init(NULL,64,7)<0 && pc_init(&state,3641,7)<0);
 assert(!pc_init(&state,512,7));
 assert(pc_record(&state,100000000,1500000,1663900,1,0,64,8)>=0);
 assert(state.stage==PC_FAILED && !state.best); /* Warmup health cannot be discarded. */
 assert(!pc_init(&state,64,7));
 for(unsigned i=0;i<60;i++)frame(1);
 for(unsigned i=0;i<599;i++)frame(1);
 assert(!state.best && state.stage==PC_SAMPLE);
 frame(1);assert(!state.best); /*600frames only nominates, not final qualification. */
 trial(1);assert(state.stage==PC_CAPACITY && state.best==64 && state.stats.frames==3600);
 frame(0);assert(state.stage==PC_FAILED && !state.best);
 assert(!pc_init(&state,128,7));trial(1);trial(0);
 while(state.stage<PC_DONE)trial(state.target<=96);
 assert(state.best==96 && state.stage==PC_DONE);
 assert(!pc_init(&state,64,7));for(unsigned i=0;i<60;i++)frame(1);
 assert(pc_record(&state,100000000,1500000,1666668,0,0,64,8)>=0);
 for(unsigned i=1;i<600;i++)assert(pc_record(&state,100000000,1500000,1666668,0,0,64,8)>=0);
 assert(!state.best); /* Precise59.9999 is not rounded60.0. */
 assert(!pc_init(&state,64,7));trial(1);trial(0);
 assert(!state.best && state.target<64 && state.stage<PC_DONE); /* Long recheck fail researches lower bracket. */
 puts("PASS performance challenge:3640active/4096descriptors,1819/909compat,capacity/canary,Alpha+Key,strict600vs3600,bounds/invalidation");
}
