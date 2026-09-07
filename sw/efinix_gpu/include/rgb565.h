#ifndef EFINIX_RGB565_H
#define EFINIX_RGB565_H
#include <stdint.h>
/* RGB888 -> 565 truncates low bits. 565 -> 888 replicates high bits.
 * Alpha rounds nearest in native 5/6/5 channels using +127 then /255. */
uint16_t rgb565_from_rgb888(uint8_t r, uint8_t g, uint8_t b);
uint32_t rgb565_to_rgb888(uint16_t pixel);
uint16_t rgb565_global_alpha(uint16_t fg, uint16_t bg, uint8_t alpha);
#endif
