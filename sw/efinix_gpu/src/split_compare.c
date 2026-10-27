#include "split_compare.h"
#include "perf_demo.h"
#include "benchmark.h"
#include <string.h>
static const unsigned targets[2]={256,512};
static char *label(char *p,const char *s){while(*s)*p++=*s++;*p=0;return p;}
static char *number(char *p,uint32_t v){char r[10];unsigned n=0;do{r[n++]=(char)('0'+v%10);v/=10;}while(v);while(n)*p++=r[--n];*p=0;return p;}
static char *decimal(char *p,uint32_t tenths){p=number(p,tenths/10);p=label(p,".");return number(p,tenths%10);}
static void text(hud_command_stream *s,uint32_t dst,unsigned x,unsigned y,const char *line,int green) {
 for(unsigned i=0;line[i] && x+(i+1u)*14u<=960;i++) {
  const char *g=strchr(HUD_GLYPH_CHARACTERS,line[i]);unsigned index=g?(unsigned)(g-HUD_GLYPH_CHARACTERS):38;
  s->commands[s->count++]=(gpu_command){.op=GPU_OP_COPY,
   .src_addr=HUD_GLYPH_ATLAS_ADDR+(green?HUD_GLYPH_BANK_BYTES:0)+index*HUD_GLYPH_CELL_BYTES,
   .dst_addr=dst+y*GPU_FRAME_STRIDE+(x+i*14u)*2u,.src_stride=28,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=14,.height_pixels=18};
 }
}
static void fill(hud_command_stream *s,uint32_t dst,unsigned y,unsigned height) {
 s->commands[s->count++]=(gpu_command){.op=GPU_OP_FILL,.dst_addr=dst+y*GPU_FRAME_STRIDE,
  .dst_stride=GPU_FRAME_STRIDE,.width_pixels=960,.height_pixels=(uint16_t)height};
}
static uint32_t fps(unsigned frames,uint64_t elapsed,uint32_t hz){return elapsed?(uint32_t)((uint64_t)frames*hz*10u/elapsed):0;}
static void cached_text(hud_command_stream *out,uint32_t dst,unsigned x,unsigned y,const char *line,int green,const char *old,char *next) {
 unsigned n=0,previous=0;while(n<63 && line[n])n++;while(previous<63 && old[previous])previous++;
 memset(next,0,64);memcpy(next,line,n);
 for(unsigned i=0;i<(n>previous?n:previous);i++) {
  char a=i<n?line[i]:' ',b=i<previous?old[i]:' ';
  if(a!=b){char glyph[2]={a,0};text(out,dst,x+i*14u,y,glyph,green);}
 }
}
static int hud(split_compare_state *s,gpu_device *gpu,uint32_t dst,hud_command_stream *out,uint32_t hz,uint32_t polls,int force) {
 unsigned bank=dst==GPU_FRAMEBUFFER_B;
 uint32_t epoch=(uint32_t)(s->elapsed_ticks[s->tier]/(hz/4u));
 if(!force && s->hud_epoch[bank]==epoch)return 0;
 char next[10][64];memcpy(next,s->hud_text[bank],sizeof next);out->count=0;
 #define LINE(id,x,y,value,green) cached_text(out,dst,x,y,value,green,s->hud_text[bank][id],next[id])
 LINE(0,28,14,"CPU VS GPU - INDEPENDENT REFRESH",1);
 char line[64],*p=number(line,targets[s->tier]);p=label(p," SPRITES - ");
 p=decimal(p,(uint32_t)(s->elapsed_ticks[s->tier]*10u/hz));label(p," OF 15.0 SECONDS");LINE(1,28,42,line,0);
 LINE(2,28,76,"CPU - SOFTWARE",0);LINE(3,508,76,"GPU - HARDWARE",1);
 unsigned frames[2]={s->cpu_frames[s->tier],s->gpu_frames[s->tier]};
 for(unsigned i=0;i<2;i++) {
  p=decimal(line,fps(frames[i],s->elapsed_ticks[s->tier],hz));p=label(p," FPS - ");p=number(p,frames[i]);label(p," FRAMES");
  LINE(4+i,28+i*480u,106,line,i);
 }
 LINE(6,28,430,"SAME 480X270 VIEW - ACTUAL DISPLAY FPS",1);
 for(unsigned i=0;i<2;i++)if(s->elapsed_ticks[i]) {
  p=number(line,targets[i]);p=label(p," - CPU ");p=decimal(p,fps(s->cpu_frames[i],s->elapsed_ticks[i],hz));
  p=label(p," FPS  GPU ");p=decimal(p,fps(s->gpu_frames[i],s->elapsed_ticks[i],hz));label(p," FPS");
  LINE(7+i,28,462+i*34u,line,0);
 }
 LINE(9,28,522,s->done?"DONE - WEB MENU TO EXIT":"15 SECONDS EACH - WEB MENU TO EXIT",0);
 #undef LINE
 int e=out->count?perf_render_gpu(gpu,out->commands,out->count,polls):0;
 if(!e){s->hud_epoch[bank]=epoch;memcpy(s->hud_text[bank],next,sizeof next);}return e;
}
int split_compare_init(split_compare_state *s) {
 if(!s)return GPU_DRIVER_ARGUMENT;
 memset(s,0,sizeof *s);s->cpu_front=SPLIT_CPU_SURFACE;s->cpu_back=SPLIT_GPU_SURFACE;
 s->hud_epoch[0]=s->hud_epoch[1]=UINT32_MAX;return game_reset(&s->game,targets[0],7);
}
static int cpu_row(split_compare_state *s) {
 if(!s->cpu_active || s->cpu_ready)return 0;
 gpu_command c=s->cpu_scene.commands[s->cpu_command];
 c.src_addr+=s->cpu_row*c.src_stride;c.dst_addr+=s->cpu_row*c.dst_stride;c.height_pixels=1;
 uint64_t start=gpu_platform_cycles();int e=perf_render_cpu_surface(&c,1,s->cpu_back);
 s->cpu_job_ticks+=gpu_platform_cycles()-start;if(e)return e;
 if(++s->cpu_row==s->cpu_scene.commands[s->cpu_command].height_pixels){s->cpu_row=0;++s->cpu_command;}
 if(s->cpu_command==s->cpu_scene.count) {
  gpu_platform_sync();s->ready_ticks=s->cpu_job_ticks;s->cpu_ready=1;s->cpu_active=0;
 }
 return 0;
}
static int start_tier(split_compare_state *s,gpu_device *gpu,framebuffer_pair *fb,hud_command_stream *scratch,uint32_t hz,uint32_t polls,int (*service)(void *),void *context) {
 int e=game_reset(&s->game,targets[s->tier],7);if(e)return e;
 s->initial=s->game;s->cpu_generation=1;s->copied_generation[0]=s->copied_generation[1]=0;
 s->clock=(game_clock){0};s->cpu_active=s->cpu_ready=0;s->cleared[0]=s->cleared[1]=0;
 s->hud_epoch[0]=s->hud_epoch[1]=UINT32_MAX;
 memset(s->hud_text,0,sizeof s->hud_text);
 gpu_command blank={.op=GPU_OP_FILL,.dst_addr=s->cpu_front,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=480,.height_pixels=270};
 s->stage=2;e=perf_render_gpu(gpu,&blank,1,polls);if(e)return e;
 /* Static display setup precedes both timed windows; no animated frame is
  * pre-rendered. CPU starts from its blank completed buffer at time0. */
 for(unsigned pass=0;pass<2;pass++) {
  uint32_t dst=fb->back;unsigned bank=dst==GPU_FRAMEBUFFER_B;
  scratch->count=0;fill(scratch,dst,0,540);e=perf_render_gpu(gpu,scratch->commands,1,polls);if(e)return e;
  s->cleared[bank]=1;e=hud(s,gpu,dst,scratch,hz,polls,1);if(e)return e;
  /* Retire static UI before reusing the former front; never draw into the
   * active scanout surface, including menu/tier transitions. */
  if(!pass){e=framebuffer_present(gpu,fb,polls);if(e)return e;}
  if(service && (e=service(context)))return e;
 }
 s->start=s->last_logic=gpu_platform_cycles();s->started=1;return 0;
}
int split_compare_step(split_compare_state *s,gpu_device *gpu,framebuffer_pair *fb,int network,
 bullet_stream *scene,hud_command_stream *scratch,uint32_t hz,uint32_t polls,int (*service)(void *),void *context) {
 if(!s || !gpu || !fb || !scene || !scratch || hz<4 || !polls || s->tier>1 || (network!=0 && network!=1))return GPU_DRIVER_ARGUMENT;
 if(s->done)return 0;
 int e;if(service && (e=service(context)))return e;
 if(!s->prepared){
  e=split_view_prepare(network,service,context);if(e)return e;
  s->stage=1;e=gpu_texture_cache_load(gpu,SPLIT_ATLAS,BULLET_ATLAS_BYTES,polls);if(e)return e;
  s->prepared=1;
 }
 if(s->completed[0] && !s->tier){s->tier=1;s->started=0;}
 if(!s->started){e=start_tier(s,gpu,fb,scratch,hz,polls,service,context);if(e)return e;}
 uint64_t window=(uint64_t)hz*SPLIT_WINDOW_SECONDS,now=gpu_platform_cycles();
 if(now-s->start>=window)goto finish;
 game_input neutral={0};e=game_advance_cached(&s->clock,&s->game,&neutral,(uint32_t)((now-s->last_logic)*1000000u/hz),&s->initial);if(e<0)return e;s->last_logic=now;
 s->logic_ticks[s->tier]+=gpu_platform_cycles()-now;
 unsigned new_cpu=s->cpu_ready;uint64_t visible_cpu_ticks=s->ready_ticks;
 if(new_cpu){uint32_t old=s->cpu_front;s->cpu_front=s->cpu_back;s->cpu_back=old;s->cpu_ready=0;++s->cpu_generation;}
 if(!s->cpu_active) {
  uint64_t build=gpu_platform_cycles();
  e=split_view_build(&s->game,network,s->cpu_back,&s->cpu_scene);if(e)return e;
  s->build_ticks[s->tier]+=gpu_platform_cycles()-build;
  s->cpu_command=s->cpu_row=0;s->cpu_job_ticks=0;s->cpu_active=1;
 }
 unsigned bank=fb->back==GPU_FRAMEBUFFER_B;
 if(!s->cleared[bank]) {scratch->count=0;fill(scratch,fb->back,0,540);s->stage=3;e=perf_render_gpu(gpu,scratch->commands,1,polls);if(e)return e;s->cleared[bank]=1;}
 gpu_command left={.op=GPU_OP_COPY,.src_addr=s->cpu_front,.dst_addr=fb->back+144u*GPU_FRAME_STRIDE,
  .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=480,.height_pixels=270};
 if(s->copied_generation[bank]!=s->cpu_generation) {
  uint64_t copy=gpu_platform_cycles();
  s->stage=4;e=perf_render_gpu(gpu,&left,1,polls);if(e)return e;
  s->copy_ticks[s->tier]+=gpu_platform_cycles()-copy;
  s->copied_generation[bank]=s->cpu_generation;
 }
 uint64_t build=gpu_platform_cycles();e=split_view_build(&s->game,network,fb->back+144u*GPU_FRAME_STRIDE+960u,scene);if(e)return e;
 s->build_ticks[s->tier]+=gpu_platform_cycles()-build;
 uint64_t render=gpu_platform_cycles();s->stage=5;e=perf_render_gpu(gpu,scene->commands,scene->count,polls);if(e)return e;
 uint64_t gpu_ticks=gpu_platform_cycles()-render;
 s->elapsed_ticks[s->tier]=gpu_platform_cycles()-s->start;
 s->stage=6;e=hud(s,gpu,fb->back,scratch,hz,polls,0);if(e)return e;
 if(service && (e=service(context)))return e;
 uint16_t tag;s->stage=7;e=gpu_present_async(gpu,fb->back,&tag);if(e)return e;
 int cancelled=0,retired=0;
 for(uint32_t i=0;i<polls;i++) {
  s->stage=8;e=gpu_poll(gpu,tag);if(e<0)return e;
  if(e!=GPU_POLL_PENDING){retired=1;break;}
  if(!cancelled && gpu_platform_cycles()-s->start<window){s->stage=9;e=cpu_row(s);if(e)cancelled=e;}
  if(!cancelled && service)cancelled=service(context);
 }
 if(!retired)return GPU_DRIVER_TIMEOUT;
 uint32_t old=fb->front;fb->front=fb->back;fb->back=old;
 if(cancelled)return cancelled; /* PRESENT and every prior command have retired. */
 now=gpu_platform_cycles();
 if(now-s->start<=window) {
  ++s->gpu_frames[s->tier];s->gpu_ticks[s->tier]+=gpu_ticks;
  if(new_cpu){++s->cpu_frames[s->tier];s->cpu_ticks[s->tier]+=visible_cpu_ticks;}
 }
 if(now-s->start<window){s->elapsed_ticks[s->tier]=now-s->start;return 0;}
finish:
 s->elapsed_ticks[s->tier]=window;s->completed[s->tier]=1;s->done=(uint8_t)(s->tier==1);
 /* Publish final scores outside the15-second window; this panel refresh does
  * not count as an extra animated frame for either renderer. */
 scratch->count=1;scratch->commands[0]=(gpu_command){.op=GPU_OP_COPY,.src_addr=fb->front,.dst_addr=fb->back,
  .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,.width_pixels=960,.height_pixels=540};
 e=perf_render_gpu(gpu,scratch->commands,1,polls);if(e)return e;
 memcpy(s->hud_text[fb->back==GPU_FRAMEBUFFER_B],s->hud_text[fb->front==GPU_FRAMEBUFFER_B],sizeof s->hud_text[0]);
 e=hud(s,gpu,fb->back,scratch,hz,polls,1);if(e)return e;
 return framebuffer_present(gpu,fb,polls);
}
