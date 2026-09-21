#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "assets.h"
#include "sparse_format.h"

static size_t decode(const uint32_t *words, size_t word_count,
                     uint16_t *pixels, uint16_t width, uint16_t height,
                     uint16_t transparent) {
    size_t at = 0;
    memset(pixels, 0, (size_t)width * height * sizeof(*pixels));
    for (uint16_t y = 0; y < height; ++y) {
        uint32_t x = 0;
        for (;;) {
            assert(at < word_count);
            uint32_t header = words[at++];
            uint16_t skip = (uint16_t)header;
            uint16_t run = (uint16_t)(header >> 16);
            assert(x + skip <= width);
            while (skip--) pixels[(size_t)y * width + x++] = transparent;
            if (!run) {
                assert(x == width);
                break;
            }
            assert(x + run <= width);
            for (uint16_t i = 0; i < run; i += 2) {
                assert(at < word_count);
                uint32_t literals = words[at++];
                pixels[(size_t)y * width + x++] = (uint16_t)literals;
                if (i + 1u < run) pixels[(size_t)y * width + x++] = (uint16_t)(literals >> 16);
                else assert((literals >> 16) == 0);
            }
        }
    }
    return at;
}

static void roundtrip(const uint16_t *source, uint16_t width, uint16_t height,
                      uint16_t stride, uint16_t key) {
    uint32_t words[512];
    uint16_t decoded[256];
    size_t count = 0;
    assert(sparse_pack_rgb565(source, width, height, stride, key,
                             words, 512, &count) == SPARSE_PACK_OK);
    assert(count && decode(words, count, decoded, width, height, key) == count);
    for (uint16_t y = 0; y < height; ++y)
        assert(!memcmp(&source[(size_t)y * stride], &decoded[(size_t)y * width],
                       (size_t)width * sizeof(uint16_t)));
}

int main(void) {
    const uint16_t key = 0;
    uint16_t transparent[12] = {0};
    uint16_t solid[12];
    for (unsigned i = 0; i < 12; ++i) solid[i] = (uint16_t)(i + 1u);
    roundtrip(transparent, 4, 3, 4, key);
    roundtrip(solid, 4, 3, 4, key);

    uint16_t odd_and_trailing[] = {0, 1, 2, 3, 0, 0, 4, 0, 0, 0};
    roundtrip(odd_and_trailing, 5, 2, 5, key);

    uint32_t words[64];
    size_t count = 99;
    assert(sparse_pack_rgb565(odd_and_trailing, 5, 2, 5, key,
                             words, 1, &count) == SPARSE_PACK_CAPACITY);
    assert(count == 0);
    assert(sparse_pack_rgb565(NULL, 5, 2, 5, key, words, 16, &count) == SPARSE_PACK_ARGUMENT);
    assert(sparse_pack_rgb565(odd_and_trailing, 5, 2, 4, key, words, 16, &count) == SPARSE_PACK_ARGUMENT);

    uint32_t state = 0x24102u;
    uint16_t random_pixels[13 * 7];
    for (unsigned pass = 0; pass < 100; ++pass) {
        for (unsigned i = 0; i < 13u * 7u; ++i) {
            state = state * 1664525u + 1013904223u;
            random_pixels[i] = (state & 3u) ? (uint16_t)(state | 1u) : key;
        }
        roundtrip(random_pixels, 13, 7, 13, key);
    }

    /* The real player asset shape is mostly transparent, so Sparse must win. */
    uint16_t sprite[16 * 16] = {0};
    for (unsigned y = 5; y < 11; ++y)
        for (unsigned x = 5; x < 11; ++x) sprite[y * 16 + x] = 0x07e0;
    assert(sparse_pack_rgb565(sprite, 16, 16, 16, key, words, 64, &count) == SPARSE_PACK_OK);
    assert(count * sizeof(uint32_t) < sizeof sprite);

    uint32_t packed_assets[GPU_SPARSE_SLOT_WORDS * 3u];
    size_t player_words = 0, enemy_words = 0, demo_words = 0;
    assert(gpu_assets_upload_sparse(packed_assets, GPU_SPARSE_SLOT_WORDS * 3u,
                                    &player_words, &enemy_words, &demo_words) == SPARSE_PACK_OK);
    uint16_t asset_pixels[GPU_ENEMY_ASSET_WORDS];
    assert(decode(packed_assets, player_words, asset_pixels, 8, 8, 0) == player_words);
    assert(!memcmp(asset_pixels, gpu_player_asset.pixels, GPU_PLAYER_ASSET_WORDS * 2u));
    assert(decode(packed_assets + GPU_SPARSE_SLOT_WORDS, enemy_words,
                  asset_pixels, 12, 8, 0) == enemy_words);
    assert(!memcmp(asset_pixels, gpu_enemy_asset.pixels, GPU_ENEMY_ASSET_WORDS * 2u));
    assert(decode(packed_assets + GPU_SPARSE_SLOT_WORDS * 2u, demo_words,
                  asset_pixels, 8, 8, 0) == demo_words);
    assert(!memcmp(asset_pixels, gpu_demo_asset.pixels, GPU_DEMO_ASSET_WORDS * 2u));
    assert(demo_words * 4u < GPU_DEMO_ASSET_WORDS * 2u);

    puts("PASS B sparse: transparent/solid/trailing/odd/capacity/random roundtrip and compression");
    return 0;
}
