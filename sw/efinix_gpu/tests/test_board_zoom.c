/* Standalone GPU zoom demo; does not change gameplay or FPS qualification. */
#include "bullet_demo.h"
#include "framebuffer.h"
#include "hud.h"
#include "perf_demo.h"
#include "zoom_control.h"
#include <stdio.h>
#include <string.h>

static unsigned zoom_text(gpu_command *commands, uint32_t dst, unsigned row,
                          const char *text) {
    static const char alphabet[] = HUD_GLYPH_CHARACTERS;
    unsigned count = 0;
    for (; text[count] && count < HUD_COMPARISON_COLUMNS; ++count) {
        const char *glyph = strchr(alphabet, text[count]);
        unsigned index = glyph ? (unsigned)(glyph - alphabet) : HUD_GLYPH_COUNT - 1u;
        commands[count] = (gpu_command){
            .op = GPU_OP_COPY,
            .src_addr = HUD_GLYPH_ATLAS_ADDR + index * HUD_GLYPH_CELL_BYTES,
            .dst_addr = dst + row * HUD_GLYPH_HEIGHT * GPU_FRAME_STRIDE +
                        (8u + count * HUD_GLYPH_WIDTH) * 2u,
            .src_stride = HUD_GLYPH_WIDTH * 2u, .dst_stride = GPU_FRAME_STRIDE,
            .width_pixels = HUD_GLYPH_WIDTH, .height_pixels = HUD_GLYPH_HEIGHT};
    }
    return count;
}

static void zoom_plane(gpu_command *c, uint32_t back, unsigned side, unsigned gray) {
    unsigned center_x = gray ? GPU_FRAME_WIDTH * 3u / 4u : GPU_FRAME_WIDTH / 4u;
    *c = (gpu_command){.op = GPU_OP_TRANSFORM,
        .src_addr = BULLET_LOCAL_ATLAS + BULLET_PLAYER_OFFSET,
        .dst_addr = back + ((GPU_FRAME_HEIGHT - side) / 2u) * GPU_FRAME_STRIDE +
                    (center_x - side / 2u) * 2u,
        .src_stride = 32, .dst_stride = GPU_FRAME_STRIDE,
        .width_pixels = (uint16_t)side, .height_pixels = (uint16_t)side,
        .src_width_pixels = 16, .src_height_pixels = 16,
        .flags = GPU_TRANSFORM_COLOR_KEY | (gray ? GPU_TRANSFORM_GRAYSCALE : 0),
        .color_key = BULLET_COLOR_KEY};
}

#ifdef ZOOM_HOST_TEST
#include <assert.h>
int main(void) {
    gpu_command c[HUD_COMPARISON_COLUMNS + 1] = {{0}};
    assert(zoom_text(c, GPU_FRAMEBUFFER_B, 2, "AZ09-. ") == 7);
    assert(c[0].op == GPU_OP_COPY && c[0].src_addr == 0x02c40000u);
    assert(c[1].src_addr == 0x02c43138u);
    assert(c[6].src_addr == 0x02c44ad0u);
    assert(c[0].dst_addr == 0x02210e10u && c[1].dst_addr == 0x02210e2cu);
    assert(c[0].src_stride == 28 && c[0].dst_stride == 1920);
    assert(c[0].width_pixels == 14 && c[0].height_pixels == 18);
    assert(zoom_text(c, GPU_FRAMEBUFFER_A, 0, "?") == 1);
    assert(c[0].src_addr == 0x02c44ad0u); /* Unsupported glyph becomes space. */
    char long_line[80]; memset(long_line, 'A', sizeof long_line);
    long_line[79] = 0;
    c[64].src_addr = 0x12345678u;
    assert(zoom_text(c, GPU_FRAMEBUFFER_A, 0, long_line) == 64);
    assert(c[64].src_addr == 0x12345678u);
    assert(zoom_text(c, GPU_FRAMEBUFFER_A, 0, "") == 0);
    gpu_command plane;
    zoom_plane(&plane, GPU_FRAMEBUFFER_B, 16, 0);
    assert(plane.op == GPU_OP_TRANSFORM && plane.width_pixels == 16 && plane.height_pixels == 16);
    assert(plane.src_width_pixels == 16 && plane.src_height_pixels == 16);
    assert(plane.flags == GPU_TRANSFORM_COLOR_KEY && plane.color_key == BULLET_COLOR_KEY);
    assert(plane.src_addr == BULLET_LOCAL_ATLAS + BULLET_PLAYER_OFFSET);
    assert(plane.dst_addr == GPU_FRAMEBUFFER_B + 262u * 1920u + 232u * 2u);
    zoom_plane(&plane, GPU_FRAMEBUFFER_B, 64, 1);
    assert(plane.width_pixels == 64 && plane.height_pixels == 64);
    assert(plane.flags == (GPU_TRANSFORM_COLOR_KEY | GPU_TRANSFORM_GRAYSCALE));
    assert(plane.dst_addr == GPU_FRAMEBUFFER_B + 238u * 1920u + 688u * 2u);
    puts("PASS zoom demo text: atlas addressing, framebuffer positioning, bounds, fallback");
    return 0;
}
#else
#include "bsp.h"
#include "gpio.h"
#include "vexriscv.h"

static gpu_command glyphs[HUD_COMPARISON_COLUMNS];
uint64_t gpu_platform_cycles(void) { return clint_getTime(BSP_CLINT); }
void gpu_platform_sync(void) {
    __asm__ volatile("fence iorw,iorw" ::: "memory");
    data_cache_invalidate_all();
    __asm__ volatile("fence iorw,iorw" ::: "memory");
}

int main(void) {
    const uint32_t polls = 10000000u;
    bsp_init();
    gpio_setOutputEnable(SYSTEM_GPIO_0_IO_CTRL, 0);
    gpu_device gpu = {0};
    int e = gpu_init(&gpu, GPU_APB_BASE);
    if (e) goto stop;
    const uint32_t required = GPU_STATUS_TRANSFORM_PRESENT | GPU_STATUS_GRAYSCALE_PRESENT;
    if ((*(volatile uint32_t *)(gpu.base + GPU_REG_STATUS) & required) != required) {
        e = GPU_DRIVER_ARGUMENT;
        goto stop;
    }
    e = gpu_set_qos(&gpu, 256, 1536, 1);
    if (e) goto stop;
    bullet_init_local_assets();
    hud_init_glyph_atlas();
    gpu_platform_sync();
    framebuffer_pair buffers;
    framebuffer_init(&buffers);
    uint32_t now = (uint32_t)(gpu_platform_cycles() / (BSP_CLINT_HZ / 1000u));
    uint32_t last_log = now - 250u;
    zoom_control control;
    zoom_control_init(&control, now);
    unsigned shown_side = 0;
    bsp_printf("ZOOM_START,source=16,min=4,max=64,key1=shrink,key2=grow,color_and_gray=1\r\n");
    for (;;) {
        now = (uint32_t)(gpu_platform_cycles() / (BSP_CLINT_HZ / 1000u));
        unsigned keys = (~gpio_getInput(SYSTEM_GPIO_0_IO_CTRL)) & 3u;
        unsigned scale = zoom_control_update(&control, (uint8_t)keys, now);
        unsigned side = scale / 16u;
        if (side == shown_side) continue;
        gpu_command base[] = {
            {.op = GPU_OP_COPY, .src_addr = BULLET_LOCAL_BACKGROUND,
             .dst_addr = buffers.back, .src_stride = GPU_FRAME_STRIDE,
             .dst_stride = GPU_FRAME_STRIDE, .width_pixels = GPU_FRAME_WIDTH,
             .height_pixels = GPU_FRAME_HEIGHT},
            {.op = GPU_OP_FILL, .dst_addr = buffers.back,
             .dst_stride = GPU_FRAME_STRIDE, .width_pixels = GPU_FRAME_WIDTH,
             .height_pixels = HUD_CACHE_HEIGHT}};
        e = perf_render_gpu(&gpu, base, 2, polls);
        if (e) goto stop;
        char size_line[HUD_COMPARISON_COLUMNS];
        /* Display the actual integer-pixel magnification, stable while the
           controller accumulates a fraction toward its next visible pixel. */
        unsigned percent = (side * 100u + 8u) / 16u;
        snprintf(size_line, sizeof size_line, "SCALE %u.%02uX  SIDE %uPX",
                 percent / 100u, percent % 100u, side);
        const char *lines[] = {"GPU ZOOM AND GRAYSCALE", "HOLD KEY1 SHRINK  HOLD KEY2 GROW",
                               size_line, "RELEASE FREEZES  BOTH KEYS PAUSE",
                               "             COLOR                            GRAYSCALE"};
        for (unsigned row = 0; row < 5; ++row) {
            unsigned count = zoom_text(glyphs, buffers.back, row, lines[row]);
            e = perf_render_gpu(&gpu, glyphs, count, polls);
            if (e) goto stop;
        }
        gpu_command planes[2];
        zoom_plane(&planes[0], buffers.back, side, 0);
        zoom_plane(&planes[1], buffers.back, side, 1);
        e = perf_render_gpu(&gpu, planes, 2, polls);
        if (e) goto stop;
        /* First PRESENT enables scanout only after a complete frame exists. */
        e = framebuffer_present(&gpu, &buffers, polls);
        if (e) goto stop;
        uint32_t log_now = (uint32_t)(gpu_platform_cycles() / (BSP_CLINT_HZ / 1000u));
        if (!shown_side || log_now - last_log >= 250u) {
            bsp_printf("ZOOM_FRAME,scale_q8=%d,side=%d,keys=%d\r\n", scale, side, keys);
            last_log = log_now;
        }
        shown_side = side;
    }
stop:
    bsp_printf("ZOOM_STOP,result=%d,hardware=%d\r\n", e, gpu.hardware_error);
    return e;
}
#endif
