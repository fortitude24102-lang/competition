/* The reference build runs the real old HUD path and must fail the batching
 * assertion. The normal build exercises real HUD/list/instance/GPU drivers;
 * only physical MMIO and pixel storage are replaced by this bounded model. */
#define _GNU_SOURCE
#include "hud.h"
#include "gpu_frame_list.h"
#include "perf_demo.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#ifdef HUD_LIST_REFERENCE
static int candidate_init(gpu_frame_list *f,int network) {(void)f;(void)network;return 0;}
static int candidate_render(gpu_frame_list *f,const hud_comparison *m,hud_raster_cache *cache,
 hud_command_stream *s,uint32_t dst,uint32_t bank,uint32_t epoch,uint32_t polls) {
 (void)bank;(void)epoch;
 int e=hud_update_gpu_cache(f->gpu,m,cache,s,polls);if(e)return e;
 gpu_command c;e=hud_cached_command(dst,cache,&c);return e?e:perf_render_gpu(f->gpu,&c,1,polls);
}
#else
#include "hud_gpu_list.h"
#define candidate_init hud_gpu_list_init
#define candidate_render hud_render_gpu_list
#endif
static uint32_t regs[512];
static gpu_instance_template templates[16];
static unsigned selected,starts,legacy,writes,synced,list_count;
static int fail_after=-1,timeout;
static hud_command_stream scratch,oracle;
static uint8_t actual[HUD_CACHE_BYTES];
static void execute(const gpu_command *c) {
 assert(c->op==GPU_OP_FILL || c->op==GPU_OP_COPY);
 assert(c->dst_addr>=GPU_FRAMEBUFFER_A);
 assert((uint64_t)c->dst_addr+(c->height_pixels-1u)*c->dst_stride+c->width_pixels*2u<=GPU_DDR_END_EXCLUSIVE);
 for(unsigned y=0;y<c->height_pixels;y++) {
  uint16_t *d=(uint16_t *)(uintptr_t)(c->dst_addr+y*c->dst_stride);
  if(c->op==GPU_OP_COPY)memcpy(d,(void *)(uintptr_t)(c->src_addr+y*c->src_stride),c->width_pixels*2u);
  else for(unsigned x=0;x<c->width_pixels;x++)d[x]=c->color;
 }
}
uint32_t gpu_io_read(uintptr_t a) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);
 if(r==GPU_REG_STATUS)return GPU_STATUS_EMPTY|(3u<<14);
 if(r==0x400)return GPU_INSTANCE_ID;
 if(r==0x500)return GPU_FRAME_LIST_ID;
 return regs[r/4];
}
void gpu_io_write(uintptr_t a,uint32_t v) {
 unsigned r=(unsigned)(a-GPU_APB_BASE);assert(r<sizeof regs);regs[r/4]=v;++writes;
 if(r==0x40c) {selected=v;assert(selected<16);}
 if(r>=0x410 && r<=0x428)memcpy((uint8_t *)(templates+selected)+r-0x410,&v,4);
 if(r==GPU_REG_CONTROL && v==GPU_CONTROL_SUBMIT) {
  gpu_command c={.op=(uint8_t)regs[GPU_REG_OP/4],.src_addr=regs[GPU_REG_SRC_ADDR/4],
   .dst_addr=regs[GPU_REG_DST_ADDR/4],.src_stride=regs[GPU_REG_SRC_STRIDE/4],
   .dst_stride=regs[GPU_REG_DST_STRIDE/4],.width_pixels=(uint16_t)regs[GPU_REG_SIZE/4],
   .height_pixels=(uint16_t)(regs[GPU_REG_SIZE/4]>>16),.color=(uint16_t)regs[GPU_REG_COLOR_KEY/4]};
  execute(&c);++legacy;regs[GPU_REG_LAST_DONE/4]=regs[GPU_REG_TAG/4];
 }
 if(r==0x508 && v==1) {
  assert(synced);synced=0;++starts;list_count=regs[0x510/4];
  regs[0x504/4]=1;if(timeout)return;
  const gpu_instance *items=(const gpu_instance *)(uintptr_t)regs[0x50c/4];
  for(unsigned i=0;i<list_count;i++) {
   if(fail_after==0){regs[0x504/4]=2|4|(9u<<8);return;}
   if(fail_after>0)--fail_after;
   gpu_command c;assert(!gpu_instance_expand(templates,items+i,(uint16_t)(regs[0x514/4]+i),&c));
   execute(&c);
  }
  regs[0x504/4]=2;regs[0x51c/4]=regs[0x518/4];regs[0x524/4]=list_count;
  regs[0x520/4]=(uint16_t)(regs[0x514/4]+list_count-1u);
  regs[GPU_REG_LAST_DONE/4]=regs[0x520/4];
 }
}
void gpu_io_fence(void) {}
void gpu_platform_sync(void) {synced=1;}
static void exact(uint32_t dst,const hud_comparison *m) {
 memcpy(actual,(void *)(uintptr_t)dst,HUD_CACHE_BYTES);
 assert(!hud_build_comparison(GPU_FRAMEBUFFER_A,m,&oracle));
 assert(!perf_render_cpu(oracle.commands,oracle.count));
 assert(!memcmp(actual,(void *)(uintptr_t)GPU_FRAMEBUFFER_A,HUD_CACHE_BYTES));
 assert(!memcmp(actual,(void *)(uintptr_t)HUD_CACHE_ADDR,HUD_CACHE_BYTES));
}
static void init(gpu_device *gpu,gpu_frame_list *f) {
 memset(regs,0,sizeof regs);memset(templates,0,sizeof templates);
 fail_after=-1;timeout=0;
 regs[GPU_REG_ID/4]=GPU_ID_VALUE;regs[GPU_REG_VERSION/4]=GPU_VERSION_VALUE;
 assert(!gpu_init(gpu,GPU_APB_BASE));assert(!gpu_frame_list_init(f,gpu,1));
 assert(!candidate_init(f,1));
}
int main(void) {
 const unsigned bytes=0xd40000;
 void *p=mmap((void *)(uintptr_t)GPU_FRAMEBUFFER_A,bytes,PROT_READ|PROT_WRITE,
  MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);assert(p==(void *)(uintptr_t)GPU_FRAMEBUFFER_A);
 memset(p,0xa5,bytes);hud_init_glyph_atlas();
 uint16_t *logo=(uint16_t *)(uintptr_t)HUD_LOGO_ADDR;
 for(unsigned i=0;i<14000;i++)logo[i]=i%17?0xffff:0x193f;
 hud_set_logo_enabled(1);
 gpu_device gpu;gpu_frame_list list;init(&gpu,&list);
 hud_raster_cache cache={0};
 hud_comparison m={.v3_mode=1,.bullet_demo=1,.gameplay=1,.hp=3,.gpu_active=1,
  .network_ready=1,.gpu_valid=1,.gpu_fps_x10=601,.gpu_render_us=8100,.sprites=512,.alpha_commands=67};
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,7,100));
 assert(cache.valid && cache.rebuilds==1);exact(GPU_FRAMEBUFFER_B,&m);
 unsigned old_starts=starts,old_legacy=legacy,old_writes=writes;
 m.score=1;
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_A,GPU_FRAME_LIST_BANK_A,8,100));
 exact(GPU_FRAMEBUFFER_A,&m);
 /* Real old path executes two legacy commands (20 register writes). */
 assert(starts==old_starts+1 && legacy==old_legacy);
 assert(list_count==2 && writes-old_writes==5);
 printf("HUD_LIST_IO,one_digit,descriptors=%u,APB_writes=%u,legacy_commands=%u\n",list_count,writes-old_writes,legacy-old_legacy);
 unsigned rebuilds=cache.rebuilds;
 old_starts=starts;old_legacy=legacy;
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,9,100));
 assert(cache.rebuilds==rebuilds && starts==old_starts && legacy==old_legacy+1);exact(GPU_FRAMEBUFFER_B,&m);
 for(unsigned i=0;i<80;i++) {
  m.score=i%2?9:999999;m.grazes=i%2?0:9999;m.hp=i%2?3:255;
  m.underflows=i%2?0:UINT32_MAX;m.error_code=i%2?0:255;
  m.v3_mode=(uint8_t)(i%6);m.perf_stage=(uint8_t)(i%7);m.perf_frames=i*50;m.perf_best=872;
  m.cpu_valid=(uint8_t)(i%2);m.cpu_fps_x10=i%2?28:0;m.cpu_render_us=i*10000;
  uint32_t dst=i%2?GPU_FRAMEBUFFER_A:GPU_FRAMEBUFFER_B,bank=i%2?GPU_FRAME_LIST_BANK_A:GPU_FRAME_LIST_BANK_B;
  assert(!candidate_render(&list,&m,&cache,&scratch,dst,bank,10+i,100));exact(dst,&m);
 }
 /* CPU produces the same cache, then the GPU consumes it without redrawing. */
 m.score=4;assert(!hud_update_cache(&m,&cache,&scratch));
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,100,100));exact(GPU_FRAMEBUFFER_B,&m);
 m.score=5;gpu.next_tag=65535;gpu.last_done=65534;regs[GPU_REG_LAST_DONE/4]=65534;
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,101,100));
 assert(gpu.next_tag==1 && gpu.last_done==0);exact(GPU_FRAMEBUFFER_B,&m);
 old_starts=starts;old_legacy=legacy;
 assert(candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B+16,102,100)==GPU_DRIVER_ARGUMENT);
 list.active=1;
 assert(candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,102,100)==GPU_DRIVER_BUSY);
 list.active=0;assert(cache.valid && starts==old_starts && legacy==old_legacy);
 /* Failure after one glyph must not commit metadata or replay via APB. */
 m=(hud_comparison){.v3_mode=1,.bullet_demo=1,.gameplay=1,.hp=3,.gpu_active=1,.network_ready=1,.score=12};
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,103,100));
 char saved[4][64];memcpy(saved,cache.text,sizeof saved);
 old_starts=starts;old_legacy=legacy;fail_after=1;m.score=345;
 assert(candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,104,100)==GPU_DRIVER_HARDWARE);
 assert(!cache.valid && !memcmp(saved,cache.text,sizeof saved) && starts==old_starts+1 && legacy==old_legacy);
 assert(list.active && !gpu.ready);
 assert(candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,104,100)<0);
 assert(starts==old_starts+1 && legacy==old_legacy);
 init(&gpu,&list);cache.valid=0;
 assert(!candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,105,100));
 timeout=1;m.score=346;
 assert(candidate_render(&list,&m,&cache,&scratch,GPU_FRAMEBUFFER_B,GPU_FRAME_LIST_BANK_B,106,2)==GPU_DRIVER_TIMEOUT);
 assert(!cache.valid && list.active && !gpu.ready);
 for(unsigned i=0;i<16;i++)assert(((uint8_t *)(uintptr_t)(GPU_FRAME_LIST_BANK_B+16384u))[i]==0xa5);
 assert(!munmap(p,bytes));
 puts("HUD_GPU_LIST,PASS,exact_pixels,A/B,logo,CPU_switch,tagwrap,cache_hit,partial_error,no_replay,timeout,bank_guard");
}
