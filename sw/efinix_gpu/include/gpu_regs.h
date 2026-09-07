#ifndef EFINIX_GPU_REGS_H
#define EFINIX_GPU_REGS_H
#include <stdint.h>
#include <stddef.h>
#define GPU_APB_BASE UINT32_C(0xf8100000)
#define GPU_APB_BYTES UINT32_C(0x10000)
#define GPU_FRAMEBUFFER_A UINT32_C(0x02000000)
#define GPU_FRAMEBUFFER_B UINT32_C(0x02200000)
#define GPU_DENSE_ASSETS UINT32_C(0x02400000)
#define GPU_SPARSE_ASSETS UINT32_C(0x06000000)
#define GPU_DDR_END_EXCLUSIVE UINT32_C(0x10000000)
#define GPU_FRAME_WIDTH 640u
#define GPU_FRAME_HEIGHT 480u
#define GPU_BYTES_PER_PIXEL 2u
#define GPU_FRAME_BYTES 614400u
#define GPU_ID_VALUE UINT32_C(0x32444750)
#define GPU_VERSION_VALUE UINT32_C(0x00010000)
#define GPU_CONTROL_SUBMIT 1u
#define GPU_STATUS_QUEUE_LEVEL_MASK 0x1fu
#define GPU_STATUS_EMPTY 0x20u
#define GPU_STATUS_FULL 0x40u
#define GPU_STATUS_BUSY 0x80u
#define GPU_OP_MASK 0x0fu
#define GPU_WIDTH_MASK 0xffffu
#define GPU_HEIGHT_SHIFT 16u
#define GPU_COLOR_MASK 0xffffu
#define GPU_COLOR_KEY_SHIFT 16u
#define GPU_ALPHA_MASK 0xffu
#define GPU_FLAGS_SHIFT 16u
#define GPU_TAG_MASK 0xffffu
#define GPU_LAST_DONE_MASK 0xffffu
#define GPU_ERROR_MASK 0xffu
/* Offsets >= 0x48 are reserved: reads zero, writes ignored by current RTL.
 * FRONT/BACK return fixed A/B; CONTROL only implements SUBMIT.
 * No MMIO pointer or hardware driver is provided by this offline contract. */
#define GPU_REG_ID 0x0000u
#define GPU_REG_VERSION 0x0004u
#define GPU_REG_STATUS 0x0008u
#define GPU_REG_CONTROL 0x000cu
#define GPU_REG_OP 0x0010u
#define GPU_REG_SRC_ADDR 0x0014u
#define GPU_REG_DST_ADDR 0x0018u
#define GPU_REG_SIZE 0x001cu
#define GPU_REG_SRC_STRIDE 0x0020u
#define GPU_REG_DST_STRIDE 0x0024u
#define GPU_REG_COLOR_KEY 0x0028u
#define GPU_REG_ALPHA_FLAGS 0x002cu
#define GPU_REG_TAG 0x0030u
#define GPU_REG_LAST_DONE 0x0034u
#define GPU_REG_ERROR 0x0038u
#define GPU_REG_QUEUE_LEVEL 0x003cu
#define GPU_REG_FRONT_BUFFER 0x0040u
#define GPU_REG_BACK_BUFFER 0x0044u
#define GPU_REG_QOS_WATERMARKS 0x0048u
#define GPU_REG_PERF_CONTROL 0x004cu
#define GPU_REG_PERF_CYCLES_LO 0x0050u
#define GPU_REG_PERF_CYCLES_HI 0x0054u
#define GPU_REG_PERF_PIXELS_LO 0x0058u
#define GPU_REG_PERF_PIXELS_HI 0x005cu
#define GPU_REG_PERF_READ_BYTES_LO 0x0060u
#define GPU_REG_PERF_READ_BYTES_HI 0x0064u
#define GPU_REG_PERF_WRITE_BYTES_LO 0x0068u
#define GPU_REG_PERF_WRITE_BYTES_HI 0x006cu
#define GPU_REG_PERF_STALLS_LO 0x0070u
#define GPU_REG_PERF_STALLS_HI 0x0074u
typedef struct {
    uint32_t id;
    uint32_t version;
    uint32_t status;
    uint32_t control;
    uint32_t op;
    uint32_t src_addr;
    uint32_t dst_addr;
    uint32_t size;
    uint32_t src_stride;
    uint32_t dst_stride;
    uint32_t color_key;
    uint32_t alpha_flags;
    uint32_t tag;
    uint32_t last_done;
    uint32_t error;
    uint32_t queue_level;
    uint32_t front_buffer;
    uint32_t back_buffer;
    uint32_t qos_watermarks;
    uint32_t perf_control;
    uint32_t perf_cycles_lo;
    uint32_t perf_cycles_hi;
    uint32_t perf_pixels_lo;
    uint32_t perf_pixels_hi;
    uint32_t perf_read_bytes_lo;
    uint32_t perf_read_bytes_hi;
    uint32_t perf_write_bytes_lo;
    uint32_t perf_write_bytes_hi;
    uint32_t perf_stalls_lo;
    uint32_t perf_stalls_hi;
} gpu_register_layout;
_Static_assert(offsetof(gpu_register_layout, id) == GPU_REG_ID, "register offset");
_Static_assert(offsetof(gpu_register_layout, version) == GPU_REG_VERSION, "register offset");
_Static_assert(offsetof(gpu_register_layout, status) == GPU_REG_STATUS, "register offset");
_Static_assert(offsetof(gpu_register_layout, control) == GPU_REG_CONTROL, "register offset");
_Static_assert(offsetof(gpu_register_layout, op) == GPU_REG_OP, "register offset");
_Static_assert(offsetof(gpu_register_layout, src_addr) == GPU_REG_SRC_ADDR, "register offset");
_Static_assert(offsetof(gpu_register_layout, dst_addr) == GPU_REG_DST_ADDR, "register offset");
_Static_assert(offsetof(gpu_register_layout, size) == GPU_REG_SIZE, "register offset");
_Static_assert(offsetof(gpu_register_layout, src_stride) == GPU_REG_SRC_STRIDE, "register offset");
_Static_assert(offsetof(gpu_register_layout, dst_stride) == GPU_REG_DST_STRIDE, "register offset");
_Static_assert(offsetof(gpu_register_layout, color_key) == GPU_REG_COLOR_KEY, "register offset");
_Static_assert(offsetof(gpu_register_layout, alpha_flags) == GPU_REG_ALPHA_FLAGS, "register offset");
_Static_assert(offsetof(gpu_register_layout, tag) == GPU_REG_TAG, "register offset");
_Static_assert(offsetof(gpu_register_layout, last_done) == GPU_REG_LAST_DONE, "register offset");
_Static_assert(offsetof(gpu_register_layout, error) == GPU_REG_ERROR, "register offset");
_Static_assert(offsetof(gpu_register_layout, queue_level) == GPU_REG_QUEUE_LEVEL, "register offset");
_Static_assert(offsetof(gpu_register_layout, front_buffer) == GPU_REG_FRONT_BUFFER, "register offset");
_Static_assert(offsetof(gpu_register_layout, back_buffer) == GPU_REG_BACK_BUFFER, "register offset");
_Static_assert(offsetof(gpu_register_layout, qos_watermarks) == GPU_REG_QOS_WATERMARKS, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_control) == GPU_REG_PERF_CONTROL, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_cycles_lo) == GPU_REG_PERF_CYCLES_LO, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_cycles_hi) == GPU_REG_PERF_CYCLES_HI, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_pixels_lo) == GPU_REG_PERF_PIXELS_LO, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_pixels_hi) == GPU_REG_PERF_PIXELS_HI, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_read_bytes_lo) == GPU_REG_PERF_READ_BYTES_LO, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_read_bytes_hi) == GPU_REG_PERF_READ_BYTES_HI, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_write_bytes_lo) == GPU_REG_PERF_WRITE_BYTES_LO, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_write_bytes_hi) == GPU_REG_PERF_WRITE_BYTES_HI, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_stalls_lo) == GPU_REG_PERF_STALLS_LO, "register offset");
_Static_assert(offsetof(gpu_register_layout, perf_stalls_hi) == GPU_REG_PERF_STALLS_HI, "register offset");
_Static_assert(sizeof(gpu_register_layout) == 0x78, "register extent");
#endif
