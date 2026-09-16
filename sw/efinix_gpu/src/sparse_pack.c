#include "sparse_format.h"

static int emit(uint32_t *output, size_t capacity, size_t *used, uint32_t word) {
    if (*used >= capacity) return SPARSE_PACK_CAPACITY;
    output[(*used)++] = word;
    return SPARSE_PACK_OK;
}

int sparse_pack_rgb565(const uint16_t *pixels, uint16_t width, uint16_t height,
                       uint16_t stride, uint16_t key, uint32_t *output,
                       size_t capacity, size_t *word_count) {
    if (word_count) *word_count = 0;
    if (!pixels || !output || !word_count || !width || !height || stride < width)
        return SPARSE_PACK_ARGUMENT;

    size_t used = 0;
    for (uint16_t y = 0; y < height; ++y) {
        const uint16_t *row = pixels + (size_t)y * stride;
        uint32_t x = 0;
        while (x < width) {
            uint16_t skip = 0;
            while (x < width && row[x] == key) { ++x; ++skip; }
            if (x == width) {
                if (emit(output, capacity, &used, skip) != SPARSE_PACK_OK)
                    return SPARSE_PACK_CAPACITY;
                break;
            }

            uint32_t run_start = x;
            while (x < width && row[x] != key) ++x;
            uint16_t run = (uint16_t)(x - run_start);
            if (emit(output, capacity, &used, (uint32_t)skip | ((uint32_t)run << 16)) != SPARSE_PACK_OK)
                return SPARSE_PACK_CAPACITY;
            for (uint16_t i = 0; i < run; i += 2) {
                uint32_t literals = row[run_start + i];
                if (i + 1u < run) literals |= (uint32_t)row[run_start + i + 1u] << 16;
                if (emit(output, capacity, &used, literals) != SPARSE_PACK_OK)
                    return SPARSE_PACK_CAPACITY;
            }
            if (x == width) {
                if (emit(output, capacity, &used, 0) != SPARSE_PACK_OK)
                    return SPARSE_PACK_CAPACITY;
            }
        }
    }
    *word_count = used;
    return SPARSE_PACK_OK;
}
