#ifndef ZOOM_CONTROL_H
#define ZOOM_CONTROL_H

#include <stdint.h>

#define ZOOM_KEY_SHRINK UINT8_C(1)
#define ZOOM_KEY_GROW UINT8_C(2)

typedef struct {
    uint16_t scale_q8_8;
    /* Caller-owned bookkeeping; initialize with zoom_control_init. */
    uint16_t fraction;
    uint32_t last_ms, candidate_since_ms;
    uint8_t candidate_mask;
    int8_t direction;
} zoom_control;

void zoom_control_init(zoom_control *state, uint32_t now_ms);
/* Active-high pressed bits: KEY1 shrinks, KEY2 grows, both cancel.
   Poll regularly. Transitions pause movement until stable for 20 ms.
   Held speed is 0.5x/second, range 0.25x..4x. A polling gap contributes
   at most 250 ms, preventing a large jump after a stalled frame.
   Timestamps use unsigned millisecond subtraction (wrap supported). */
uint16_t zoom_control_update(zoom_control *state, uint8_t pressed_mask,
                             uint32_t now_ms);

#endif
