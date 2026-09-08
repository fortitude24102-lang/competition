#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "golden_renderer.h"
static unsigned seed=17;
static unsigned rnd(unsigned n) { seed=seed*1664525u+1013904223u; return seed%n; }
int main(void) {
 _Alignas(2) unsigned char src[1024],dst[1024],want[1024];
 for(unsigned i=0;i<1024;i++) src[i]=(unsigned char)(i*37);
 for(unsigned k=0;k<1000;k++) {
  golden_surface a={src,sizeof src,16,16,32+2*rnd(8)},b={dst,sizeof dst,16,16,32+2*rnd(8)};
  unsigned w=1+rnd(16),h=1+rnd(16),sx=rnd(17-w),sy=rnd(17-h),dx=rnd(17-w),dy=rnd(17-h);
  memset(dst,0xa5,sizeof dst); memcpy(want,dst,sizeof dst);
  for(unsigned y=0;y<h;y++) for(unsigned x=0;x<w*2;x++) want[(dy+y)*b.stride_bytes+dx*2+x]=src[(sy+y)*a.stride_bytes+sx*2+x];
  assert(golden_copy(&b,dx,dy,&a,sx,sy,w,h)==0);
  assert(memcmp(want,dst,sizeof dst)==0);
 }
 golden_surface a={src,sizeof src,16,16,32};
 assert(golden_copy(&a,1,0,&a,0,0,4,2)==GPU_ERROR_OVERLAPPING_COPY);
 assert(golden_copy(&a,0,15,&a,0,0,16,1)==0);
 assert(golden_copy(&a,16,0,&a,0,0,1,1)==GPU_ERROR_ADDRESS_RANGE);
 puts("PASS: 1000 seeded stride/odd/even copy rectangles, overlap and boundary rejection");
}
