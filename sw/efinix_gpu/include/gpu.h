#ifndef EFINIX_GPU_H
#define EFINIX_GPU_H
#include "gpu_regs.h"
enum gpu_opcode { GPU_OP_NOP=0, GPU_OP_FILL=1, GPU_OP_COPY=2,
    GPU_OP_COLOR_KEY=3, GPU_OP_ALPHA=4, GPU_OP_SPARSE=5, GPU_OP_PRESENT=6 };
enum gpu_error { GPU_ERROR_NONE=0, GPU_ERROR_INVALID_OPCODE=1,
    GPU_ERROR_ZERO_SIZE=2, GPU_ERROR_MISALIGNED_ADDRESS=3,
    GPU_ERROR_STRIDE_TOO_SMALL=4, GPU_ERROR_ADDRESS_RANGE=5,
    GPU_ERROR_OVERLAPPING_COPY=6, GPU_ERROR_QUEUE_FULL=7,
    GPU_ERROR_SPARSE_FORMAT=8, GPU_ERROR_AXI_RESPONSE=9 };
/* Field contract, not a packed hardware descriptor. op uses only low 4 bits;
 * flags are reserved by current execution logic: callers should supply zero. */
typedef struct {
    uint32_t src_addr, dst_addr, src_stride, dst_stride;
    uint16_t width_pixels, height_pixels, color, color_key, flags, tag;
    uint8_t op, alpha;
} gpu_command;
_Static_assert(sizeof(uint32_t)==4 && sizeof(uint16_t)==2 && sizeof(uint8_t)==1,
               "command scalar widths");
_Static_assert((GPU_ALPHA_MASK & (0xffffu << GPU_FLAGS_SHIFT)) == 0,
               "alpha flags fields must not overlap");
_Static_assert((GPU_STATUS_QUEUE_LEVEL_MASK | GPU_STATUS_EMPTY |
                GPU_STATUS_FULL | GPU_STATUS_BUSY) == 0xff, "status fields");
static inline uint32_t gpu_pack_size(uint16_t width, uint16_t height) {
    return (uint32_t)width | ((uint32_t)height << GPU_HEIGHT_SHIFT);
}
static inline uint32_t gpu_pack_color_key(uint16_t color, uint16_t key) {
    return (uint32_t)color | ((uint32_t)key << GPU_COLOR_KEY_SHIFT);
}
static inline uint32_t gpu_pack_alpha_flags(uint8_t alpha, uint16_t flags) {
    return (uint32_t)alpha | ((uint32_t)flags << GPU_FLAGS_SHIFT);
}
#endif
