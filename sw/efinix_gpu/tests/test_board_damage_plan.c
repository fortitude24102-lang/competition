/* Isolated Sapphire planner timings: NO render, NO display, NOT FPS evidence. */
#define main reference_main
#include "../src/main.c"
#undef main
static gpu_damage_state damage;
static gpu_damage_result plan;
int main(void) {
 bsp_init();
 static const gpu_damage_config policies[]={
  {16,4,128,{517,64,164}},{32,4,128,{517,64,164}}};
 bsp_printf("DAMAGE_PLAN_START,no_render=1,hz=%d\r\n",BSP_CLINT_HZ);
 for(unsigned k=0;k<2;k++) {
  int e=gpu_damage_init(&damage,policies+k); if(e) return e;
  e=bullet_reset(&bullets,512,7); if(e) return e;
  uint64_t total=0; unsigned max=0;
  for(unsigned frame=0;frame<102;frame++) {
   uint32_t base=frame&1?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
   e=bullet_build_frame(&bullets,base,1,1,BULLET_MAX_COMMANDS,&scene); if(e) return e;
   e=bullet_clip_background_for_hud(&scene,72); if(e) return e;
   gpu_platform_sync(); uint64_t t=gpu_platform_cycles();
   e=gpu_damage_plan(&damage,scene.commands,scene.count,1,&plan); if(e<0) return e;
   gpu_damage_commit(&damage,1); uint64_t ticks=gpu_platform_cycles()-t;
   if(frame>=2) { total+=ticks; if(ticks>max) max=(unsigned)ticks; }
   e=bullet_step(&bullets); if(e) return e;
  }
  bsp_printf("DAMAGE_PLAN,tile=%d,gap=4,target=512,samples=100,ticks=%d,max_ticks=%d,no_render=1\r\n",
   policies[k].tile,(unsigned)(total/100),max);
 }
 bsp_printf("DAMAGE_PLAN_STOP,result=0\r\n"); return 0;
}
