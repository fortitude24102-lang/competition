/* Private cached-Key pixel oracle, eligible for CachedKeyStream row trimming.
 * No PRESENT, game workload, FPS estimate or performance-gain claim. */
#include "gpu.h"
#include "bsp.h"
#include "vexriscv.h"

#define K 0xf81fu
#define A 0xa55au
static const uint16_t source_pixels[3][32] = {
    {K,K,K,K,K,K,K,K,
     K,K,0x1111,0x2222,K,0x3333,K,K,
     0x4444,K,K,0x5555,K,K,K,0x6666,
     K,0x7777,0x8888,K,0x9999,K,0xaaaa,K},
    {K,K,K,K,K,K,K,K, K,K,K,K,K,K,K,K,
     K,K,K,K,K,K,K,K, K,K,K,K,K,K,K,K},
    {0x1001,0x1002,0x1003,0x1004,0x1005,0x1006,0x1007,0x1008,
     0x1009,0x100a,0x100b,0x100c,0x100d,0x100e,0x100f,0x1010,
     0x1011,0x1012,0x1013,0x1014,0x1015,0x1016,0x1017,0x1018,
     0x1019,0x101a,0x101b,0x101c,0x101d,0x101e,0x101f,0x1020}
};
/* Independent literal DDR oracle: eight image halfwords plus two padding
 * halfwords per row. Key pixels must leave the prefilled destination intact. */
static const uint16_t expected_pixels[3][40] = {
    {A,A,A,A,A,A,A,A,A,A,
     A,A,0x1111,0x2222,A,0x3333,A,A,A,A,
     0x4444,A,A,0x5555,A,A,A,0x6666,A,A,
     A,0x7777,0x8888,A,0x9999,A,0xaaaa,A,A,A},
    {A,A,A,A,A,A,A,A,A,A, A,A,A,A,A,A,A,A,A,A,
     A,A,A,A,A,A,A,A,A,A, A,A,A,A,A,A,A,A,A,A},
    {0x1001,0x1002,0x1003,0x1004,0x1005,0x1006,0x1007,0x1008,A,A,
     0x1009,0x100a,0x100b,0x100c,0x100d,0x100e,0x100f,0x1010,A,A,
     0x1011,0x1012,0x1013,0x1014,0x1015,0x1016,0x1017,0x1018,A,A,
     0x1019,0x101a,0x101b,0x101c,0x101d,0x101e,0x101f,0x1020,A,A}
};
static const unsigned opaque_pixels[3] = {10,0,32};

uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
    __asm__ volatile("fence iorw,iorw" ::: "memory");
    data_cache_invalidate_all();
    __asm__ volatile("fence iorw,iorw" ::: "memory");
}

int main(void) {
    bsp_init();
    gpu_device gpu = {0};
    unsigned fixture = 0, phase = 0;
    int e = gpu_init(&gpu, GPU_APB_BASE);
    if (e) goto stop;
    volatile uint16_t *source = (volatile uint16_t *)(uintptr_t)0x02410000u;
    for (fixture = 0; fixture < 3; ++fixture) for (phase = 0; phase < 2; ++phase) {
        uint32_t destination = 0x02600000u + phase * 2u;
        volatile uint16_t *dst = (volatile uint16_t *)(uintptr_t)destination;
        for (unsigned i = 0; i < 32; ++i) source[i] = source_pixels[fixture][i];
        gpu_platform_sync();
        e = gpu_texture_cache_load(&gpu, 0x02410000u, 64, 10000000u);
        if (e) goto stop;
        /* Cache contents must win over these different DDR pixels. */
        for (unsigned i = 0; i < 32; ++i) source[i] = 0xdeadu;
        for (int i = -2; i < 42; ++i) dst[i] = A;
        gpu_platform_sync();
        e = gpu_clear_perf(&gpu);
        if (e) goto stop;
        uint16_t tag;
        e = gpu_color_key_async(&gpu, 0x02410000u, destination, 16, 20, 8, 4, K, &tag);
        if (e) goto stop;
        e = gpu_wait_tag(&gpu, tag, 10000000u);
        if (e) goto stop;
        gpu_platform_sync();
        gpu_perf_snapshot p;
        e = gpu_read_perf_snapshot(&gpu, &p);
        if (e) goto stop;
        for (int i = -2; i < 42; ++i) {
            uint16_t expected = i >= 0 && i < 40 ? expected_pixels[fixture][i] : A;
            if (dst[i] != expected) {
                bsp_printf("KEY_TRIM_BOARD_MISMATCH,case=%d,phase=%d,index=%d,actual=%x,expected=%x\r\n",
                           fixture,phase,i,dst[i],expected);
                e = GPU_DRIVER_HARDWARE;
                goto stop;
            }
        }
        if (p.pixels != 32 || p.read_bytes != 0 || p.cache_bytes != 64 ||
            p.write_bytes != opaque_pixels[fixture] * 2u || gpu.hardware_error) {
            bsp_printf("KEY_TRIM_BOARD_COUNTERS,case=%d,phase=%d,pixels=%d,rd=%d,cache=%d,wr=%d\r\n",
                       fixture,phase,(unsigned)p.pixels,(unsigned)p.read_bytes,
                       (unsigned)p.cache_bytes,(unsigned)p.write_bytes);
            e = GPU_DRIVER_HARDWARE;
            goto stop;
        }
        bsp_printf("KEY_TRIM_BOARD_CASE_PASS,case=%d,phase=%d,pixels=%d,rd=%d,cache=%d,wr=%d\r\n",
                   fixture,phase,(unsigned)p.pixels,(unsigned)p.read_bytes,
                   (unsigned)p.cache_bytes,(unsigned)p.write_bytes);
    }
stop:
    if (e) bsp_printf("KEY_TRIM_BOARD_FAIL,case=%d,phase=%d,result=%d,hardware=%d\r\n",
                      fixture,phase,e,gpu.hardware_error);
    bsp_printf("KEY_TRIM_BOARD_STOP,result=%d,hardware=%d\r\n",e,gpu.hardware_error);
    return e;
}
