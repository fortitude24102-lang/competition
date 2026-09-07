#include "rgb565.h"
uint16_t rgb565_from_rgb888(uint8_t r, uint8_t g, uint8_t b) {
    return (uint16_t)(((uint16_t)(r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}
uint32_t rgb565_to_rgb888(uint16_t p) {
    uint32_t r=p>>11, g=(p>>5)&63, b=p&31;
    return ((r<<3 | r>>2)<<16) | ((g<<2 | g>>4)<<8) | (b<<3 | b>>2);
}
uint16_t rgb565_global_alpha(uint16_t fg, uint16_t bg, uint8_t a) {
    unsigned r=((fg>>11)*a + (bg>>11)*(255u-a) +127)/255;
    unsigned g=(((fg>>5)&63)*a + ((bg>>5)&63)*(255u-a) +127)/255;
    unsigned b=((fg&31)*a + (bg&31)*(255u-a) +127)/255;
    return (uint16_t)((r<<11)|(g<<5)|b);
}
