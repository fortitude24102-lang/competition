#include "split_compare.h"
#include "split_view.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint64_t clock_ticks,present_at;
static unsigned native_gpu,partial_cpu,presented,cache_loads,left_copies,hud_commands;
static int fail;
static int pending,cancel_pending;
static uint32_t scan_front=GPU_FRAMEBUFFER_A,pending_front;
static char painted[2][10][64];
static void paint(const gpu_command *c) {
 assert(c->dst_addr<scan_front || c->dst_addr>=scan_front+GPU_FRAME_BYTES);
 unsigned bank=c->dst_addr>=GPU_FRAMEBUFFER_B;uint32_t base=bank?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
 if(c->dst_addr<base || c->dst_addr-base>=GPU_FRAME_BYTES)return;
 if(c->op==GPU_OP_FILL && c->dst_addr==base && c->width_pixels==960 && c->height_pixels==540){memset(painted[bank],0,sizeof painted[bank]);return;}
 if(c->op==GPU_OP_COPY && c->width_pixels==960 && c->height_pixels==540 && (c->src_addr==GPU_FRAMEBUFFER_A || c->src_addr==GPU_FRAMEBUFFER_B)){memcpy(painted[bank],painted[c->src_addr==GPU_FRAMEBUFFER_B],sizeof painted[bank]);return;}
 if(c->op!=GPU_OP_COPY || c->width_pixels!=14 || c->height_pixels!=18 || c->src_addr<HUD_GLYPH_ATLAS_ADDR || c->src_addr>=HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES)return;
 unsigned off=c->dst_addr-base,y=off/GPU_FRAME_STRIDE,x=(off%GPU_FRAME_STRIDE)/2,line=99,origin=28;
 if(y==14)line=0;else if(y==42)line=1;else if(y==76 || y==106){unsigned side=x>=508;line=(y==76?2:4)+side;origin+=side*480;}else if(y==430)line=6;else if(y==462)line=7;else if(y==496)line=8;else if(y==522)line=9;
 assert(line<10 && x>=origin && !((x-origin)%14));unsigned col=(x-origin)/14;
 unsigned glyph=((c->src_addr-HUD_GLYPH_ATLAS_ADDR)%HUD_GLYPH_BANK_BYTES)/HUD_GLYPH_CELL_BYTES;
 assert(col<64 && glyph<39);painted[bank][line][col]=HUD_GLYPH_CHARACTERS[glyph];
}
uint64_t gpu_platform_cycles(void){return clock_ticks;}
void gpu_platform_sync(void){}
int game_reset(bullet_state *s,unsigned n,uint32_t seed){memset(s,0,sizeof *s);s->count=n;s->seed=seed;return 0;}
int game_advance_cached(game_clock *c,bullet_state *s,const game_input *in,uint32_t elapsed,const bullet_state *initial){(void)c;assert(!in->held && initial->count==s->count && initial->seed==s->seed);s->tick+=elapsed/16666;return 0;}
int split_view_prepare(int n,int(*service)(void *),void *ctx){assert(n==1);return service?service(ctx):0;}
int split_view_build(const bullet_state *s,int network,uint32_t dst,bullet_stream *b){
 assert(network==1);b->count=2;b->visible=s->count;
 b->commands[0]=(gpu_command){.op=GPU_OP_COPY,.src_addr=SPLIT_BACKGROUND,.src_stride=960,.dst_addr=dst,.dst_stride=1920,.width_pixels=480,.height_pixels=270};
 b->commands[1]=(gpu_command){.op=GPU_OP_COLOR_KEY,.src_addr=SPLIT_ATLAS,.src_stride=8,.dst_addr=dst+100*1920+100,.dst_stride=1920,.width_pixels=4,.height_pixels=4};return 0;
}
int perf_render_cpu_surface(const gpu_command *c,unsigned n,uint32_t base){assert(n==1 && c->height_pixels==1 && (base==SPLIT_CPU_SURFACE || base==SPLIT_GPU_SURFACE));partial_cpu++;clock_ticks+=c->width_pixels;return 0;}
int perf_render_gpu(gpu_device *d,const gpu_command *c,unsigned n,uint32_t polls){(void)d;assert(polls && n);clock_ticks+=1000+n*3;if(n==2 && c[0].src_addr==SPLIT_BACKGROUND)native_gpu++;if(n==1 && (c[0].src_addr==SPLIT_CPU_SURFACE || c[0].src_addr==SPLIT_GPU_SURFACE))left_copies++;for(unsigned i=0;i<n;i++){paint(c+i);if(c[i].op==GPU_OP_COPY && c[i].src_addr>=HUD_GLYPH_ATLAS_ADDR && c[i].src_addr<HUD_GLYPH_ATLAS_ADDR+HUD_GLYPH_ATLAS_BYTES)hud_commands++;}return fail?GPU_DRIVER_HARDWARE:0;}
int gpu_texture_cache_load(gpu_device *d,uint32_t base,uint32_t bytes,uint32_t polls){(void)d;assert(base==SPLIT_ATLAS && bytes==BULLET_ATLAS_BYTES && bytes<=4096 && polls);cache_loads++;return 0;}
int gpu_present_async(gpu_device *d,uint32_t dst,uint16_t *tag){(void)d;assert((dst==GPU_FRAMEBUFFER_A || dst==GPU_FRAMEBUFFER_B) && dst!=scan_front);pending_front=dst;present_at=(clock_ticks/16666+1)*16666;*tag=1;presented++;pending=1;return 0;}
int gpu_poll(gpu_device *d,uint16_t tag){(void)d;assert(tag==1);if(clock_ticks<present_at){clock_ticks+=200;return GPU_POLL_PENDING;}pending=0;scan_front=pending_front;return 0;}
int framebuffer_present(gpu_device *d,framebuffer_pair *fb,uint32_t polls){uint16_t tag;assert(polls);gpu_present_async(d,fb->back,&tag);while(gpu_poll(d,tag)==GPU_POLL_PENDING){}uint32_t a=fb->front;fb->front=fb->back;fb->back=a;return 0;}
static int service(void *ctx){return pending && cancel_pending?cancel_pending:ctx?1:0;}
static split_compare_state state;static bullet_stream scene;static hud_command_stream scratch;
int main(void){
 gpu_device gpu={.ready=1};framebuffer_pair fb={GPU_FRAMEBUFFER_A,GPU_FRAMEBUFFER_B};
 assert(!split_compare_init(&state));
 for(unsigned guard=0;!state.done;guard++){
  assert(guard<2500);assert(!split_compare_step(&state,&gpu,&fb,1,&scene,&scratch,1000000,1000,service,NULL));
  for(unsigned b=0;b<2;b++)for(unsigned l=0;l<10;l++)for(unsigned c=0;c<64;c++)assert((painted[b][l][c]?painted[b][l][c]:' ')==(state.hud_text[b][l][c]?state.hud_text[b][l][c]:' '));
 }
 for(unsigned i=0;i<2;i++){assert(state.completed[i] && state.elapsed_ticks[i]==15000000);assert(state.cpu_frames[i]>0);assert(state.gpu_frames[i]>300 && state.gpu_frames[i]>2*state.cpu_frames[i]);}
 assert(native_gpu>600 && partial_cpu>1000 && presented>600 && cache_loads==1);
 assert(left_copies<=2*(state.cpu_frames[0]+state.cpu_frames[1]+4));
 assert(hud_commands<10000);
 unsigned old=presented;assert(!split_compare_step(&state,&gpu,&fb,1,&scene,&scratch,1000000,1000,service,NULL) && presented==old);
 assert(!split_compare_init(&state));assert(split_compare_step(&state,&gpu,&fb,1,&scene,&scratch,1000000,1000,service,&state)==1 && !state.gpu_frames[0]);
 fail=1;assert(split_compare_step(&state,&gpu,&fb,1,&scene,&scratch,1000000,1000,service,NULL)==GPU_DRIVER_HARDWARE && !state.gpu_frames[0]);
 fail=0;
 for(int reason=1;reason>=-2;reason-=3) {
  assert(!split_compare_init(&state));cancel_pending=reason;
  assert(split_compare_step(&state,&gpu,&fb,1,&scene,&scratch,1000000,1000,service,NULL)==reason);
  assert(!pending && fb.front==scan_front && fb.front!=fb.back && !state.gpu_frames[0] && !state.cpu_frames[0]);
  cancel_pending=0;assert(!split_compare_init(&state));
  assert(!split_compare_step(&state,&gpu,&fb,1,&scene,&scratch,1000000,1000,service,NULL));
  assert(state.gpu_frames[0]==1 && !pending);
 }
 puts("PASS timed split:2x15seconds,independent presented-frame counts,CPU work during GPU/PRESENT,no300limit,cancel/error/noextra-after-done");
}
