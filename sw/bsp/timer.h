#ifndef SMALLPROJECT_TIMER_H
#define SMALLPROJECT_TIMER_H

#include <stdint.h>

#include "mmio.h"

#define MTIME_LOW  0x0200bff8u
#define MTIME_HIGH 0x0200bffcu
#define MTIMECMP_LOW  0x02004000u
#define MTIMECMP_HIGH 0x02004004u

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

static inline void timer_set_compare(uint64_t value) {
  mmio_write32(MTIMECMP_HIGH, UINT32_MAX);
  mmio_write32(MTIMECMP_LOW, (uint32_t)value);
  mmio_write32(MTIMECMP_HIGH, (uint32_t)(value >> 32));
}

#endif
