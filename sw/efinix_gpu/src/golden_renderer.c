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
