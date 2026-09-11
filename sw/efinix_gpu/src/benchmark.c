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

int gpu_benchmark_submit_stream(gpu_device *d,const gpu_command *commands,size_t count,
 enum gpu_submit_mode mode,uint32_t polls,gpu_submit_metrics *m) {
 if(!d || !commands || !count || !m || (mode!=GPU_SUBMIT_WAIT_EACH && mode!=GPU_SUBMIT_BATCH))
  return GPU_DRIVER_ARGUMENT;
 *m=(gpu_submit_metrics){.command_count=(uint32_t)count};
 d->queue_high_watermark=d->outstanding;
 gpu_platform_sync();
 uint64_t start=gpu_platform_cycles();
 uint16_t tag=0;
 for(size_t i=0;i<count;i++) {
  int e=gpu_submit(d,&commands[i],polls,&tag); if(e) return e;
  if(mode==GPU_SUBMIT_WAIT_EACH) {
   ++m->wait_count;
   e=gpu_wait_tag(d,tag,polls); if(e) return e;
  }
 }
 if(mode==GPU_SUBMIT_BATCH) {
  m->wait_count=1;
  int e=gpu_wait_tag(d,tag,polls); if(e) return e;
 }
 gpu_platform_sync();
 m->cpu_cycles=gpu_platform_cycles()-start;
 m->queue_high_watermark=d->queue_high_watermark;
 m->waits_per_command_permille=(uint16_t)((uint64_t)m->wait_count*1000u/count);
 return 0;
}

static uint16_t percentile5(uint16_t *values,size_t count) {
 for(size_t i=1;i<count;i++) {
  uint16_t value=values[i]; size_t j=i;
  while(j && values[j-1]>value) { values[j]=values[j-1]; --j; }
  values[j]=value;
 }
 size_t rank=(count*5u+99u)/100u;
 return values[rank-1u];
}

int benchmark_summarize_run(const benchmark_frame_sample *samples,size_t count,
 benchmark_run_summary *summary) {
 if(!samples || !summary || count!=BENCHMARK_FRAME_COUNT) return GPU_DRIVER_ARGUMENT;
 uint16_t fps[BENCHMARK_FRAME_COUNT],tier_fps[BENCHMARK_FRAME_COUNT];
 *summary=(benchmark_run_summary){0};
 for(size_t i=0;i<count;i++) {
  fps[i]=samples[i].fps;
  summary->total_underflows+=samples[i].underflow_count;
  summary->total_errors+=samples[i].error_count;
 }
 summary->p5_fps=percentile5(fps,count);
 if(summary->p5_fps<60 || summary->total_underflows || summary->total_errors) return 0;
 for(size_t candidate=0;candidate<count;candidate++) {
  uint16_t sprites=samples[candidate].sprite_count;
  if(sprites<=summary->stable_sprite_count) continue;
  size_t tier_count=0;
  for(size_t i=0;i<count;i++) if(samples[i].sprite_count>=sprites)
   tier_fps[tier_count++]=samples[i].fps;
  if(tier_count>=BENCHMARK_MIN_CAPACITY_SAMPLES && percentile5(tier_fps,tier_count)>=60)
   summary->stable_sprite_count=sprites;
 }
 return 0;
}

