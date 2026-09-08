#ifndef EFINIX_GOLDEN_RENDERER_H
#define EFINIX_GOLDEN_RENDERER_H
#include <stddef.h>
#include "gpu.h"
typedef struct {
    uint8_t *pixels;
    size_t size_bytes;
    uint16_t width, height;
    uint32_t stride_bytes;
} golden_surface;
/* Reject invalid rectangles without any write; no clipping. Stride is bytes.
 * Buffer contains at least (height-1)*stride + width*2 bytes; padding untouched. */
enum gpu_error golden_fill(const golden_surface *s, uint16_t x, uint16_t y,
                          uint16_t width, uint16_t height, uint16_t color);
/* CRC-32/ISO-HDLC: reflected polynomial EDB88320, init/xorout FFFFFFFF.
 * Covers exactly size bytes in memory order, including padding if supplied.
 * Framebuffer acceptance uses the full allocated span, initialized padding. */
uint32_t golden_crc32(const void *data, size_t size);
enum gpu_error golden_copy(const golden_surface *dst,uint16_t dx,uint16_t dy,
 const golden_surface *src,uint16_t sx,uint16_t sy,uint16_t w,uint16_t h);
#endif
