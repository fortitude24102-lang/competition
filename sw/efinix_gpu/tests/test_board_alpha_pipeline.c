/* Offscreen DDR pixel oracle, not a CPU/GPU performance qualification. */
#include "gpu.h"
#include "rgb565.h"
#include "bsp.h"
#include "vexriscv.h"
uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
#define CHECK(c) do {if(!(c)){bsp_printf("ALPHA_PIPELINE_BOARD_FAIL,line=%d,case=%d,hardware=%d\r\n",__LINE__,cases,d.hardware_error);return 1;}}while(0)
int main(void) {
 bsp_init();gpu_device d={0};unsigned cases=0;
 CHECK(!gpu_init(&d,GPU_APB_BASE));
 static const uint16_t fg[]={0xf800,0x07e0,0x001f,0xffff,0,0x1234};
 static const uint16_t bg[]={0x001f,0xf800,0x07e0,0,0xffff,0xabcd};
 static const unsigned widths[]={1,3,16,65};
 for(unsigned wi=0;wi<4;wi++) for(unsigned phase=0;phase<=2;phase+=2)
  for(unsigned cached=0;cached<2;cached++) for(unsigned mode=0;mode<3;mode++) {
   unsigned width=widths[wi];
   if(mode && width!=3) continue;
   unsigned alpha=mode==1?0:mode==2?255:128;
   unsigned stride=width*2u+6u;
   uint32_t source_base=0x02420000u,source_addr=source_base+phase;
   uint32_t destination_addr=0x02610000u+phase;
   volatile uint16_t *source=(volatile uint16_t *)(uintptr_t)source_addr;
   volatile uint16_t *destination=(volatile uint16_t *)(uintptr_t)destination_addr;
   CHECK(!gpu_texture_cache_invalidate(&d));
   for(unsigned i=0;i<160;i++){source[i]=0xdead;destination[i]=0xa55a;}
   destination[-1]=0xa55a;
   for(unsigned y=0;y<2;y++) for(unsigned x=0;x<width;x++) {
    unsigned i=(y*width+x)%6u;
    source[y*stride/2u+x]=fg[i];destination[y*stride/2u+x]=bg[i];
   }
   gpu_platform_sync();
   if(cached) {
    CHECK(!gpu_texture_cache_load(&d,source_base,(2u*stride+phase+3u)&~3u,10000000u));
    for(unsigned y=0;y<2;y++) for(unsigned x=0;x<width;x++) source[y*stride/2u+x]=0;
    gpu_platform_sync(); /* Prove the source comes from cache, not modified DDR. */
   }
   CHECK(!gpu_clear_perf(&d));uint16_t tag;
   CHECK(!gpu_alpha_async(&d,source_addr,destination_addr,stride,stride,
     (uint16_t)width,2,(uint8_t)alpha,&tag));
   CHECK(!gpu_wait_tag(&d,tag,10000000u));gpu_platform_sync();
   CHECK(destination[-1]==0xa55a);
   for(unsigned y=0;y<2;y++) {
    for(unsigned x=0;x<width;x++) {
     unsigned i=(y*width+x)%6u;
     CHECK(destination[y*stride/2u+x]==rgb565_global_alpha(fg[i],bg[i],(uint8_t)alpha));
    }
    for(unsigned x=width;x<width+3u;x++) CHECK(destination[y*stride/2u+x]==0xa55a);
   }
   CHECK(destination[stride]==0xa55a);
   gpu_perf_snapshot p;CHECK(!gpu_read_perf_snapshot(&d,&p));
   unsigned source_bytes=0;
   /* Each 64-pixel chunk aligns its own read. At phase2, width65 reads
      the boundary word twice: 132+4 bytes/row, not132 for the whole row. */
   for(unsigned y=0;y<2;y++) for(unsigned x=0;x<width;x+=64u) {
    unsigned n=width-x<64u?width-x:64u;
    source_bytes+=(n*2u+((phase+y*stride+x*2u)&3u)+3u)&~3u;
   }
   CHECK(p.pixels==width*2u && p.write_bytes==width*4u);
   CHECK(p.cache_bytes==(cached?source_bytes:0u));
   CHECK(p.read_bytes==source_bytes*(cached?1u:2u));
   bsp_printf("ALPHA_PIPELINE_BOARD,case=%d,width=%d,phase=%d,cached=%d,alpha=%d,pixels=%d,rd=%d,wr=%d,cache=%d,under_offscreen=%d\r\n",
    cases,width,phase,cached,alpha,(unsigned)p.pixels,(unsigned)p.read_bytes,
    (unsigned)p.write_bytes,(unsigned)p.cache_bytes,(unsigned)p.underflows);
   cases++;
  }
 CHECK(cases==24);
 bsp_printf("ALPHA_PIPELINE_BOARD_STOP,result=0,cases=%d,hardware=%d\r\n",cases,d.hardware_error);
 return 0;
}
