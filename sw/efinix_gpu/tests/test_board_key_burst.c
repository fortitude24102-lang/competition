/* Board-only DDR byte-lane check; does not alter the demo or CPU baseline. */
#define main reference_main
#include "../src/main.c"
#undef main

int main(void) {
 bsp_init();
 gpu_device gpu;
 int e=gpu_init(&gpu,GPU_APB_BASE);
 if(e) { bsp_printf("KEY_BOARD_FAIL,init=%d\r\n",e); return e; }
 const uint16_t pattern[]={0x1111,0x1234,0x2222,0xbeef,0xbeef,0x3333,0xbeef,0xbeef};
 const unsigned widths[]={1,2,3,8,11,12,513};
 for(unsigned trial=0;trial<29;trial++) {
  unsigned width=widths[trial<28?trial/4u:3u];
  unsigned src_offset=(trial&2u),dst_offset=(trial&1u)*2u;
  unsigned transparent=trial==28,stride=width*2u+6u,height=3u;
  uint32_t src=GPU_DENSE_ASSETS+0xff8u+src_offset;
  uint32_t dst=GPU_FRAMEBUFFER_A+0xff4u+dst_offset;
  volatile uint16_t *guard=(volatile uint16_t *)(uintptr_t)(dst-2u);
  unsigned guard_count=(height*stride)/2u+2u;
  for(unsigned i=0;i<guard_count;i++) guard[i]=0xa55a;
  for(unsigned row=0;row<height;row++) {
   volatile uint16_t *pixels=(volatile uint16_t *)(uintptr_t)(src+row*stride);
   for(unsigned x=0;x<width;x++) pixels[x]=transparent?0xbeef:pattern[(row*width+x)%8u];
  }
  gpu_platform_sync();
  gpu_command command={.op=GPU_OP_COLOR_KEY,.src_addr=src,.dst_addr=dst,
   .src_stride=stride,.dst_stride=stride,.width_pixels=(uint16_t)width,
   .height_pixels=(uint16_t)height,.color_key=0xbeef};
  e=gpu_clear_perf(&gpu); if(e) return e;
  e=perf_render_gpu(&gpu,&command,1,10000000u);
  if(e) { bsp_printf("KEY_BOARD_FAIL,case=%d,driver=%d\r\n",trial,e); return e; }
  gpu_platform_sync();
  gpu_perf_snapshot counters;
  e=gpu_read_perf_snapshot(&gpu,&counters); if(e) return e;
  unsigned written=0;
  for(unsigned i=0;i<width*height;i++) if(!transparent && pattern[i%8u]!=0xbeef) written+=2;
  unsigned read=0;
  for(unsigned row=0;row<height;row++) read+=(width*2u+((src+row*stride)&3u)+3u)&~3u;
  if(counters.pixels!=width*height || counters.read_bytes!=read || counters.write_bytes!=written) {
   bsp_printf("KEY_BOARD_FAIL,case=%d,pixels=%d,rd=%d,wr=%d\r\n",trial,
    (uint32_t)counters.pixels,(uint32_t)counters.read_bytes,(uint32_t)counters.write_bytes);
   return 1;
  }
  for(unsigned i=0;i<guard_count;i++) {
   int index=(int)i-1;
   uint16_t expected=0xa55a;
   unsigned row=index>=0?(unsigned)index/(stride/2u):height;
   unsigned x=index>=0?(unsigned)index%(stride/2u):width;
   if(row<height && x<width) {
    uint16_t pixel=transparent?0xbeef:pattern[(row*width+x)%8u];
    if(pixel!=0xbeef) expected=pixel;
   }
   if(guard[i]!=expected) {
    bsp_printf("KEY_BOARD_FAIL,case=%d,index=%d,actual=%d,expected=%d\r\n",
     trial,i,guard[i],expected);
    return 1;
   }
  }
  bsp_printf("KEY_BOARD_CASE_PASS,case=%d,width=%d,src_offset=%d,dst_offset=%d,pixels=%d,rd=%d,wr=%d\r\n",
   trial,width,src_offset,dst_offset,(uint32_t)counters.pixels,(uint32_t)counters.read_bytes,(uint32_t)counters.write_bytes);
 }
 bsp_printf("KEY_BOARD_STOP,result=0,hardware=%d\r\n",gpu.hardware_error);
 return 0;
}
