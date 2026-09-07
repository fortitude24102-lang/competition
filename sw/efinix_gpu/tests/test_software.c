#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "gpu.h"
#include "rgb565.h"
#include "golden_renderer.h"

int main(int argc, char **argv) {
    assert(gpu_pack_size(0x1234, 0xabcd) == 0xabcd1234u);
    assert(gpu_pack_color_key(0x1234, 0xabcd) == 0xabcd1234u);
    assert(gpu_pack_alpha_flags(0x56, 0xabcd) == 0xabcd0056u);
    assert(rgb565_from_rgb888(255, 255, 255) == 0xffff);
    assert(rgb565_to_rgb888(0x8410) == 0x848284);
    assert(rgb565_global_alpha(0xf800, 0x001f, 128) == 0x800f);
    assert(rgb565_global_alpha(0x1234, 0xabcd, 0) == 0xabcd);
    assert(rgb565_global_alpha(0x1234, 0xabcd, 255) == 0x1234);
    for (unsigned p = 0; p < 65536; ++p) {
        uint32_t c = rgb565_to_rgb888((uint16_t)p);
        assert(rgb565_from_rgb888(c >> 16, c >> 8, c) == p);
    }
    /* Independent nearest-candidate oracle, not the production division. */
    for (unsigned max = 31; max <= 63; max += 32)
        for (unsigned f = 0; f <= max; ++f)
            for (unsigned b = 0; b <= max; ++b)
                for (unsigned a = 0; a <= 255; ++a) {
                    unsigned target = f*a + b*(255-a), want = 0;
                    while (want < max && target > want*255 + 127) ++want;
                    uint16_t fg = max == 31 ? (uint16_t)((f<<11)|f) : (uint16_t)(f<<5);
                    uint16_t bg = max == 31 ? (uint16_t)((b<<11)|b) : (uint16_t)(b<<5);
                    uint16_t expected = max == 31 ? (uint16_t)((want<<11)|want) : (uint16_t)(want<<5);
                    assert(rgb565_global_alpha(fg, bg, (uint8_t)a) == expected);
                }
    uint8_t buf[46], before[46];
    memset(buf, 0xa5, sizeof buf);
    golden_surface s = {buf+2, 40, 5, 3, 14};
    assert(golden_fill(&s, 1, 1, 3, 2, 0x1234) == GPU_ERROR_NONE);
    for (unsigned i = 0; i < sizeof buf; ++i) {
        unsigned hit = (i >= 18 && i < 24) || (i >= 32 && i < 38);
        assert(buf[i] == (hit ? (i%2 ? 0x12 : 0x34) : 0xa5));
    }
    memcpy(before, buf, sizeof buf);
    assert(golden_fill(&s, 4, 0, 2, 1, 0) == GPU_ERROR_ADDRESS_RANGE);
    assert(golden_fill(&s, 0, 0, 0, 1, 0) == GPU_ERROR_ZERO_SIZE);
    s.stride_bytes = 8;
    assert(golden_fill(&s, 0, 0, 1, 1, 0) == GPU_ERROR_STRIDE_TOO_SMALL);
    s.stride_bytes = 14; s.size_bytes = 37;
    assert(golden_fill(&s, 0, 0, 1, 1, 0) == GPU_ERROR_ADDRESS_RANGE);
    s.size_bytes = 40; s.pixels++;
    assert(golden_fill(&s, 0, 0, 1, 1, 0) == GPU_ERROR_MISALIGNED_ADDRESS);
    s.pixels--; s.stride_bytes = 15;
    assert(golden_fill(&s, 0, 0, 1, 1, 0) == GPU_ERROR_MISALIGNED_ADDRESS);
    s.stride_bytes = 0xfffffffeu; s.height = 65535;
    assert(golden_fill(&s, 0, 0, 1, 1, 0) == GPU_ERROR_ADDRESS_RANGE);
    s.stride_bytes = 14; s.height = 3; s.size_bytes = 38;
    assert(golden_fill(&s, 65535, 0, 1, 1, 0) == GPU_ERROR_ADDRESS_RANGE);
    assert(memcmp(buf, before, sizeof buf) == 0);
    assert(golden_fill(NULL, 0, 0, 1, 1, 0) == GPU_ERROR_ADDRESS_RANGE);
    assert(golden_fill(&s, 4, 2, 1, 1, 0x1234) == GPU_ERROR_NONE);
    assert(buf[38] == 0x34 && buf[39] == 0x12);
    assert(buf[40] == 0xa5 && buf[41] == 0xa5);
    assert(golden_crc32("123456789", 9) == 0xcbf43926u);
    assert(golden_crc32("", 0) == 0);
    static uint8_t frame[GPU_FRAME_BYTES];
    golden_surface full = {frame, sizeof frame, 640, 480, 1280};
    assert(golden_fill(&full, 0, 0, 640, 480, 0x07e0) == GPU_ERROR_NONE);
    assert(golden_fill(&full, 639, 479, 1, 1, 0xf800) == GPU_ERROR_NONE);
    for (size_t i=0; i<sizeof frame-2; i+=2) {
        assert(frame[i]==0xe0 && frame[i+1]==0x07);
    }
    assert(frame[sizeof frame-2]==0 && frame[sizeof frame-1]==0xf8);
    if (argc > 1) {
        FILE *out=fopen(argv[1], "wb");
        assert(out);
        assert(fwrite(frame, 1, sizeof frame, out)==sizeof frame);
        assert(fclose(out)==0);
    }
    printf("reference RGB565: %zu bytes, CRC32=%08x\n", sizeof frame,
           (unsigned)golden_crc32(frame, sizeof frame));
    puts("PASS: packing, RGB roundtrip, exhaustive alpha, guarded odd-width fill, CRC32");
    return 0;
}

