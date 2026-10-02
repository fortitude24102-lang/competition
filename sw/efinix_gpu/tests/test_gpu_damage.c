/* Breaks caught: full-only restoration, wrong physical history, Alpha residue,
 * missing CPU/epoch invalidation, failed-frame commit, and changed draw order.
 * Real R7 commands + independent full golden rendering, every ROI byte checked. */
#include "gpu_damage.h"
#include "bullet_demo.h"
#include "golden_renderer.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static gpu_damage_state damage;
static gpu_damage_result plan;
static bullet_state game;
static bullet_stream stream;
static uint8_t bg[GPU_FRAME_BYTES],reference[GPU_FRAME_BYTES],back[2][GPU_FRAME_BYTES];
static uint8_t atlas[BULLET_ATLAS_BYTES];
static gpu_damage_config config={16,0,128,{1000,100,768}};
static gpu_command background(unsigned b) {
 return (gpu_command){.op=GPU_OP_COPY,.src_addr=BULLET_BACKGROUND_ADDR+72*1920,
 .dst_addr=(b?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A)+72*1920,
 .src_stride=1920,.dst_stride=1920,.width_pixels=960,.height_pixels=468};
}
static gpu_command sprite(unsigned b,unsigned x,unsigned y,unsigned w,unsigned h) {
 return (gpu_command){.op=GPU_OP_ALPHA,.src_addr=BULLET_ATLAS_ADDR,
 .src_stride=w*2,.dst_stride=1920,.width_pixels=w,.height_pixels=h,.alpha=112,
 .dst_addr=(b?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A)+y*1920+x*2};
}
static void units(void) {
 gpu_command cross={.src_addr=0x02900ffcu,.dst_addr=GPU_FRAMEBUFFER_A,
  .src_stride=1920,.dst_stride=1920,.width_pixels=8,.height_pixels=1};
 uint32_t copy_bytes,copy_bursts;
 assert(gpu_damage_copy_cost(&cross,&config.cost,&copy_bytes,&copy_bursts)==1348);
 assert(copy_bytes==16 && copy_bursts==3);
 cross=background(0);
 assert(gpu_damage_copy_cost(&cross,&config.cost,&copy_bytes,&copy_bursts)==2919080);
 assert(copy_bytes==898560 && copy_bursts==2224);
 assert(!gpu_damage_init(&damage,&config));
 gpu_command c[3]={background(0),sprite(0,0,72,16,16)};
 assert(gpu_damage_plan(&damage,c,2,1,&plan)==1 && plan.reason==GPU_DAMAGE_COLD);
 gpu_damage_commit(&damage,1);
 c[1]=sprite(0,400,200,8,8);
 assert(gpu_damage_plan(&damage,c,2,1,&plan)==1);
 assert(plan.reason==GPU_DAMAGE_PARTIAL && plan.bytes==512);
 assert(plan.commands[0].width_pixels==16 && plan.commands[0].height_pixels==16);
 gpu_damage_commit(&damage,1);
 c[0]=background(1); c[1]=sprite(1,944,539,16,1);
 assert(gpu_damage_plan(&damage,c,2,1,&plan)==1 && plan.reason==GPU_DAMAGE_COLD);
 gpu_damage_commit(&damage,1);
 assert(gpu_damage_plan(&damage,c,1,1,&plan)==1 && plan.bytes==128);
 gpu_damage_commit(&damage,1);
 assert(gpu_damage_plan(&damage,c,1,1,&plan)==0 && !plan.bytes);
 gpu_damage_commit(&damage,1);
 c[0]=background(0);
 /* x=400,y=200 are tile boundaries relative to ROI y=72: one16x16 tile. */
 assert(gpu_damage_plan(&damage,c,1,1,&plan)==1 && plan.bytes==512);
 gpu_damage_commit(&damage,0);
 assert(!damage.valid[0] && !damage.valid[1]);
 assert(gpu_damage_plan(&damage,c,1,1,&plan)==1 && plan.reason==GPU_DAMAGE_COLD);
 gpu_damage_commit(&damage,1);
 assert(gpu_damage_plan(&damage,c,1,2,&plan)==1 && plan.reason==GPU_DAMAGE_COLD);
 gpu_damage_commit(&damage,1);
 c[0].src_addr+=0x100000;
 assert(gpu_damage_plan(&damage,c,1,2,&plan)==1 && plan.reason==GPU_DAMAGE_COLD);
 gpu_damage_commit(&damage,1);
 gpu_damage_invalidate(&damage);
 assert(!damage.valid[0] && !damage.valid[1]);
 config.capacity=1;
 assert(!gpu_damage_init(&damage,&config));
 c[0]=background(0); c[1]=sprite(0,0,72,8,8); c[2]=sprite(0,100,120,8,8);
 assert(gpu_damage_plan(&damage,c,3,1,&plan)==1); gpu_damage_commit(&damage,1);
 assert(gpu_damage_plan(&damage,c,1,1,&plan)==1 && plan.reason==GPU_DAMAGE_CAPACITY);
 gpu_damage_commit(&damage,1);
 config.capacity=128; config.cost=(gpu_damage_cost){100000000,1,256};
 assert(!gpu_damage_init(&damage,&config));
 assert(gpu_damage_plan(&damage,c,3,1,&plan)==1); gpu_damage_commit(&damage,1);
 assert(gpu_damage_plan(&damage,c,1,1,&plan)==1 && plan.reason==GPU_DAMAGE_COST);
 gpu_damage_commit(&damage,1);
 c[1].dst_addr=GPU_FRAMEBUFFER_A+70*1920;
 assert(gpu_damage_plan(&damage,c,2,1,&plan)==GPU_DRIVER_ARGUMENT);
 assert(!damage.valid[0] && !damage.valid[1]);
 config=(gpu_damage_config){16,0,128,{1000,100,768}};
 config.tile=17; assert(gpu_damage_init(&damage,&config)==GPU_DRIVER_ARGUMENT);
 config.tile=16; config.gap=5; assert(gpu_damage_init(&damage,&config)==GPU_DRIVER_ARGUMENT);
 config.gap=0;
 puts("DAMAGE_UNIT,PASS,two_buffers,alpha_bottom,cold,epoch,capacity,cost,failed_commit,bounds");
}
static golden_surface surface(uint8_t *p) {
 return (golden_surface){p,GPU_FRAME_BYTES,960,540,1920};
}
static void restore(uint8_t *p,const gpu_command *c,uint32_t base) {
 unsigned d=c->dst_addr-base,s=c->src_addr-BULLET_BACKGROUND_ADDR;
 golden_surface dst=surface(p),src=surface(bg);
 assert(!golden_copy(&dst,(d%1920)/2,d/1920,&src,(s%1920)/2,s/1920,
  c->width_pixels,c->height_pixels));
}
static void draw(uint8_t *p,uint32_t base) {
 golden_surface dst=surface(p);
 for(unsigned i=1;i<stream.count;i++) {
  const gpu_command *c=&stream.commands[i];
  unsigned d=c->dst_addr-base,s=c->src_addr-BULLET_ATLAS_ADDR;
  golden_surface src={atlas+s,BULLET_ATLAS_BYTES-s,(uint16_t)(c->src_stride/2),
   c->height_pixels,c->src_stride};
  if(c->op==GPU_OP_COLOR_KEY)
   assert(!golden_color_key(&dst,(d%1920)/2,d/1920,&src,0,0,c->width_pixels,c->height_pixels,c->color_key));
  else {
   assert(c->op==GPU_OP_ALPHA);
   assert(!golden_alpha_blend(&dst,(d%1920)/2,d/1920,&src,0,0,c->width_pixels,c->height_pixels,c->alpha));
  }
 }
}
static void asset(const char *path,uint8_t *p,size_t n) {
 FILE *f=fopen(path,"rb"); assert(f);
 assert(fread(p,1,n,f)==n && fgetc(f)==EOF && !fclose(f));
}
int main(int argc,char **argv) {
 units();
 if(argc==1) return 0;
 assert(argc==3); asset(argv[1],bg,sizeof bg); asset(argv[2],atlas,sizeof atlas);
 const unsigned tiers[]={32,64,128,256,512};
 for(unsigned tile=16;tile<=32;tile*=2) for(unsigned gap=0;gap<=4;gap+=2)
  for(unsigned tier=0;tier<5;tier++) {
   config.tile=tile; config.gap=gap;
   assert(!gpu_damage_init(&damage,&config));
   memset(back,0x5a,sizeof back); memset(reference,0x5a,sizeof reference);
   assert(!bullet_reset(&game,tiers[tier],7));
   uint64_t bytes=0; unsigned full=0,commands=0;
   for(unsigned frame=0;frame<600;frame++) {
    unsigned b=frame&1; uint32_t base=b?GPU_FRAMEBUFFER_B:GPU_FRAMEBUFFER_A;
    if(frame==300) { memset(back[b],0x33,sizeof back[b]); gpu_damage_invalidate(&damage); }
    if(frame==450) bg[200*1920+400]^=0x7f;
    assert(!bullet_build_frame(&game,base,1,1,BULLET_MAX_COMMANDS,&stream));
    assert(!bullet_clip_background_for_hud(&stream,72));
    gpu_command before[BULLET_MAX_COMMANDS]; memcpy(before,stream.commands,stream.count*sizeof *before);
    int n=gpu_damage_plan(&damage,stream.commands,stream.count,frame>=450?2:1,&plan);
    assert(n>=0 && (unsigned)n==plan.count);
    assert(!memcmp(before,stream.commands,stream.count*sizeof *before));
    restore(reference,&stream.commands[0],base);
    for(unsigned i=0;i<plan.count;i++) restore(back[b],&plan.commands[i],base);
    draw(reference,base); draw(back[b],base);
    assert(!memcmp(reference+72*1920,back[b]+72*1920,468*1920));
    /* HUD must stay poisoned; scene restoration never touches it. */
    assert(back[b][0]==(frame>=300 && b==0?0x33:0x5a));
    bytes+=plan.bytes; commands+=plan.count; full+=plan.reason!=GPU_DAMAGE_PARTIAL;
    gpu_damage_commit(&damage,1); assert(!bullet_step(&game));
   }
   bg[200*1920+400]^=0x7f;
   printf("DAMAGE_GOLDEN,tile=%u,gap=%u,target=%u,equal_frames=600,full=%u,bytes_mean=%u,extra_commands_x10=%u\n",
    tile,gap,tiers[tier],full,(unsigned)(bytes/600),commands*10/600);
  }
 puts("DAMAGE_RESULT,PASS,frames=18000,bytewise_ROI_and_HUD");
 return 0;
}
