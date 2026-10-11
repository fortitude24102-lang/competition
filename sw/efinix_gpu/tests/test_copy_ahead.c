/* Catch waiting before build, duplicated background, changed Sprite order,
 * unsafe mismatch/partial-frame retries, and a lost final tag. Real driver
 * and builders; only external MMIO/DDR are replaced by the host fixture. */
#define V3_COPY_AHEAD 1
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
static void execute(const gpu_command *c) {
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
  assert(commits<BULLET_MAX_COMMANDS);gpu_command *c=&emitted[commits++];
  memset(c,0,sizeof *c);
  c->op=(uint8_t)regs[GPU_REG_OP/4];c->src_addr=regs[GPU_REG_SRC_ADDR/4];c->dst_addr=regs[GPU_REG_DST_ADDR/4];
  c->src_stride=regs[GPU_REG_SRC_STRIDE/4];c->dst_stride=regs[GPU_REG_DST_STRIDE/4];
  c->width_pixels=(uint16_t)regs[GPU_REG_SIZE/4];c->height_pixels=(uint16_t)(regs[GPU_REG_SIZE/4]>>16);
  c->color=(uint16_t)regs[GPU_REG_COLOR_KEY/4];c->color_key=(uint16_t)(regs[GPU_REG_COLOR_KEY/4]>>16);
  c->alpha=(uint8_t)regs[GPU_REG_ALPHA_FLAGS/4];c->flags=(uint16_t)(regs[GPU_REG_ALPHA_FLAGS/4]>>16);
  execute(c);regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];
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
}
