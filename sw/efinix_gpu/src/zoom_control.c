#include "zoom_control.h"

void zoom_control_init(zoom_control *s, uint32_t now_ms) {
    *s = (zoom_control){.scale_q8_8 = 256, .last_ms = now_ms,
                       .candidate_since_ms = now_ms};
}

uint16_t zoom_control_update(zoom_control *s, uint8_t mask, uint32_t now_ms) {
    uint32_t elapsed = now_ms - s->last_ms;
    int direction = 0;
    s->last_ms = now_ms;
    mask &= ZOOM_KEY_SHRINK | ZOOM_KEY_GROW;
    if (mask != s->candidate_mask) {
        s->candidate_mask = mask;
        s->candidate_since_ms = now_ms;
    }
    if (now_ms - s->candidate_since_ms >= 20)
        direction = mask == ZOOM_KEY_GROW ? 1 : mask == ZOOM_KEY_SHRINK ? -1 : 0;
    if (direction != s->direction) {
        s->direction = (int8_t)direction;
        s->fraction = 0;
        return s->scale_q8_8;
    }
    if (direction) {
        /* ponytail: cap unobserved hold time; poll at least every 250 ms
           for exact wall-clock speed rather than jumping after a stall. */
        if (elapsed > 250) elapsed = 250;
        uint32_t numerator = s->fraction + elapsed * 128;
        int scale = s->scale_q8_8 + direction * (int)(numerator / 1000);
        s->fraction = (uint16_t)(numerator % 1000);
        if ((scale <= 64 && direction < 0) || (scale >= 1024 && direction > 0)) {
            scale = scale <= 64 ? 64 : 1024;
            s->fraction = 0;
        }
        s->scale_q8_8 = (uint16_t)scale;
    }
    return s->scale_q8_8;
}
