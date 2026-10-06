/* Diagnostic only: same R7 replay/HUD, old CPU renderer remains untouched.
 * Compare on ONE bitstream. Never infer frontend FPS from the legacy fallback.
 * Includes existing platform/asset/HUD helpers, removed by gc if unused. */
#define main reference_main
#include "../src/main.c"
#undef main
#include "gpu_instances.h"
#include <limits.h>
#define INSTANCE_SAMPLES 300u
static gpu_instance_stream compact;
static gpu_instance_template templates[GPU_INSTANCE_TEMPLATES];
static uint32_t work_us[INSTANCE_SAMPLES];
static unsigned us(uint64_t ticks,unsigned n) { return (unsigned)(ticks/((uint64_t)n*(BSP_CLINT_HZ/1000000u))); }
static int measure(gpu_device *gpu,gpu_instances *frontend,framebuffer_pair *buffers,unsigned target,int use_instances) {
 int e=bullet_reset(&bullets,target,7);if(e) return e;
 hud_comparison m={.bullet_demo=1,.gameplay=1,.gpu_active=1,.network_ready=1};
 perf_window window={0};
 uint64_t build=0,render=0,busy=0,wall=0,work=0,read=0,write=0,cache=0;
 unsigned miss=0,late=0,under=0,commands=0,min=UINT_MAX,max=0;
 uint64_t previous=gpu_platform_cycles(),previous_under=0;
 for(unsigned f=0;f<30u+INSTANCE_SAMPLES;f++) {
  uint64_t t=gpu_platform_cycles();
  if(use_instances) e=gpu_instances_build(&bullets,buffers->back,1,1,HUD_CACHE_HEIGHT,BULLET_MAX_COMMANDS,&compact);
  else {
   e=bullet_build_frame(&bullets,buffers->back,1,1,BULLET_MAX_COMMANDS,&scene);
   if(!e) e=bullet_clip_background_for_hud(&scene,HUD_CACHE_HEIGHT);
  }
  if(e) return e;
  uint64_t b=gpu_platform_cycles()-t;
  gpu_perf_snapshot before,after,done;
  e=gpu_read_perf_snapshot(gpu,&before);if(e) return e;
  gpu_platform_sync();t=gpu_platform_cycles();
  e=use_instances?gpu_instances_render(frontend,templates,&compact,10000000u):
   perf_render_gpu(gpu,scene.commands,scene.count,10000000u);
  if(e) return e;
  gpu_platform_sync();uint64_t r=gpu_platform_cycles()-t;
  e=gpu_read_perf_snapshot(gpu,&after);if(e) return e;
  unsigned visible=use_instances?compact.visible:scene.visible;
  m.sprites=(uint16_t)visible;m.alpha_commands=(uint16_t)(use_instances?compact.alpha_commands:scene.alpha_commands);
  m.hp=bullets.hp;m.score=bullets.score;m.grazes=bullets.grazes;
  m.invulnerable=bullets.invulnerable!=0;m.game_over=bullets.hp==0;m.error_code=gpu->hardware_error;
  e=hud_update_gpu_cache(gpu,&m,&hud_cache,&overlay,10000000u);if(e) return e;
  e=hud_cached_command(buffers->back,&hud_cache,&overlay.commands[0]);if(e) return e;
  e=perf_render_gpu(gpu,overlay.commands,1,10000000u);if(e) return e;
  gpu_platform_sync();t=gpu_platform_cycles();uint64_t w=t-previous;
  e=framebuffer_present(gpu,buffers,10000000u);if(e) return e;
  uint64_t end=gpu_platform_cycles(),duration=end-previous;previous=end;
  e=gpu_read_perf_snapshot(gpu,&done);if(e) return e;
  m.underflows=(uint32_t)done.underflows;
  if(f>=30) {
   unsigned n=f-30;
   build+=b;render+=r;busy+=after.cycles-before.cycles;wall+=duration;work+=w;
   read+=after.read_bytes-before.read_bytes;write+=after.write_bytes-before.write_bytes;
   cache+=after.cache_bytes-before.cache_bytes;under+=(unsigned)(done.underflows-previous_under);
   commands+=use_instances?compact.count:scene.count;
   work_us[n]=us(w,1);miss+=w>BSP_CLINT_HZ/60u;late+=duration>BSP_CLINT_HZ/60u;
   if(visible<min) min=visible;
   if(visible>max) max=visible;
  }
  previous_under=done.underflows;
  e=perf_window_add(&window,duration,r);if(e) return e;
  if(window.frames==30) {
   m.gpu_fps_x10=perf_fps_x10(&window,BSP_CLINT_HZ);
   m.gpu_render_us=perf_render_us(&window,BSP_CLINT_HZ);m.gpu_valid=1;window=(perf_window){0};
  }
  e=bullet_step(&bullets);if(e) return e;
 }
 for(unsigned j=1;j<INSTANCE_SAMPLES;j++) {
  uint32_t v=work_us[j];unsigned k=j;
  while(k && work_us[k-1]>v) {work_us[k]=work_us[k-1];--k;}work_us[k]=v;
 }
 bsp_printf("INSTANCE_FRAME,target=%d,instances=%d,present=%d,frames=300,fps_x10=%d,build_us=%d,scene_us=%d,busy_us=%d,work_us=%d,p95_us=%d,max_us=%d,miss=%d,late=%d,under=%d,error=%d\r\n",
  target,use_instances,frontend->present,(unsigned)((uint64_t)BSP_CLINT_HZ*INSTANCE_SAMPLES*10u/wall),
  us(build,INSTANCE_SAMPLES),us(render,INSTANCE_SAMPLES),us(busy,INSTANCE_SAMPLES),us(work,INSTANCE_SAMPLES),
  work_us[284],work_us[299],miss,late,under,gpu->hardware_error);
 bsp_printf("INSTANCE_TRAFFIC,target=%d,instances=%d,commands_x10=%d,visible_min=%d,visible_max=%d,rd=%d,wr=%d,cache=%d\r\n",
  target,use_instances,commands*10u/INSTANCE_SAMPLES,min,max,(unsigned)(read/INSTANCE_SAMPLES),
  (unsigned)(write/INSTANCE_SAMPLES),(unsigned)(cache/INSTANCE_SAMPLES));
 return under || gpu->hardware_error?GPU_DRIVER_HARDWARE:0;
}
int main(void) {
 bsp_init();gpu_device gpu;int e=gpu_init(&gpu,GPU_APB_BASE);if(e) return e;
 gpu_instances frontend;e=gpu_instances_init(&frontend,&gpu);if(e) goto stop;
 bsp_printf("INSTANCE_START,present=%d,warmup=30,samples=300,hz=%d\r\n",frontend.present,BSP_CLINT_HZ);
 if(!frontend.present) {e=GPU_DRIVER_ID;goto stop;} // No false hardware measurement on fallback.
 unsigned n=gpu_instances_templates(1,templates);
 e=gpu_instances_program(&frontend,templates,n);if(e) goto stop;
#ifdef INSTANCE_EXPAND_PROBE
 /* Isolated Sapphire cost, NOT FPS or pure instruction timing: includes the
  * call, full validation/expansion and one volatile checksum update per item.
  * No resource load/PRESENT/AXI rendering and no repeated 300-frame campaign. */
 static const unsigned probe_targets[]={256,512};
 volatile uint32_t checksum=0;
 for(unsigned j=0;j<2;j++) {
  e=bullet_reset(&bullets,probe_targets[j],7);if(e) goto stop;
  e=gpu_instances_build(&bullets,GPU_FRAMEBUFFER_A,1,1,HUD_CACHE_HEIGHT,BULLET_MAX_COMMANDS,&compact);if(e) goto stop;
  uint64_t begin=gpu_platform_cycles();
  for(unsigned repeat=0;repeat<100;repeat++) for(unsigned k=0;k<compact.count;k++) {
   gpu_command command;
   e=gpu_instance_expand(templates,&compact.items[k],(uint16_t)k,&command);if(e) goto stop;
   checksum+=command.src_addr+command.dst_addr+command.tag;
  }
  uint64_t elapsed=gpu_platform_cycles()-begin;
  bsp_printf("INSTANCE_EXPAND_COST,target=%d,count=%d,repeats=100,frame_us=%d,checksum=%d\r\n",
   probe_targets[j],compact.count,us(elapsed,100),checksum);
 }
 goto stop;
#endif
 e=bullet_prepare_assets(GPU_APB_BASE,(uint32_t)gpu_platform_cycles()|1u);if(e) goto stop;
 hud_init_glyph_atlas();gpu_platform_sync();
 e=bullet_prepare_texture_cache(&gpu,0,10000000u);if(e) goto stop;
 e=gpu_set_qos(&gpu,256,1536,1);if(e) goto stop;
 framebuffer_pair buffers;framebuffer_init(&buffers);
 static const unsigned targets[]={256,512};
 for(unsigned j=0;j<2;j++) for(int mode=0;mode<2;mode++) {
  e=measure(&gpu,&frontend,&buffers,targets[j],mode);if(e) goto stop;
 }
stop:
 bsp_printf("INSTANCE_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error);return e;
}
