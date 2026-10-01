/* Research-only host probe. NOT linked into Sapphire firmware or GPU RTL.
 * Uses the real R7 command stream and existing pixel golden model.
 * ponytail: exact vertical merging only; a production cost policy needs board timings. */
#include "bullet_demo.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HUD 72u
#define MAX_TILES 1800u
typedef struct { unsigned x,y,w,h; } rect;
static unsigned tile,cols,rows,gap;
static unsigned char history[2][MAX_TILES],valid[2];
static unsigned char background[GPU_FRAME_BYTES],reference[GPU_FRAME_BYTES];
static unsigned char back[2][GPU_FRAME_BYTES],atlas[BULLET_ATLAS_BYTES];
static bullet_state state;
static bullet_stream stream;
static rect rectangles[MAX_TILES];

static void mark(unsigned char *mask,const gpu_command *c,uint32_t base) {
 unsigned off=c->dst_addr-base,x=(off%GPU_FRAME_STRIDE)/2,y=off/GPU_FRAME_STRIDE;
 assert(y>=HUD && x+c->width_pixels<=960 && y+c->height_pixels<=540);
 for(unsigned ty=(y-HUD)/tile;ty<=(y-HUD+c->height_pixels-1)/tile;ty++)
  for(unsigned tx=x/tile;tx<=(x+c->width_pixels-1)/tile;tx++) mask[ty*cols+tx]=1;
}
static unsigned merge(const unsigned char *mask) {
 unsigned n=0;
 for(unsigned y=0;y<rows;y++) for(unsigned x=0;x<cols;) {
  if(!mask[y*cols+x]) { ++x; continue; }
  unsigned start=x;
  while(x<cols) {
   if(mask[y*cols+x]) { ++x; continue; }
   unsigned next=x;
   while(next<cols && !mask[y*cols+next]) ++next;
   if(next==cols || next-x>gap) break;
   x=next;
  }
  unsigned j;
  for(j=0;j<n;j++) if(rectangles[j].x==start && rectangles[j].w==x-start &&
      rectangles[j].y+rectangles[j].h==y) { ++rectangles[j].h; break; }
  if(j==n) { assert(n<MAX_TILES); rectangles[n++]=(rect){start,y,x-start,1}; }
 }
 return n;
}
static golden_surface surface(unsigned char *pixels) {
 return (golden_surface){pixels,GPU_FRAME_BYTES,960,540,GPU_FRAME_STRIDE};
}
static void restore(unsigned char *pixels,rect r) {
 unsigned x=r.x*tile,y=HUD+r.y*tile,w=r.w*tile,h=r.h*tile;
 if(y+h>540) h=540-y;
 golden_surface dst=surface(pixels),src=surface(background);
 assert(!golden_copy(&dst,x,y,&src,x,y,w,h));
}
static void draw(unsigned char *pixels,uint32_t base) {
 golden_surface dst=surface(pixels);
 for(unsigned i=1;i<stream.count;i++) {
  gpu_command *c=&stream.commands[i];
  unsigned d=c->dst_addr-base,s=c->src_addr-BULLET_ATLAS_ADDR;
  golden_surface src={atlas+s,BULLET_ATLAS_BYTES-s,
   (uint16_t)(c->src_stride/2),c->height_pixels,c->src_stride};
  if(c->op==GPU_OP_COLOR_KEY)
   assert(!golden_color_key(&dst,(d%GPU_FRAME_STRIDE)/2,d/GPU_FRAME_STRIDE,
    &src,0,0,c->width_pixels,c->height_pixels,c->color_key));
  else {
   assert(c->op==GPU_OP_ALPHA);
   assert(!golden_alpha_blend(&dst,(d%GPU_FRAME_STRIDE)/2,d/GPU_FRAME_STRIDE,
    &src,0,0,c->width_pixels,c->height_pixels,c->alpha));
  }
 }
}
static unsigned burst_count(unsigned offset,unsigned bytes) {
 unsigned n=0;
 while(bytes) {
  unsigned part=4096-(offset&4095);
  if(part>1024) part=1024;
  if(part>bytes) part=bytes;
  offset+=part; bytes-=part; ++n;
 }
 return n;
}
static void read_asset(const char *path,unsigned char *dst,size_t size) {
 FILE *f=fopen(path,"rb"); assert(f);
 assert(fread(dst,1,size,f)==size && fgetc(f)==EOF); assert(!fclose(f));
}
static void checks(void) {
 tile=16; cols=60; rows=30;
 unsigned char mask[MAX_TILES]={0};
 gpu_command c={.dst_addr=GPU_FRAMEBUFFER_A+HUD*1920+30,
  .width_pixels=2,.height_pixels=17};
 mark(mask,&c,GPU_FRAMEBUFFER_A);
 assert(mask[0] && mask[1] && mask[60] && mask[61] && !mask[2]);
 assert(merge(mask)==1 && rectangles[0].w==2 && rectangles[0].h==2);
 assert(burst_count(4080,1920)==3);
 puts("CHECK,clipped_tile_union_exact_merge_4KiB,PASS");
}
int main(int argc,char **argv) {
 assert(argc==3 || argc==4);
 checks();
 read_asset(argv[1],background,sizeof background);
 read_asset(argv[2],atlas,sizeof atlas);
 gap=argc==4?(unsigned)strtoul(argv[3],NULL,10):0;
 assert(gap<=8);
 printf("CONFIG,seed=7,frames=600,merge_gap_tiles=%u,CPU_invalidate=300,bg_invalidate=450\n",gap);
 puts("tier,tile,frames,full_resets,restore_pct_mean,restore_pct_max,rect_mean,rect_max,burst_mean,baseline_bursts,scene_commands_mean,instances16B_mean,apb10writes_mean,equal_frames");
 const unsigned tiers[]={32,64,128,256,512},tiles[]={16,32,64};
 unsigned baseline=0;
 for(unsigned y=HUD;y<540;y++) baseline+=burst_count(y*1920,1920);
 for(unsigned t=0;t<3;t++) for(unsigned level=0;level<5;level++) {
  tile=tiles[t]; cols=(960+tile-1)/tile; rows=(468+tile-1)/tile;
  assert(cols*rows<=MAX_TILES);
  memset(valid,0,sizeof valid); memset(history,0,sizeof history);
  /* Poison both buffers: initialization cannot accidentally appear correct. */
  memset(back,0x5a,sizeof back); memset(reference,0x5a,sizeof reference);
  assert(!bullet_reset(&state,tiers[level],7));
  uint64_t pixels=0,commands=0,bursts=0,scene_commands=0;
  unsigned samples=0,full=0,max_pixels=0,max_commands=0;
  for(unsigned frame=0;frame<600;frame++) {
   unsigned b=frame&1u; uint32_t base=b?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
   /* A CPU rendering interval invalidates BOTH histories. A background change
    * does the same. The changed pixels are synthetic, assets otherwise actual. */
   if(frame==300) {
    memset(back[b],0x33,GPU_FRAME_BYTES);
#ifndef PROBE_SKIP_INVALIDATE
    valid[0]=valid[1]=0;
#endif
   }
   if(frame==450) { background[200*1920+400]^=0x7f; valid[0]=valid[1]=0; }
   assert(!bullet_build_frame(&state,base,1,1,BULLET_MAX_COMMANDS,&stream));
   assert(!bullet_clip_background_for_hud(&stream,HUD));
   golden_surface ref=surface(reference),bg=surface(background);
   assert(!golden_copy(&ref,0,HUD,&bg,0,HUD,960,468));
   unsigned n;
   if(!valid[b]) {
    rectangles[0]=(rect){0,0,cols,rows}; n=1; ++full;
   } else {
#ifdef PROBE_WRONG_HISTORY
    n=merge(history[b^1u]);
#else
    n=merge(history[b]);
#endif
   }
   unsigned area=0,count=0;
   for(unsigned i=0;i<n;i++) {
    rect r=rectangles[i]; unsigned y=HUD+r.y*tile,h=r.h*tile;
    if(y+h>540) h=540-y;
    area+=r.w*tile*h;
    for(unsigned row=y;row<y+h;row++) count+=burst_count(row*1920+r.x*tile*2,r.w*tile*2);
    restore(back[b],r);
   }
   draw(reference,base); draw(back[b],base);
   /* All ROI bytes must match, not only tile coverage or a CRC. */
   assert(!memcmp(reference+HUD*1920,back[b]+HUD*1920,468*1920));
   if(valid[b]) {
    pixels+=area; commands+=n; bursts+=count; ++samples;
    if(area>max_pixels) max_pixels=area;
    if(n>max_commands) max_commands=n;
   }
   scene_commands+=stream.count;
   memset(history[b],0,sizeof history[b]);
   for(unsigned i=1;i<stream.count;i++) mark(history[b],&stream.commands[i],base);
   valid[b]=1;
   assert(!bullet_step(&state));
  }
  double mean_cmd=scene_commands/600.0;
  printf("%u,%u,600,%u,%.3f,%.3f,%.2f,%u,%.2f,%u,%.2f,%.0f,%.0f,600\n",
   tiers[level],tile,full,100.0*pixels/samples/(960*468),100.0*max_pixels/(960*468),
   (double)commands/samples,max_commands,(double)bursts/samples,baseline,mean_cmd,
   (mean_cmd-1)*16,mean_cmd*10);
  background[200*1920+400]^=0x7f;
 }
 puts("RESULT,research_only_pixel_equivalence,PASS,frames=9000");
 return 0;
}
