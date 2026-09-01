#ifndef SMALLPROJECT_TIMER_H
#define SMALLPROJECT_TIMER_H

#include <stdint.h>

#include "mmio.h"

#define MTIME_LOW  0x0200bff8u
#define MTIME_HIGH 0x0200bffcu

static inline uint64_t timer_read(void) {
  uint32_t high_before;
  uint32_t low;
  uint32_t high_after;

  do {
    high_before = mmio_read32(MTIME_HIGH);
    low = mmio_read32(MTIME_LOW);
    high_after = mmio_read32(MTIME_HIGH);
  } while (high_before != high_after);

  return ((uint64_t)high_after << 32) | low;
}

#endif
