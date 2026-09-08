#include "benchmark.h"
static const struct { uint16_t x,y,w,h,color; } scene[]={
 {0,0,640,480,0x07e0},{1,1,63,31,0xf800},{100,80,200,100,0x001f},{639,479,1,1,0xffff}};
int gpu_benchmark(gpu_device *d,const golden_surface *cpu,const golden_surface *gpu,uint32_t address,uint32_t polls,gpu_benchmark_result *r) {
 if(!d || !cpu || !gpu || !r || !cpu->pixels || !gpu->pixels || cpu->width!=640 || cpu->height!=480 || gpu->width!=640 || gpu->height!=480 || cpu->stride_bytes!=1280 || gpu->stride_bytes!=1280 || cpu->size_bytes!=GPU_FRAME_BYTES || gpu->size_bytes!=GPU_FRAME_BYTES) return GPU_DRIVER_ARGUMENT;
 *r=(gpu_benchmark_result){0};
 for(unsigned i=0;i<sizeof scene/sizeof scene[0];i++) r->pixels+=(uint32_t)scene[i].w*scene[i].h;
 gpu_platform_sync(); uint64_t start=gpu_platform_cycles();
 for(unsigned i=0;i<sizeof scene/sizeof scene[0];i++) {
  int e=golden_fill(cpu,scene[i].x,scene[i].y,scene[i].w,scene[i].h,scene[i].color); if(e) return e;
 }
 gpu_platform_sync(); r->cpu_cycles=gpu_platform_cycles()-start;
 gpu_platform_sync(); start=gpu_platform_cycles();
 for(unsigned i=0;i<sizeof scene/sizeof scene[0];i++) {
  uint16_t tag; int e=gpu_fill_async(d,address+(uint32_t)scene[i].y*1280+scene[i].x*2u,1280,scene[i].w,scene[i].h,scene[i].color,&tag);
  if(e) return e;
  e=gpu_wait_tag(d,tag,polls); if(e) return e;
 }
 gpu_platform_sync(); r->gpu_cycles=gpu_platform_cycles()-start;
 gpu_platform_sync();
 r->cpu_crc=golden_crc32(cpu->pixels,cpu->size_bytes);
 r->gpu_crc=golden_crc32(gpu->pixels,gpu->size_bytes);
 return r->cpu_crc==r->gpu_crc ? 0 : GPU_DRIVER_HARDWARE;
}

