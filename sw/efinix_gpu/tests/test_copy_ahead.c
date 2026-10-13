/* Catch waiting before build, duplicated background, changed Sprite order,
 * unsafe mismatch/partial-frame retries, and a lost final tag. Real driver
 * and builders; only external MMIO/DDR are replaced by the host fixture. */
#define V3_COPY_AHEAD 1
#define V3_LOGIC_COPY 1
#include "../src/v3_demo.c"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[64];
static unsigned commits,done_reads;
static gpu_command emitted[BULLET_MAX_COMMANDS],baseline[BULLET_MAX_COMMANDS];
static uint8_t background_pixels[GPU_FRAME_BYTES],atlas[BULLET_ATLAS_BYTES];
static uint8_t pixels[GPU_FRAME_BYTES],reference[GPU_FRAME_BYTES];
static bullet_state state;
static bullet_stream stream;
static uint32_t frame_base;
static v3_runtime runtime;
static int observe_tick,defer_done;
static void execute(const gpu_command *c) {
 if(c->op==GPU_OP_FILL) {
  golden_surface dst={pixels,sizeof pixels,960,540,1920};
  unsigned pixel=(c->dst_addr-frame_base)/2u;
  assert(!golden_fill(&dst,pixel%960,pixel/960,c->width_pixels,c->height_pixels,c->color));return;
 }
 unsigned offset;
 uint8_t *data;unsigned available;
 if(c->src_addr>=BULLET_LOCAL_BACKGROUND && c->src_addr<BULLET_LOCAL_BACKGROUND+GPU_FRAME_BYTES)
  {offset=c->src_addr-BULLET_LOCAL_BACKGROUND;data=background_pixels+offset;available=GPU_FRAME_BYTES-offset;}
 else if(c->src_addr>=BULLET_BACKGROUND_ADDR && c->src_addr<BULLET_BACKGROUND_ADDR+GPU_FRAME_BYTES)
  {offset=c->src_addr-BULLET_BACKGROUND_ADDR;data=background_pixels+offset;available=GPU_FRAME_BYTES-offset;}
 else {
  offset=c->src_addr-(c->src_addr>=BULLET_LOCAL_ATLAS?BULLET_LOCAL_ATLAS:BULLET_ATLAS_ADDR);
  assert(offset<BULLET_ATLAS_BYTES);data=atlas+offset;available=BULLET_ATLAS_BYTES-offset;
 }
 golden_surface src={data,available,c->width_pixels,c->height_pixels,c->src_stride};
 golden_surface dst={pixels,sizeof pixels,960,540,1920};
 unsigned pixel=(c->dst_addr-frame_base)/2u;int e;
 if(c->op==GPU_OP_COPY)e=golden_copy(&dst,pixel%960,pixel/960,&src,0,0,c->width_pixels,c->height_pixels);
 else if(c->op==GPU_OP_COLOR_KEY)e=golden_color_key(&dst,pixel%960,pixel/960,&src,0,0,c->width_pixels,c->height_pixels,c->color_key);
 else {assert(c->op==GPU_OP_ALPHA);e=golden_alpha_blend(&dst,pixel%960,pixel/960,&src,0,0,c->width_pixels,c->height_pixels,c->alpha);}
 assert(!e);
}
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);if(r==GPU_REG_LAST_DONE)++done_reads;
 return regs[r/4];
}
void gpu_io_write(uintptr_t a,uint32_t v) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);regs[r/4]=v;
 if(r==GPU_REG_CONTROL && v==GPU_CONTROL_SUBMIT) {
  if(observe_tick)assert(runtime.game.tick==0); /* Actual issue must precede advance. */
  assert(commits<BULLET_MAX_COMMANDS);gpu_command *c=&emitted[commits++];
  memset(c,0,sizeof *c);
  c->op=(uint8_t)regs[GPU_REG_OP/4];c->src_addr=regs[GPU_REG_SRC_ADDR/4];c->dst_addr=regs[GPU_REG_DST_ADDR/4];
  c->src_stride=regs[GPU_REG_SRC_STRIDE/4];c->dst_stride=regs[GPU_REG_DST_STRIDE/4];
  c->width_pixels=(uint16_t)regs[GPU_REG_SIZE/4];c->height_pixels=(uint16_t)(regs[GPU_REG_SIZE/4]>>16);
  c->color=(uint16_t)regs[GPU_REG_COLOR_KEY/4];c->color_key=(uint16_t)(regs[GPU_REG_COLOR_KEY/4]>>16);
  c->alpha=(uint8_t)regs[GPU_REG_ALPHA_FLAGS/4];c->flags=(uint16_t)(regs[GPU_REG_ALPHA_FLAGS/4]>>16);
  execute(c);if(!defer_done)regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];
 }
}
void gpu_io_fence(void) {}
static void reset(gpu_device *d) {
 memset(regs,0,sizeof regs);regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 regs[GPU_REG_STATUS/4]=GPU_STATUS_EMPTY;regs[GPU_REG_LAST_DONE/4]=65534;
 assert(!gpu_init(d,GPU_APB_BASE));commits=done_reads=0;memset(pixels,0xa5,sizeof pixels);
}
static void read_file(const char *path,void *dst,unsigned size) {
 FILE *f=fopen(path,"rb");assert(f && fread(dst,1,size,f)==size && fgetc(f)==EOF && !fclose(f));
}
int main(void) {
 read_file("sw/efinix_gpu/assets/interactive/background.rgb565",background_pixels,sizeof background_pixels);
 read_file("sw/efinix_gpu/assets/interactive/atlas.rgb565",atlas,sizeof atlas);
 assert(!game_reset(&state,512,7));gpu_device d;gpu_command bg;uint16_t tag;
 unsigned samples=0;
 for(unsigned tick=0;tick<600;tick++) {
  game_input in={.held=V3_KEY_FIRE|(tick%120<60?V3_KEY_RIGHT:V3_KEY_LEFT)};
  assert(!game_update(&state,&in));if(tick%30!=29)continue;
  unsigned net=samples&1;frame_base=samples&2?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
  reset(&d);assert(!game_build(&state,frame_base,net,1,BULLET_MAX_COMMANDS,&stream));
  assert(!bullet_clip_background_for_hud(&stream,72));unsigned count=stream.count;
  assert(!perf_render_gpu(&d,stream.commands,count,100));
  memcpy(baseline,emitted,sizeof baseline);memcpy(reference,pixels,sizeof pixels);
  reset(&d);assert(!copy_ahead_begin(&d,frame_base,net,&bg,&tag,100));
  assert(commits==1 && done_reads==0 && d.outstanding==1);
  assert(bg.op==GPU_OP_COPY && bg.width_pixels==960 && bg.height_pixels==468 && bg.dst_addr==frame_base+138240);
  assert(bg.src_addr==(net?0x02921c00u:0x02b21c00u));
  assert(!game_build(&state,frame_base,net,1,BULLET_MAX_COMMANDS,&stream));
  assert(!bullet_clip_background_for_hud(&stream,72));
  assert(!copy_ahead_finish(&d,&bg,tag,&stream,100));
  assert(commits==count && !d.outstanding && !memcmp(baseline,emitted,count*sizeof *emitted));
  assert(!memcmp(reference,pixels,sizeof pixels));++samples;
 }
 frame_base=GPU_FRAMEBUFFER_A;reset(&d);
 assert(!copy_ahead_begin(&d,frame_base,1,&bg,&tag,100));
 stream.commands[0]=bg;stream.count=1;assert(!copy_ahead_finish(&d,&bg,tag,&stream,100));
 assert(commits==1 && done_reads && !d.outstanding);
 reset(&d);assert(copy_ahead_begin(&d,frame_base+2,1,&bg,&tag,100)==GPU_DRIVER_ARGUMENT && !commits);
 assert(copy_ahead_begin(&d,frame_base,2,&bg,&tag,100)==GPU_DRIVER_ARGUMENT && !commits);
 assert(!copy_ahead_begin(&d,frame_base,1,&bg,&tag,100));
 stream.commands[0]=bg;stream.count=1;stream.commands[0].height_pixels=467;
 assert(copy_ahead_finish(&d,&bg,tag,&stream,100)==GPU_DRIVER_ARGUMENT && commits==1);
 stream.count=0;assert(copy_ahead_finish(&d,&bg,tag,&stream,100)==GPU_DRIVER_ARGUMENT && commits==1);
 regs[GPU_REG_ERROR/4]=9;
 assert(copy_ahead_begin(&d,frame_base,1,&bg,&tag,100)==GPU_DRIVER_HARDWARE && commits==1);
 reset(&d);regs[GPU_REG_STATUS/4]=GPU_STATUS_FULL;tag=0xbeef;
 assert(copy_ahead_begin(&d,frame_base,1,&bg,&tag,0)==GPU_DRIVER_TIMEOUT && !commits && tag==0xbeef);
 printf("PASS Copy ahead: 600 game ticks, %u full-pixel/ordered-MMIO samples, A/B local/net, no early wait/double Copy, mismatch/error/timeout\n",samples);
 /* Real game/runtime/driver, only external MMIO/DDR substituted. An early
  * Copy overlapping CPU/MENU, or a duplicate launch, breaks these checks. */
 for(unsigned net=0;net<2;net++)for(unsigned bank=0;bank<2;bank++) {
  frame_base=bank?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
  reset(&d);assert(!v3_runtime_init(&runtime,512,7,1));
  game_input in={0};assert(v3_runtime_advance(&runtime,&in,16667)==1);
  assert(!game_build(&runtime.game,frame_base,net,1,BULLET_MAX_COMMANDS,&stream));
  assert(!bullet_clip_background_for_hud(&stream,72));
  assert(!perf_render_gpu(&d,stream.commands,stream.count,100));
  memcpy(reference,pixels,sizeof pixels);unsigned count=commits;
  reset(&d);assert(!v3_runtime_init(&runtime,512,7,1));int issued=-1;
  observe_tick=1;
  assert(copy_ahead_advance(&d,&runtime,&in,16667,frame_base,net,&bg,&tag,&issued,100)==1);
  observe_tick=0;
  assert(runtime.game.tick==1 && issued && commits==1 && !done_reads && d.outstanding==1);
  assert(!game_build(&runtime.game,frame_base,net,1,BULLET_MAX_COMMANDS,&stream));
  assert(!bullet_clip_background_for_hud(&stream,72));
  assert(!copy_ahead_finish(&d,&bg,tag,&stream,100));
  assert(commits==count && !d.outstanding && !memcmp(reference,pixels,sizeof pixels));
 }
 frame_base=GPU_FRAMEBUFFER_A;game_input in={0};int issued;
 reset(&d);assert(!v3_runtime_menu_init(&runtime,7,1));
 assert(!copy_ahead_advance(&d,&runtime,&in,16667,frame_base,1,&bg,&tag,&issued,100));
 assert(!issued && !commits); /* Explicit MENU is not a background workload. */
 assert(!v3_runtime_game_command(&runtime,V3_GAME_START,4,1,1));
 runtime.game.hp=0;runtime.game.game_over_ticks=1;
 assert(!copy_ahead_advance(&d,&runtime,&in,16667,frame_base,1,&bg,&tag,&issued,100));
 assert(runtime.phase==V3_PHASE_MENU && !issued && commits==1 && !d.outstanding && done_reads);
 reset(&d);assert(!v3_runtime_init(&runtime,512,7,1));
 for(unsigned i=0;i<600;i++)assert(!replay_record(&runtime.recording,&in));
 assert(!replay_seal(&runtime.recording));in.pressed=V3_KEY_COMPARE;
 assert(copy_ahead_advance(&d,&runtime,&in,16667,frame_base,1,&bg,&tag,&issued,100)==1);
 assert(runtime.mode==V3_MODE_CPU && !issued && commits==1 && !d.outstanding && done_reads);
 /* Delayed background must fail before any CPU writer can run. */
 reset(&d);runtime.mode=V3_MODE_LIVE;defer_done=1;
 assert(copy_ahead_advance(&d,&runtime,&in,16667,frame_base,1,&bg,&tag,&issued,2)==GPU_DRIVER_TIMEOUT);
 assert(runtime.mode==V3_MODE_CPU && commits==1 && d.outstanding);defer_done=0;
 reset(&d);assert(!v3_runtime_init(&runtime,512,7,1));in=(game_input){.held=UINT16_MAX};
 assert(copy_ahead_advance(&d,&runtime,&in,16667,frame_base,1,&bg,&tag,&issued,100)<0);
 assert(commits==1 && runtime.game.tick==0); /* Error cannot reach render/PRESENT. */
 reset(&d);in=(game_input){0};regs[GPU_REG_STATUS/4]=GPU_STATUS_FULL;
 assert(copy_ahead_advance(&d,&runtime,&in,16667,frame_base,1,&bg,&tag,&issued,0)==GPU_DRIVER_TIMEOUT);
 assert(!commits && runtime.game.tick==0);
 reset(&d);assert(!game_reset(&state,64,7));state.won=1;memset(state.enemy_hp,0,sizeof state.enemy_hp);
 assert(!game_build(&state,frame_base,1,1,BULLET_MAX_COMMANDS,&stream));
 assert(!bullet_clip_background_for_hud(&stream,72));
 assert(!perf_render_gpu(&d,stream.commands,stream.count,100));memcpy(reference,pixels,sizeof pixels);
 reset(&d);assert(!copy_ahead_begin(&d,frame_base,1,&bg,&tag,100));
 assert(!copy_ahead_finish(&d,&bg,tag,&stream,100) && commits==33 && !memcmp(reference,pixels,sizeof pixels));
 puts("PASS early Copy actual issue-before-logic, A/B local/net pixels, MENU/death/CPU drains, timeout/error no alternate writer, WIN Fill");
}
