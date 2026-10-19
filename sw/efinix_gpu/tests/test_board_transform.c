/* JTAG-only offscreen pixel oracle. This is NOT gameplay/FPS qualification. */
#include "perf_demo.h"
#include "bsp.h"
#include "vexriscv.h"
uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
 __asm__ volatile("fence iorw,iorw" ::: "memory");
 data_cache_invalidate_all();
 __asm__ volatile("fence iorw,iorw" ::: "memory");
}
int main(void) {
 bsp_init();gpu_device d;int result=gpu_init(&d,GPU_APB_BASE);
 if(result) return result;
 uint32_t required=GPU_STATUS_TRANSFORM_PRESENT|GPU_STATUS_GRAYSCALE_PRESENT;
 if((*(volatile uint32_t *)(d.base+GPU_REG_STATUS)&required)!=required) {
  bsp_printf("TRANSFORM_BOARD_FAIL,capability=0\r\n");return GPU_DRIVER_ARGUMENT;
 }
 /* Private test firmware owns these surfaces, no game/assets/list are live. */
 volatile uint16_t *src=(volatile uint16_t *)0x02410002u;
 volatile uint16_t *dst=(volatile uint16_t *)0x02600002u;
 static const uint16_t pixels[16]={0xf800,0xbeef,0x07e0,0x001f,
  0x1111,0x2222,0x3333,0x4444,0x5555,0x6666,0xbeef,0x8888,
  0x9999,0xaaaa,0xbbbb,0xcccc};
 for(unsigned y=0;y<4;y++) for(unsigned x=0;x<6;x++) src[y*6+x]=x<4?pixels[y*4+x]:0xdead;
 for(unsigned mode=0;mode<5;mode++) for(unsigned mirror=0;mirror<4;mirror++)
  for(unsigned keyed=0;keyed<2;keyed++) for(unsigned gray=0;gray<2;gray++) {
   unsigned side=mode==1?8:mode==2?2:mode==3?5:mode==4?3:4;
   uint16_t flags=(uint16_t)(mirror|(keyed?GPU_TRANSFORM_COLOR_KEY:0)|
    (gray?GPU_TRANSFORM_GRAYSCALE:0));
   for(unsigned i=0;i<100;i++) dst[i]=0xa55a;
   dst[-1]=0xa55a;gpu_platform_sync();gpu_perf_snapshot before,after;
   result=gpu_read_perf_snapshot(&d,&before);if(result) goto stop;
   uint16_t tag;uint64_t start=gpu_platform_cycles();
   result=gpu_transform_blit_async(&d,(uint32_t)(uintptr_t)src,(uint32_t)(uintptr_t)dst,
    12,22,4,4,(uint16_t)side,(uint16_t)side,flags,0xbeef,&tag);
   if(result) goto stop;
   result=gpu_wait_tag(&d,tag,10000000u);if(result) goto stop;
   unsigned us=(unsigned)((gpu_platform_cycles()-start)/(BSP_CLINT_HZ/1000000u));
   gpu_platform_sync();result=gpu_read_perf_snapshot(&d,&after);if(result) goto stop;
   unsigned mismatch=dst[-1]!=0xa55a,written=0;
   for(unsigned y=0;y<9;y++) for(unsigned x=0;x<11;x++) {
    uint16_t expected=0xa55a;
    if(y<side && x<side) {
     unsigned sx=x*4u/side;
     unsigned sy=y*4u/side;
     if(mirror&1u) sx=3u-sx;
     if(mirror&2u) sy=3u-sy;
     uint16_t p=pixels[sy*4+sx];
     if(!keyed || p!=0xbeef) {
      if(gray) {
       unsigned r=p>>11,g=(p>>5)&63u,b=p&31u;
       unsigned y8=((r*8u+r/4u)+2u*(g*4u+g/16u)+(b*8u+b/4u))/4u;
       p=(uint16_t)((y8/8u)*2048u+(y8/4u)*32u+y8/8u);
      }
      expected=p;written++;
     }
    }
    mismatch+=dst[y*11+x]!=expected;
   }
   /* No PRESENT/scanout is started by this offscreen oracle. HDMI's missing
      input episodes are logged, not mistaken for failures of the DDR raster.
      Normal display/qualification still requires zero new underflows. */
   unsigned failed=mismatch || d.hardware_error || after.pixels-before.pixels!=side*side ||
    after.write_bytes-before.write_bytes!=written*2u;
   bsp_printf("TRANSFORM_BOARD,mode=%d,flags=%d,side=%d,us=%d,pixels=%d,wr=%d,mismatch=%d,under_offscreen=%d,failed=%d\r\n",
    mode,flags,side,us,(unsigned)(after.pixels-before.pixels),
    (unsigned)(after.write_bytes-before.write_bytes),mismatch,
    (unsigned)(after.underflows-before.underflows),failed);
   if(failed) {result=GPU_DRIVER_HARDWARE;goto stop;}
  }
stop:
 if(result) bsp_printf("TRANSFORM_BOARD_FAIL,result=%d\r\n",result);
 bsp_printf("TRANSFORM_BOARD_STOP,result=%d,hardware=%d\r\n",result,d.hardware_error);
 return result;
}
