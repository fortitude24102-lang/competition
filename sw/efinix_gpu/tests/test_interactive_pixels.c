#include "replay_input.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t background[GPU_FRAME_BYTES],atlas[BULLET_ATLAS_BYTES],cpu_frame[GPU_FRAME_BYTES];
/* Host-only evidence: retain each sampled CPU frame, not production BSS. */
static uint8_t cpu_samples[10][GPU_FRAME_BYTES];
static uint16_t reference_frame[GPU_FRAME_WIDTH*GPU_FRAME_HEIGHT];
static bullet_state initial,state,final_cpu;
static bullet_stream stream;
static replay_recording recording;
static replay_cursor cursor;
static uint16_t load16(const uint8_t *p) { return (uint16_t)(p[0]|((uint16_t)p[1]<<8)); }
static const uint8_t *source(uint32_t address,uint32_t *available) {
 if(address>=BULLET_LOCAL_BACKGROUND && address<BULLET_LOCAL_BACKGROUND+GPU_FRAME_BYTES) {
  uint32_t offset=address-BULLET_LOCAL_BACKGROUND; *available=GPU_FRAME_BYTES-offset; return background+offset;
 }
 assert(address>=BULLET_LOCAL_ATLAS && address<BULLET_LOCAL_ATLAS+BULLET_ATLAS_BYTES);
 uint32_t offset=address-BULLET_LOCAL_ATLAS; *available=BULLET_ATLAS_BYTES-offset; return atlas+offset;
}
static void read_file(const char *path,uint8_t *bytes,unsigned size) {
 FILE *f=fopen(path,"rb"); assert(f);
 assert(fread(bytes,1,size,f)==size && fgetc(f)==EOF && !fclose(f));
}
static void cpu_render(const gpu_command *c) {
 uint32_t available;
 const uint8_t *p=source(c->src_addr,&available);
 golden_surface src={(uint8_t *)p,available,c->width_pixels,c->height_pixels,c->src_stride};
 golden_surface dst={cpu_frame,sizeof cpu_frame,960,540,1920};
 unsigned pixel=(c->dst_addr-GPU_FRAMEBUFFER_A)/2u;
 enum gpu_error error=c->op==GPU_OP_COPY?golden_copy(&dst,pixel%960u,pixel/960u,&src,0,0,c->width_pixels,c->height_pixels):
  c->op==GPU_OP_COLOR_KEY?golden_color_key(&dst,pixel%960u,pixel/960u,&src,0,0,c->width_pixels,c->height_pixels,c->color_key):
  golden_alpha_blend(&dst,pixel%960u,pixel/960u,&src,0,0,c->width_pixels,c->height_pixels,c->alpha);
 assert(error==GPU_ERROR_NONE);
}
/* Independent scalar GPU oracle, with actual Key skips and previous Alpha
 * destination reads. Emit full-frame operands to the unchanged pixel RTL. */
static void reference_render(const gpu_command *c,FILE *vectors) {
 uint32_t available;
 const uint8_t *p=source(c->src_addr,&available);
 unsigned first=(c->dst_addr-GPU_FRAMEBUFFER_A)/2u;
 assert((c->height_pixels-1u)*c->src_stride+c->width_pixels*2u<=available);
 for(unsigned y=0;y<c->height_pixels;y++) for(unsigned x=0;x<c->width_pixels;x++) {
  unsigned offset=first+y*960+x; assert(offset<960*540);
  uint16_t fg=load16(p+y*c->src_stride+x*2u),bg=reference_frame[offset],value=fg;
  unsigned write=c->op!=GPU_OP_COLOR_KEY || fg!=c->color_key;
  if(c->op==GPU_OP_ALPHA) {
   unsigned a=c->alpha,b=255u-a;
   unsigned r=((fg>>11)*a+(bg>>11)*b+127u)/255u;
   unsigned g=(((fg>>5)&63u)*a+((bg>>5)&63u)*b+127u)/255u;
   unsigned blue=((fg&31u)*a+(bg&31u)*b+127u)/255u;
   value=(uint16_t)((r<<11)|(g<<5)|blue);
  }
  if(vectors) assert(fprintf(vectors,"%x %04x %04x %04x %02x %04x %x\n",
   c->op,fg,bg,c->color_key,c->alpha,value,write)>0);
  if(write) reference_frame[offset]=value;
 }
}
int main(void) {
 read_file("sw/efinix_gpu/assets/interactive/background.rgb565",background,sizeof background);
 read_file("sw/efinix_gpu/assets/interactive/atlas.rgb565",atlas,sizeof atlas);
 assert(!game_reset(&initial,512,7)); state=initial;
 assert(!replay_init(&recording,&initial,0x30001));
 for(unsigned tick=0;tick<600;tick++) {
  game_input in={.held=(uint16_t)(V3_KEY_FIRE|(tick%120<60?V3_KEY_RIGHT:V3_KEY_LEFT))};
  if(tick%90<30) in.held|=V3_KEY_SLOW;
  if(tick==245) in.pressed=V3_KEY_RESTART;
  assert(!replay_record(&recording,&in) && !game_update(&state,&in));
 }
 assert(!replay_seal(&recording));
 for(unsigned backend=0;backend<2;backend++) {
  assert(!replay_begin(&recording,0x30001,&state,&cursor));
  for(unsigned tick=0;tick<600;tick++) {
   game_input in;
   assert(replay_next(&recording,&cursor,&in)==1 && !game_update(&state,&in));
   if(tick%60u==59u) {
    assert(!game_build(&state,GPU_FRAMEBUFFER_A,0,1,BULLET_MAX_COMMANDS,&stream));
    FILE *f=NULL;
    if(backend && tick==59) { f=fopen("generated/verification/v3/game/pixels.txt","w"); assert(f); }
    for(unsigned n=0;n<stream.count;n++) {
     if(!backend) cpu_render(&stream.commands[n]);
     else reference_render(&stream.commands[n],f);
    }
    if(!backend) memcpy(cpu_samples[tick/60u],cpu_frame,sizeof cpu_frame);
    else for(unsigned pixel=0;pixel<960u*540u;pixel++)
     assert(load16(cpu_samples[tick/60u]+2u*pixel)==reference_frame[pixel]);
    if(f) {
     assert(!fclose(f));
     unsigned shots=0;
     for(unsigned i=0;i<state.count;i++) shots+=state.objects[i].kind==3 && state.objects[i].age!=UINT16_MAX;
     assert(shots && state.hp);
     f=fopen("generated/verification/v3/game/interactive_live.rgb565","wb"); assert(f);
     assert(fwrite(reference_frame,1,sizeof reference_frame,f)==sizeof reference_frame && !fclose(f));
     printf("PASS interactive live frame: tick=60 visible=%u shots=%u commands=%u alpha=%u\n",
      stream.visible,shots,stream.count,stream.alpha_commands);
    }
   }
  }
  if(!backend) final_cpu=state;
  else assert(!memcmp(&final_cpu,&state,sizeof state));
 }
 for(unsigned i=0;i<960*540;i++) assert(load16(cpu_frame+2*i)==reference_frame[i]);
 FILE *f=fopen("generated/verification/v3/game/interactive.rgb565","wb"); assert(f);
 assert(fwrite(cpu_frame,1,sizeof cpu_frame,f)==sizeof cpu_frame && !fclose(f));
 printf("PASS interactive pixels: replay_ticks=600 samples=10 visible=%u commands=%u alpha=%u CRC=%08x\n",
  stream.visible,stream.count,stream.alpha_commands,golden_crc32(cpu_frame,sizeof cpu_frame));
 printf("V3_GAME_MEMORY,state=%u,stream=%u,record=%u,clock=%u bytes\n",
  (unsigned)sizeof state,(unsigned)sizeof stream,(unsigned)sizeof recording,(unsigned)sizeof(game_clock));
 return 0;
}
