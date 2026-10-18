#include <stdint.h>
#include <stdio.h>
#include "zoom_control.h"

static unsigned failures;
#define CHECK(actual, expected) do { \
    unsigned got_ = (actual), want_ = (expected); \
    if (got_ != want_) { \
        fprintf(stderr, "line %d: got %u, expected %u\n", __LINE__, got_, want_); \
        ++failures; \
    } \
} while (0)

static void hold(zoom_control *s, uint8_t mask, uint32_t *now, unsigned ms) {
    for (unsigned i = 0; i < ms; ++i)
        zoom_control_update(s, mask, ++*now);
}

int main(void) {
    zoom_control s;
    uint32_t now = 0;
    zoom_control_init(&s, now);
    CHECK(zoom_control_update(&s, 0, now), 256);

    /* A short press/bounce must not move; stable press starts after 20 ms. */
    CHECK(zoom_control_update(&s, 2, 1), 256);
    CHECK(zoom_control_update(&s, 0, 10), 256);
    CHECK(zoom_control_update(&s, 2, 15), 256);
    CHECK(zoom_control_update(&s, 2, 34), 256);
    CHECK(zoom_control_update(&s, 2, 35), 256);
    now = 35;
    hold(&s, 2, &now, 1000);
    CHECK(s.scale_q8_8, 384);
    /* Sub-unit fractions accumulate, and release freezes immediately. */
    CHECK(zoom_control_update(&s, 0, ++now), 384);
    hold(&s, 0, &now, 1000);
    CHECK(s.scale_q8_8, 384);
    CHECK(zoom_control_update(&s, 3, ++now), 384);
    hold(&s, 3, &now, 1000);
    CHECK(s.scale_q8_8, 384);

    zoom_control_init(&s, 0);
    now = 0;
    zoom_control_update(&s, 1, now);
    hold(&s, 1, &now, 1520);
    CHECK(s.scale_q8_8, 64);
    hold(&s, 1, &now, 10000);
    CHECK(s.scale_q8_8, 64);
    zoom_control_update(&s, 2, ++now);
    hold(&s, 2, &now, 7520);
    CHECK(s.scale_q8_8, 1024);
    hold(&s, 2, &now, 10000);
    CHECK(s.scale_q8_8, 1024);

    /* Reversing direction must not apply the old direction's fraction. */
    zoom_control_init(&s, 0);
    zoom_control_update(&s, 2, 0);
    zoom_control_update(&s, 2, 20);
    CHECK(zoom_control_update(&s, 2, 27), 256);
    zoom_control_update(&s, 1, 28);
    zoom_control_update(&s, 1, 48);
    CHECK(zoom_control_update(&s, 1, 49), 256);
    CHECK(zoom_control_update(&s, 1, 56), 255);

    /* A bounced release/re-press must earn the full debounce interval. */
    zoom_control_init(&s, 0);
    zoom_control_update(&s, 2, 0);
    zoom_control_update(&s, 2, 20);
    CHECK(zoom_control_update(&s, 2, 28), 257);
    zoom_control_update(&s, 0, 29);
    zoom_control_update(&s, 2, 30);
    CHECK(zoom_control_update(&s, 2, 49), 257);
    CHECK(zoom_control_update(&s, 2, 50), 257);
    CHECK(zoom_control_update(&s, 2, 58), 258);

    /* One stalled frame is bounded; subsequent frames use fresh time. */
    zoom_control_init(&s, 0);
    zoom_control_update(&s, 2, 0);
    zoom_control_update(&s, 2, 20);
    CHECK(zoom_control_update(&s, 2, 10020), 288);
    CHECK(zoom_control_update(&s, 2, 10028), 289);

    /* Ignore unrelated GPIO bits and preserve normal speed across wrap. */
    now = UINT32_MAX - 30;
    zoom_control_init(&s, now);
    zoom_control_update(&s, 0x82, now);
    hold(&s, 0x82, &now, 1020);
    CHECK(s.scale_q8_8, 384);
    if (failures) return 1;
    puts("PASS zoom_control: debounce, duration, fractions, release, both keys, bounds, reversal, stall, wrap");
    return 0;
}
