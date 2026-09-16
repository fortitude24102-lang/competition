#ifndef EFINIX_SPARSE_FORMAT_H
#define EFINIX_SPARSE_FORMAT_H
#include <stddef.h>
#include <stdint.h>

enum sparse_pack_result {
    SPARSE_PACK_OK = 0,
    SPARSE_PACK_ARGUMENT = -1,
    SPARSE_PACK_CAPACITY = -2
};

/* Encode rows as {skipPixels, runPixels} headers followed by packed RGB565
 * literals. Every row ends with a runPixels=0 header. */
int sparse_pack_rgb565(const uint16_t *pixels, uint16_t width, uint16_t height,
                       uint16_t stride_pixels, uint16_t transparent_key,
                       uint32_t *output, size_t capacity_words,
                       size_t *word_count);
#endif
