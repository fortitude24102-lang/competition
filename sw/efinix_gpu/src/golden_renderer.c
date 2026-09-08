#include "golden_renderer.h"
enum gpu_error golden_fill(const golden_surface *s, uint16_t x, uint16_t y,
                          uint16_t width, uint16_t height, uint16_t color) {
    if (!s || !s->pixels) return GPU_ERROR_ADDRESS_RANGE;
    if (!width || !height || !s->width || !s->height) return GPU_ERROR_ZERO_SIZE;
    if (((uintptr_t)s->pixels & 1) || (s->stride_bytes & 1))
        return GPU_ERROR_MISALIGNED_ADDRESS;
    if (s->stride_bytes < (uint32_t)s->width*2) return GPU_ERROR_STRIDE_TOO_SMALL;
    uint64_t end=(uint64_t)(s->height-1)*s->stride_bytes + (uint32_t)s->width*2;
    if (end > s->size_bytes || end > SIZE_MAX ||
        (uint32_t)x+width > s->width || (uint32_t)y+height > s->height)
        return GPU_ERROR_ADDRESS_RANGE;
    for (uint32_t row=y; row < (uint32_t)y+height; ++row) {
        uint8_t *dst=s->pixels + (size_t)row*s->stride_bytes + (size_t)x*2;
        for (uint32_t col=0; col<width; ++col) {
            dst[col*2]=(uint8_t)color;
            dst[col*2+1]=(uint8_t)(color>>8);
        }
    }
    return GPU_ERROR_NONE;
}
uint32_t golden_crc32(const void *data, size_t size) {
    const uint8_t *bytes=data;
    uint32_t crc=UINT32_MAX;
    for (size_t i=0; i<size; ++i) {
        crc ^= bytes[i];
        for (unsigned bit=0; bit<8; ++bit)
            crc=(crc>>1)^((crc&1) ? UINT32_C(0xedb88320) : 0);
    }
    return crc^UINT32_MAX;
}

enum gpu_error golden_copy(const golden_surface *dst,uint16_t dx,uint16_t dy,
 const golden_surface *src,uint16_t sx,uint16_t sy,uint16_t w,uint16_t h) {
 const golden_surface *s[2]={src,dst}; uint16_t x[2]={sx,dx},y[2]={sy,dy};
 uintptr_t start[2],end[2];
 if(!w || !h) return GPU_ERROR_ZERO_SIZE;
 for(unsigned i=0;i<2;i++) {
  if(!s[i] || !s[i]->pixels) return GPU_ERROR_ADDRESS_RANGE;
  if(((uintptr_t)s[i]->pixels|s[i]->stride_bytes)&1) return GPU_ERROR_MISALIGNED_ADDRESS;
  if(s[i]->stride_bytes<(uint32_t)s[i]->width*2) return GPU_ERROR_STRIDE_TOO_SMALL;
  if(!s[i]->height || (uint32_t)x[i]+w>s[i]->width || (uint32_t)y[i]+h>s[i]->height) return GPU_ERROR_ADDRESS_RANGE;
  uint64_t extent=(uint64_t)(s[i]->height-1)*s[i]->stride_bytes+s[i]->width*2u;
  if(extent>s[i]->size_bytes || extent>UINTPTR_MAX-(uintptr_t)s[i]->pixels) return GPU_ERROR_ADDRESS_RANGE;
  start[i]=(uintptr_t)s[i]->pixels+(size_t)y[i]*s[i]->stride_bytes+x[i]*2u;
  end[i]=start[i]+(size_t)(h-1)*s[i]->stride_bytes+w*2u;
 }
 /* Match hardware's conservative bounding-span overlap contract, including padding. */
 if(start[0]<end[1] && start[1]<end[0]) return GPU_ERROR_OVERLAPPING_COPY;
 for(unsigned row=0;row<h;row++) for(unsigned byte=0;byte<w*2u;byte++)
  ((uint8_t *)start[1])[(size_t)row*dst->stride_bytes+byte]=((const uint8_t *)start[0])[(size_t)row*src->stride_bytes+byte];
 return GPU_ERROR_NONE;
}
